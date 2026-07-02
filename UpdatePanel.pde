// ============================================================
// UpdatePanel — reusable "update available / progress / done / error"
// overlay, shared by SelfUpdater (control panel app) and FirmwareUpdater
// (wheel firmware). Two independent instances are created — toastSlot
// keeps their corner toasts from overlapping if both have something to
// show. Follows the same draw()-computes-geometry / handleClick()-tests-it
// pattern as SetupWizard.
// ============================================================

class UpdatePanel {
  int colBg    = color(24, 24, 30);
  int colPanel = color(32, 32, 40);
  int colEdge  = color(55, 55, 66);
  int colText  = color(195, 200, 210);
  int colDim   = color(125, 130, 140);
  int colAcc   = color(70, 150, 230);
  int colOk    = color(60, 180, 120);
  int colWarn  = color(220, 180, 60);
  int colErr   = color(200, 70, 70);
  int colBtn   = color(50, 120, 180);
  int colBtnH  = color(65, 140, 200);
  int colBtnO  = color(58, 58, 68);

  final int HIDDEN = 0, AVAILABLE = 1, WORKING = 2, DONE = 3, ERROR = 4;
  int state = HIDDEN;

  String title = "";
  String currentLabel = "";
  String newLabel = "";
  String notes = "";
  float progress = 0;
  String statusText = "";
  ArrayList<String> logLines = new ArrayList<String>();
  String errorText = "";
  int toastSlot = 0;

  // transient click results — owner polls then resets to false
  boolean clickedUpdate = false;
  boolean clickedDismiss = false;
  boolean clickedClose = false;
  boolean clickedRetry = false;

  // geometry cached each draw() for handleClick()
  float tBtnUpdX, tBtnUpdY, tBtnUpdW, tBtnUpdH;
  float tBtnDisX, tBtnDisY, tBtnDisW, tBtnDisH;
  float mBtnCloseX, mBtnCloseY, mBtnCloseW, mBtnCloseH;
  float mBtnRetryX, mBtnRetryY, mBtnRetryW, mBtnRetryH;
  boolean toastVisible = false, modalCloseVisible = false, modalRetryVisible = false;

  void showAvailable(String title_, String cur, String neu, String notes_) {
    title = title_; currentLabel = cur; newLabel = neu; notes = notes_;
    state = AVAILABLE;
  }

  void showWorking(String title_) {
    title = title_; progress = 0; statusText = ""; logLines.clear();
    state = WORKING;
  }

  void setProgress(float p, String status) {
    progress = constrain(p, 0, 1);
    if (status != null && status.length() > 0 && !status.equals(statusText)) {
      statusText = status;
      logLines.add(status);
      if (logLines.size() > 7) logLines.remove(0);
    }
  }

  void showDone(String msg) {
    statusText = msg;
    state = DONE;
  }

  void showError(String msg) {
    errorText = msg;
    state = ERROR;
  }

  void hide() { state = HIDDEN; }
  boolean isModal() { return state == WORKING || state == ERROR; }
  boolean isActive() { return state != HIDDEN; }

  // ============ DRAW ============
  void draw() {
    toastVisible = false; modalCloseVisible = false; modalRetryVisible = false;
    if (state == HIDDEN) return;
    pushStyle();
    if (state == AVAILABLE) drawToast();
    else drawModal();
    popStyle();
  }

  void drawToast() {
    toastVisible = true;
    float w = 360, h = notes.length() > 0 ? 108 : 88;
    float x = WIN_W - w - 16;
    float y = 16 + toastSlot * (h + 10);

    fill(colPanel); stroke(colAcc); strokeWeight(1);
    rect(x, y, w, h, 8);
    fill(colAcc); noStroke();
    rect(x, y, w, 26, 8, 8, 0, 0);
    fill(255); textAlign(LEFT, CENTER); textSize(12);
    text("⬆ " + title, x + 12, y + 13);

    fill(colText); textAlign(LEFT, TOP); textSize(11);
    String verLine = currentLabel.length() > 0 ? (currentLabel + "  →  " + newLabel) : newLabel;
    text(verLine, x + 12, y + 34);
    if (notes.length() > 0) {
      fill(colDim); textSize(10);
      text(notes, x + 12, y + 52);
    }

    float bw = 100, bh = 26, bgap = 8;
    float by = y + h - bh - 8;
    tBtnUpdX = x + w - bw * 2 - bgap - 8; tBtnUpdY = by; tBtnUpdW = bw; tBtnUpdH = bh;
    tBtnDisX = x + w - bw - 8; tBtnDisY = by; tBtnDisW = bw; tBtnDisH = bh;

    drawBtn(tBtnUpdX, tBtnUpdY, tBtnUpdW, tBtnUpdH, strings.get("Обновить", "Update"), colBtn);
    drawBtn(tBtnDisX, tBtnDisY, tBtnDisW, tBtnDisH, strings.get("Позже", "Later"), colBtnO);
  }

  void drawModal() {
    fill(0, 0, 0, 170); noStroke();
    rect(0, 0, WIN_W, WIN_H);

    float pw = 460, ph = state == ERROR ? 200 : 220;
    float px = (WIN_W - pw) / 2, py = (WIN_H - ph) / 2;

    fill(colPanel); stroke(colEdge); strokeWeight(1);
    rect(px, py, pw, ph, 8);

    int barCol = state == ERROR ? colErr : colAcc;
    fill(barCol); noStroke();
    rect(px, py, pw, 38, 8, 8, 0, 0);
    fill(255); textAlign(LEFT, CENTER); textSize(14);
    text(title, px + 16, py + 19);

    float cy = py + 54;
    if (state == WORKING) {
      fill(colText); textAlign(LEFT, TOP); textSize(12);
      text(statusText, px + 16, cy);
      cy += 26;
      float barX = px + 16, barW = pw - 32, barH = 10;
      fill(colBg); noStroke(); rect(barX, cy, barW, barH, 5);
      fill(colAcc); rect(barX, cy, barW * progress, barH, 5);
      fill(colDim); textAlign(RIGHT, TOP); textSize(10);
      text(round(progress * 100) + "%", barX + barW, cy + 14);
      cy += 34;
      textAlign(LEFT, TOP); textSize(10);
      for (int i = 0; i < logLines.size(); i++) {
        fill(i == logLines.size() - 1 ? colAcc : colDim);
        text(logLines.get(i), px + 16, cy + i * 14);
      }
    } else if (state == DONE) {
      fill(colOk); textAlign(LEFT, TOP); textSize(13);
      text("✓ " + statusText, px + 16, cy, pw - 32, ph - 100);

      modalCloseVisible = true;
      float bw = 120, bh = 34;
      mBtnCloseX = px + pw - bw - 14; mBtnCloseY = py + ph - bh - 14; mBtnCloseW = bw; mBtnCloseH = bh;
      drawBtn(mBtnCloseX, mBtnCloseY, mBtnCloseW, mBtnCloseH, strings.get("Закрыть", "Close"), colBtn);
    } else if (state == ERROR) {
      fill(colErr); textAlign(LEFT, TOP); textSize(12);
      text(errorText, px + 16, cy, pw - 32, ph - 100);

      modalRetryVisible = true; modalCloseVisible = true;
      float bw = 120, bh = 34, by2 = py + ph - bh - 14;
      mBtnRetryX = px + pw - bw * 2 - 24; mBtnRetryY = by2; mBtnRetryW = bw; mBtnRetryH = bh;
      mBtnCloseX = px + pw - bw - 14; mBtnCloseY = by2; mBtnCloseW = bw; mBtnCloseH = bh;
      drawBtn(mBtnRetryX, mBtnRetryY, mBtnRetryW, mBtnRetryH, strings.get("Повторить", "Retry"), colBtn);
      drawBtn(mBtnCloseX, mBtnCloseY, mBtnCloseW, mBtnCloseH, strings.get("Закрыть", "Close"), colBtnO);
    }
  }

  void drawBtn(float x, float y, float w, float h, String label, int baseCol) {
    boolean hov = mouseX >= x && mouseX <= x + w && mouseY >= y && mouseY <= y + h;
    fill(hov ? colBtnH : baseCol); noStroke();
    rect(x, y, w, h, 4);
    fill(255); textAlign(CENTER, CENTER); textSize(11);
    text(label, x + w / 2, y + h / 2);
  }

  // ============ CLICK (called from main sketch mousePressed) ============
  // Returns true if the click was consumed (caller should stop propagating it).
  boolean handleClick() {
    if (state == HIDDEN) return false;
    if (toastVisible) {
      if (hit(tBtnUpdX, tBtnUpdY, tBtnUpdW, tBtnUpdH)) { clickedUpdate = true; return true; }
      if (hit(tBtnDisX, tBtnDisY, tBtnDisW, tBtnDisH)) { clickedDismiss = true; return true; }
      return false;
    }
    if (state == ERROR) {
      if (modalRetryVisible && hit(mBtnRetryX, mBtnRetryY, mBtnRetryW, mBtnRetryH)) { clickedRetry = true; return true; }
      if (modalCloseVisible && hit(mBtnCloseX, mBtnCloseY, mBtnCloseW, mBtnCloseH)) { clickedClose = true; return true; }
    }
    if (state == DONE) {
      if (modalCloseVisible && hit(mBtnCloseX, mBtnCloseY, mBtnCloseW, mBtnCloseH)) { clickedClose = true; return true; }
    }
    // WORKING is click-eating but has no interactive elements
    return isModal();
  }

  boolean hit(float x, float y, float w, float h) {
    return mouseX >= x && mouseX <= x + w && mouseY >= y && mouseY <= y + h;
  }
}
