// Вкладка «Шифтер» — H-образный кулисный переключатель.
// Реальные команды прошивки: калибровка HA..HE, конфиг HF (биты),
// сохранение HG, сброс HR. Живая позиция X/Y — из HID.
class ShifterTab {
  float cx, cy, cw, ch;

  // калибровочные точки (0..1023): A,B,C — делители по X; D,E — верх/низ по Y
  float[] cal = { 255, 511, 767, 300, 720 };
  String[] calLbl;
  String[] calCmd = { "HA ", "HB ", "HC ", "HD ", "HE " };

  // конфиг (биты sConfig): 0 реверс инверт, 1 реверс в 8-й, 2 X инверт, 3 Y инверт
  boolean revInverted = false, reverseIn8th = false, xInverted = false, yInverted = false;

  float liveX = 512, liveY = 512;

  int colBg = color(24, 24, 30), colEdge = color(55, 55, 66);
  int colText = color(195, 200, 210), colDim = color(125, 130, 140), colAcc = color(70, 150, 230);

  float mapX, mapY, mapW, mapH;     // зона карты передач
  float rpX, rpY, rpW;              // правая панель
  int dragCal = -1;

  int langVer = -1;   // последняя версия strings, для которой пересобран calLbl

  ShifterTab(float cx, float cy, float cw, float ch) {
    this.cx = cx; this.cy = cy; this.cw = cw; this.ch = ch;
    refreshLabels();
  }

  void refreshLabels() {
    calLbl = new String[]{ strings.get("A — граница X 1", "A — X boundary 1"), strings.get("B — граница X 2", "B — X boundary 2"), strings.get("C — граница X 3", "C — X boundary 3"), strings.get("D — верх Y", "D — top Y"), strings.get("E — низ Y", "E — bottom Y") };
    langVer = strings.version;
  }

  void draw() {
    if (langVer != strings.version) refreshLabels();
    pushStyle();
    textAlign(LEFT, TOP);
    // NOTE: Shifter X/Y are hardcoded to physical axes 3 (RX) and 4 (RY).
    // This is a known limitation — the shifter assumes these axes are not
    // reassigned to other roles (e.g. clutch, handbrake) by the user.
    // A future fix should resolve axes from a configurable shifterAxisX/Y setting.
    liveX = (axes[3].rawValue + 1) / 2.0 * 1023;
    liveY = (axes[4].rawValue + 1) / 2.0 * 1023;

    fill(colText); textSize(15);
    text(strings.get("Аналоговый H-шифтер (8 передач + реверс)", "Analog H-Shifter (8 gears + reverse)"), cx + 12, cy + 10);

    mapX = cx + 12; mapY = cy + 40; mapW = 460; mapH = ch - 52;
    rpX = cx + 12 + mapW + 12; rpY = cy + 40; rpW = cw - mapW - 36;
    drawGearMap();
    drawRight();
    popStyle();
  }

  void panel(float x, float y, float w, float h, String t) {
    fill(colBg); stroke(colEdge); strokeWeight(1); rect(x, y, w, h, 6);
    fill(colDim); textAlign(LEFT, TOP); textSize(12); text(t, x + 10, y + 8);
  }

  void drawGearMap() {
    panel(mapX, mapY, mapW, mapH, strings.get("Карта передач (живая позиция)", "Gear Map (Live Position)"));
    float gx = mapX + 16, gy = mapY + 34, gw = mapW - 32, gh = mapH - 60;
    fill(15, 15, 22); stroke(colEdge); rect(gx, gy, gw, gh, 4);

    float nA = gw * cal[0] / 1023.0, nB = gw * cal[1] / 1023.0, nC = gw * cal[2] / 1023.0;
    float nE = gh * 0.5;
    int[] zc = { color(40, 60, 40), color(60, 40, 40), color(40, 40, 60), color(58, 58, 35) };
    String[] g = { "1", "2", "3", "4", "5", "6", "7", "8" };
    float[] xx = { 0, 0, nA, nA, nB, nB, nC, nC };
    float[] yy = { 0, nE, 0, nE, 0, nE, 0, nE };
    float[] ww = { nA, nA, nB - nA, nB - nA, nC - nB, nC - nB, gw - nC, gw - nC };
    float[] hh = { nE, gh - nE, nE, gh - nE, nE, gh - nE, nE, gh - nE };
    for (int i = 0; i < 8; i++) {
      fill(zc[i / 2]); noStroke(); rect(gx + xx[i], gy + yy[i], ww[i], hh[i]);
      fill(180); textAlign(CENTER, CENTER); textSize(16); text(g[i], gx + xx[i] + ww[i] / 2, gy + yy[i] + hh[i] / 2);
    }
    stroke(190, 190, 90); strokeWeight(1);
    line(gx + nA, gy, gx + nA, gy + gh); line(gx + nB, gy, gx + nB, gy + gh);
    line(gx + nC, gy, gx + nC, gy + gh); line(gx, gy + nE, gx + gw, gy + nE);

    float lx = gw * constrain(liveX, 0, 1023) / 1023.0, ly = gh * constrain(liveY, 0, 1023) / 1023.0;
    stroke(255, 90, 45); strokeWeight(2);
    line(gx + lx - 7, gy + ly, gx + lx + 7, gy + ly);
    line(gx + lx, gy + ly - 7, gx + lx, gy + ly + 7);
    fill(255, 90, 45); noStroke(); ellipse(gx + lx, gy + ly, 9, 9);

    tipZone(gx, gy, gw, gh, strings.get("Жёлтые линии — границы передач (двигаются калибровкой справа). Оранжевый крест — текущее положение рычага шифтера.", "Yellow lines — gear boundaries (moved by the calibration sliders on the right). Orange cross — current shifter lever position."));
  }

  void drawRight() {
    panel(rpX, rpY, rpW, ch - 52, strings.get("Калибровка и настройка", "Calibration & Settings"));

    // калибровка
    float y = rpY + 34;
    fill(colDim); textAlign(LEFT, TOP); textSize(10);
    text(strings.get("Перетащите границы. Применяется при отпускании.", "Drag boundaries. Applied on release."), rpX + 12, y); y += 18;
    for (int i = 0; i < 5; i++) {
      drawCalSlider(i, rpX + 12, y, rpW - 24); y += 40;
    }

    // конфиг-тогглы
    y += 6;
    fill(colDim); textAlign(LEFT, TOP); textSize(11); text(strings.get("Настройки шифтера:", "Shifter settings:"), rpX + 12, y); y += 18;
    drawToggle(rpX + 12, y, strings.get("Реверс в 8-й передаче", "Reverse in 8th gear"), reverseIn8th,
      strings.get("ВКЛ — 8 передач, реверс на месте 8-й. ВЫКЛ — 6 передач + реверс.", "ON — 8 gears, reverse at 8th. OFF — 6 gears + reverse.")); y += 26;
    drawToggle(rpX + 12, y, strings.get("Инвертировать кнопку реверса", "Invert reverse button"), revInverted,
      strings.get("Для рычагов Logitech G25/G27/G29/G923, где кнопка реверса работает наоборот.", "For Logitech G25/G27/G29/G923 where reverse button works opposite.")); y += 26;
    drawToggle(rpX + 12, y, strings.get("Инвертировать ось X", "Invert X axis"), xInverted, strings.get("Если передачи 1/2 и 7/8 перепутаны местами.", "If gears 1/2 and 7/8 are swapped.")); y += 26;
    drawToggle(rpX + 12, y, strings.get("Инвертировать ось Y", "Invert Y axis"), yInverted, strings.get("Если верхний и нижний ряды передач перепутаны.", "If top and bottom gear rows are swapped.")); y += 30;

    // сброс (сохранение теперь автоматическое — см. WheelProtocol.markDirty)
    smlBtn(rpX + 12, y, rpW - 24, 26, strings.get("Сброс калибровки шифтера", "Reset Shifter Calibration"), color(110, 60, 50));
    tipZone(rpX + 12, y, rpW - 24, 26, strings.get("Сбросить калибровку шифтера к значениям по умолчанию.", "Reset shifter calibration to defaults."));
  }

  void drawCalSlider(int i, float x, float y, float w) {
    float ratio = constrain(cal[i] / 1023.0, 0, 1);
    fill(colText); textAlign(LEFT, TOP); textSize(10); text(calLbl[i], x, y);
    fill(colAcc); textAlign(RIGHT, TOP); textSize(11); text(int(cal[i]), x + w, y - 1);
    float sy = y + 18;
    fill(20); noStroke(); rect(x, sy, w, 6, 3);
    fill(colAcc); rect(x, sy, w * ratio, 6, 3);
    fill(230); ellipse(x + w * ratio, sy + 3, 12, 12);
  }

  void drawToggle(float x, float y, String label, boolean on, String tip) {
    fill(on ? color(70, 180, 100) : color(45, 47, 56)); stroke(colEdge); rect(x, y, 34, 17, 8);
    fill(255); noStroke(); ellipse(on ? x + 25 : x + 9, y + 8, 13, 13);
    fill(colText); textAlign(LEFT, CENTER); textSize(11); text(label, x + 44, y + 8);
    tipZone(x, y - 2, rpW - 24, 22, tip);
  }

  void smlBtn(float x, float y, float w, float h, String label, int bg) {
    boolean hov = mouseX >= x && mouseX <= x + w && mouseY >= y && mouseY <= y + h;
    fill(hov ? lerpColor(bg, color(255), 0.18) : bg); stroke(colEdge); rect(x, y, w, h, 4);
    fill(230); noStroke(); textAlign(CENTER, CENTER); textSize(10); text(label, x + w / 2, y + h / 2);
  }

  int buildConfig() {
    int c = 0;
    if (revInverted) c |= (1 << 0);
    if (reverseIn8th) c |= (1 << 1);
    if (xInverted) c |= (1 << 2);
    if (yInverted) c |= (1 << 3);
    return c;
  }
  void sendConfig() { proto.setParam("HF ", buildConfig()); proto.update(); }

  // геометрия строк калибровки (для попадания)
  float calRowY(int i) { return rpY + 34 + 18 + i * 40 + 18; }

  void handleClick() {
    // тогглы
    float y = rpY + 34 + 18 + 5 * 40 + 6 + 18;
    if (toggleHit(y)) { reverseIn8th = !reverseIn8th; sendConfig(); return; } y += 26;
    if (toggleHit(y)) { revInverted = !revInverted; sendConfig(); return; } y += 26;
    if (toggleHit(y)) { xInverted = !xInverted; sendConfig(); return; } y += 26;
    if (toggleHit(y)) { yInverted = !yInverted; sendConfig(); return; } y += 30;
    // сброс
    if (mouseY >= y && mouseY <= y + 26 && mouseX >= rpX + 12 && mouseX <= rpX + rpW - 12) {
      cal[0] = 255; cal[1] = 511; cal[2] = 767; cal[3] = 300; cal[4] = 720;
      proto.sendNow("HR"); proto.requestAutosave("HG"); Log.info("SHIFTER", strings.get("Сброс калибровки", "Calibration reset")); return;
    }
  }
  boolean toggleHit(float y) { return mouseX >= rpX + 12 && mouseX <= rpX + rpW - 24 && mouseY >= y && mouseY <= y + 17; }

  void handlePress() {
    for (int i = 0; i < 5; i++) {
      float sy = calRowY(i);
      if (mouseX >= rpX + 12 - 6 && mouseX <= rpX + rpW - 12 + 6 && mouseY >= sy - 9 && mouseY <= sy + 15) {
        dragCal = i; applyDrag(); return;
      }
    }
  }
  void handleDrag() { if (dragCal >= 0) applyDrag(); }
  void applyDrag() {
    float x = rpX + 12, w = rpW - 24;
    float ratio = constrain((mouseX - x) / w, 0, 1);
    cal[dragCal] = round(ratio * 1023);
  }
  void handleRelease() {
    if (dragCal >= 0) {
      proto.setParam(calCmd[dragCal], int(cal[dragCal]));
      Log.info("SHIFTER", calLbl[dragCal] + " = " + int(cal[dragCal]));
    }
    dragCal = -1;
  }
}
