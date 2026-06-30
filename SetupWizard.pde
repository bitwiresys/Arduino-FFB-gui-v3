// ============================================================
// SetupWizard — first-run configuration overlay
// Multi-step wizard: HID → COM → Firmware → Features → Bind → Done
// ============================================================

class SetupWizard {
  boolean active = false;
  int step = 0;
  // wizard steps: 0=welcome  1=COM select  2=firmware  3=bind  4=done

  // colors (matches v3 dark theme)
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
  int colBtnO  = color(40, 40, 48);
  int colItem  = color(38, 38, 48);
  int colItemH = color(50, 50, 62);

  // state
  boolean hidFound = false;
  String hidName = "";
  ControlDevice[] hidDevices = new ControlDevice[0];
  int selHID = -1;
  String[] comPorts = new String[0];
  int selPort = -1;
  String fwVersion = "";
  int fwNum = 0;

  // features from firmware
  ArrayList<String> featureList = new ArrayList<String>();
  ArrayList<String> buttonMap = new ArrayList<String>();
  ArrayList<String> axisMap = new ArrayList<String>();
  ArrayList<String> logLines = new ArrayList<String>();

  // button geometry
  float btnW = 200, btnH = 40;

  // scroll for long lists
  float scrollY = 0;

  PApplet papplet;

  // non-blocking fw polling state
  int fwWaitFrames = 0;
  boolean fwRequestSent = false;

  SetupWizard() {
    papplet = wheel_control_v3.this;
  }

  void start() {
    active = true;
    step = 0;
    logLines.clear();
    featureList.clear();
    buttonMap.clear();
    axisMap.clear();
    scrollY = 0;
    fwWaitFrames = 0;
    fwRequestSent = false;
  }

  void addLog(String s) {
    logLines.add(s);
    if (logLines.size() > 6) logLines.remove(0);
  }

  // ============ MAIN DRAW ============
  void draw() {
    if (!active) return;
    updateFwPoll();
    pushStyle();

    // overlay
    fill(0, 0, 0, 180);
    noStroke();
    rect(0, 0, WIN_W, WIN_H);

    float pw = min(720, WIN_W - 60);
    float ph = min(540, WIN_H - 40);
    float px = (WIN_W - pw) / 2;
    float py = (WIN_H - ph) / 2;

    // panel
    fill(colPanel);
    stroke(colEdge);
    strokeWeight(1);
    rect(px, py, pw, ph, 8);

    // title bar
    fill(colAcc);
    noStroke();
    rect(px, py, pw, 42, 8, 8, 0, 0);
    fill(255);
    textAlign(LEFT, CENTER);
    textSize(15);
    text(strings.get("Настройка Wheel Control v3.0", "Wheel Control v3.0 Setup"), px + 16, py + 21);

    // step indicator
    String[] stepNames = {"", "HID", "COM", strings.get("Прошивка", "Firmware"), strings.get("Привязка", "Binding"), ""};
    float sx = px + pw - 200;
    textAlign(RIGHT, CENTER);
    textSize(11);
    fill(colDim);
    text(strings.get("Шаг ", "Step ") + step + "/4: " + stepNames[step], sx + 180, py + 21);

    // progress bar
    float pbx = px + 12, pby = py + 44, pbw = pw - 24, pbh = 3;
    fill(colBg);
    noStroke();
    rect(pbx, pby, pbw, pbh, 2);
    fill(colAcc);
    rect(pbx, pby, pbw * step / 4.0, pbh, 2);

    float cx = px + 20, cy = py + 58, cw = pw - 40;
    float ch = ph - 130;

    switch (step) {
      case 0: drawWelcome(cx, cy, cw, ch); break;
      case 1: drawCOM(cx, cy, cw, ch); break;
      case 2: drawFirmware(cx, cy, cw, ch); break;
      case 3: drawFeatures(cx, cy, cw, ch); break;
      case 4: drawDone(cx, cy, cw, ch); break;
    }

    // log
    float logY = py + ph - 72;
    fill(colBg);
    noStroke();
    rect(px + 10, logY, pw - 20, 60, 4);
    textAlign(LEFT, TOP);
    textSize(10);
    for (int i = 0; i < logLines.size(); i++) {
      fill(i == logLines.size() - 1 ? colAcc : colDim);
      text(logLines.get(i), px + 16, logY + 5 + i * 13);
    }

    popStyle();
  }

  // ============ STEP 0: Welcome ============
  void drawWelcome(float x, float y, float w, float h) {
    textAlign(LEFT, TOP);
    fill(colText);
    textSize(16);
    text(strings.get("Добро пожаловать!", "Welcome!"), x, y);
    y += 32;
    fill(colDim);
    textSize(13);
    text(strings.get("Первый запуск. Настройка подключения к Arduino FFB Wheel.", "First run. Setting up Arduino FFB Wheel connection."), x, y);
    y += 24;
    text(strings.get("Убедитесь, что плата подключена по USB.", "Make sure the board is connected via USB."), x, y);
    y += 40;
    if (btn(x + w / 2 - btnW / 2, y, btnW, btnH, strings.get("Начать", "Start"), colBtn)) {
      step = 1;
      doDiscoverCOM();
    }
  }

  // ============ STEP 1: COM ============
  void drawCOM(float x, float y, float w, float h) {
    textAlign(LEFT, TOP);
    fill(colText);
    textSize(15);
    text(strings.get("Шаг 1: Выбор COM-порта", "Step 1: Select COM Port"), x, y);
    y += 36;

    if (comPorts.length == 0) {
      fill(colErr);
      textSize(13);
      text(strings.get("COM-порты не найдены", "No COM ports found"), x, y);
      y += 30;
      if (btn(x + w / 2 - 80, y, 160, btnH, strings.get("Обновить", "Refresh"), colBtn)) {
        doDiscoverCOM();
      }
      return;
    }

    fill(colDim);
    textSize(12);
    text(strings.get("Найдено: ", "Found: ") + comPorts.length + "  —  " + strings.get("выберите порт Arduino:", "select Arduino port:"), x, y);
    y += 24;

    float itemH = 32;
    float listW = w - 8;
    float maxItems = min(comPorts.length, (int)((h - 120) / (itemH + 3)));

    for (int i = 0; i < comPorts.length && i < maxItems; i++) {
      float iy = y + i * (itemH + 3);
      boolean hov = mouseX >= x + 4 && mouseX <= x + 4 + listW && mouseY >= iy && mouseY <= iy + itemH;
      boolean sel = (i == selPort);

      fill(sel ? colAcc : (hov ? colItemH : colItem));
      noStroke();
      rect(x + 4, iy, listW, itemH, 4);

      fill(sel ? 255 : colText);
      textAlign(LEFT, CENTER);
      textSize(13);
      text(comPorts[i], x + 16, iy + itemH / 2);

      // radio
      float rx = x + listW - 8;
      noFill();
      stroke(sel ? 255 : colDim);
      strokeWeight(1.5);
      ellipse(rx, iy + itemH / 2, 14, 14);
      if (sel) { fill(255); noStroke(); ellipse(rx, iy + itemH / 2, 7, 7); }
    }

    float btnY = y + comPorts.length * (itemH + 3) + 12;
    if (btnY + btnH > y + h - 10) btnY = y + h - btnH - 10;

      if (btn(x + w / 2 - btnW - 8, btnY, btnW, btnH, strings.get("Обновить", "Refresh"), colBtnO)) {
      doDiscoverCOM();
    }
    if (selPort >= 0) {
      if (btn(x + w / 2 + 8, btnY, btnW, btnH, strings.get("Подключить", "Connect"), colBtn)) {
        doConnect();
      }
    }
  }

  // ============ STEP 2: Firmware ============
  void drawFirmware(float x, float y, float w, float h) {
    textAlign(LEFT, TOP);
    fill(colText);
    textSize(15);
    text(strings.get("Шаг 2: Прошивка", "Step 2: Firmware"), x, y);
    y += 36;

    textSize(13);
    if (fwVersion.length() > 0) {
      fill(colOk);
      text("  ✓  ", x, y);
      fill(colText);
      text(fwVersion + "  (v" + fwNum + ")", x + 30, y);
      y += 30;
      fill(colDim);
      textSize(12);
      text(strings.get("Определены функции:", "Detected features:"), x + 8, y);
      y += 22;
      fill(colText);
      textSize(12);
      for (int i = 0; i < featureList.size(); i++) {
        text("  •  " + featureList.get(i), x + 12, y);
        y += 18;
      }
      y += 16;
      if (btn(x + w / 2 - btnW / 2, y, btnW, btnH, strings.get("Далее", "Next"), colBtn)) {
        step = 3;
        buildButtonAxisMap();
      }
    } else {
      fill(colWarn);
      text(strings.get("Ожидание ответа от Arduino...", "Waiting for Arduino response..."), x, y);
    }
  }

  // ---- состояние привязки + калибровки осей (горизонтальные строки) ----
  // calMin/calMax — нормализованные 0..1 границы по физической оси i (0=лево,1=право).
  float[] calMin = {0, 0, 0, 0, 0};
  float[] calMax = {1, 1, 1, 1, 1};
  boolean[] calDraggingMin = {false, false, false, false, false};
  boolean[] calDraggingMax = {false, false, false, false, false};
  boolean calMarkersVisible = false;     // маркеры мин/макс показываются по кнопке «Калибровка»
  String[] calCmdMin = {"", "YA", "YC", "YE", "YG"};   // команды прошивки по физ-оси
  String[] calCmdMax = {"", "YB", "YD", "YF", "YH"};
  float calAdMax = 1023;
  int releasedAxis = -1;                 // какой маркер отпущен (для отправки в onRelease)
  boolean releasedIsMin = false;

  // геометрия строк осей (заполняется в drawFeatures, читается в handleClick)
  float[] rowBarX  = new float[5], rowBarW = new float[5];
  float[] rowY     = new float[5], rowBarY = new float[5];
  float[] roleBtnX = new float[5], roleBtnW = new float[5];
  float wizRowH = 0, wizBarH = 0;
  float calToggleX, calToggleY, calToggleW = 170, calToggleH = 34;

  color[] axisColors = {
    color(70, 150, 230),   // X
    color(200, 70, 70),    // Y
    color(60, 180, 120),   // Z
    color(200, 180, 60),   // RX
    color(180, 100, 200)   // RY
  };
  String[] axisPhys = {"X", "Y", "Z", "RX", "RY"};

  // ============ STEP 3: Привязка осей + верификация + калибровка ============
  void drawFeatures(float x, float y, float w, float h) {
    textAlign(LEFT, TOP);
    fill(colText);
    textSize(15);
    text(strings.get("Шаг 3: Привязка осей и калибровка", "Step 3: Axis Binding & Calibration"), x, y);

    fill(colDim); textSize(11);
    text(strings.get("Крутите руль и жмите педали — двигается «своя» полоса. Клик по функции слева — сменить назначение.", "Turn wheel and press pedals — the matching bar moves. Click function name on the left to change assignment."),
         x, y + 22);

    if (gpad == null) {
      fill(colErr); textSize(13);
      text(strings.get("HID не подключён — вернитесь на шаг COM.", "HID not connected — go back to the COM step."), x, y + 44);
    }

    calAdMax = fw != null ? fw.getDefaultADMax() : 1023;

    float leftW = w * 0.60;
    float rowsTop = y + 50;
    float rowGap = 8;
    wizRowH = 40;
    wizBarH = 16;

    // ---- ЛЕВО: 5 строк осей (буква + функция + живая полоса) ----
    for (int i = 0; i < 5; i++) {
      float ry = rowsTop + i * (wizRowH + rowGap);
      rowY[i] = ry;
      drawAxisBindRow(i, x, ry, leftW);
    }

    // ---- ПРАВО: статус железа + кнопки (1:1) ----
    float rx = x + leftW + 18;
    float rw = w - leftW - 18;
    float ry = rowsTop;

    fill(colDim); textSize(10); textAlign(LEFT, TOP);
    text(strings.get("ОБНАРУЖЕНО", "DETECTED"), rx, ry); ry += 16;
    fill(colOk); noStroke(); ellipse(rx + 4, ry + 6, 7, 7);
    fill(colText); textSize(11);
    text(gpad != null ? trim(gpad.getName()) : "—", rx + 14, ry); ry += 18;
    fill(colDim); textSize(11);
    text("FW: " + (fwVersion.length() > 0 ? fwVersion : "—"), rx, ry); ry += 24;

    fill(colAcc); textSize(12);
    text(strings.get("Кнопки (1:1 с прошивкой)", "Buttons (1:1 with firmware)"), rx, ry); ry += 6;
    fill(colDim); textSize(9);
    text(strings.get("кнопка N = физическая кнопка N", "button N = physical button N"), rx, ry + 12); ry += 28;

    int numBtn = 8;
    if (fw != null && (fw.buttonMatrix || fw.buttonBox)) numBtn = 16;
    float btnSize = 26, btnGap = 4;
    int cols = 8;
    for (int i = 0; i < numBtn; i++) {
      int row = i / cols, col = i % cols;
      float bx = rx + col * (btnSize + btnGap);
      float by = ry + row * (btnSize + btnGap);
      boolean pressed = false;
      try { if (gpad != null) pressed = gpad.getButton(i).pressed(); } catch (Throwable t) {}
      fill(pressed ? colOk : colItem); noStroke();
      rect(bx, by, btnSize, btnSize, 4);
      fill(pressed ? color(0) : colDim);
      textAlign(CENTER, CENTER); textSize(10);
      text(str(i), bx + btnSize / 2, by + btnSize / 2);
    }
    float hatY = ry + ceil(numBtn / (float)cols) * (btnSize + btnGap) + 6;
    if (fw != null && fw.hatSwitch) {
      fill(colDim); textAlign(LEFT, TOP); textSize(10);
      text(strings.get("Hat / POV: есть (проверка по кнопкам)", "Hat / POV: present (test via buttons)"), rx, hatY);
    }

    // ---- НИЗ: кнопка калибровки + Завершить ----
    float btnY = y + h - btnH - 2;
    calToggleX = x; calToggleY = btnY; calToggleH = btnH;
    boolean calHov = mouseX >= calToggleX && mouseX <= calToggleX + calToggleW &&
                     mouseY >= calToggleY && mouseY <= calToggleY + calToggleH;
    fill(calMarkersVisible ? colOk : (calHov ? colBtnH : colBtn)); noStroke();
    rect(calToggleX, calToggleY, calToggleW, calToggleH, 4);
    fill(255); textAlign(CENTER, CENTER); textSize(12);
    text(calMarkersVisible ? strings.get("Скрыть калибровку", "Hide calibration") : strings.get("Калибровка мин/макс", "Min/Max calibration"), calToggleX + calToggleW / 2, calToggleY + calToggleH / 2);

    if (btn(x + w - btnW, btnY, btnW, btnH, strings.get("Завершить", "Finish"), colOk)) {
      step = 4;
      saveAxisRoles();
      saveConfig();
    }
  }

  // одна строка оси: [буква] [функция-кнопка] [живая полоса + ADC] (+ маркеры калибровки)
  void drawAxisBindRow(int i, float x, float y, float w) {
    float val = 0;
    try { if (gpad != null) val = gpad.getSlider(i).getValue(); } catch (Throwable t) {}
    float frac = constrain(map(val, -1, 1, 0, 1), 0, 1);
    int adc = round(frac * calAdMax);

    // буква оси
    fill(axisColors[i]); noStroke();
    rect(x, y + 6, 26, 26, 4);
    fill(0); textAlign(CENTER, CENTER); textSize(11);
    text(axisPhys[i], x + 13, y + 19);

    // кнопка-функция (клик циклически меняет роль со свопом). Ось 0 (X) —
    // аппаратный энкодер руля, роль «Руль» с неё снимать нельзя (см. ту же
    // защиту в DashboardTab и loadAxisRoles в главном файле).
    float fbX = x + 32, fbW = 104;
    roleBtnX[i] = fbX; roleBtnW[i] = fbW;
    boolean fbHov = i > 0 && mouseX >= fbX && mouseX <= fbX + fbW && mouseY >= y + 6 && mouseY <= y + 32;
    fill(fbHov ? colItemH : colItem); stroke(colEdge); strokeWeight(1);
    rect(fbX, y + 6, fbW, 26, 4);
    fill(fbHov ? color(255, 220, 120) : colText); noStroke();
    textAlign(LEFT, CENTER); textSize(12);
    text(ROLE_NAMES[axisRole[i]], fbX + 8, y + 19);
    fill(colDim); textAlign(RIGHT, CENTER); textSize(9);
    text(i == 0 ? strings.get("фиксировано", "fixed") : strings.get("сменить", "change"), fbX + fbW - 6, y + 19);

    // живая полоса
    float barX = fbX + fbW + 12;
    float barW = (x + w) - barX - 44;
    float barY = y + 12;
    rowBarX[i] = barX; rowBarW[i] = barW; rowBarY[i] = barY;
    fill(16); stroke(colEdge); strokeWeight(1);
    rect(barX, barY, barW, wizBarH, 3);
    // тики на четвертях
    stroke(45); strokeWeight(1);
    for (int q = 1; q < 4; q++) { float qx = barX + barW * q / 4.0; line(qx, barY, qx, barY + wizBarH); }
    noStroke(); fill(axisColors[i]);
    rect(barX, barY, barW * frac, wizBarH, 3);

    // ADC
    fill(colAcc); textAlign(LEFT, CENTER); textSize(11);
    text(adc, barX + barW + 8, y + 19);

    // маркеры мин/макс (горизонтальные, как на главном экране)
    if (calMarkersVisible) {
      float minX = barX + barW * calMin[i];
      float maxX = barX + barW * calMax[i];
      if (calDraggingMin[i]) { minX = constrain(mouseX, barX, maxX - 4); calMin[i] = (minX - barX) / barW; }
      if (calDraggingMax[i]) { maxX = constrain(mouseX, minX + 4, barX + barW); calMax[i] = (maxX - barX) / barW; }
      // затемнить вне диапазона
      fill(0, 0, 0, 120); noStroke();
      rect(barX, barY, minX - barX, wizBarH); rect(maxX, barY, barX + barW - maxX, wizBarH);
      // min (синий, сверху)
      stroke(80, 150, 240); strokeWeight(2); line(minX, barY - 3, minX, barY + wizBarH + 3);
      fill(80, 150, 240); noStroke(); triangle(minX - 4, barY - 3, minX + 4, barY - 3, minX, barY + 3);
      // max (оранжевый, снизу)
      stroke(240, 150, 70); strokeWeight(2); line(maxX, barY - 3, maxX, barY + wizBarH + 3);
      fill(240, 150, 70); noStroke(); triangle(maxX - 4, barY + wizBarH + 3, maxX + 4, barY + wizBarH + 3, maxX, barY + wizBarH - 3);
      // подпись диапазона
      fill(colDim); textAlign(RIGHT, TOP); textSize(8);
      text(round(calMin[i] * calAdMax) + ".." + round(calMax[i] * calAdMax), barX + barW + 36, barY + wizBarH + 1);
    }

    tipZone(x, y + 4, w, wizRowH - 4,
      axisPhys[i] + " -> " + ROLE_NAMES[axisRole[i]] + ". Click function to change.");
  }

  // Called from mouseReleased — sends calibration command for the released marker
  void handleRelease() {
    if (step != 3 || !active) return;
    if (releasedAxis >= 0) {
      int i = releasedAxis;
      if (releasedIsMin && i >= 1 && calCmdMin[i].length() > 0) {
        int val = round(calMin[i] * calAdMax);
        serial.sendImmediate(calCmdMin[i] + " " + str(val));
        addLog(calCmdMin[i] + " = " + val);
      } else if (!releasedIsMin && i >= 1 && calCmdMax[i].length() > 0) {
        int val = round(calMax[i] * calAdMax);
        serial.sendImmediate(calCmdMax[i] + " " + str(val));
        addLog(calCmdMax[i] + " = " + val);
      }
      releasedAxis = -1;
    }
    // Clear all dragging flags
    for (int i = 0; i < 5; i++) {
      calDraggingMin[i] = false;
      calDraggingMax[i] = false;
    }
  }

  // ============ STEP 4: Done ============
  void drawDone(float x, float y, float w, float h) {
    textAlign(LEFT, TOP);
    fill(colOk);
    textSize(16);
    text(strings.get("Настройка завершена!", "Setup complete!"), x, y);
    y += 36;
    fill(colText);
    textSize(13);
    String portName = (selPort >= 0 && selPort < comPorts.length) ? comPorts[selPort] : "?";
    text("COM: " + portName, x, y); y += 22;
    text("FW:  " + fwVersion, x, y); y += 22;
    text(strings.get("Конфиг сохранён в data/COM_cfg.txt", "Config saved to data/COM_cfg.txt"), x, y);
    y += 50;
    if (btn(x + w / 2 - btnW / 2, y, btnW, btnH, strings.get("Готово", "Done"), colOk)) {
      active = false;
      // re-init serial with saved config
      try {
        File f = new File(papplet.dataPath("COM_cfg.txt"));
        if (f.exists()) {
          String[] port = papplet.loadStrings("COM_cfg.txt");
          if (port != null && port.length > 0) {
            serial.connect(port[0], 115200);
            serial.enqueueCommand("V");
            serial.enqueueCommand("U");
          }
        }
      } catch (Throwable t) {
        Log.error("SERIAL", "Post-wizard init: " + t.getMessage());
      }
    }
  }

  // ============ ACTIONS ============
  void doHIDCheck() {
    addLog(strings.get("Поиск HID...", "Searching for HID..."));
    try {
      control = ControlIO.getInstance(papplet);
      java.util.List<ControlDevice> devList = control.getDevices();
      ControlDevice[] devs = devList.toArray(new ControlDevice[0]);
      hidDevices = devs;
      hidFound = false;
      hidName = "";
      StringBuilder sb = new StringBuilder(strings.get("Найдено: ", "Found: ") + devs.length + strings.get(" устройств", " devices"));
      addLog(sb.toString());
      for (int i = 0; i < devs.length; i++) {
        String n = trim(devs[i].getName());
        addLog("  " + (i+1) + ". " + n);
        if (n.toLowerCase().contains("arduino")) {
          hidFound = true;
          hidName = n;
          gpad = devs[i];
          gpad.open();
        }
      }
      if (!hidFound && devs.length > 0) {
        // No Arduino by name — let user pick in step 1b
        addLog(strings.get("Arduino не определён по имени, выберите вручную", "Arduino not identified by name, please select manually"));
      }
    } catch (Throwable t) {
      hidFound = false;
      addLog(strings.get("HID ошибка: ", "HID error: ") + t.getMessage());
    }
  }

  void doDiscoverCOM() {
    addLog(strings.get("Поиск COM...", "Searching for COM ports..."));
    try {
      comPorts = Serial.list();
      selPort = -1;
      addLog(strings.get("Найдено портов: ", "Ports found: ") + comPorts.length);
    } catch (Throwable t) {
      comPorts = new String[0];
      addLog(strings.get("Ошибка: ", "Error: ") + t.getMessage());
    }
  }

  void doConnect() {
    if (selPort < 0 || selPort >= comPorts.length) return;
    String portName = comPorts[selPort];
    addLog(strings.get("Подключение к ", "Connecting to ") + portName + "...");

    try {
      if (serial.connect(portName, 115200)) {
        addLog("OK: " + portName);
        // Auto-detect HID device by name
        try {
          if (control == null) control = ControlIO.getInstance(papplet);
          java.util.List<ControlDevice> devList = control.getDevices();
          for (ControlDevice dev : devList) {
            String n = trim(dev.getName());
            if (n.toLowerCase().contains("arduino")) {
              gpad = dev;
              gpad.open();
              hidFound = true;
              hidName = n;
              addLog("HID: " + n);
              break;
            }
          }
          if (!hidFound) addLog(strings.get("HID не найден (не критично)", "HID not found (not critical)"));
        } catch (Throwable t) {
          addLog("HID: " + t.getMessage());
        }

        step = 2;
        // Send "V" directly — enqueue might not work if queue is busy
        serial.sendImmediate("V");
        fwRequestSent = true;
        fwWaitFrames = 0;
      } else {
        addLog(strings.get("Ошибка подключения", "Connection error"));
      }
    } catch (Throwable t) {
      addLog(strings.get("Ошибка: ", "Error: ") + t.getMessage());
    }
  }

  // Called every frame from draw() when step==2 (firmware) and waiting for fw
  void updateFwPoll() {
    if (step != 2 || !fwRequestSent) return;
    fwWaitFrames++;

    // Check lastLine from serialEvent (safe — no port stealing)
    if (serial.lastLine != null && serial.lastLine.startsWith("fw-")) {
      fwVersion = serial.lastLine.trim();
      serial.lastLine = null;
      fw.parse(fwVersion);
      fwNum = fw.versionNumber;
      addLog("FW: " + fwVersion);
      featureList.clear();
      buildFeatureList();
      fwRequestSent = false;
      return;
    }

    // Also check lastRead from serialEvent
    if (serial.lastRead != null && serial.lastRead.startsWith("fw-")) {
      fwVersion = serial.lastRead.trim();
      fw.parse(fwVersion);
      fwNum = fw.versionNumber;
      addLog("FW: " + fwVersion);
      featureList.clear();
      buildFeatureList();
      fwRequestSent = false;
      return;
    }

    // Timeout after ~5 seconds (300 frames at 60fps)
    if (fwWaitFrames > 300) {
      addLog(strings.get("FW не отвечает — попробуйте перезалить прошивку", "FW not responding — try reflashing the firmware"));
      fwRequestSent = false;
    }
  }

  void buildFeatureList() {
    if (fw.hatSwitch) featureList.add("Hat Switch (D-pad)");
    if (fw.buttonMatrix) featureList.add("4×4 Button Matrix");
    if (fw.buttonBox) featureList.add("Button Box (SN74ALS166)");
    if (fw.xyShifter) featureList.add(strings.get("XY Аналоговый шифтер", "XY Analog Shifter"));
    if (fw.extraButtons) featureList.add(strings.get("2 доп. кнопки", "2 extra buttons"));
    if (fw.magneticEncoder) featureList.add(strings.get("Магнитный энкодер AS5600", "Magnetic encoder AS5600"));
    if (fw.noOpticalEncoder) featureList.add(strings.get("Потенциометр (без оптики)", "Potentiometer (no optical)"));
    if (fw.encoderZIndex) featureList.add(strings.get("Энкодер с Z-index", "Encoder with Z-index"));
    if (fw.loadCell) featureList.add(strings.get("Load Cell тормоз (HX711)", "Load Cell brake (HX711)"));
    if (fw.externalDAC) featureList.add(strings.get("Внешний DAC (MCP4725)", "External DAC (MCP4725)"));
    if (fw.twoFFB) featureList.add(strings.get("2 оси FFB", "2-axis FFB"));
    if (fw.splitAxis) featureList.add("Split Z-axis");
    if (fw.hardwareCenter) featureList.add(strings.get("HW кнопка центрирования", "HW center button"));
    if (fw.analogFFB) featureList.add(strings.get("Аналоговый FFB выход", "Analog FFB output"));
    if (fw.proMicroPins) featureList.add(strings.get("ProMicro распиновка", "ProMicro pinout"));
    if (featureList.size() == 0) featureList.add(strings.get("Базовая прошивка (без опций)", "Basic firmware (no options)"));
  }

  void buildButtonAxisMap() {
    axisMap.clear();
    axisMap.add("X  — Руль (энкодер)");
    if (fw.xyShifter || true) {
      axisMap.add("Y  — Тормоз / педаль");
      axisMap.add("Z  — Акселератор");
      axisMap.add("RX — Сцепление");
      axisMap.add("RY — Ручной тормоз");
    }

    buttonMap.clear();
    int numBtn = 8;
    if (fw.hatSwitch) {
      buttonMap.add("HAT — D-pad (переключатель POV)");
      numBtn = 4;
    }
    if (fw.buttonMatrix) numBtn = 16;
    if (fw.buttonBox) numBtn = 16;
    if (fw.extraButtons) numBtn += 2;
    for (int i = 0; i < numBtn; i++) {
      buttonMap.add("BTN " + i + " — пин " + getPinName(i));
    }
    if (fw.xyShifter) {
      buttonMap.add("SHF 0 — 1-я передача");
      buttonMap.add("SHF 1 — 2-я передача");
    }
  }

  String getPinName(int i) {
    String[] pins = {"2", "3", "4", "5", "6", "7", "8", "9",
                     "10", "11", "12", "13", "A0", "A1", "A2", "A3"};
    if (i < pins.length) return pins[i];
    return "?" + i;
  }

  void saveConfig() {
    try {
      saveStrings("data/COM_cfg.txt", new String[]{comPorts[selPort]});
      addLog(strings.get("COM_cfg.txt сохранён", "COM_cfg.txt saved"));
    } catch (Throwable t) {
      addLog(strings.get("Ошибка сохранения: ", "Save error: ") + t.getMessage());
    }
  }

  // ============ UI HELPERS ============
  boolean btn(float x, float y, float w, float h, String label, int baseCol) {
    boolean hov = mouseX >= x && mouseX <= x + w && mouseY >= y && mouseY <= y + h;
    fill(hov ? colBtnH : baseCol);
    noStroke();
    rect(x, y, w, h, 4);
    fill(255);
    textAlign(CENTER, CENTER);
    textSize(13);
    text(label, x + w / 2, y + h / 2);
    return hov && mousePressed;
  }

  // ============ MOUSE ============
  void handleClick() {
    if (!active) return;
    float pw = min(720, WIN_W - 60);
    float ph = min(540, WIN_H - 40);
    float px = (WIN_W - pw) / 2;
    float py = (WIN_H - ph) / 2;
    float cx = px + 20;
    float listW = pw - 48;
    float itemH = 36;

    if (step == 1) {
      // COM port selection
      float cy = py + 58 + 60;
      float maxItems = min(comPorts.length, (int)((ph - 130 - 120) / (itemH + 3)));
      for (int i = 0; i < comPorts.length && i < maxItems; i++) {
        float iy = cy + i * (itemH + 3);
        if (mouseX >= cx + 4 && mouseX <= cx + 4 + listW && mouseY >= iy && mouseY <= iy + itemH) {
          selPort = i;
          return;
        }
      }
    }

    if (step == 3) {
      // 1) тоггл маркеров калибровки
      if (mouseX >= calToggleX && mouseX <= calToggleX + calToggleW &&
          mouseY >= calToggleY && mouseY <= calToggleY + calToggleH) {
        calMarkersVisible = !calMarkersVisible;
        return;
      }
      // 2) клик по кнопке-функции — сменить роль оси (циклически, со свопом).
      // Ось 0 (X) пропускаем — аппаратный энкодер, роль «Руль» не снимается.
      for (int i = 1; i < 5; i++) {
        if (mouseX >= roleBtnX[i] && mouseX <= roleBtnX[i] + roleBtnW[i] &&
            mouseY >= rowY[i] + 6 && mouseY <= rowY[i] + 32) {
          int next = (axisRole[i] % 4) + 1;
          int j = axisForRole(next);
          int prev = axisRole[i];
          axisRole[i] = next;
          if (j >= 0 && j != i) axisRole[j] = prev;
          saveAxisRoles();
          addLog(axisPhys[i] + " → " + ROLE_NAMES[next]);
          return;
        }
      }
      // 3) захват маркеров мин/макс (только когда видимы; ось X/руль без калибровки)
      if (calMarkersVisible) {
        for (int i = 1; i < 5; i++) {
          float bx = rowBarX[i], bw = rowBarW[i], by = rowBarY[i];
          if (mouseX >= bx - 8 && mouseX <= bx + bw + 8 &&
              mouseY >= by - 8 && mouseY <= by + wizBarH + 8) {
            float minX = bx + bw * calMin[i];
            float maxX = bx + bw * calMax[i];
            if (abs(mouseX - minX) <= abs(mouseX - maxX)) {
              calDraggingMin[i] = true; releasedAxis = i; releasedIsMin = true;
            } else {
              calDraggingMax[i] = true; releasedAxis = i; releasedIsMin = false;
            }
            return;
          }
        }
      }
    }
  }
}
