// ============================================================
// SetupWizard — first-run configuration overlay
// Multi-step wizard: HID → COM → Firmware → Features → Bind → Done
// ============================================================

class SetupWizard {
  boolean active = false;
  int step = 0;
  // wizard steps: 0=welcome  1=auto board search  2=auto firmware install  3=bind  4=done
  // Никаких «тыкалок» с портами: мастер сам ищет плату по всем COM-портам
  // (в т.ч. совсем без прошивки — по появлению нового порта), сам определяет
  // конфигурацию по буквам ответа 'V' и сам ставит подходящую прошивку с GitHub.

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
  String fwVersion = "";
  int fwNum = 0;

  // ---- автопоиск платы (шаг 1) ----
  HashSet<String> portsAtStart = new HashSet<String>();  // порты, существовавшие до подключения платы
  volatile boolean scanBusy = false;
  volatile String scanStatus = "";
  volatile String foundPort = null;     // порт найденной платы
  volatile String foundFwLine = null;   // строка "fw-v..." (null = плата без нашей прошивки)
  boolean scanHandled = false;          // результат уже обработан в draw()
  int scanRound = 0;

  // ---- автопрошивка (шаг 2) ----
  boolean blankBoard = false;           // плата была без прошивки — ставили с нуля
  boolean fwStepStarted = false;
  boolean fwSkipOffered = false;
  int fwStepFrames = 0;

  // ---- конфигуратор для «чистой» платы (без прошивки — 'V' спросить некому) ----
  // Пользователь выбирает из реально собранных CI вариантов (manifest.json релиза),
  // ничего не ставится по умолчанию втихую.
  String chosenLetters = null;   // выбор пользователя; null — ещё не выбрано
  int selConfigVariant = -1;
  float cfgListY, cfgListH, cfgRowH = 46;
  float cfgScroll = 0;

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

  // защёлка кнопок: btn() раньше срабатывал каждый кадр, пока держишь мышь
  // (mousePressed — состояние, а не событие), из-за чего клики «проваливались»
  // сквозь сменившийся экран и действия выполнялись многократно
  boolean btnLatch = false;

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
    foundPort = null;
    foundFwLine = null;
    scanHandled = false;
    blankBoard = false;
    fwStepStarted = false;
    fwSkipOffered = false;
    fwStepFrames = 0;
    chosenLetters = null;
    selConfigVariant = -1;
    cfgScroll = 0;
    firmwareUpdater.autoFlash = true; // в мастере прошиваем сразу, без тостов
  }

  void finish() {
    active = false;
    firmwareUpdater.autoFlash = false;
  }

  void addLog(String s) {
    logLines.add(s);
    if (logLines.size() > 6) logLines.remove(0);
  }

  // ============ MAIN DRAW ============
  void draw() {
    if (!active) return;
    if (!mousePressed) btnLatch = false; // кнопка отпущена — снова разрешаем клики btn()
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
    String[] stepNames = {"", strings.get("Поиск платы", "Board search"), strings.get("Прошивка", "Firmware"), strings.get("Привязка", "Binding"), ""};
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
      case 1: drawScan(cx, cy, cw, ch); break;
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
    text(strings.get("Первый запуск. Мастер всё сделает сам:", "First run. The wizard does everything automatically:"), x, y);
    y += 26;
    text(strings.get("• найдёт плату Arduino Leonardo (прошита она или нет — неважно);", "• finds your Arduino Leonardo board (flashed or blank — doesn't matter);"), x, y); y += 20;
    text(strings.get("• если прошивка уже есть — определит конфигурацию по ней и обновит при необходимости;", "• if it's already flashed — reads its configuration and updates it if needed;"), x, y); y += 20;
    text(strings.get("• если плата чистая — попросит выбрать, что к ней подключено, и установит подходящую прошивку с официального репозитория.", "• if it's blank — asks you what's connected to it, then installs the matching firmware from the official repository."), x, y); y += 32;
    fill(colText);
    text(strings.get("Подключите плату по USB и нажмите «Начать».", "Plug the board in via USB and press Start."), x, y);
    y += 40;
    if (btn(x + w / 2 - btnW / 2, y, btnW, btnH, strings.get("Начать", "Start"), colBtn)) {
      beginSearch();
    }
  }

  // Запуск шага 1: запоминаем текущий список портов (чтобы заметить НОВЫЙ порт,
  // когда пользователь воткнёт непрошитую плату) и начинаем циклический опрос.
  void beginSearch() {
    step = 1;
    foundPort = null;
    foundFwLine = null;
    scanHandled = false;
    scanRound = 0;
    portsAtStart.clear();
    try { for (String p : jssc.SerialPortList.getPortNames()) portsAtStart.add(p); } catch (Throwable t) {}
    scanStatus = strings.get("Поиск платы...", "Searching for the board...");
    addLog(strings.get("Поиск платы по всем портам...", "Scanning all ports for the board..."));
  }

  // ============ STEP 1: Автопоиск платы ============
  void drawScan(float x, float y, float w, float h) {
    textAlign(LEFT, TOP);
    fill(colText);
    textSize(15);
    text(strings.get("Шаг 1: Поиск платы (автоматически)", "Step 1: Board search (automatic)"), x, y);
    y += 36;

    // обработка результата фонового скана
    if (foundPort != null && !scanHandled) {
      scanHandled = true;
      onBoardFound();
      return;
    }

    // раз в ~1.5 с запускаем очередной проход по портам
    if (!scanBusy && foundPort == null && frameCount % 90 == 0) scanOnce();

    // анимированный индикатор
    fill(colAcc); noStroke();
    float t = millis() / 400.0;
    for (int i = 0; i < 3; i++) {
      float a = 4 + 3 * sin(t + i * 0.9);
      ellipse(x + 12 + i * 22, y + 8, a, a);
    }
    fill(colText); textSize(13);
    text(scanStatus, x + 80, y);
    y += 34;
    fill(colDim); textSize(12);
    text(strings.get("Подключите плату Arduino Leonardo по USB — мастер найдёт её сам.", "Plug the Arduino Leonardo board in via USB — the wizard will find it."), x, y); y += 20;
    text(strings.get("Если плата была подключена заранее и не находится — передёрните USB-кабель.", "If the board was already plugged in and isn't found — re-plug the USB cable."), x, y); y += 20;
    text(strings.get("Плата без прошивки тоже подойдёт: прошивка будет установлена на следующем шаге.", "A blank board works too: firmware will be installed on the next step."), x, y);
  }

  // Один проход поиска: 1) порт, отвечающий на 'V' — наша плата с прошивкой;
  // 2) порт, появившийся после старта мастера — плата без прошивки (или с чужой).
  void scanOnce() {
    scanBusy = true;
    scanRound++;
    Thread t = new Thread(new Runnable() {
      public void run() {
        try {
          String[] ports = jssc.SerialPortList.getPortNames();
          for (String p : ports) {
            String line = probeFwVersionLine(p);
            if (line != null) { foundFwLine = line; foundPort = p; return; }
          }
          for (String p : ports) {
            if (!portsAtStart.contains(p)) { foundFwLine = null; foundPort = p; return; }
          }
          scanStatus = strings.get("Плата не найдена. Подключите её по USB... (попытка " + scanRound + ")",
                                   "Board not found. Plug it in via USB... (attempt " + scanRound + ")");
        } catch (Throwable tt) {
          scanStatus = strings.get("Ошибка поиска: ", "Scan error: ") + tt.getMessage();
        } finally {
          scanBusy = false;
        }
      }
    });
    t.setDaemon(true);
    t.start();
  }

  // Плата найдена: сохраняем порт, подключаемся (если есть прошивка) и уходим на шаг 2
  void onBoardFound() {
    try { saveStrings(papplet.dataPath("COM_cfg.txt"), new String[]{foundPort}); } catch (Throwable t) {}
    if (foundFwLine != null) {
      blankBoard = false;
      addLog(strings.get("Плата найдена: ", "Board found: ") + foundPort + "  (" + foundFwLine + ")");
      if (serial.connect(foundPort, 115200)) {
        attachHID();
        requestDeviceState(); // ответ 'V' запустит firmwareUpdater.checkForUpdate() (autoFlash)
      } else {
        addLog(strings.get("Не удалось открыть порт", "Failed to open the port"));
      }
    } else {
      blankBoard = true;
      addLog(strings.get("Найдена плата без прошивки: ", "Found a board without firmware: ") + foundPort);
      // 'V' спросить некому — на шаге 2 покажем конфигуратор (список реальных сборок
      // CI) и дождёмся выбора пользователя, прежде чем что-либо ставить на плату.
      firmwareUpdater.fetchConfiguratorVariants();
    }
    step = 2;
    fwStepStarted = true;
    fwStepFrames = 0;
  }

  // Автопоиск HID-устройства руля (как раньше делал doConnect)
  void attachHID() {
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
  }

  // ============ STEP 2: Прошивка ============
  void drawFirmware(float x, float y, float w, float h) {
    textAlign(LEFT, TOP);
    fill(colText);
    textSize(15);
    text(blankBoard && chosenLetters == null ? strings.get("Шаг 2: Что подключено к плате?", "Step 2: What's connected to the board?")
                                              : strings.get("Шаг 2: Прошивка (автоматически)", "Step 2: Firmware (automatic)"), x, y);
    y += 36;

    // Плата без прошивки: сначала спрашиваем пользователя, ЧТО к ней подключено
    // (энкодер, шифтер, load cell...) — определить это программно невозможно, 'V'
    // ответить некому. Ничего не устанавливаем, пока не выбрано и не подтверждено.
    if (blankBoard && chosenLetters == null) {
      drawConfigurator(x, y, w, h);
      return;
    }

    fwStepFrames++;

    // подтягиваем распознанную версию из глобального парсера
    if (fw != null && fw.fullVersionString != null && fw.fullVersionString.length() > 0) {
      if (!fwVersion.equals(fw.fullVersionString)) {
        fwVersion = fw.fullVersionString;
        fwNum = fw.versionNumber;
        featureList.clear();
        buildFeatureList();
      }
    }

    boolean fwReady = serial.isConnected() && fw != null && fw.versionNumber > 0;

    textSize(13);
    if (firmwareUpdater.flashing) {
      fill(colWarn);
      text(strings.get("Установка прошивки — не отключайте плату...", "Installing firmware — do not unplug the board..."), x, y);
      y += 24;
    } else if (firmwareUpdater.lastFlashFinished && !firmwareUpdater.lastFlashOk) {
      fill(colErr);
      text(strings.get("Не удалось установить прошивку (см. журнал ниже).", "Failed to install firmware (see the log below)."), x, y);
      y += 34;
      if (btn(x, y, 180, btnH, strings.get("Повторить", "Retry"), colBtn)) {
        if (blankBoard) firmwareUpdater.installFresh(foundPort, chosenLetters);
        else firmwareUpdater.startUpdate();
      }
      if (btn(x + 200, y, 180, btnH, strings.get("Выбрать другую конфигурацию", "Pick a different configuration"), colBtnO) && blankBoard) {
        chosenLetters = null; selConfigVariant = -1; // назад в конфигуратор
      }
      if (fwReady && btn(x + 200, y, 180, btnH, strings.get("Пропустить", "Skip"), colBtnO)) {
        advanceToBinding();
      }
      y += btnH + 10;
    } else if (fwReady && (firmwareUpdater.upToDate || firmwareUpdater.lastFlashOk || firmwareUpdater.checkFailed)) {
      // готово: либо уже последняя сборка, либо только что прошили, либо нет сети (едем дальше как есть)
      fill(colOk);
      String okMsg = firmwareUpdater.lastFlashOk ? strings.get("Прошивка установлена: ", "Firmware installed: ") + fwVersion
                   : firmwareUpdater.upToDate    ? strings.get("Прошивка актуальна: ", "Firmware is up to date: ") + fwVersion
                   : strings.get("Нет сети — оставляю текущую прошивку: ", "No network — keeping current firmware: ") + fwVersion;
      text("  ✓  " + okMsg, x, y);
      y += 26;
      addLogOnce(okMsg);
      advanceToBinding();
      return;
    } else {
      fill(colWarn);
      text(blankBoard ? strings.get("Подготовка установки прошивки...", "Preparing firmware installation...")
                      : strings.get("Проверка версии и обновление...", "Checking version and updating..."), x, y);
      y += 24;
    }

    if (fwVersion.length() > 0) {
      fill(colDim); textSize(12);
      text(strings.get("Обнаружено: ", "Detected: ") + fwVersion + "  (v" + fwNum + ")", x, y);
      y += 20;
      for (int i = 0; i < featureList.size(); i++) {
        text("  •  " + featureList.get(i), x + 6, y);
        y += 17;
      }
    }

    // страховка: если через ~60 с ничего не решилось — даём выйти вручную
    if (fwStepFrames > 3600 && !firmwareUpdater.flashing) {
      float byy = y + 16;
      if (fwReady) {
        if (btn(x, byy, 220, btnH, strings.get("Продолжить без обновления", "Continue without updating"), colBtnO)) advanceToBinding();
      } else {
        if (btn(x, byy, 220, btnH, strings.get("Начать поиск заново", "Restart the search"), colBtnO)) beginSearch();
      }
    }
  }

  // Конфигуратор для платы без прошивки: показывает реально собранные CI варианты
  // (manifest.json последнего релиза) с человекочитаемым списком опций, пользователь
  // выбирает и подтверждает — только тогда что-то устанавливается на плату.
  void drawConfigurator(float x, float y, float w, float h) {
    fill(colDim); textSize(12); textAlign(LEFT, TOP);
    text(strings.get("На плате нет прошивки — определить оборудование программно нельзя. Выберите вручную, что подключено:", "The board has no firmware — hardware can't be auto-detected. Manually select what's connected:"), x, y, w, 32);
    y += 36;

    FirmwareUpdater fwu = firmwareUpdater;
    if (fwu.configuratorLoading) {
      fill(colWarn); textSize(13);
      text(strings.get("Загрузка списка доступных сборок...", "Loading available builds..."), x, y);
      return;
    }
    if (fwu.configuratorError != null) {
      fill(colErr); textSize(12);
      text(strings.get("Ошибка: ", "Error: ") + fwu.configuratorError, x, y, w, 40);
      y += 46;
      if (btn(x, y, 180, btnH, strings.get("Повторить", "Retry"), colBtn)) {
        fwu.configuratorError = null;
        fwu.fetchConfiguratorVariants();
      }
      return;
    }
    if (fwu.configuratorVariants.isEmpty()) {
      fill(colErr); textSize(12);
      text(strings.get("Список сборок пуст (странно) — попробуйте обновить.", "Build list is empty (odd) — try refreshing."), x, y);
      y += 24;
      if (btn(x, y, 180, btnH, strings.get("Обновить", "Refresh"), colBtn)) fwu.fetchConfiguratorVariants();
      return;
    }

    ArrayList<FwVariant> vs = fwu.configuratorVariants;
    float listTop = y;
    float listBot = y + h - 56;
    cfgListY = listTop; cfgListH = listBot - listTop;
    int visibleRows = max(1, int(cfgListH / cfgRowH));
    float maxScroll = max(0, vs.size() * cfgRowH - cfgListH);
    cfgScroll = constrain(cfgScroll, 0, maxScroll);

    // область списка (обрезаем содержимое по границам через clip не поддерживается в
    // Processing напрямую — просто не рисуем строки, полностью ушедшие за границы)
    stroke(colEdge); noFill(); rect(x, listTop, w, cfgListH);
    int firstRow = max(0, int(cfgScroll / cfgRowH));
    int lastRow = min(vs.size(), firstRow + visibleRows + 2);
    for (int i = firstRow; i < lastRow; i++) {
      float ry = listTop + i * cfgRowH - cfgScroll;
      if (ry + cfgRowH < listTop || ry > listBot) continue;
      FwVariant v = vs.get(i);
      boolean sel = i == selConfigVariant;
      boolean hov = mouseX >= x + 4 && mouseX <= x + w - 4 && mouseY >= max(ry, listTop) && mouseY <= min(ry + cfgRowH - 3, listBot);
      fill(sel ? color(45, 90, 130) : (hov ? colItemH : colItem)); noStroke();
      rect(x + 4, ry, w - 8, cfgRowH - 3, 4);
      fill(sel ? 255 : colText); textAlign(LEFT, TOP); textSize(11);
      String letters = v.letters.length() > 0 ? v.letters : "-";
      text(letters, x + 12, ry + 4);
      fill(sel ? color(220, 230, 245) : colDim); textSize(9);
      String feats = v.features.isEmpty() ? strings.get("базовая сборка, без доп. опций", "base build, no extra options") : join(v.features.toArray(new String[0]), " · ");
      text(feats, x + 12, ry + 20, w - 24, cfgRowH - 22);
      // клик по строке — выделить (реальный клик ловим ниже через простой hit-test,
      // используя тот же btnLatch-паттерн, что и btn(), чтобы не срабатывало на каждый кадр)
      if (hov && mousePressed && !btnLatch) { selConfigVariant = i; btnLatch = true; }
    }
    if (maxScroll > 0) {
      fill(colDim); textAlign(RIGHT, TOP); textSize(9);
      text(strings.get("прокрутка колесом мыши", "scroll with mouse wheel"), x + w - 4, listTop - 12);
    }

    float btnY = listBot + 10;
    if (selConfigVariant >= 0 && selConfigVariant < vs.size()) {
      FwVariant sel = vs.get(selConfigVariant);
      if (btn(x + w - 220, btnY, 220, btnH, strings.get("Установить эту прошивку", "Install this firmware"), colBtn)) {
        chosenLetters = sel.letters;
        firmwareUpdater.installFresh(foundPort, chosenLetters);
      }
    } else {
      fill(colDim); textAlign(RIGHT, CENTER); textSize(11);
      text(strings.get("Выберите вариант из списка выше", "Pick a variant from the list above"), x + w - 12, btnY + btnH / 2);
    }
  }

  // Прокрутка списка конфигуратора (вызывается из главного mouseWheel())
  void handleScroll(float delta) {
    if (active && step == 2 && blankBoard && chosenLetters == null) {
      cfgScroll += delta * 40;
    }
  }

  String lastOnceMsg = "";
  void addLogOnce(String m) {
    if (!m.equals(lastOnceMsg)) { lastOnceMsg = m; addLog(m); }
  }

  void advanceToBinding() {
    step = 3;
    buildButtonAxisMap();
    if (gpad == null) attachHID(); // после прошивки «чистой» платы HID появился только что
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
        proto.setParam(calCmdMin[i] + " ", val); // через очередь + автосохранение
        addLog(calCmdMin[i] + " = " + val);
      } else if (!releasedIsMin && i >= 1 && calCmdMax[i].length() > 0) {
        int val = round(calMax[i] * calAdMax);
        proto.setParam(calCmdMax[i] + " ", val);
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
    text("COM: " + (foundPort != null ? foundPort : "?"), x, y); y += 22;
    text("FW:  " + fwVersion, x, y); y += 22;
    text(strings.get("Конфиг сохранён в data/COM_cfg.txt", "Config saved to data/COM_cfg.txt"), x, y);
    y += 50;
    if (btn(x + w / 2 - btnW / 2, y, btnW, btnH, strings.get("Готово", "Done"), colOk)) {
      finish();
      // re-init serial with saved config
      try {
        File f = new File(papplet.dataPath("COM_cfg.txt"));
        if (f.exists()) {
          String[] port = papplet.loadStrings("COM_cfg.txt");
          if (port != null && port.length > 0) {
            if (!serial.isConnected()) serial.connect(trim(port[0]), 115200);
            requestDeviceState();
          }
        }
      } catch (Throwable t) {
        Log.error("SERIAL", "Post-wizard init: " + t.getMessage());
      }
    }
  }

  // ============ ACTIONS ============
  // (устаревшие doHIDCheck/doDiscoverCOM/doConnect/updateFwPoll удалены: порт больше не выбирается
  // вручную, версия прошивки подтягивается из глобального парсера в drawFirmware)
  void updateFwPoll() { }

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
      if (foundPort == null || foundPort.length() == 0) { addLog(strings.get("Порт не определён", "Port unknown")); return; }
      // dataPath, а не относительный путь: в упакованном приложении рабочая папка
      // может не совпадать с папкой data/, из-за чего конфиг «терялся»
      saveStrings(papplet.dataPath("COM_cfg.txt"), new String[]{foundPort});
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
    boolean fired = hov && mousePressed && !btnLatch;
    if (fired) btnLatch = true; // одно срабатывание на одно нажатие
    return fired;
  }

  // ============ MOUSE ============
  void handleClick() {
    if (!active) return;
    float pw = min(720, WIN_W - 60);
    float ph = min(540, WIN_H - 40);
    float px = (WIN_W - pw) / 2;
    float py = (WIN_H - ph) / 2;
    // шаг 1 теперь полностью автоматический — кликов по списку портов больше нет

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
