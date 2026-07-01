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
      port.stop();
      port = null;
      Log.info("SERIAL", strings.get("Отключено", "Disconnected"));
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
    port.write(cmd + (char)13);
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
