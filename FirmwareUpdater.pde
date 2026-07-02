// ============================================================
// FirmwareUpdater — compares the connected board's CI-baked build number
// (read via the 'X' serial command, see FW_BUILD_ID in the firmware's
// Config.h) against the latest GitHub release. If they differ - regardless
// of which is "newer" - offers to flash the release's matching hex for this
// exact board+options combo (matched via manifest.json in the release zip).
//
// No persistence: declining just hides the prompt for this session. The
// board's own build number is the only source of truth, so the next time
// the app connects to it, it asks again if still not equal.
//
// Bootloader entry: Leonardo/Micro/ProMicro (32u4, avr109 protocol) reset
// into their bootloader when their CDC serial port is opened at 1200 baud
// and then closed - the same trick arduino-cli/the Arduino IDE use, so no
// physical reset button press is needed in the common case.
// ============================================================

interface AvrdudeProgress {
  void onLine(String line);
}

class FirmwareUpdater {
  static final String REPO = "bitwiresys/Arduino-FFB-wheel-v3";
  Http http = new Http();
  UpdatePanel panel = new UpdatePanel();
  PApplet papplet;

  boolean checked = false;    // have we already decided (shown/skipped the toast) this connection
  boolean busy = false;
  // dustin's rig, added - set for the whole doFlash() duration. Other code (SettingsTab's
  // NTC poll timer, wizard steps, etc.) must check this and skip any serial.* call while
  // true - discovered the hard way: that 500ms poll racing with disconnect()/the 1200-baud
  // touch on a background thread was silently corrupting the port, making the touch-reset
  // reliably fail every time despite the reset logic itself being correct in isolation.
  boolean flashing = false;
  boolean localIdRequested = false;
  int localBuildId = -1;      // from the 'X' reply
  boolean networkReady = false;
  int latestBuildId = -1;
  String latestTag = "";
  String buildZipUrl = "";
  String matchedFile = "";
  String matchedBoard = "";
  String matchedLetters = "";
  File cachedZipFile = null;

  FirmwareUpdater() {
    panel.toastSlot = 1; // stacks below the control-panel update toast
    papplet = wheel_control_v3.this;
  }

  // "abx" or "abxm" -> sorted, board-marker-stripped letter set, so the firmware's
  // raw emission order and the manifest's canonical order compare equal regardless of order.
  String normalizeLetters(String raw) {
    if (raw == null) return "";
    char[] c = raw.toLowerCase().replace("m", "").toCharArray();
    java.util.Arrays.sort(c);
    return new String(c);
  }

  // Call once fw.fullVersionString is known (right after the 'V' reply is parsed).
  // Fires the 'X' build-id request and the GitHub check in parallel; whichever
  // finishes last triggers the actual decision in tryDecide().
  void checkForUpdate() {
    if (checked || busy) return;
    if (fw == null || fw.fullVersionString == null || fw.fullVersionString.length() == 0) return;

    if (!localIdRequested) {
      localIdRequested = true;
      serial.sendImmediate("X");
    }

    busy = true;
    Thread worker = new Thread(new Runnable() {
      public void run() { doCheckNetwork(); }
    });
    worker.setDaemon(true);
    worker.start();
  }

  // Called from parseResponse() in the main sketch when a bare integer line
  // arrives while we're waiting on the 'X' reply.
  void onLocalBuildId(int id) {
    if (!localIdRequested || localBuildId >= 0) return; // not expecting one / already have it
    localBuildId = id;
    Log.info("UPDATE", strings.get("Прошивка: сборка платы ", "Firmware: board build ") + id);
    tryDecide();
  }

  void doCheckNetwork() {
    try {
      String json = http.getString("https://api.github.com/repos/" + REPO + "/releases/latest");
      JSONObject obj = parseJSONObject(json);
      latestTag = obj.getString("tag_name");
      latestBuildId = buildNumber(latestTag);
      JSONArray assets = obj.getJSONArray("assets");
      buildZipUrl = "";
      for (int i = 0; i < assets.size(); i++) {
        JSONObject a = assets.getJSONObject(i);
        if (a.getString("name").equals("build.zip")) { buildZipUrl = a.getString("browser_download_url"); break; }
      }
      Log.info("UPDATE", strings.get("Прошивка: последний релиз ", "Firmware: latest release ") + latestTag);
    } catch (Throwable t) {
      Log.warn("UPDATE", strings.get("Проверка обновлений прошивки не удалась: ", "Firmware update check failed: ") + errText(t));
    } finally {
      networkReady = true;
      busy = false;
      tryDecide();
    }
  }

  // "fw-build-12" -> 12
  int buildNumber(String tag) {
    if (tag == null || tag.length() == 0) return -1;
    int i = tag.lastIndexOf('-');
    if (i < 0) return -1;
    try { return Integer.parseInt(tag.substring(i + 1)); }
    catch (Exception e) { return -1; }
  }

  // Runs once both the board's build id and the GitHub check have come back
  // (order-independent - whichever arrives second calls this and it's a no-op
  // the first time since the other piece isn't ready yet).
  void tryDecide() {
    if (checked) return;
    if (localBuildId < 0 || !networkReady) return;
    checked = true;

    if (buildZipUrl.length() == 0 || latestBuildId < 0) {
      Log.warn("UPDATE", "Firmware release has no build.zip asset or unparsable tag");
      return;
    }
    if (localBuildId == latestBuildId) {
      Log.info("UPDATE", strings.get("Прошивка: уже последняя сборка", "Firmware: already on the latest build"));
      return;
    }

    // Different build number - find the matching hex for this exact board+options
    // combo before bothering the user (still needed: the numeric id alone doesn't
    // say which file in the release is ours).
    Thread worker = new Thread(new Runnable() {
      public void run() { doMatchAndOffer(); }
    });
    worker.setDaemon(true);
    worker.start();
  }

  void doMatchAndOffer() {
    try {
      File tmpZip = new File(System.getProperty("java.io.tmpdir"), "wheel_fw_release.zip");
      http.downloadFile(buildZipUrl, tmpZip, null);

      JSONObject manifest = readJsonEntry(tmpZip, "manifest.json");
      if (manifest == null) { Log.warn("UPDATE", "manifest.json not found in release zip"); return; }

      boolean isPromicro = fw.proMicroPins;
      String myLetters = normalizeLetters(fw.optionLetters);
      String myBoard = isPromicro ? "promicro" : "leonardo";

      matchedFile = ""; matchedBoard = ""; matchedLetters = "";
      JSONArray variants = manifest.getJSONArray("variants");
      for (int i = 0; i < variants.size(); i++) {
        JSONObject v = variants.getJSONObject(i);
        if (!v.getString("board").equals(myBoard)) continue;
        if (!normalizeLetters(v.getString("letters")).equals(myLetters)) continue;
        matchedBoard = myBoard;
        matchedLetters = v.getString("letters");
        matchedFile = myBoard + "/" + v.getString("file");
        break;
      }

      if (matchedFile.length() > 0) {
        cachedZipFile = tmpZip;
        panel.showAvailable(strings.get("Обновление прошивки руля", "Wheel firmware update"),
          strings.get("сборка ", "build ") + localBuildId, strings.get("сборка ", "build ") + latestBuildId,
          strings.get("Плата: ", "Board: ") + myBoard + ", " + strings.get("опции: ", "options: ") + (matchedLetters.length() > 0 ? matchedLetters : "-"));
      } else {
        Log.warn("UPDATE", strings.get("В новом релизе нет сборки для вашей конфигурации: ", "New release has no build for your configuration: ") + myBoard + " " + myLetters);
      }
    } catch (Throwable t) {
      Log.warn("UPDATE", strings.get("Проверка обновлений прошивки не удалась: ", "Firmware update check failed: ") + errText(t));
    }
  }

  JSONObject readJsonEntry(File zipFile, String entryName) throws IOException {
    java.util.zip.ZipFile zf = new java.util.zip.ZipFile(zipFile);
    try {
      java.util.zip.ZipEntry e = zf.getEntry(entryName);
      if (e == null) return null;
      String text = http.readAll(zf.getInputStream(e));
      return parseJSONObject(text);
    } finally {
      zf.close();
    }
  }

  void update() {
    if (panel.clickedDismiss) { panel.clickedDismiss = false; panel.hide(); }
    if (panel.clickedUpdate)  { panel.clickedUpdate = false; startUpdate(); }
    if (panel.clickedClose)   { panel.clickedClose = false; panel.hide(); }
    if (panel.clickedRetry)   { panel.clickedRetry = false; startUpdate(); }
  }

  void draw() { panel.draw(); }
  boolean handleClick() { return panel.handleClick(); }

  void startUpdate() {
    panel.showWorking(strings.get("Обновление прошивки", "Updating firmware"));
    Thread t = new Thread(new Runnable() {
      public void run() { doFlash(); }
    });
    t.setDaemon(true);
    t.start();
  }

  void doFlash() {
    String originalPort = serial.portName;
    flashing = true;
    try {
      panel.setProgress(0.05f, strings.get("Извлечение файла прошивки...", "Extracting firmware file..."));
      File hexFile = extractHex(cachedZipFile, matchedFile);

      if (originalPort == null || originalPort.length() == 0) throw new IOException(strings.get("Порт не определён", "Serial port unknown"));

      panel.setProgress(0.15f, strings.get("Отключение...", "Disconnecting..."));
      serial.disconnect();
      Thread.sleep(1000);

      // Hand-rolled 1200-baud touch-reset (jssc, direct port polling) was tried extensively
      // and, despite working 100% reliably in isolated standalone tests, reliably FAILED
      // inside the actual packaged app for reasons that resisted every isolation attempt
      // (ruled out: Processing's Serial.list() staleness, the SettingsTab NTC-poll race,
      // connection duration, DTR handling, GameControlPlus/HID interference). arduino-cli
      // itself, run directly, never once failed to reset+flash this exact hardware across
      // dozens of manual tests this session - so it's what actually does the flashing here,
      // bundled with just enough offline board+avrdude+discovery-tool data to run with zero
      // network access and no separate Arduino IDE/CLI install on the user's machine.
      String fqbn = matchedBoard.equals("promicro") ? "arduino:avr:micro" : "arduino:avr:leonardo";
      panel.setProgress(0.3f, strings.get("Заливка через arduino-cli...", "Flashing via arduino-cli..."));
      boolean ok = runArduinoCliUpload(originalPort, fqbn, hexFile, new AvrdudeProgress() {
        public void onLine(String line) {
          String shown = line.length() > 70 ? line.substring(0, 70) : line;
          panel.setProgress(min(panel.progress + 0.01f, 0.9f), shown);
        }
      });
      if (!ok) throw new IOException(strings.get("arduino-cli завершился с ошибкой", "arduino-cli exited with an error"));

      panel.setProgress(0.95f, strings.get("Переподключение...", "Reconnecting..."));
      Thread.sleep(2000); // board reboots back into the application after a successful flash
      reconnectAfterFlash(originalPort);

      panel.showDone(strings.get("Прошивка обновлена: ", "Firmware updated to ") + latestTag);
      Log.info("UPDATE", strings.get("Прошивка обновлена: ", "Firmware updated to ") + latestTag);
    } catch (Throwable t) {
      Log.error("UPDATE", "Firmware flash: " + errText(t));
      panel.showError(strings.get("Не удалось обновить прошивку: ", "Failed to update firmware: ") + errText(t));
      try { if (!serial.isConnected() && originalPort != null) serial.connect(originalPort, 115200); } catch (Throwable t2) {}
    } finally {
      flashing = false;
    }
  }

  File extractHex(File zipFile, String entryName) throws IOException {
    java.util.zip.ZipFile zf = new java.util.zip.ZipFile(zipFile);
    try {
      java.util.zip.ZipEntry e = zf.getEntry(entryName);
      if (e == null) throw new IOException("Entry not found in release zip: " + entryName);
      File out = new File(System.getProperty("java.io.tmpdir"), "wheel_fw_update.hex");
      InputStream in = zf.getInputStream(e);
      FileOutputStream fos = new FileOutputStream(out);
      byte[] buf = new byte[16384];
      int n;
      while ((n = in.read(buf)) != -1) fos.write(buf, 0, n);
      fos.close();
      in.close();
      return out;
    } finally {
      zf.close();
    }
  }

  // arduino-cli does its own 1200-baud touch-reset internally as part of `upload` (that's
  // exactly the mechanism proven reliable in this session's manual testing) - no separate
  // touch/port-polling step needed here at all.
  boolean runArduinoCliUpload(String port, String fqbn, File hexFile, AvrdudeProgress progress) throws Exception {
    File cliDir = new File(getInstallDir(), "arduino-cli");
    File cliExe = new File(cliDir, "arduino-cli.exe");
    File dataDir = new File(cliDir, "data");
    if (!cliExe.exists()) throw new IOException("arduino-cli.exe not found: " + cliExe.getAbsolutePath());

    File configFile = writeArduinoCliConfig(dataDir);

    ProcessBuilder pb = new ProcessBuilder(
      cliExe.getAbsolutePath(),
      "upload",
      "-p", port,
      "--fqbn", fqbn,
      "-i", hexFile.getAbsolutePath(),
      "--config-file", configFile.getAbsolutePath()
    );
    pb.redirectErrorStream(true);
    Process proc = pb.start();
    BufferedReader r = new BufferedReader(new InputStreamReader(proc.getInputStream()));
    String line;
    while ((line = r.readLine()) != null) {
      if (progress != null) progress.onLine(line);
      Log.debug("FLASH", line);
    }
    int code = proc.waitFor();
    return code == 0;
  }

  // arduino-cli needs an explicit config pointing its data directory at the bundled
  // packages/ folder (board defs + avrdude + the serial-discovery tool it uses for the
  // touch-reset) - otherwise it falls back to the machine's real Arduino IDE install
  // (if any) or tries to hit the network for a fresh one. Regenerated each flash since
  // the install path (and therefore these paths) is only known at runtime.
  File writeArduinoCliConfig(File dataDir) throws IOException {
    File stagingDir = new File(System.getProperty("java.io.tmpdir"), "wheelcontrol_arduino_cli_staging");
    stagingDir.mkdirs();
    File configFile = new File(System.getProperty("java.io.tmpdir"), "wheelcontrol_arduino_cli.yaml");
    String yaml = "directories:\r\n" +
      "  data: " + dataDir.getAbsolutePath() + "\r\n" +
      "  downloads: " + stagingDir.getAbsolutePath() + "\r\n" +
      "  user: " + dataDir.getAbsolutePath() + "\r\n" +
      "board_manager:\r\n" +
      "  additional_urls: []\r\n";
    PrintWriter pw = new PrintWriter(configFile, "UTF-8");
    pw.print(yaml);
    pw.close();
    return configFile;
  }

  boolean portListContains(String[] list, String port) {
    for (String p : list) if (p.equals(port)) return true;
    return false;
  }

  // After flashing, the board can re-enumerate on a different COM port number than it
  // had before (observed: COM5/COM6/COM7 shuffling across attempts on the same physical
  // port) - blindly reconnecting to the old originalPort left the app stuck showing
  // "Disconnected" even though the flash itself succeeded. Try the old port a few times
  // (the common case), then fall back to scanning for whatever's actually available now.
  void reconnectAfterFlash(String originalPort) {
    for (int attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        try { Thread.sleep(700); } catch (InterruptedException ie) {}
      }
      if (originalPort != null && portListContains(jssc.SerialPortList.getPortNames(), originalPort)) {
        if (serial.connect(originalPort, 115200)) {
          readFWVersion();
          serial.enqueueCommand("U");
          return;
        }
      }
    }

    Log.warn("UPDATE", strings.get("Плата не найдена на прежнем порту, ищу новый...", "Board not found on its old port, scanning for a new one..."));
    String[] candidates = jssc.SerialPortList.getPortNames();
    for (String p : candidates) {
      if (serial.connect(p, 115200)) {
        saveStrings("data/COM_cfg.txt", new String[]{p});
        readFWVersion();
        serial.enqueueCommand("U");
        return;
      }
    }
    Log.error("UPDATE", strings.get("Не удалось переподключиться после прошивки", "Failed to reconnect after flashing"));
  }

  File getInstallDir() throws Exception {
    File jarFile = new File(FirmwareUpdater.class.getProtectionDomain().getCodeSource().getLocation().toURI());
    File appDir = jarFile.getParentFile();
    return appDir.getParentFile();
  }
}
