// ============================================================
// SerialManager — non-blocking serial communication layer
// Replaces the blocking executeWR() spin-loop with async I/O
// ============================================================

class SerialManager {
  Serial port;
  String portName = ""; // dustin's rig, added — FirmwareUpdater needs the port name to touch-reset into bootloader
  String readBuffer = "";
  String lastRead = "empty";
  String lastLine = null;  // set by onSerialData; polled by SetupWizard instead of readAvailable()
  String lastWrite = "";
  int responseTimeMs = 0;
  long writeTimestamp = 0;
  boolean waitingForResponse = false;
  int timeoutMs = 2000;
  int maxRetries = 2;
  int retryCount = 0;
  // подряд идущие таймауты: после connectionLostThreshold считаем связь потерянной
  // (плата выдернута/зависла) и отключаемся — авто-реконнект в главном цикле подхватит
  int consecutiveTimeouts = 0;
  int connectionLostThreshold = 5;

  // Command queue for non-blocking writes
  ArrayList<String> commandQueue = new ArrayList<String>();
  boolean commandInProgress = false;

  // Stats
  int totalWrites = 0;
  int totalReads = 0;
  int totalErrors = 0;
  int totalTimeouts = 0;
  long lastActivityTime = 0;
  PApplet app;

  SerialManager(PApplet app) {
    this.app = app;
  }

  boolean connect(String portName, int baud) {
    try {
      if (port != null) disconnect(); // не оставляем старый порт открытым при повторном подключении
      resetLinkState();
      port = new Serial(app, portName, baud);
      port.bufferUntil(10); // LF terminator
      this.portName = portName;
      Log.info("SERIAL", strings.get("Подключено к ", "Connected to ") + portName + " @ " + baud + " baud");
      return true;
    } catch (Exception e) {
      Log.error("SERIAL", strings.get("Не удалось подключиться: ", "Failed to connect: ") + e.getMessage());
      return false;
  }
  }

  void disconnect() {
    if (port != null) {
      closeUnderlyingPort(port);
      port = null;
      Log.info("SERIAL", strings.get("Отключено", "Disconnected"));
    }
    resetLinkState();
  }

  // dustin's rig, added - Processing's Serial.stop() just calls jssc's closePort() and
  // silently swallows any SerialPortException, without removing the event listener first.
  // On Windows that can leave the OS handle actually held a little longer than stop()
  // returning implies - the background event-listener thread can still be mid-read. The
  // caller here (disconnect(), used right before FirmwareUpdater's arduino-cli upload) needs
  // the port GENUINELY free the moment this returns, not just "stop() didn't throw" - a busy
  // handle at that point makes the touch-reset/upload fail with a port-busy error. So: drop
  // the event listener first, then retry closePort() for up to ~500ms until isOpened() is
  // actually false, instead of trusting a single fire-and-forget close + a blind sleep.
  void closeUnderlyingPort(Serial p) {
    jssc.SerialPort raw = p.port;
    try { if (raw != null) raw.removeEventListener(); } catch (Throwable t) {}
    try { p.stop(); } catch (Throwable t) {}
    if (raw == null) return;
    for (int i = 0; i < 10 && raw.isOpened(); i++) {
      try { raw.closePort(); } catch (Throwable t) {}
      if (!raw.isOpened()) break;
      try { Thread.sleep(50); } catch (InterruptedException ie) {}
    }
    if (raw.isOpened()) {
      Log.warn("SERIAL", strings.get(
        "Порт не удалось закрыть полностью — возможна ошибка занятости порта при следующем открытии",
        "Could not fully release the port - a busy-port error may occur the next time it's opened"));
    }
  }

  // Полный сброс состояния очереди/ожиданий. Раньше disconnect() оставлял
  // commandInProgress/waitingForResponse/очередь как есть — после переподключения
  // очередь могла навсегда «зависнуть» (commandInProgress=true без живого запроса).
  void resetLinkState() {
    synchronized(this) {
      commandQueue.clear();
      commandInProgress = false;
      waitingForResponse = false;
      retryCount = 0;
      consecutiveTimeouts = 0;
    }
  }

  boolean isConnected() {
    return port != null;
  }

  // Non-blocking write — queues command
  void enqueueCommand(String cmd) {
    commandQueue.add(cmd);
    processQueue();
  }

  // Direct write (for time-critical commands)
  void sendImmediate(String cmd) {
    if (port == null) return;
    // dustin's rig, added — while FirmwareUpdater is mid-flash (disconnected, doing the
    // 1200-baud touch-reset on a background thread), nothing else may touch the port:
    // any stray write here (e.g. a periodic UI poll) races with that sequence and can
    // silently corrupt the port state, making the touch-reset fail. FirmwareUpdater
    // itself never calls sendImmediate() during that window, so this can't block it.
    if (firmwareUpdater != null && firmwareUpdater.flashing) return;
    try {
      port.write(cmd + (char)13);
    } catch (Throwable t) {
      // порт умер на записи (плату выдернули) — закрываемся, авто-реконнект подхватит
      Log.error("SERIAL", strings.get("Ошибка записи в порт: ", "Port write failed: ") + t.getMessage());
      disconnect();
      return;
    }
    lastWrite = cmd;
    writeTimestamp = millis();
    waitingForResponse = true;
    totalWrites++;
    lastActivityTime = millis();
    Log.debug("SERIAL", "TX: " + cmd);
  }

  void processQueue() {
    synchronized(this) {
      if (commandInProgress || commandQueue.isEmpty()) return;
      if (waitingForResponse) return;

      String cmd = commandQueue.remove(0);
      commandInProgress = true;
      sendImmediate(cmd);
      // sendImmediate мог тихо не отправить (порт закрыт / идёт прошивка) —
      // иначе commandInProgress остался бы true навсегда и очередь бы встала
      if (!waitingForResponse) commandInProgress = false;
    }
  }

  // Called from serialEvent — processes incoming data
  void onSerialData(String data) {
    synchronized(this) {
      if (data == null) return;
      data = data.trim();
      if (data.length() == 0) return;

      lastRead = data;
      lastLine = data;
      responseTimeMs = (int)(millis() - writeTimestamp);
      waitingForResponse = false;
      commandInProgress = false;
      retryCount = 0;           // бюджет ретраев — на команду, а не на всю сессию
      consecutiveTimeouts = 0;  // связь жива
      totalReads++;
      lastActivityTime = millis();

      Log.debug("SERIAL", "RX: " + data + " (" + responseTimeMs + "ms)");

      // Process next queued command
      processQueue();
    }
  }

  // Check for timeouts — call from draw()
  void update() {
    synchronized(this) {
      if (waitingForResponse && (millis() - writeTimestamp > timeoutMs)) {
        totalTimeouts++;
        waitingForResponse = false;
        commandInProgress = false;

        String msg = "Timeout waiting for response to: " + lastWrite;
        Log.warn("SERIAL", msg);

        consecutiveTimeouts++;
        if (consecutiveTimeouts >= connectionLostThreshold) {
          Log.warn("SERIAL", strings.get("Плата не отвечает — считаю связь потерянной", "Board not responding — treating the link as lost"));
          disconnect();
          return;
        }

        if (retryCount < maxRetries) {
          retryCount++;
          Log.warn("SERIAL", "Retry " + retryCount + "/" + maxRetries);
          commandQueue.add(0, lastWrite); // re-queue at front
          processQueue();
        } else {
          retryCount = 0;
          processQueue(); // skip to next
        }
      }
    }
  }

  // DEPRECATED: readAvailable() steals bytes from serialEvent, causing
  // commandInProgress to get stuck. Use lastLine field instead.
  @Deprecated
  String readAvailable() {
    return "empty";
  }

  String getStatsString() {
    return "TX:" + totalWrites + " RX:" + totalReads +
           " ERR:" + totalErrors + " TO:" + totalTimeouts +
           " RT:" + responseTimeMs + "ms" +
           " Q:" + commandQueue.size();
  }
}
