// Вкладка «Настройки» — конфигурация ШИМ (команда W) и профили (файлы на ПК).
class SettingsTab {
  float cx, cy, cw, ch;

  int colBg = color(24, 24, 30), colEdge = color(55, 55, 66);
  int colText = color(195, 200, 210), colDim = color(125, 130, 140), colAcc = color(70, 150, 230);

  int pwmType = 0;   // 0 Fast, 1 Phase correct
  int pwmMode = 0;   // 0 PWM+-, 1 PWM+dir, 2 PWM 0-50-100
  int pwmFreq = 1;   // индекс
  boolean pwmUserEdited = false;

  String[] typeNames = { "Fast PWM", "Phase correct" };
  String[] modeNames;
  String[] freqNames = { "40 kHz", "20 kHz", "16 kHz", "8 kHz", "4 kHz", "3.2 kHz", "1.6 kHz", "976 Hz", "800 Hz", "488 Hz" };

  int NSLOTS = 8;
  int selSlot = 0;

  float pwmX, pwmY, pwmW, pwmH, prX, prY, prW, prH;

  int langVer = -1;   // последняя версия strings, для которой пересобраны локализованные массивы

  SettingsTab(float cx, float cy, float cw, float ch) {
    this.cx = cx; this.cy = cy; this.cw = cw; this.ch = ch;
    refreshLabels();
  }

  // Пересобрать тексты, зависящие от языка. Вызывается из конструктора и
  // из draw(), когда strings.version меняется (т.е. язык переключили) —
  // иначе массив, заполненный один раз в конструкторе, навсегда останется
  // на том языке, что был при запуске приложения.
  void refreshLabels() {
    modeNames = new String[]{ strings.get("ШИМ +/−", "PWM +/−"), strings.get("ШИМ + направление", "PWM + direction"), strings.get("ШИМ 0-50-100", "PWM 0-50-100") };
    langVer = strings.version;
  }

  int bitW(int reg, int pos, boolean v) { return v ? (reg | (1 << pos)) : (reg & ~(1 << pos)); }

  void decodePwm(int s) {
    pwmType = (s & 1);
    int m = ((s >> 1) & 1) | (((s >> 6) & 1) << 1);
    pwmMode = constrain(m, 0, 2);
    pwmFreq = (s >> 2) & 0x0F;
  }
  int buildPwm() {
    int s = 0;
    s = bitW(s, 0, pwmType == 1);
    s = bitW(s, 1, (pwmMode & 1) != 0);
    s = bitW(s, 6, (pwmMode & 2) != 0);
    for (int i = 2; i <= 5; i++) s = bitW(s, i, ((pwmFreq >> (i - 2)) & 1) != 0);
    return s;
  }

  void draw(FirmwareParser fw) {
    if (langVer != strings.version) refreshLabels();
    pushStyle();
    textAlign(LEFT, TOP);
    if (!pwmUserEdited) decodePwm(int(pwmstate) & 0xFF);

    fill(colText); textSize(15);
    text(strings.get("Настройки прошивки", "Firmware Settings"), cx + 12, cy + 10);

    // Language switch
    float langX = cx + cw - 200, langY = cy + 8;
    fill(colDim); textSize(11); textAlign(RIGHT, CENTER);
    text(strings.get("Язык:", "Language:"), langX - 8, langY + 10);
    // EN button
    boolean enOn = strings.lang.equals("en");
    boolean enHov = mouseX >= langX && mouseX <= langX + 50 && mouseY >= langY && mouseY <= langY + 22;
    fill(enOn ? color(50, 110, 160) : (enHov ? color(55, 58, 70) : color(45, 47, 56)));
    stroke(colEdge); rect(langX, langY, 50, 22, 4);
    fill(enOn ? 255 : colDim); noStroke(); textAlign(CENTER, CENTER); textSize(10);
    text("EN", langX + 25, langY + 11);
    // RU button
    boolean ruOn = strings.lang.equals("ru");
    boolean ruHov = mouseX >= langX + 54 && mouseX <= langX + 104 && mouseY >= langY && mouseY <= langY + 22;
    fill(ruOn ? color(50, 110, 160) : (ruHov ? color(55, 58, 70) : color(45, 47, 56)));
    stroke(colEdge); rect(langX + 54, langY, 50, 22, 4);
    fill(ruOn ? 255 : colDim); noStroke(); textAlign(CENTER, CENTER); textSize(10);
    text("RU", langX + 79, langY + 11);
    tipZone(langX, langY, 104, 22, strings.get("Переключить язык интерфейса.", "Switch the interface language."));

    pwmX = cx + 12; pwmY = cy + 40; pwmW = 560; pwmH = 260;
    prX = cx + 12 + pwmW + 12; prY = cy + 40; prW = cw - pwmW - 36; prH = ch - 52;
    drawPwm();
    float fwInfoH = 76;
    drawFwInfo(fw, pwmX, pwmY + pwmH + 12, pwmW, fwInfoH);
    // dustin's rig, added — NTC panel fills the rest of the left column down to the same
    // bottom edge as the profiles panel on the right, so the two columns end flush.
    float ntcY = pwmY + pwmH + 12 + fwInfoH + 12;
    float colBottom = prY + prH;
    drawNtcPanel(pwmX, ntcY, pwmW, colBottom - ntcY);
    drawProfiles();
    popStyle();
  }

  void panel(float x, float y, float w, float h, String t) {
    fill(colBg); stroke(colEdge); strokeWeight(1); rect(x, y, w, h, 6);
    fill(colDim); textAlign(LEFT, TOP); textSize(12); text(t, x + 10, y + 8);
  }

  void drawPwm() {
    panel(pwmX, pwmY, pwmW, pwmH, strings.get("Конфигурация ШИМ (драйвер мотора)", "PWM Configuration (Motor Driver)"));
    fill(colDim); textAlign(LEFT, TOP); textSize(10);
    text(strings.get("Применяется автоматически. Чтобы вступило в силу, перезагрузите/переподключите Arduino.", "Applies automatically. Restart/reconnect Arduino for it to take effect."), pwmX + 12, pwmY + 26);

    float y = pwmY + 48;
    // тип
    label(strings.get("Тип", "Type"), pwmX + 12, y);
    segm(pwmX + 120, y, typeNames, pwmType, 130, "type");
    tipZone(pwmX + 12, y - 2, pwmW - 24, 24, strings.get("Phase correct рекомендуется. Fast PWM даёт вдвое большую частоту при той же разрядности.", "Phase correct recommended. Fast PWM gives double frequency at same resolution."));
    y += 36;
    label(strings.get("Режим", "Mode"), pwmX + 12, y);
    segm(pwmX + 120, y, modeNames, pwmMode, 140, "mode");
    tipZone(pwmX + 12, y - 2, pwmW - 24, 24, strings.get("ШИМ +/− нужен для драйверов BTS7960. Выбирайте по типу вашего драйвера мотора.", "PWM +/− for BTS7960 drivers. Choose based on your motor driver type."));
    y += 36;
    label(strings.get("Частота", "Frequency"), pwmX + 12, y);
    smlBtn(pwmX + 120, y - 2, 34, 22, "<", color(50, 52, 60));
    fill(colText); textAlign(CENTER, CENTER); textSize(13); text(freqNames[constrain(pwmFreq, 0, 9)], pwmX + 220, y + 9);
    smlBtn(pwmX + 290, y - 2, 34, 22, ">", color(50, 52, 60));
    tipZone(pwmX + 12, y - 2, pwmW - 24, 24, strings.get("Частота ШИМ. Идеально 8 кГц или ниже. Слишком высокая снижает разрядность управления.", "PWM frequency. Ideally 8 kHz or lower. Too high reduces control resolution."));
    y += 40;

    fill(colDim); textAlign(LEFT, TOP); textSize(9);
    drawWrappedSettings(strings.get("Изменения отправляются в Arduino сразу же, перезапуск нужен только для самого драйвера мотора.", "Changes are sent to Arduino right away — only the motor driver itself needs a restart to pick them up."), pwmX + 12, y, pwmW - 24, 12);
  }

  void drawWrappedSettings(String s, float x, float y, float w, float lh) {
    textAlign(LEFT, TOP);
    String[] words = split(s, ' '); String cur = ""; float yy = y;
    for (String wd : words) { String t = cur.length() == 0 ? wd : cur + " " + wd;
      if (textWidth(t) > w && cur.length() > 0) { text(cur, x, yy); yy += lh; cur = wd; } else cur = t; }
    if (cur.length() > 0) text(cur, x, yy);
  }

  void applyPwm() {
    pwmstate = byte(buildPwm()); proto.setPwmState(int(pwmstate) & 0xFF);
    pwmUserEdited = false;
    Log.info("SYSTEM", strings.get("ШИМ применён (нужен перезапуск Arduino)", "PWM applied (Arduino restart required)"));
  }

  void label(String s, float x, float y) { fill(colDim); textAlign(LEFT, TOP); textSize(12); text(s, x, y); }

  void segm(float x, float y, String[] opts, int sel, float bw, String tag) {
    for (int i = 0; i < opts.length; i++) {
      float bx = x + i * (bw + 6);
      boolean on = i == sel;
      fill(on ? color(50, 110, 160) : color(45, 47, 56)); stroke(colEdge); rect(bx, y - 2, bw, 22, 4);
      fill(on ? color(255) : colDim); noStroke(); textAlign(CENTER, CENTER); textSize(10);
      text(opts[i], bx + bw / 2, y + 9);
    }
  }

  void drawFwInfo(FirmwareParser fw, float x, float y, float w, float h) {
    panel(x, y, w, h, strings.get("Прошивка и связь", "Firmware & Connection"));
    float sy = y + 30;
    boolean conn = serial.isConnected();
    fill(conn ? color(80, 200, 110) : color(210, 80, 80)); noStroke(); ellipse(x + 16, sy + 5, 9, 9);
    fill(colText); textAlign(LEFT, CENTER); textSize(11);
    text(conn ? strings.get("Подключено к ", "Connected to ") + (serial.port != null ? "COM" : "") + " (" + strings.get("см. журнал", "see log") + ")" : strings.get("Нет связи с Arduino", "No Arduino connection"), x + 28, sy + 5);
    sy += 22;
    fill(colDim); textAlign(LEFT, TOP); textSize(10);
    if (fw != null && fw.versionNumber > 0) {
      text(strings.get("Версия: ", "Version: ") + fw.fullVersionString, x + 12, sy); sy += 16;
      text(fw.getSummary(), x + 12, sy);
    } else text(strings.get("Прошивка не определена", "Firmware unknown"), x + 12, sy);
  }

  // dustin's rig, added — motor NTC thermistor panel: live temperature (fixed 100k/B3950/330-ohm
  // formula, no calibration UI — known hardware) and a drag slider for the cutoff threshold, 80-200°C.
  int lastNtcPoll = 0;
  float ntcSliderX, ntcSliderY, ntcSliderW, ntcSliderH;
  boolean ntcSliderDragging = false;

  void drawNtcPanel(float x, float y, float w, float h) {
    panel(x, y, w, h, strings.get("Термистор мотора (NTC)", "Motor Thermistor (NTC)"));
    if (serial.isConnected() && millis() - lastNtcPoll > 500) { lastNtcPoll = millis(); serial.enqueueCommand("N"); }

    float sy = y + 30;
    boolean haveReading = ntcRaw >= 0;
    float liveC = haveReading ? rawToTempC(ntcRaw) : 0;
    color statusCol = ntcTripped ? color(220, 70, 70) : (liveC > ntcThreshC() * 0.85 ? color(220, 180, 60) : color(80, 200, 110));
    fill(haveReading ? statusCol : colDim); noStroke(); ellipse(x + 17, sy + 7, 11, 11);
    fill(colText); textAlign(LEFT, CENTER); textSize(16);
    text(haveReading ? nf(liveC, 1, 1) + "°C" : "—", x + 32, sy + 6);
    fill(colDim); textAlign(LEFT, CENTER); textSize(9);
    text((ntcTripped ? strings.get("ПЕРЕГРЕВ — FFB отключён", "OVERHEAT — FFB cut") : strings.get("норма", "OK")) + (haveReading ? "  (raw " + ntcRaw + ")" : ""), x + 32, sy + 21);
    tipZone(x + 12, sy - 6, w - 24, 32, strings.get("Живая температура мотора по датчику NTC. Красный — сработала критическая защита и FFB отключён.", "Live motor temperature from the NTC sensor. Red — critical protection tripped, FFB is cut."));
    sy += 40;

    stroke(colEdge); strokeWeight(1); line(x + 12, sy, x + w - 12, sy); sy += 16;

    float threshC = ntcThreshC();
    fill(colDim); textAlign(LEFT, CENTER); textSize(10);
    text(strings.get("Порог отключения FFB", "FFB cutoff threshold"), x + 12, sy);
    fill(colAcc); textAlign(RIGHT, CENTER); textSize(14);
    text(nf(threshC, 1, 0) + "°C", x + w - 12, sy);
    sy += 24;

    ntcSliderX = x + 16; ntcSliderY = sy; ntcSliderW = w - 32; ntcSliderH = 14;
    float frac = constrain((threshC - NTC_THRESH_MIN_C) / (NTC_THRESH_MAX_C - NTC_THRESH_MIN_C), 0, 1);
    fill(16); stroke(colEdge); rect(ntcSliderX, ntcSliderY, ntcSliderW, ntcSliderH, 7);
    noStroke(); fill(color(215, 130, 60)); rect(ntcSliderX, ntcSliderY, ntcSliderW * frac, ntcSliderH, 7);
    float knobX = ntcSliderX + ntcSliderW * frac;
    fill(255); ellipse(knobX, ntcSliderY + ntcSliderH / 2.0, 20, 20);
    fill(colDim); textAlign(LEFT, TOP); textSize(9);
    text(int(NTC_THRESH_MIN_C) + "°C", ntcSliderX, ntcSliderY + ntcSliderH + 6);
    textAlign(RIGHT, TOP); text(int(NTC_THRESH_MAX_C) + "°C", ntcSliderX + ntcSliderW, ntcSliderY + ntcSliderH + 6);
    tipZone(ntcSliderX - 10, ntcSliderY - 12, ntcSliderW + 20, ntcSliderH + 34, strings.get("Тяните, чтобы задать температуру мотора, при которой FFB критически отключается.", "Drag to set the motor temperature at which FFB critically cuts off."));
  }

  void applyNtcSliderDrag() {
    float frac = constrain((mouseX - ntcSliderX) / ntcSliderW, 0, 1);
    float newC = NTC_THRESH_MIN_C + frac * (NTC_THRESH_MAX_C - NTC_THRESH_MIN_C);
    int raw = int(constrain(tempCToRaw(newC), 0, 1023));
    if (raw != ntcThreshold) {
      ntcThreshold = raw;
      proto.setParam("M ", ntcThreshold);
    }
  }

  void handleDrag() { if (ntcSliderDragging) applyNtcSliderDrag(); }
  void handleRelease() {
    if (ntcSliderDragging) Log.info("SAFETY", strings.get("Порог NTC: ", "NTC threshold: ") + nf(ntcThreshC(), 1, 0) + "°C (raw " + ntcThreshold + ")");
    ntcSliderDragging = false;
  }

  void drawProfiles() {
    panel(prX, prY, prW, prH, strings.get("Профили настроек (на ПК)", "Settings Profiles (PC)"));
    fill(colDim); textAlign(LEFT, TOP); textSize(10);
    text(strings.get("Сохраняйте наборы настроек FFB и быстро их загружайте.", "Save FFB setting presets and load them quickly."), prX + 12, prY + 26);

    float ly = prY + 46, lh = 28;
    for (int i = 0; i < NSLOTS; i++) {
      float ey = ly + i * (lh + 4);
      boolean sel = i == selSlot;
      boolean exists = profileExists(i);
      fill(sel ? color(35, 55, 80) : color(20, 21, 27)); stroke(colEdge); rect(prX + 12, ey, prW - 24, lh, 4);
      fill(exists ? colText : colDim); noStroke(); textAlign(LEFT, CENTER); textSize(11);
      text(strings.get("Профиль ", "Profile ") + (i + 1) + (exists ? "" : "  (" + strings.get("пусто", "empty") + ")"), prX + 22, ey + lh / 2);
      tipZone(prX + 12, ey, prW - 24, lh, strings.get("Выбрать слот профиля " + (i + 1) + ". Кнопки ниже работают с выбранным слотом.", "Select profile slot " + (i + 1) + ". The buttons below act on the selected slot."));
    }
    float by = ly + NSLOTS * (lh + 4) + 8;
    float bw = (prW - 24 - 2 * 8) / 3.0;
    smlBtn(prX + 12, by, bw, 28, strings.get("Загрузить", "Load"), color(45, 95, 130));
    tipZone(prX + 12, by, bw, 28, strings.get("Загрузить выбранный профиль и сразу применить настройки к рулю.", "Load selected profile and apply settings to wheel."));
    smlBtn(prX + 12 + bw + 8, by, bw, 28, strings.get("Сохранить", "Save"), color(45, 110, 65));
    tipZone(prX + 12 + bw + 8, by, bw, 28, strings.get("Сохранить текущие настройки FFB в выбранный слот на ПК.", "Save current FFB settings to selected PC slot."));
    smlBtn(prX + 12 + 2 * (bw + 8), by, bw, 28, strings.get("Удалить", "Delete"), color(110, 50, 50));
    tipZone(prX + 12 + 2 * (bw + 8), by, bw, 28, strings.get("Удалить выбранный профиль.", "Delete selected profile."));
  }

  String profilePath(int i) { return "profiles/profile" + (i + 1) + ".txt"; }
  boolean profileExists(int i) { return new File(dataPath(profilePath(i))).exists(); }

  void saveProfile(int i) {
    String[] lines = new String[14];
    lines[0] = str(int(effects[0].gain));
    for (int e = 1; e < 12; e++) lines[e] = str(effects[e].gain);
    lines[12] = str(encoderTab.cpr);
    lines[13] = str(int(pwmstate) & 0xFF);
    saveStrings(dataPath(profilePath(i)), lines);
    Log.info("PROFILE", strings.get("Сохранён профиль ", "Saved profile ") + (i + 1));
  }
  void loadProfile(int i) {
    String[] lines = loadStrings(dataPath(profilePath(i)));
    if (lines == null || lines.length < 13) { Log.warn("PROFILE", strings.get("Профиль пуст", "Profile is empty")); return; }
    effects[0].gain = int(lines[0]); proto.setEffect(0, effects[0].gain);
    for (int e = 1; e < 12; e++) { effects[e].gain = float(lines[e]); proto.setEffect(e, effects[e].gain); }
    encoderTab.cpr = int(lines[12]); proto.setCPR(encoderTab.cpr);
    if (lines.length > 13) {
      pwmstate = byte(int(lines[13])); proto.setPwmState(int(pwmstate) & 0xFF);
    }
    Log.info("PROFILE", strings.get("Загружен профиль ", "Loaded profile ") + (i + 1) + strings.get(" — настройки отправлены в Arduino", " — settings sent to Arduino"));
  }
  void deleteProfile(int i) {
    File f = new File(dataPath(profilePath(i)));
    if (f.exists()) { f.delete(); Log.info("PROFILE", strings.get("Удалён профиль ", "Deleted profile ") + (i + 1)); }
  }

  void smlBtn(float x, float y, float w, float h, String label, int bg) {
    boolean hov = mouseX >= x && mouseX <= x + w && mouseY >= y && mouseY <= y + h;
    fill(hov ? lerpColor(bg, color(255), 0.18) : bg); stroke(colEdge); rect(x, y, w, h, 4);
    fill(230); noStroke(); textAlign(CENTER, CENTER); textSize(10); text(label, x + w / 2, y + h / 2);
  }

  void handleClick() {
    // Language switch
    float langX = cx + cw - 200, langY = cy + 8;
    if (hit(langX, langY, 50, 22)) { strings.setLang("en"); return; }
    if (hit(langX + 54, langY, 50, 22)) { strings.setLang("ru"); return; }
    // PWM type
    float y = pwmY + 48;
    for (int i = 0; i < 2; i++) { float bx = pwmX + 120 + i * 136; if (hit(bx, y - 2, 130, 22)) { pwmType = i; applyPwm(); return; } }
    y += 36;
    for (int i = 0; i < 3; i++) { float bx = pwmX + 120 + i * 146; if (hit(bx, y - 2, 140, 22)) { pwmMode = i; applyPwm(); return; } }
    y += 36;
    if (hit(pwmX + 120, y - 2, 34, 22)) { pwmFreq = max(0, pwmFreq - 1); applyPwm(); return; }
    if (hit(pwmX + 290, y - 2, 34, 22)) { pwmFreq = min(9, pwmFreq + 1); applyPwm(); return; }
    // dustin's rig, added — захват слайдера порога NTC
    if (hit(ntcSliderX - 10, ntcSliderY - 12, ntcSliderW + 20, ntcSliderH + 34)) { ntcSliderDragging = true; applyNtcSliderDrag(); return; }
    // профили: выбор слота
    float ly = prY + 46, lh = 28;
    for (int i = 0; i < NSLOTS; i++) {
      float ey = ly + i * (lh + 4);
      if (hit(prX + 12, ey, prW - 24, lh)) { selSlot = i; return; }
    }
    float by = ly + NSLOTS * (lh + 4) + 8;
    float bw = (prW - 24 - 2 * 8) / 3.0;
    if (mouseY >= by && mouseY <= by + 28) {
      if (hit(prX + 12, by, bw, 28)) { loadProfile(selSlot); return; }
      if (hit(prX + 12 + bw + 8, by, bw, 28)) { saveProfile(selSlot); return; }
      if (hit(prX + 12 + 2 * (bw + 8), by, bw, 28)) { deleteProfile(selSlot); return; }
    }
  }
  boolean hit(float x, float y, float w, float h) { return mouseX >= x && mouseX <= x + w && mouseY >= y && mouseY <= y + h; }
}
