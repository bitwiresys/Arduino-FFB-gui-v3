// Вкладка «Энкодер» — реальные данные: угол руля из HID (по rotation),
// скорость и RPM, настройка CPR (команда O), сброс Z-индекса (команда Z).
class EncoderTab {
  float contentX, contentY, contentW, contentH;

  float position = 0.0;   // градусы (реальный угол)
  float prevPos = 0.0;
  float velocity = 0.0;   // град/с
  float rpm = 0.0;
  int cpr = 4096;
  int lastUpdateTime = 0;

  boolean cprEditing = false;
  String cprInput = "";

  float[] rpmHistory = new float[120];
  int rpmHistIdx = 0;

  int colBg = color(24, 24, 30), colEdge = color(55, 55, 66);
  int colText = color(195, 200, 210), colDim = color(125, 130, 140), colAcc = color(70, 150, 230);
  int[] cprPresets = { 600, 1024, 2400, 4096 };

  // геометрия панели CPR (для кликов)
  float cprX, cprY, cprW, cprH;

  EncoderTab(float cx, float cy, float cw, float ch) {
    contentX = cx; contentY = cy; contentW = cw; contentH = ch;
  }

  void update(float angleDeg) {
    position = angleDeg;
    int now = millis();
    float dt = (now - lastUpdateTime) / 1000.0;
    if (dt > 0) velocity = (position - prevPos) / dt;        // град/с
    prevPos = position;
    lastUpdateTime = now;
    rpm = abs(velocity) / 360.0 * 60.0;
    rpmHistory[rpmHistIdx] = rpm;
    rpmHistIdx = (rpmHistIdx + 1) % rpmHistory.length;
  }

  void panel(float x, float y, float w, float h, String t) {
    fill(colBg); stroke(colEdge); strokeWeight(1); rect(x, y, w, h, 6);
    fill(colDim); textAlign(LEFT, TOP); textSize(12); text(t, x + 10, y + 8);
  }

  void draw(FirmwareParser fw) {
    pushStyle();
    textAlign(LEFT, TOP);
    fill(colText); textSize(15);
    text(strings.get("Энкодер: положение, скорость, настройка", "Encoder: position, speed, settings"), contentX + 12, contentY + 10);

    float top = contentY + 40;
    drawDial(contentX + 12, top, 360, 360);
    drawLive(contentX + 384, top, 300, 170, fw);
    drawCPR(contentX + 384, top + 184, 300, 176);
    drawRPMGraph(contentX + 696, top, contentW - 696 - 12, 360);
    popStyle();
  }

  // ---- круговой индикатор угла ----
  void drawDial(float x, float y, float w, float h) {
    panel(x, y, w, h, strings.get("Угол руля", "Wheel Angle"));
    float ccx = x + w / 2, ccy = y + h / 2 + 6, r = 130;
    noFill(); stroke(colEdge); strokeWeight(2); ellipse(ccx, ccy, r * 2, r * 2);
    stroke(70); strokeWeight(1);
    for (int i = 0; i < 36; i++) {
      float a = i * 10 * PI / 180.0 - PI / 2;
      float ir = (i % 9 == 0) ? r * 0.78 : r * 0.9;
      line(ccx + cos(a) * ir, ccy + sin(a) * ir, ccx + cos(a) * r * 0.97, ccy + sin(a) * r * 0.97);
    }
    float na = radians(position) - PI / 2;
    stroke(255, 110, 60); strokeWeight(3);
    line(ccx, ccy, ccx + cos(na) * r * 0.82, ccy + sin(na) * r * 0.82);
    fill(255, 110, 60); noStroke(); ellipse(ccx, ccy, 12, 12);
    fill(colText); textAlign(CENTER, CENTER); textSize(30);
    text(nf(position, 1, 1) + "°", ccx, ccy + r * 0.45);
    tipZone(x, y, w, h, strings.get("Реальный угол поворота руля, рассчитанный из показаний энкодера и заданного диапазона «Поворот руля».", "Real wheel rotation angle, computed from the encoder reading and the configured “Rotation” range."));
  }

  // ---- живые данные ----
  void drawLive(float x, float y, float w, float h, FirmwareParser fw) {
    panel(x, y, w, h, strings.get("Данные в реальном времени", "Live Data"));
    float sy = y + 34;
    row(x, sy, w, strings.get("Положение", "Position"), nf(position, 1, 1) + " °", color(100, 200, 120)); sy += 30;
    row(x, sy, w, strings.get("Скорость", "Velocity"), nf(velocity, 1, 0) + " °/s", color(200, 170, 90)); sy += 30;
    row(x, sy, w, strings.get("Обороты", "RPM"), nf(rpm, 1, 1) + " rpm", color(200, 130, 90)); sy += 30;
    String enc = (fw == null) ? "?" : (fw.magneticEncoder ? "AS5600 (" + strings.get("магнитный", "magnetic") + ")" : (fw.noOpticalEncoder ? strings.get("потенциометр", "potentiometer") : strings.get("оптический", "optical")));
    row(x, sy, w, strings.get("Тип энкодера", "Encoder type"), enc, colDim);
    tipZone(x, y, w, h, strings.get("Скорость и обороты считаются по изменению угла. Тип энкодера определяется прошивкой автоматически и не настраивается тут.", "Velocity and RPM are derived from the angle change. Encoder type is auto-detected by the firmware and isn't configurable here."));
  }
  void row(float x, float y, float w, String k, String v, int vc) {
    fill(colDim); textAlign(LEFT, TOP); textSize(11); text(k, x + 12, y);
    fill(vc); textAlign(RIGHT, TOP); textSize(13); text(v, x + w - 12, y - 1);
  }

  // ---- CPR ----
  void drawCPR(float x, float y, float w, float h) {
    cprX = x; cprY = y; cprW = w; cprH = h;
    panel(x, y, w, h, strings.get("CPR энкодера", "Encoder CPR"));
    fill(cprEditing ? colAcc : colText); textAlign(CENTER, TOP); textSize(34);
    text(cprEditing ? cprInput + "_" : str(cpr), x + w / 2, y + 30);
    fill(colDim); textAlign(CENTER, TOP); textSize(9);
    text(strings.get("кликните по числу, чтобы ввести вручную (Enter — применить)", "click number to type manually (Enter to apply)"), x + w / 2, y + 74);

    float by = y + 96, bw = (w - 24 - 3 * 6) / 4.0;
    for (int i = 0; i < 4; i++) {
      float bx = x + 12 + i * (bw + 6);
      boolean on = cpr == cprPresets[i];
      smlBtn(bx, by, bw, 24, str(cprPresets[i]), on ? color(50, 110, 160) : color(45, 47, 56));
    }
    tipZone(x + 12, by, w - 24, 24, strings.get("Готовые значения CPR для распространённых энкодеров.", "Common CPR presets for popular encoders."));
    float sy = by + 30;
    smlBtn(x + 12, sy, 46, 22, "−100", color(60, 50, 50));
    smlBtn(x + 64, sy, 46, 22, "+100", color(50, 60, 50));
    tipZone(x + 12, sy, 98, 22, strings.get("Подстроить CPR на ±100 за клик.", "Fine-tune CPR by ±100 per click."));
    smlBtn(x + w - 130, sy, 130, 22, strings.get("Сброс Z-индекса", "Reset Z-index"), color(70, 80, 110));
    tipZone(x, y, w, 90, strings.get("CPR = 4 × PPR × передаточное число. Для AS5600 = 4096. Меняется сразу в Arduino.", "CPR = 4 × PPR × gear ratio. For AS5600 = 4096. Applied to Arduino immediately."));
    tipZone(x + w - 130, sy, 130, 22, strings.get("Сбросить смещение Z-индекса энкодера к нулю.", "Reset the encoder's Z-index offset to zero."));
  }

  void drawRPMGraph(float x, float y, float w, float h) {
    panel(x, y, w, h, strings.get("История оборотов", "RPM History"));
    float gx = x + 12, gy = y + 32, gw = w - 24, gh = h - 60;
    fill(15, 15, 22); stroke(colEdge); rect(gx, gy, gw, gh, 3);
    float maxR = 1;
    for (int i = 0; i < rpmHistory.length; i++) maxR = max(maxR, rpmHistory[i]);
    noStroke();
    float bw = gw / rpmHistory.length;
    for (int i = 0; i < rpmHistory.length; i++) {
      int idx = (rpmHistIdx + i) % rpmHistory.length;
      float bh = rpmHistory[idx] / maxR * (gh - 6);
      fill(80, 170, 240, 170); rect(gx + i * bw, gy + gh - bh, bw - 1, bh);
    }
    fill(colText); textAlign(CENTER, BOTTOM); textSize(22);
    text(nf(rpm, 1, 0) + strings.get(" об/мин", " rpm"), x + w / 2, y + h - 8);
    tipZone(x, y, w, h, strings.get("График скорости вращения руля за последние секунды. Удобно проверять плавность хода.", "Wheel rotation speed graph over the last few seconds. Useful for checking smoothness of travel."));
  }

  void smlBtn(float x, float y, float w, float h, String label, int bg) {
    boolean hov = mouseX >= x && mouseX <= x + w && mouseY >= y && mouseY <= y + h;
    fill(hov ? lerpColor(bg, color(255), 0.18) : bg); stroke(colEdge); rect(x, y, w, h, 4);
    fill(230); noStroke(); textAlign(CENTER, CENTER); textSize(10); text(label, x + w / 2, y + h / 2);
  }

  void handleClick() {
    // число CPR — режим ввода
    if (mouseX >= cprX && mouseX <= cprX + cprW && mouseY >= cprY + 24 && mouseY <= cprY + 70) {
      cprEditing = true; cprInput = ""; return;
    }
    // пресеты
    float by = cprY + 96, bw = (cprW - 24 - 3 * 6) / 4.0;
    for (int i = 0; i < 4; i++) {
      float bx = cprX + 12 + i * (bw + 6);
      if (mouseX >= bx && mouseX <= bx + bw && mouseY >= by && mouseY <= by + 24) {
        cpr = cprPresets[i]; proto.setCPR(cpr); Log.info("ENCODER", "CPR = " + cpr); return;
      }
    }
    // степпер / сброс Z
    float sy = by + 30;
    if (mouseY >= sy && mouseY <= sy + 22) {
      if (mouseX >= cprX + 12 && mouseX <= cprX + 58) { cpr = max(4, cpr - 100); proto.setCPR(cpr); return; }
      if (mouseX >= cprX + 64 && mouseX <= cprX + 110) { cpr = cpr + 100; proto.setCPR(cpr); return; }
      if (mouseX >= cprX + cprW - 130 && mouseX <= cprX + cprW) { proto.resetZIndex(); Log.info("ENCODER", strings.get("Сброс Z", "Z-index reset")); return; }
    }
  }

  void handleKey(char k) {
    if (!cprEditing) return;
    if (k == BACKSPACE) { if (cprInput.length() > 0) cprInput = cprInput.substring(0, cprInput.length() - 1); }
    else if (k == ENTER || k == RETURN) {
      if (cprInput.length() > 0) { cpr = constrain(int(cprInput), 4, 99999); proto.setCPR(cpr); Log.info("ENCODER", "CPR = " + cpr); } // мин. 4 — как constrain в прошивке
      cprEditing = false;
    } else if (k == ESCAPE) { cprEditing = false; }
    else if (k >= '0' && k <= '9' && cprInput.length() < 5) { cprInput += k; }
  }
}
