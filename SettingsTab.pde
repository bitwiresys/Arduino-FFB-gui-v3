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
    float colBottom = prY + prH;
    float fwInfoY = pwmY + pwmH + 12;
    float fwInfoH = 76;
    drawFwInfo(fw, pwmX, fwInfoY, pwmW, fwInfoH);
    // остаток левой колонки делим пополам: версия релиза сверху, конфигурация (буквы) снизу
    float fvY = fwInfoY + fwInfoH + 12;
    float remainH = colBottom - fvY;
    float fvH1 = remainH * 0.42 - 6;
    drawFwVersions(pwmX, fvY, pwmW, fvH1);
    drawFwConfig(pwmX, fvY + fvH1 + 12, pwmW, remainH - fvH1 - 12);
    drawProfiles();
    popStyle();
  }

  // ---- ручная перепрошивка: выбор версии из релизов GitHub ----
  int selRelease = 0;
  float fvX, fvY, fvW, fvH, fvListY, fvRowH = 22;
  float fvBtnY;

  void drawFwVersions(float x, float y, float w, float h) {
    fvX = x; fvY = y; fvW = w; fvH = h;
    panel(x, y, w, h, strings.get("Версия прошивки", "Firmware Version"));

    // список подгружаем лениво при первом показе панели
    if (!firmwareUpdater.releasesFetchedOnce) firmwareUpdater.fetchReleases();

    float sy = y + 26;
    fill(colDim); textAlign(LEFT, TOP); textSize(9);
    if (firmwareUpdater.releasesLoading) {
      text(strings.get("Загрузка списка релизов...", "Loading release list..."), x + 12, sy);
    } else if (firmwareUpdater.releasesError != null) {
      fill(color(210, 120, 80));
      text(strings.get("Ошибка: ", "Error: ") + firmwareUpdater.releasesError, x + 12, sy);
    } else if (firmwareUpdater.releases.isEmpty()) {
      text(strings.get("Релизы не найдены", "No releases found"), x + 12, sy);
    } else {
      text(strings.get("Версия + конфигурация текущей платы. Свою конфигурацию — в панели ниже.", "Version + current board's configuration. Pick your own config in the panel below."), x + 12, sy, w - 24, 20);
    }
    sy += 16;
    fvListY = sy;

    ArrayList<FwRelease> rel = firmwareUpdater.releases;
    if (selRelease >= rel.size()) selRelease = 0;
    int maxRows = max(0, int((y + h - 34 - fvListY) / fvRowH));
    for (int i = 0; i < rel.size() && i < maxRows; i++) {
      FwRelease r = rel.get(i);
      float ry = fvListY + i * fvRowH;
      boolean sel = i == selRelease;
      boolean isCurrent = firmwareUpdater.localBuildId >= 0 && r.buildId == firmwareUpdater.localBuildId;
      fill(sel ? color(35, 55, 80) : color(20, 21, 27)); stroke(colEdge); strokeWeight(1);
      rect(x + 12, ry, w - 24, fvRowH - 3, 4);
      fill(sel ? colText : colDim); noStroke(); textAlign(LEFT, CENTER); textSize(10);
      text(r.tag + (i == 0 ? strings.get("  (последняя)", "  (latest)") : ""), x + 22, ry + (fvRowH - 3) / 2);
      if (isCurrent) {
        fill(color(90, 190, 120)); textAlign(RIGHT, CENTER); textSize(9);
        text(strings.get("на плате ✓", "on board ✓"), x + w - 22, ry + (fvRowH - 3) / 2);
      }
    }

    fvBtnY = y + h - 30;
    float bw = (w - 24 - 8) / 2.0;
    smlBtn(x + 12, fvBtnY, bw, 22, strings.get("Обновить список", "Refresh list"), color(50, 52, 60));
    boolean canFlash = !firmwareUpdater.releases.isEmpty() && !firmwareUpdater.flashing && firmwareUpdater.currentLetters().length() > 0;
    smlBtn(x + 12 + bw + 8, fvBtnY, bw, 22,
      strings.get("Прошить выбранную", "Flash selected"), canFlash ? color(140, 80, 45) : color(45, 45, 52));
    tipZone(x + 12 + bw + 8, fvBtnY, bw, 22, strings.get("Скачает выбранный релиз и прошьёт плату (вариант — по текущей конфигурации подключённой платы).",
      "Downloads the selected release and flashes the board (variant matched to the currently connected board's configuration)."));
  }

  // ---- выбор конфигурации (букв) из последнего релиза — независимо от того, что уже на плате.
  // Тот же источник данных, что и конфигуратор мастера для чистой платы (manifest.json).
  int selConfig = -1;
  float cfX, cfY, cfW, cfH, cfListY, cfRowH = 34;
  float cfBtnY;
  float cfScroll = 0;

  void drawFwConfig(float x, float y, float w, float h) {
    cfX = x; cfY = y; cfW = w; cfH = h;
    panel(x, y, w, h, strings.get("Конфигурация (буквы, из последнего релиза)", "Configuration (letters, from the latest release)"));

    if (!firmwareUpdater.configuratorLoading && firmwareUpdater.configuratorVariants.isEmpty() && firmwareUpdater.configuratorError == null) {
      firmwareUpdater.fetchConfiguratorVariants();
    }

    float sy = y + 24;
    if (firmwareUpdater.configuratorLoading) {
      fill(colDim); textAlign(LEFT, TOP); textSize(9);
      text(strings.get("Загрузка списка конфигураций...", "Loading configuration list..."), x + 12, sy);
      return;
    }
    if (firmwareUpdater.configuratorError != null) {
      fill(color(210, 120, 80)); textAlign(LEFT, TOP); textSize(9);
      text(strings.get("Ошибка: ", "Error: ") + firmwareUpdater.configuratorError, x + 12, sy, w - 24, 30);
      return;
    }

    ArrayList<FwVariant> vs = firmwareUpdater.configuratorVariants;
    if (vs.isEmpty()) {
      fill(colDim); textAlign(LEFT, TOP); textSize(9);
      text(strings.get("Список пуст", "List is empty"), x + 12, sy);
      return;
    }

    float listTop = sy, listBot = y + h - 34;
    cfListY = listTop;
    float maxScroll = max(0, vs.size() * cfRowH - (listBot - listTop));
    cfScroll = constrain(cfScroll, 0, maxScroll);
    stroke(colEdge); noFill(); rect(x + 8, listTop, w - 16, listBot - listTop);
    int first = max(0, int(cfScroll / cfRowH)), last = min(vs.size(), first + int((listBot - listTop) / cfRowH) + 2);
    for (int i = first; i < last; i++) {
      FwVariant v = vs.get(i);
      float ry = listTop + i * cfRowH - cfScroll;
      if (ry + cfRowH < listTop || ry > listBot) continue;
      boolean sel = i == selConfig;
      fill(sel ? color(45, 90, 130) : color(20, 21, 27)); noStroke();
      rect(x + 12, ry, w - 24, cfRowH - 3, 4);
      fill(sel ? 255 : colText); textAlign(LEFT, TOP); textSize(11);
      text(v.letters.length() > 0 ? v.letters : "-", x + 20, ry + 3);
      fill(sel ? color(220, 230, 245) : colDim); textSize(9);
      String feats = v.features.isEmpty() ? strings.get("базовая, без опций", "base, no extras") : join(v.features.toArray(new String[0]), " · ");
      text(feats, x + 20, ry + 18, w - 32, cfRowH - 20);
    }
    if (maxScroll > 0) {
      fill(colDim); textAlign(RIGHT, TOP); textSize(8);
      text(strings.get("колесо мыши — прокрутка", "mouse wheel to scroll"), x + w - 12, listTop - 10);
    }

    cfBtnY = y + h - 26;
    boolean canFlash = selConfig >= 0 && selConfig < vs.size() && !firmwareUpdater.flashing
      && (serial.isConnected() || firmwareUpdater.lastKnownPort().length() > 0);
    smlBtn(x + 12, cfBtnY, w - 24, 22, strings.get("Прошить эту конфигурацию", "Flash this configuration"),
      canFlash ? color(140, 80, 45) : color(45, 45, 52));
    tipZone(x + 12, cfBtnY, w - 24, 22, strings.get("Скачает последний релиз и прошьёт плату выбранной конфигурацией — независимо от того, что на ней сейчас.",
      "Downloads the latest release and flashes the board with the selected configuration - regardless of what's on it now."));
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
    text(conn ? strings.get("Подключено к ", "Connected to ") + serial.portName : strings.get("Нет связи с Arduino", "No Arduino connection"), x + 28, sy + 5);
    sy += 22;
    fill(colDim); textAlign(LEFT, TOP); textSize(10);
    if (fw != null && fw.versionNumber > 0) {
      text(strings.get("Версия: ", "Version: ") + fw.fullVersionString, x + 12, sy); sy += 16;
      text(fw.getSummary(), x + 12, sy);
    } else text(strings.get("Прошивка не определена", "Firmware unknown"), x + 12, sy);
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

  // dustin's rig, added — profile format was originally frozen at 14 fields (gains/cpr/pwm
  // only), so axis invert/disable, pedal min/max calibration, NTC threshold, current limit
  // and per-effect enable toggles silently didn't round-trip through PC profile slots even
  // though they already autosave to the Arduino's own EEPROM. Extended to 32 fields;
  // loadProfile() stays backward-compatible with older/shorter profile files.
  void saveProfile(int i) {
    String[] lines = new String[27]; // ровно столько полей и заполняем (32 оставляло 5 строк "null" в файле)
    lines[0] = str(int(effects[0].gain));
    for (int e = 1; e < 12; e++) lines[e] = str(effects[e].gain);
    lines[12] = str(encoderTab.cpr);
    lines[13] = str(int(pwmstate) & 0xFF);
    lines[14] = str(int(axisInvertMask) & 0xFF);
    lines[15] = str(int(axisDisableMask) & 0xFF);
    lines[16] = "1023"; // зарезервировано (бывший порог NTC) — оставлено ради совместимости формата
    lines[17] = "1023"; // зарезервировано (бывший лимит тока)
    lines[18] = str(int(effstate) & 0xFF);
    for (int a = 1; a < 5; a++) lines[18 + a] = str(int(dashboardTab.calMin[a]));
    for (int a = 1; a < 5; a++) lines[22 + a] = str(int(dashboardTab.calMax[a]));
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
    if (lines.length > 26) {
      // I/D шлём только если прошивка собрана с опцией 'v' —
      // иначе неизвестная команда молчит и очередь копит таймауты
      axisInvertMask = byte(int(lines[14]) & 0xFF);
      axisDisableMask = byte(int(lines[15]) & 0xFF);
      if (fwSupportsAxisTweaks()) {
        proto.setParam("I ", int(axisInvertMask) & 0xFF);
        proto.setParam("D ", int(axisDisableMask) & 0xFF);
      }
      // lines[16]/lines[17] — зарезервированные поля (бывшие NTC/лимит тока), игнорируем
      effstate = byte(int(lines[18]) & 0xFF); decodeEffstate(effstate); applyEffstate();
      for (int a = 1; a < 5; a++) {
        dashboardTab.calMin[a] = float(lines[18 + a]);
        proto.setParam(dashboardTab.cmdMin[a], int(dashboardTab.calMin[a]));
      }
      for (int a = 1; a < 5; a++) {
        dashboardTab.calMax[a] = float(lines[22 + a]);
        proto.setParam(dashboardTab.cmdMax[a], int(dashboardTab.calMax[a]));
      }
    }
    proto.requestAutosave();
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
    // ручная прошивка: выбор релиза и кнопки
    ArrayList<FwRelease> rel = firmwareUpdater.releases;
    int maxRows = max(0, int((fvY + fvH - 34 - fvListY) / fvRowH));
    for (int i = 0; i < rel.size() && i < maxRows; i++) {
      float ry = fvListY + i * fvRowH;
      if (hit(fvX + 12, ry, fvW - 24, fvRowH - 3)) { selRelease = i; return; }
    }
    float fvBw = (fvW - 24 - 8) / 2.0;
    if (hit(fvX + 12, fvBtnY, fvBw, 22)) { firmwareUpdater.fetchReleases(); return; }
    if (hit(fvX + 12 + fvBw + 8, fvBtnY, fvBw, 22)) {
      if (!rel.isEmpty() && !firmwareUpdater.flashing && selRelease < rel.size() && firmwareUpdater.currentLetters().length() > 0) {
        firmwareUpdater.startManualFlash(rel.get(selRelease));
      }
      return;
    }
    // выбор конфигурации (буквы) из последнего релиза
    ArrayList<FwVariant> vs = firmwareUpdater.configuratorVariants;
    float listBot = cfY + cfH - 34;
    int first = max(0, int(cfScroll / cfRowH)), last = min(vs.size(), first + int((listBot - cfListY) / cfRowH) + 2);
    for (int i = first; i < last; i++) {
      float ry = cfListY + i * cfRowH - cfScroll;
      if (ry + cfRowH < cfListY || ry > listBot) continue;
      if (hit(cfX + 12, ry, cfW - 24, cfRowH - 3)) { selConfig = i; return; }
    }
    if (hit(cfX + 12, cfBtnY, cfW - 24, 22)) {
      if (selConfig >= 0 && selConfig < vs.size() && !firmwareUpdater.flashing) {
        String port = serial.isConnected() ? serial.portName : firmwareUpdater.lastKnownPort();
        if (port.length() > 0) firmwareUpdater.installFresh(port, vs.get(selConfig).letters);
      }
      return;
    }
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

  void handleScroll(float delta) {
    if (mouseX >= cfX && mouseX <= cfX + cfW && mouseY >= cfY && mouseY <= cfY + cfH) cfScroll += delta * 40;
  }
}
