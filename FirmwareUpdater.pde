// ============================================================
// FirmwareUpdater — checks GitHub for a newer firmware build matching the
// currently-connected board's exact hardware combo (board + option letters,
// matched via manifest.json inside the release zip), offers to flash it,
// and drives the whole reset-into-bootloader -> avrdude -> reconnect flow.
//
// Bootloader entry: Leonardo/Micro/ProMicro (32u4, avr109 protocol) reset
// into their bootloader when their CDC serial port is opened at 1200 baud
// and then closed — the same trick arduino-cli/the Arduino IDE use, so no
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

  boolean checked = false;
  boolean busy = false;
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

  String loadSeenTag() {
    try {
      File f = new File(dataPath("fw_release_seen.txt"));
      if (f.exists()) {
        String[] lines = loadStrings("fw_release_seen.txt");
        if (lines != null && lines.length > 0) return trim(lines[0]);
      }
    } catch (Throwable t) {}
    return "";
  }

  void saveSeenTag(String tag) {
    try { saveStrings("data/fw_release_seen.txt", new String[]{tag}); }
    catch (Throwable t) { Log.warn("UPDATE", "fw_release_seen.txt: " + errText(t)); }
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
  // NB: only ever runs once per session (checked latch) — if the user swaps to a
  // different wheel mid-session without restarting the app, re-check won't fire.
  void checkForUpdate() {
    if (checked || busy) return;
    if (fw == null || fw.fullVersionString == null || fw.fullVersionString.length() == 0) return;
    busy = true;
    Thread worker = new Thread(new Runnable() {
      public void run() { doCheck(); }
    });
    worker.setDaemon(true);
    worker.start();
  }

  void doCheck() {
    try {
      String json = http.getString("https://api.github.com/repos/" + REPO + "/releases/latest");
      JSONObject obj = parseJSONObject(json);
      latestTag = obj.getString("tag_name");
      JSONArray assets = obj.getJSONArray("assets");
      buildZipUrl = "";
      for (int i = 0; i < assets.size(); i++) {
        JSONObject a = assets.getJSONObject(i);
        if (a.getString("name").equals("build.zip")) { buildZipUrl = a.getString("browser_download_url"); break; }
      }
      if (buildZipUrl.length() == 0) { Log.warn("UPDATE", "Firmware release has no build.zip asset"); return; }

      String seenTag = loadSeenTag();
      if (seenTag.equals(latestTag)) {
        Log.info("UPDATE", strings.get("Прошивка: релиз ", "Firmware: release ") + latestTag + strings.get(" уже проверен", " already checked"));
        return;
      }

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
          fw.fullVersionString, latestTag,
          strings.get("Плата: ", "Board: ") + myBoard + ", " + strings.get("опции: ", "options: ") + (matchedLetters.length() > 0 ? matchedLetters : "-"));
      } else {
        Log.warn("UPDATE", strings.get("В новом релизе нет сборки для вашей конфигурации: ", "New release has no build for your configuration: ") + myBoard + " " + myLetters);
      }
    } catch (Throwable t) {
      Log.warn("UPDATE", strings.get("Проверка обновлений прошивки не удалась: ", "Firmware update check failed: ") + errText(t));
    } finally {
      checked = true;
      busy = false;
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
    if (panel.clickedDismiss) { panel.clickedDismiss = false; panel.hide(); saveSeenTag(latestTag); }
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
    try {
      panel.setProgress(0.05f, strings.get("Извлечение файла прошивки...", "Extracting firmware file..."));
      File hexFile = extractHex(cachedZipFile, matchedFile);

      if (originalPort == null || originalPort.length() == 0) throw new IOException(strings.get("Порт не определён", "Serial port unknown"));

      panel.setProgress(0.15f, strings.get("Отключение...", "Disconnecting..."));
      serial.disconnect();
      Thread.sleep(300);

      panel.setProgress(0.25f, strings.get("Перевод платы в режим загрузчика...", "Resetting board into bootloader..."));
      String bootPort = touchResetAndFindBootloaderPort(originalPort);
      if (bootPort == null) {
        throw new IOException(strings.get(
          "Плата не перешла в режим загрузчика. Нажмите кнопку Reset на плате вручную и повторите.",
          "Board did not enter bootloader mode. Press the board's Reset button manually and retry."));
      }

      panel.setProgress(0.4f, strings.get("Заливка прошивки...", "Flashing..."));
      boolean ok = runAvrdude(bootPort, hexFile, new AvrdudeProgress() {
        public void onLine(String line) {
          String shown = line.length() > 70 ? line.substring(0, 70) : line;
          panel.setProgress(min(panel.progress + 0.01f, 0.9f), shown);
        }
      });
      if (!ok) throw new IOException(strings.get("avrdude завершился с ошибкой", "avrdude exited with an error"));

      panel.setProgress(0.95f, strings.get("Переподключение...", "Reconnecting..."));
      Thread.sleep(2000); // board reboots back into the application after a successful flash
      saveSeenTag(latestTag);
      try { initSerial(); } catch (Throwable t2) { Log.warn("UPDATE", "Reconnect: " + t2.getMessage()); }

      panel.showDone(strings.get("Прошивка обновлена: ", "Firmware updated to ") + latestTag);
      Log.info("UPDATE", strings.get("Прошивка обновлена: ", "Firmware updated to ") + latestTag);
    } catch (Throwable t) {
      Log.error("UPDATE", "Firmware flash: " + errText(t));
      panel.showError(strings.get("Не удалось обновить прошивку: ", "Failed to update firmware: ") + errText(t));
      try { if (!serial.isConnected() && originalPort != null) serial.connect(originalPort, 115200); } catch (Throwable t2) {}
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

  // Opens the port at 1200 baud and immediately closes it (32u4/avr109 bootloader
  // touch-reset), then polls Serial.list() for up to 8s for the board re-enumerating —
  // preferring a newly-appeared port name, falling back to the original name reappearing.
  String touchResetAndFindBootloaderPort(String originalPort) throws Exception {
    String[] before = Serial.list();
    try {
      Serial touch = new Serial(papplet, originalPort, 1200);
      Thread.sleep(250);
      touch.stop();
    } catch (Exception e) {
      // some drivers throw while the port is yanked out from under them during reset — expected
      Log.debug("UPDATE", "1200-baud touch: " + e.getMessage());
    }

    long deadline = System.currentTimeMillis() + 8000;
    while (System.currentTimeMillis() < deadline) {
      Thread.sleep(200);
      String[] now = Serial.list();
      for (String p : now) {
        boolean wasThereBefore = false;
        for (String b : before) if (b.equals(p)) { wasThereBefore = true; break; }
        if (!wasThereBefore) return p;
      }
      for (String p : now) if (p.equals(originalPort)) return p;
    }
    return null;
  }

  boolean runAvrdude(String port, File hexFile, AvrdudeProgress progress) throws Exception {
    File avrdudeDir = new File(getInstallDir(), "avrdude");
    File avrdudeExe = new File(avrdudeDir, "avrdude.exe");
    File avrdudeConf = new File(avrdudeDir, "avrdude.conf");
    if (!avrdudeExe.exists()) throw new IOException("avrdude.exe not found: " + avrdudeExe.getAbsolutePath());

    ProcessBuilder pb = new ProcessBuilder(
      avrdudeExe.getAbsolutePath(),
      "-C", avrdudeConf.getAbsolutePath(),
      "-p", "atmega32u4",
      "-c", "avr109",
      "-P", port,
      "-b", "57600",
      "-D",
      "-U", "flash:w:" + hexFile.getAbsolutePath() + ":i"
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

  File getInstallDir() throws Exception {
    File jarFile = new File(FirmwareUpdater.class.getProtectionDomain().getCodeSource().getLocation().toURI());
    File appDir = jarFile.getParentFile();
    return appDir.getParentFile();
  }
}
