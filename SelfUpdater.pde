// ============================================================
// SelfUpdater — checks GitHub for a newer control-panel build, downloads
// + extracts it, and relaunches the app from the new copy.
//
// Update application while running: the running WheelControlApp.exe/app/*.jar
// can't be overwritten in place on Windows (file lock), so we download+extract
// the new build to a temp folder, spawn a detached .bat that waits out any
// remaining file lock via robocopy's own retry loop, copies the new files over
// the install dir (skipping data/ so COM_cfg.txt/axis_roles.txt/logs survive),
// relaunches the exe, then this process exits.
// ============================================================

class SelfUpdater {
  static final String REPO = "bitwiresys/Arduino-FFB-gui-v3";
  Http http = new Http();
  UpdatePanel panel = new UpdatePanel();

  String currentBuildTag = "";
  String latestTag = "";
  String downloadUrl = "";
  boolean checked = false;
  boolean busy = false;

  SelfUpdater() {
    panel.toastSlot = 0;
    loadCurrentBuild();
  }

  void loadCurrentBuild() {
    try {
      File f = new File(dataPath("build_info.txt"));
      if (f.exists()) {
        String[] lines = loadStrings("build_info.txt");
        if (lines != null && lines.length > 0) currentBuildTag = trim(lines[0]);
      }
    } catch (Throwable t) {
      Log.warn("UPDATE", "build_info.txt: " + errText(t));
    }
  }

  // "gui-build-12" -> 12; missing/unparsable (e.g. local dev build) -> -1,
  // which never triggers an update prompt (we can't tell if we're behind).
  int buildNumber(String tag) {
    if (tag == null || tag.length() == 0) return -1;
    int i = tag.lastIndexOf('-');
    if (i < 0) return -1;
    try { return Integer.parseInt(tag.substring(i + 1)); }
    catch (Exception e) { return -1; }
  }

  void checkForUpdate() {
    if (checked || busy) return;
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
      downloadUrl = "";
      for (int i = 0; i < assets.size(); i++) {
        JSONObject a = assets.getJSONObject(i);
        String n = a.getString("name");
        if (n.toLowerCase().endsWith(".zip")) { downloadUrl = a.getString("browser_download_url"); break; }
      }
      int cur = buildNumber(currentBuildTag);
      int latest = buildNumber(latestTag);
      Log.info("UPDATE", strings.get("Панель: текущая ", "Panel: current ") + (currentBuildTag.length() > 0 ? currentBuildTag : "?") +
        strings.get(", последняя ", ", latest ") + latestTag);
      if (downloadUrl.length() > 0 && cur >= 0 && latest > cur) {
        panel.showAvailable(strings.get("Обновление панели управления", "Control panel update"),
          currentBuildTag, latestTag, "");
      }
    } catch (Throwable t) {
      Log.warn("UPDATE", strings.get("Проверка обновлений панели не удалась: ", "Panel update check failed: ") + errText(t));
    } finally {
      checked = true;
      busy = false;
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
    panel.showWorking(strings.get("Обновление панели управления", "Updating control panel"));
    Thread t = new Thread(new Runnable() {
      public void run() { doUpdate(); }
    });
    t.setDaemon(true);
    t.start();
  }

  void doUpdate() {
    try {
      panel.setProgress(0.05f, strings.get("Загрузка...", "Downloading..."));
      File tmpZip = new File(System.getProperty("java.io.tmpdir"), "wheelcontrol_update.zip");
      http.downloadFile(downloadUrl, tmpZip, new HttpProgress() {
        public void onProgress(long downloaded, long total) {
          float frac = total > 0 ? (float) downloaded / total : 0;
          panel.setProgress(0.05f + 0.55f * frac,
            strings.get("Загрузка: ", "Downloading: ") + (downloaded / 1024 / 1024) + "MB" +
            (total > 0 ? ("/" + (total / 1024 / 1024) + "MB") : ""));
        }
      });

      panel.setProgress(0.65f, strings.get("Распаковка...", "Extracting..."));
      File extractDir = new File(System.getProperty("java.io.tmpdir"), "wheelcontrol_update_extracted");
      deleteRecursive(extractDir);
      extractZipSkippingData(tmpZip, extractDir);
      tmpZip.delete();

      panel.setProgress(0.85f, strings.get("Подготовка перезапуска...", "Preparing restart..."));
      File installDir = getInstallDir();
      File updaterBat = writeUpdaterBatch(extractDir, installDir, "WheelControlApp.exe");

      ProcessBuilder pb = new ProcessBuilder("cmd.exe", "/c", updaterBat.getAbsolutePath());
      pb.directory(installDir);
      pb.start();

      panel.setProgress(1.0f, strings.get("Готово, перезапуск...", "Done, restarting..."));
      panel.showDone(strings.get("Обновление скачано — панель перезапустится через пару секунд", "Update downloaded — the panel will restart in a moment"));
      Log.info("UPDATE", strings.get("Панель обновлена, перезапуск через updater.bat", "Panel updated, restarting via updater.bat"));
      Thread.sleep(800);
      System.exit(0);
    } catch (Throwable t) {
      Log.error("UPDATE", "Self-update: " + errText(t));
      panel.showError(strings.get("Не удалось обновить панель: ", "Failed to update control panel: ") + errText(t));
    }
  }

  File getInstallDir() throws Exception {
    File jarFile = new File(SelfUpdater.class.getProtectionDomain().getCodeSource().getLocation().toURI());
    // jarFile ~= WheelControlApp/app/wheel_control_v3.jar (jpackage app-image layout)
    File appDir = jarFile.getParentFile();
    return appDir.getParentFile();
  }

  // Skips everything under data/ EXCEPT build_info.txt - that file is the whole reason
  // this method exists to skip data/ at all (avoid clobbering the user's COM_cfg.txt,
  // axis_roles.txt, logs), but it's also the version marker this exact update mechanism
  // depends on. Skipping it unconditionally meant every update "succeeded" while leaving
  // the old build number in place, so the app kept re-detecting the same update forever.
  void extractZipSkippingData(File zipFile, File destDir) throws IOException {
    destDir.mkdirs();
    ZipInputStream zis = new ZipInputStream(new FileInputStream(zipFile));
    ZipEntry entry;
    byte[] buf = new byte[32768];
    while ((entry = zis.getNextEntry()) != null) {
      String name = entry.getName().replace('\\', '/');
      boolean isDataPath = name.equals("data") || name.startsWith("data/");
      boolean isBuildInfo = name.equals("data/build_info.txt");
      if (isDataPath && !isBuildInfo) { zis.closeEntry(); continue; }
      File outFile = new File(destDir, name);
      if (entry.isDirectory()) {
        outFile.mkdirs();
      } else {
        File outParent = outFile.getParentFile();
        if (outParent != null) outParent.mkdirs();
        FileOutputStream fos = new FileOutputStream(outFile);
        int n;
        while ((n = zis.read(buf)) != -1) fos.write(buf, 0, n);
        fos.close();
      }
      zis.closeEntry();
    }
    zis.close();
  }

  void deleteRecursive(File f) {
    if (f == null || !f.exists()) return;
    if (f.isDirectory()) {
      File[] children = f.listFiles();
      if (children != null) for (File c : children) deleteRecursive(c);
    }
    f.delete();
  }

  // robocopy's own /R retry loop absorbs the race between our exit() and the
  // OS actually releasing the file lock on the old exe/jars — no PID polling needed.
  File writeUpdaterBatch(File srcDir, File destDir, String exeName) throws IOException {
    File bat = new File(System.getProperty("java.io.tmpdir"), "wheelcontrol_apply_update.bat");
    StringBuilder sb = new StringBuilder();
    sb.append("@echo off\r\n");
    // No /XD "data" here: the staging tree's data/ folder only ever contains
    // build_info.txt (extractZipSkippingData already dropped everything else under
    // data/ before this runs), so copying it is exactly the point - it's the new
    // version marker. Plain robocopy /E only touches files present in the source,
    // so the user's own data/ files (COM_cfg.txt, logs, etc.) are untouched.
    sb.append("robocopy \"" + srcDir.getAbsolutePath() + "\" \"" + destDir.getAbsolutePath() + "\" /E /R:20 /W:1 /NFL /NDL /NJH /NJS\r\n");
    sb.append("start \"\" \"" + new File(destDir, exeName).getAbsolutePath() + "\"\r\n");
    sb.append("rmdir /s /q \"" + srcDir.getAbsolutePath() + "\" >nul 2>nul\r\n");
    sb.append("del \"%~f0\" >nul 2>nul\r\n");
    PrintWriter pw = new PrintWriter(bat, "UTF-8");
    pw.print(sb.toString());
    pw.close();
    return bat;
  }
}
