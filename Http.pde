// ============================================================
// Http — minimal GET / download-with-progress helpers used by
// SelfUpdater and FirmwareUpdater to talk to the GitHub API and
// download release assets. No external HTTP library dependency —
// java.net.HttpURLConnection only.
// ============================================================

interface HttpProgress {
  void onProgress(long downloaded, long total);
}

// getMessage() is null for plenty of exceptions (NPE, some IOExceptions) — always
// show something diagnosable in the log / error dialog instead of a blank string.
String errText(Throwable t) {
  String m = t.getMessage();
  return (m != null && m.length() > 0) ? m : t.getClass().getSimpleName();
}

class Http {
  static final String USER_AGENT = "Arduino-FFB-Wheel-Control-Panel";

  // PApplet.runSketch() forces java.net.useSystemProxies=true on every Processing
  // sketch (regardless of any -D flag passed on the command line, since it calls
  // System.setProperty() itself at startup). On machines where the Windows system
  // proxy/WPAD config is broken or points to a SOCKS proxy that doesn't resolve
  // cleanly, this makes every HttpURLConnection fail before sending a single byte
  // (observed: UnknownHostException / "Can't connect to SOCKS proxy"). Passing
  // Proxy.NO_PROXY to openConnection() is NOT enough to work around it — the
  // property still gets consulted deeper down. Flipping it back to false right
  // before connecting is what actually fixes it.
  void disableSystemProxies() {
    System.setProperty("java.net.useSystemProxies", "false");
  }

  // Blocking GET, returns response body as a String. Throws on network error
  // or non-2xx status (message includes the body, useful for GitHub API errors).
  String getString(String urlStr) throws IOException {
    disableSystemProxies();
    HttpURLConnection conn = (HttpURLConnection) new URL(urlStr).openConnection();
    conn.setRequestProperty("User-Agent", USER_AGENT);
    conn.setRequestProperty("Accept", "application/vnd.github+json");
    conn.setConnectTimeout(8000);
    conn.setReadTimeout(15000);
    int code = conn.getResponseCode();
    InputStream in = (code >= 200 && code < 300) ? conn.getInputStream() : conn.getErrorStream();
    String body = readAll(in);
    conn.disconnect();
    if (code < 200 || code >= 300) throw new IOException("HTTP " + code + ": " + body);
    return body;
  }

  // Blocking download of a URL (follows redirects — GitHub asset URLs redirect
  // to an objects.githubusercontent.com CDN link) into destFile, reporting
  // progress via listener (may be null). Caller is expected to run this off
  // the render thread.
  void downloadFile(String urlStr, File destFile, HttpProgress listener) throws IOException {
    disableSystemProxies();
    HttpURLConnection conn = (HttpURLConnection) new URL(urlStr).openConnection();
    conn.setRequestProperty("User-Agent", USER_AGENT);
    conn.setInstanceFollowRedirects(true);
    conn.setConnectTimeout(8000);
    conn.setReadTimeout(20000);
    int code = conn.getResponseCode();
    if (code < 200 || code >= 300) {
      String body = readAll(conn.getErrorStream());
      conn.disconnect();
      throw new IOException("HTTP " + code + ": " + body);
    }
    long total = conn.getContentLengthLong();

    File destParent = destFile.getParentFile();
    if (destParent != null) destParent.mkdirs();

    InputStream in = conn.getInputStream();
    FileOutputStream out = new FileOutputStream(destFile);
    byte[] chunk = new byte[32768];
    long downloaded = 0;
    int n;
    while ((n = in.read(chunk)) != -1) {
      out.write(chunk, 0, n);
      downloaded += n;
      if (listener != null) listener.onProgress(downloaded, total);
    }
    out.close();
    in.close();
    conn.disconnect();
  }

  String readAll(InputStream in) throws IOException {
    if (in == null) return "";
    ByteArrayOutputStream buf = new ByteArrayOutputStream();
    byte[] chunk = new byte[8192];
    int n;
    while ((n = in.read(chunk)) != -1) buf.write(chunk, 0, n);
    in.close();
    return new String(buf.toByteArray(), "UTF-8");
  }
}
