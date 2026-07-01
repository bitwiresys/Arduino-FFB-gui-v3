// Главный экран. Слева — монитор (руль, кнопки, состояние + живые оси).
// В центре — калибровка осей карточками (роль, мин/макс, команды Y*).
// Справа — ВСЕ 12 параметров FFB карточками (отдельной вкладки больше нет).
class DashboardTab {
  float cx, cy, cw, ch;
  boolean[] buttonStates = new boolean[24];
  int hatValue = 0;
  float wheelAngle = 0;

  int colBg = color(24, 24, 30), colEdge = color(55, 55, 66);
  int colText = color(195, 200, 210), colDim = color(125, 130, 140), colAcc = color(70, 150, 230);
  int colCard = color(31, 32, 40), colCardE = color(50, 52, 64);

  color[] axColors = { color(70, 150, 230), color(200, 70, 70), color(60, 180, 120),
                       color(200, 180, 60), color(180, 100, 200) };

  // ---- калибровка осей ----
  // ось 0 (X) — энкодер/руль (мин/макс не применяется, калибруется на вкладке Энкодер).
  // оси 1..4 (Y,Z,RX,RY) — аналоговые, мин/макс через команды Y*.
  String[] axPhys = { "X", "Y", "Z", "RX", "RY" };
  String[] cmdMin = { "", "YA ", "YC ", "YE ", "YG " };
  String[] cmdMax = { "", "YB ", "YD ", "YF ", "YH " };
  float[] calMin = { 0, 0, 0, 0, 0 };
  float[] calMax = { 1023, 1023, 1023, 1023, 1023 };
  float adMax = 1023;

  // ---- ВСЕ 12 параметров FFB ----
  int[]    ctlIdx  = { 0, 1, 10, 2, 3, 4, 5, 6, 7, 8, 9, 11 };
  String[] ctlName;
  float[]  ctlMin  = { 30, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
  float[]  ctlMax  = { 1800, 2, 20, 2, 2, 2, 2, 2, 2, 2, 2, 255 };
  String[] ctlTip;

  // геометрия панелей
  float capX, capY, capW, capH;     // калибровка осей
  float epX, epY, epW, epH;         // FFB
  float fGridTop, fColW, fRowH;     // сетка FFB
  int fCols = 2, fRows = 6;
  int dragCtl = -1;                 // активный слайдер FFB
  int dragAxis = -1, dragMM = -1;   // активная ось и маркер (0=мин,1=макс)

  // сохранённая геометрия для хит-тестов (заполняется в draw)
  float[] axBarX = new float[5], axBarW = new float[5], axBarY = new float[5];
  float axBarH = 22;
  float[] axRoleX = new float[5], axRoleY = new float[5], axRoleW = new float[5];
  float axRoleH = 26;
  float[] ctlCardX = new float[12], ctlCardY = new float[12], ctlCardW = new float[12], ctlCardH = new float[12];
  float[] ctlTrkX = new float[12], ctlTrkY = new float[12], ctlTrkW = new float[12];
  float[] ctlChkX = new float[12], ctlChkY = new float[12];   // чекбоксы desktop-эффектов в карточках (-1 = нет чекбокса)
  float ctlChkS = 14;
  // dustin's rig, added — invert/disable pill-переключатели на карточках осей (команды 'I'/'D' прошивки)
  float[] axInvX = new float[5], axInvY = new float[5];
  float[] axDisX = new float[5], axDisY = new float[5];
  float axPillW = 60, axPillH = 22;   // общие для всех 5 осей за кадр (см. drawAxisCard)
  float wheelBtnX, wheelBtnY, wheelBtnW, wheelBtnH;
  float resetBtnX, resetBtnY, resetBtnW, resetBtnH;

  // эффекты, у которых есть desktop-тоггл (постоянно включён поверх игры): Демпфер, Трение, Пружина, Инерция
  boolean isDesktopToggle(int idx) { return idx == 2 || idx == 3 || idx == 6 || idx == 7; }

  int langVer = -1;   // последняя версия strings, для которой пересобраны ctlName/ctlTip

  DashboardTab(float cx, float cy, float cw, float ch) {
    this.cx = cx; this.cy = cy; this.cw = cw; this.ch = ch;
    refreshLabels();
  }

  // Пересобрать названия и описания FFB-эффектов под текущий язык.
  // ctlName/ctlTip — поля объекта, заполняются один раз в конструкторе;
  // без этого пересчёта переключение языка их бы не затрагивало.
  void refreshLabels() {
    ctlName = new String[]{ strings.get("Поворот руля", "Rotation"), strings.get("Общий гейн", "Global Gain"), strings.get("Мин. момент", "Min Torque"),
                       strings.get("Демпфер", "Damper"), strings.get("Трение", "Friction"), strings.get("Пост. сила", "Constant"), strings.get("Периодич.", "Periodic"),
                       strings.get("Пружина", "Spring"), strings.get("Инерция", "Inertia"), strings.get("Автоцентр", "Centering"), strings.get("Стоп-упор", "Stop"), strings.get("Баланс Л/П", "Balance L/R") };
    ctlTip = new String[]{
      strings.get("Угол поворота руля от упора до упора. Дрифт ~360-540°, ралли ~720-900°, формула ~270-360°. Применяется сразу.", "Rotation angle lock-to-lock. Drift ~360-540°, rally ~720-900°, F1 ~270-360°. Applied immediately."),
      strings.get("Главная сила обратной связи (мастер-громкость FFB). Если руль стучит в упор/клипует - уменьшите; если слабо - увеличьте.", "Master FFB gain. If wheel clips/bangs at stops - reduce; if weak - increase."),
      strings.get("Стартовый момент. Компенсирует трение покоя и пусковой ток мотора (важно для DC-моторов).", "Min torque. Compensates motor stiction and startup current (important for DC motors)."),
      strings.get("Вязкость руля. Гасит резкие рывки и колебания.", "Wheel viscosity. Dampens sharp jolts and oscillations."),
      strings.get("Постоянное сопротивление вращению, как механическое трение.", "Constant rotational resistance, like mechanical friction."),
      strings.get("Усиление эффектов постоянной силы (Constant Force), которые шлёт игра.", "Gain for Constant Force effects sent by the game."),
      strings.get("Усиление периодических эффектов от игры (вибрация, синус, пила и т.п.).", "Gain for periodic effects from the game (vibration, sine, sawtooth, etc)."),
      strings.get("Сила, возвращающая руль к центру.", "Force returning the wheel to center."),
      strings.get("Имитация массы маховика мотора.", "Simulates motor flywheel mass."),
      strings.get("Доп. автоцентрирование, если игра не возвращает руль в центр.", "Extra centering if the game doesn't return the wheel to center."),
      strings.get("Жёсткость виртуальных упоров в конце хода руля.", "Stiffness of virtual endstops at the end of wheel travel."),
      strings.get("Баланс силы влево/вправо. 128 = симметрично.", "Force balance left/right. 128 = symmetrical.") };
    langVer = strings.version;
  }

  void draw(AxisConfig[] axes, boolean[] axisEn, int ffbX, int ffbY, boolean ffbMon) {
    if (langVer != strings.version) refreshLabels();
    pushStyle();
    textAlign(LEFT, TOP);
    if (fw != null) adMax = fw.getDefaultADMax();
    float top = cy + 8;                 // 38
    float bot = cy + ch - 8;            // 792
    // левая колонка
    float lx = 8, lw = 288;
    drawWheelPanel(lx, top, lw, 206, axes);
    drawButtonsPanel(lx, top + 212, lw, 120);
    drawStatusPanel(lx, top + 338, lw, bot - (top + 338), axes);
    // центральная колонка — калибровка осей
    float mx = 304, mw = 334;
    drawAxisCal(mx, top, mw, bot - top, axes);
    // правая колонка — FFB
    float rxx = 648;
    drawControlPanel(rxx, top, cw - rxx - 8, bot - top);
    popStyle();
  }

  // ---- общие хелперы ----
  void panel(float x, float y, float w, float h, String t) {
    fill(colBg); stroke(colEdge); strokeWeight(1); rect(x, y, w, h, 6);
    if (t != null) { fill(colText); textAlign(LEFT, TOP); textSize(12); text(t, x + 12, y + 9); }
  }
  void card(float x, float y, float w, float h) {
    fill(colCard); stroke(colCardE); strokeWeight(1); rect(x, y, w, h, 6);
  }
  boolean hov(float x, float y, float w, float h) { return mouseX >= x && mouseX <= x + w && mouseY >= y && mouseY <= y + h; }
  void button(float x, float y, float w, float h, String label, int bg, boolean active) {
    int c = active ? bg : (hov(x, y, w, h) ? color(58, 60, 70) : color(42, 44, 54));
    fill(c); stroke(active ? lerpColor(bg, color(255), 0.3) : colEdge); strokeWeight(active ? 2 : 1); rect(x, y, w, h, 5);
    fill(active ? color(255) : colText); noStroke(); textAlign(CENTER, CENTER); textSize(11); text(label, x + w / 2, y + h / 2 - 1);
  }

  // ============ РУЛЬ ============
  void drawWheelPanel(float x, float y, float w, float h, AxisConfig[] axes) {
    panel(x, y, w, h, strings.get("Положение руля", "Wheel Position"));
    float cxw = x + w / 2, cyw = y + 86, r = 60;
    float rotDeg = max(effects[0].gain, 1);
    int wheelAx = axisForRole(0); if (wheelAx < 0) wheelAx = 0;
    wheelAngle = lerp(wheelAngle, radians(axes[wheelAx].rawValue * rotDeg / 2.0), 0.4);
    pushMatrix(); translate(cxw, cyw);
    if (wheelImg != null) { pushMatrix(); rotate(wheelAngle); imageMode(CENTER); image(wheelImg, 0, 0, r * 2, r * 2); popMatrix(); }
    else { noFill(); stroke(90); strokeWeight(3); ellipse(0, 0, r * 2, r * 2); }
    popMatrix();
    tipZone(cxw - r, cyw - r, r * 2, r * 2, strings.get("Текущий угол поворота руля. Крутится на весь диапазон «Поворот руля».", "Current wheel rotation angle. Spans the full “Rotation” range."));
    fill(colText); textAlign(CENTER, TOP); textSize(20);
    text(nf(degrees(wheelAngle), 1, 0) + "°", cxw, cyw + r + 4);
    fill(colDim); textSize(10);
    text(strings.get("диапазон ±", "range ±") + int(rotDeg / 2) + "°", cxw, cyw + r + 28);
    wheelBtnX = x + 10; wheelBtnY = y + h - 30; wheelBtnW = w - 20; wheelBtnH = 24;
    button(wheelBtnX, wheelBtnY, wheelBtnW, wheelBtnH, strings.get("ЦЕНТР (запомнить 0°)", "CENTER (save 0°)"), color(45, 110, 70), false);
    tipZone(wheelBtnX, wheelBtnY, wheelBtnW, wheelBtnH, strings.get("Запомнить текущее положение руля как центр. Выставьте руль ровно и нажмите.", "Remember the current wheel position as center. Straighten the wheel and click."));
  }

  // ============ КНОПКИ / HAT ============
  void drawButtonsPanel(float x, float y, float w, float h) {
    panel(x, y, w, h, strings.get("Кнопки / Hat (монитор)", "Buttons / Hat (Monitor)"));
    float bs = 21, gap = 5;
    float gx = x + 14, gy = y + 30;
    for (int i = 0; i < 24; i++) {
      int rr = i / 8, c = i % 8;
      float bx = gx + c * (bs + gap), byy = gy + rr * (bs + gap);
      boolean on = buttonStates[i];
      fill(on ? color(80, 200, 110) : color(40, 42, 50)); stroke(on ? color(120, 230, 150) : colEdge);
      strokeWeight(1); rect(bx, byy, bs, bs, 4);
      fill(on ? color(0) : colDim); noStroke(); textAlign(CENTER, CENTER); textSize(9);
      text(str(i + 1), bx + bs / 2, byy + bs / 2);
    }
    // Hat — справа от сетки
    float hx = x + w - 38, hy = gy + bs + gap, hr = 18;
    noFill(); stroke(colEdge); strokeWeight(1); ellipse(hx, hy, hr * 2, hr * 2);
    fill(40, 42, 50); stroke(colEdge); ellipse(hx, hy, 14, 14);
    if (hatValue > 0) { pushMatrix(); translate(hx, hy); rotate(TWO_PI * hatValue / 8.0 + PI);
      fill(80, 200, 110); noStroke(); triangle(-4, -hr * 0.4, 4, -hr * 0.4, 0, -hr * 0.75); popMatrix(); }
    fill(colDim); textAlign(CENTER, TOP); textSize(8); text("Hat", hx, hy + hr + 2);
    tipZone(x, y + 24, w, h - 24, strings.get("Монитор кнопок (1:1 с прошивкой): кнопка N = физическая кнопка N. Загорается при нажатии.", "Button monitor (1:1 with firmware): button N = physical button N. Lights up when pressed."));
  }

  // ============ СОСТОЯНИЕ + ЖИВЫЕ ОСИ ============
  void drawStatusPanel(float x, float y, float w, float h, AxisConfig[] axes) {
    panel(x, y, w, h, strings.get("Состояние", "Status"));
    float sy = y + 32;
    boolean conn = serial.isConnected();
    fill(conn ? color(80, 200, 110) : color(210, 80, 80)); noStroke(); ellipse(x + 18, sy + 5, 10, 10);
    fill(colText); textAlign(LEFT, CENTER); textSize(12); text(conn ? strings.get("Подключено", "Connected") : strings.get("Нет связи", "Disconnected"), x + 32, sy + 5);
    tipZone(x, y + 24, w, 22, conn ? strings.get("Связь с Arduino есть. Изменения уходят сразу.", "Connected to Arduino. Changes apply instantly.") : strings.get("Нет связи. Проверьте кабель и COM-порт на вкладке «Настройки».", "No connection. Check the cable and COM port on the Settings tab."));
    sy += 26;
    textAlign(LEFT, TOP); textSize(10);
    if (fw != null && fw.versionNumber > 0) {
      info(x, sy, w, strings.get("Прошивка", "Firmware"), fw.fullVersionString); sy += 19;
      info(x, sy, w, strings.get("Энкодер", "Encoder"), fw.magneticEncoder ? strings.get("магнитный", "magnetic") : (fw.noOpticalEncoder ? strings.get("потенциометр", "potentiometer") : strings.get("оптический", "optical"))); sy += 19;
      info(x, sy, w, "FFB / " + strings.get("Выход", "Output"), (fw.twoFFB ? strings.get("2 оси", "2 axis") : strings.get("1 ось", "1 axis")) + " · " + (fw.externalDAC ? "DAC" : "PWM")); sy += 19;
    } else { fill(colDim); text(strings.get("Прошивка не определена", "Firmware unknown"), x + 12, sy); sy += 19; }
    info(x, sy, w, strings.get("CPR энкодера", "Encoder CPR"), str(encoderTab.cpr)); sy += 19;
    info(x, sy, w, strings.get("Макс. момент", "Max Torque"), str(maxTorque)); sy += 19;
    if (fw != null && fw.magneticEncoder) { drawMotorTempRow(x, sy, w); sy += 19; } // dustin's rig, added

    // разделитель
    sy += 6; stroke(colEdge); strokeWeight(1); line(x + 12, sy, x + w - 12, sy); sy += 8;
    fill(colDim); textAlign(LEFT, TOP); textSize(10); text(strings.get("Живые оси (АЦП)", "Live Axes (ADC)"), x + 12, sy); sy += 18;

    // живые мини-полосы всех 5 осей — заполняем низ панели
    float availH = (y + h - 12) - sy;
    float rowH = constrain(availH / 5.0, 18, 30);
    tipZone(x, sy - 2, w, availH + 2, strings.get("Сырые значения АЦП всех 5 физических осей в реальном времени (та же шкала, что и в калибровке по центру экрана).", "Live raw ADC values of all 5 physical axes (same scale as the calibration bars in the center column)."));
    for (int i = 0; i < 5; i++) {
      float ry = sy + i * rowH;
      float live = constrain(map(axes[i].rawValue, -1, 1, 0, adMax), 0, adMax);
      fill(axColors[i]); noStroke(); rect(x + 12, ry + 2, 22, 12, 3);
      fill(0); textAlign(CENTER, CENTER); textSize(8); text(axPhys[i], x + 23, ry + 8);
      fill(colDim); textAlign(LEFT, CENTER); textSize(9); text(ROLE_NAMES[axisRole[i]], x + 40, ry + 8);
      float tX = x + 108, tW = w - 108 - 50, tY = ry + 3, tH = 10;
      fill(16); stroke(colCardE); strokeWeight(1); rect(tX, tY, tW, tH, 2);
      noStroke(); fill(axColors[i]); rect(tX, tY, tW * live / adMax, tH, 2);
      fill(colAcc); textAlign(RIGHT, CENTER); textSize(10); text(int(live), x + w - 12, ry + 8);
    }
  }
  void info(float x, float y, float w, String k, String v) {
    fill(colDim); textAlign(LEFT, TOP); textSize(10); text(k, x + 12, y);
    fill(colText); textAlign(RIGHT, TOP); text(v, x + w - 12, y);
  }

  // dustin's rig, added — motor temperature row on the main Dashboard, color-coded
  void drawMotorTempRow(float x, float y, float w) {
    fill(colDim); textAlign(LEFT, TOP); textSize(10); text(strings.get("Темп. мотора", "Motor temp"), x + 12, y);
    boolean have = ntcRaw >= 0;
    float c = have ? rawToTempC(ntcRaw) : 0;
    color vCol = ntcTripped ? color(220, 70, 70) : (c > ntcThreshC() * 0.85 ? color(220, 180, 60) : color(120, 200, 140));
    fill(have ? vCol : colDim); textAlign(RIGHT, TOP); textSize(10);
    text(!have ? "—" : (nf(c, 1, 0) + "°C" + (ntcTripped ? " ⚠" : "")), x + w - 12, y);
    tipZone(x, y - 2, w, 18, strings.get("Живая температура мотора. Порог критического отключения FFB — на вкладке «Настройки».", "Live motor temperature. The FFB critical cutoff threshold is on the Settings tab."));
  }
  void drawWrapped(String s, float x, float y, float w, float lh) {
    textAlign(LEFT, TOP);
    String[] words = split(s, ' '); String cur = ""; float yy = y;
    for (String wd : words) { String t = cur.length() == 0 ? wd : cur + " " + wd;
      if (textWidth(t) > w && cur.length() > 0) { text(cur, x, yy); yy += lh; cur = wd; } else cur = t; }
    if (cur.length() > 0) text(cur, x, yy);
  }

  // ============ КАЛИБРОВКА ОСЕЙ (карточки) ============
  void drawAxisCal(float x, float y, float w, float h, AxisConfig[] axes) {
    capX = x; capY = y; capW = w; capH = h;
    panel(x, y, w, h, strings.get("Калибровка и привязка осей", "Axis Calibration & Binding"));
    fill(colDim); textAlign(RIGHT, TOP); textSize(9);
    text("0.." + int(adMax) + strings.get(" АЦП · тяните маркеры", " ADC · drag markers"), x + w - 12, y + 11);

    float listTop = y + 34, listBot = y + h - 32;
    float gap = 8;
    float cardH = (listBot - listTop - 4 * gap) / 5.0;
    for (int i = 0; i < 5; i++) {
      float cyy = listTop + i * (cardH + gap);
      drawAxisCard(i, x + 10, cyy, w - 20, cardH, axes);
    }
    resetBtnX = x + 10; resetBtnY = y + h - 26; resetBtnW = w - 20; resetBtnH = 20;
    button(resetBtnX, resetBtnY, resetBtnW, resetBtnH, strings.get("Сбросить калибровку всех осей", "Reset All Calibration"), color(110, 60, 50), false);
    tipZone(resetBtnX, resetBtnY, resetBtnW, resetBtnH, strings.get("Сбросить мин/макс всех осей к 0..", "Reset min/max of all axes to 0..") + int(adMax) + strings.get(" (команда YR).", " (command YR)."));
  }

  void drawAxisCard(int i, float x, float y, float w, float h, AxisConfig[] axes) {
    card(x, y, w, h);
    float live = constrain(map(axes[i].rawValue, -1, 1, 0, adMax), 0, adMax);
    boolean calib = cmdMin[i].length() > 0;

    // whole-card tooltip drawn FIRST so the more specific pill tipZone()s below can
    // override it later in the same frame (tipZone just last-writer-wins on hoverTip).
    if (calib) {
      tipZone(x, y, w, h, axPhys[i] + " (" + ROLE_NAMES[axisRole[i]] + ")" + strings.get(": «мин» чуть выше отпущенного значения, «макс» чуть ниже максимума хода. Команды ", ": “min” just above the released value, “max” just below full travel. Commands ") + trim(cmdMin[i]) + "/" + trim(cmdMax[i]) + ".");
    } else {
      tipZone(x, y, w, h, axPhys[i] + strings.get(" — руль/энкодер. Центр и CPR на вкладке «Энкодер».", " — steering/encoder. Center and CPR are on the Encoder tab."));
    }

    // бейдж оси
    float rowAY = y + max(6, h * 0.05);
    fill(axColors[i]); noStroke(); rect(x + 10, rowAY, 28, 26, 5);
    fill(0); textAlign(CENTER, CENTER); textSize(12); text(axPhys[i], x + 24, rowAY + 13);

    // роль (кликабельна для осей 1..4; ось 0 — аппаратный энкодер, роль фиксирована)
    float roleX = x + 46, roleW = w - 46 - 96;
    axRoleX[i] = roleX; axRoleY[i] = rowAY; axRoleW[i] = roleW;
    boolean roleHov = i > 0 && mouseX >= roleX && mouseX <= roleX + roleW && mouseY >= rowAY && mouseY <= rowAY + axRoleH;
    fill(roleHov ? color(255, 220, 120) : colText); textAlign(LEFT, TOP); textSize(14); text(ROLE_NAMES[axisRole[i]], roleX, rowAY + 1);
    fill(colDim); textSize(8);
    text(i == 0 ? strings.get("аппаратный энкодер — фиксировано", "hardware encoder — fixed") : strings.get("клик — сменить функцию", "click to change role"), roleX, rowAY + 18);

    // живое значение
    fill(colAcc); textAlign(RIGHT, TOP); textSize(16);
    text(int(live) + (calib ? "" : strings.get(" энк", " enc")), x + w - 12, rowAY + 3);

    // dustin's rig, redesigned — invert/disable as full-width labeled pill toggles (was two
    // unlabeled 14x14 mini-checkboxes, too small/unclear). Own row, scales with card height.
    float rowBY = y + h * 0.42;
    axPillH = max(20, h * 0.19);
    float pillGap = 8;
    axPillW = (w - 24 - pillGap) / 2.0;
    float invX = x + 12, disX = invX + axPillW + pillGap;
    axInvX[i] = invX; axInvY[i] = rowBY;
    axDisX[i] = disX; axDisY[i] = rowBY;
    boolean invOn = bitReadByte(axisInvertMask, i) == 1;
    boolean disOn = bitReadByte(axisDisableMask, i) == 1;
    drawTogglePill(invX, rowBY, axPillW, axPillH, strings.get("Инверсия", "Invert"), invOn, color(70, 140, 210));
    drawTogglePill(disX, rowBY, axPillW, axPillH, strings.get("Откл. ось", "Disable axis"), disOn, color(210, 80, 80));
    tipZone(invX, rowBY, axPillW, axPillH, strings.get("Инвертировать направление оси (команда I)", "Invert this axis' direction (command I)"));
    tipZone(disX, rowBY, axPillW, axPillH, strings.get("Отключить ось — зафиксировать в нейтрали (команда D)", "Disable this axis — force it to neutral (command D)"));

    // полоса
    float bX = x + 12, bW = w - 24, bY = rowBY + axPillH + max(6, h * 0.06);
    axBarH = max(14, h * 0.15);
    axBarX[i] = bX; axBarW[i] = bW; axBarY[i] = bY;
    fill(14); stroke(colCardE); strokeWeight(1); rect(bX, bY, bW, axBarH, 3);
    stroke(42); strokeWeight(1);
    for (int q = 1; q < 4; q++) { float qx = bX + bW * q / 4.0; line(qx, bY, qx, bY + axBarH); }
    noStroke(); fill(axColors[i]); rect(bX, bY, bW * live / adMax, axBarH, 3);

    if (calib) {
      float minX = bX + bW * calMin[i] / adMax;
      float maxX = bX + bW * calMax[i] / adMax;
      fill(0, 0, 0, 130); noStroke(); rect(bX, bY, minX - bX, axBarH); rect(maxX, bY, bX + bW - maxX, axBarH);
      stroke(80, 150, 240); strokeWeight(2); line(minX, bY - 3, minX, bY + axBarH + 3);
      fill(80, 150, 240); noStroke(); triangle(minX - 5, bY - 4, minX + 5, bY - 4, minX, bY + 3);
      stroke(240, 150, 70); strokeWeight(2); line(maxX, bY - 3, maxX, bY + axBarH + 3);
      fill(240, 150, 70); noStroke(); triangle(maxX - 5, bY + axBarH + 4, maxX + 5, bY + axBarH + 4, maxX, bY + axBarH - 3);
      fill(colDim); textAlign(LEFT, TOP); textSize(9);
      text(strings.get("мин ", "min ") + int(calMin[i]) + "    " + strings.get("макс ", "max ") + int(calMax[i]), bX, bY + axBarH + 7);
      float span = max(calMax[i] - calMin[i], 1);
      int travel = int(constrain((live - calMin[i]) / span * 100, 0, 100));
      fill(colAcc); textAlign(RIGHT, TOP); textSize(9); text(strings.get("ход ", "travel ") + travel + "%", bX + bW, bY + axBarH + 7);
    } else {
      fill(colDim); textAlign(LEFT, TOP); textSize(9);
      text(strings.get("руль / энкодер — калибровка на вкладке «Энкодер»", "steering/encoder — calibrate on Encoder tab"), bX, bY + axBarH + 7);
    }
  }

  // dustin's rig, added — a labeled on/off pill switch: filled+bright when on, outlined+dim when off.
  void drawTogglePill(float x, float y, float w, float h, String label, boolean on, color onColor) {
    fill(on ? onColor : color(20, 20, 26));
    stroke(on ? lerpColor(onColor, color(255), 0.3) : colCardE);
    strokeWeight(1);
    rect(x, y, w, h, h / 2.0);
    // маленький кружок-индикатор слева, как у классического toggle-переключателя
    float knobR = h * 0.6;
    float knobX = on ? x + w - h / 2.0 : x + h / 2.0;
    fill(on ? 255 : colDim); noStroke();
    ellipse(knobX, y + h / 2.0, knobR, knobR);
    fill(on ? 255 : colDim); textAlign(CENTER, CENTER); textSize(min(11, h * 0.42));
    text(label, x + w / 2.0 + (on ? -h * 0.25 : h * 0.25), y + h / 2.0);
  }

  // ============ FFB (карточки) ============
  void drawControlPanel(float x, float y, float w, float h) {
    epX = x; epY = y; epW = w; epH = h;
    panel(x, y, w, h, strings.get("Эффекты обратной связи (FFB) — все параметры", "FFB Effects — All Parameters"));
    fill(colDim); textAlign(RIGHT, TOP); textSize(9); text(strings.get("меняется сразу в Arduino", "applied to Arduino immediately"), x + w - 12, y + 11);

    fGridTop = y + 30;
    float gridBot = y + h - 8;
    fColW = (w - 24) / fCols;
    fRowH = (gridBot - fGridTop) / fRows;
    for (int i = 0; i < ctlIdx.length; i++) {
      int col = i % fCols, row = i / fCols;
      drawControl(i, x + 12 + col * fColW, fGridTop + row * fRowH, fColW - 8, fRowH - 6);
    }
  }

  void drawControl(int i, float x, float y, float w, float h) {
    int idx = ctlIdx[i];
    float g = effects[idx].gain;
    float ratio = constrain((g - ctlMin[i]) / (ctlMax[i] - ctlMin[i]), 0, 1);
    card(x, y, w, h);
    ctlCardX[i] = x; ctlCardY[i] = y; ctlCardW[i] = w; ctlCardH[i] = h;

    float titleX = x + 12;
    if (isDesktopToggle(idx)) {
      // маленький чекбокс: включить эффект как постоянный поверх игры (desktop-эффект)
      ctlChkX[i] = x + 12; ctlChkY[i] = y + 9;
      boolean on = effects[idx].userEnabled;
      fill(on ? color(70, 180, 100) : color(20, 20, 26)); stroke(on ? color(120, 230, 150) : colCardE); strokeWeight(1);
      rect(ctlChkX[i], ctlChkY[i], ctlChkS, ctlChkS, 3);
      if (on) {
        stroke(255); strokeWeight(2);
        line(ctlChkX[i] + 3, ctlChkY[i] + 7, ctlChkX[i] + 6, ctlChkY[i] + 10.5f);
        line(ctlChkX[i] + 6, ctlChkY[i] + 10.5f, ctlChkX[i] + 11, ctlChkY[i] + 3);
      }
      tipZone(ctlChkX[i] - 4, ctlChkY[i] - 4, ctlChkS + 8, ctlChkS + 8,
        strings.get("Включить «" + ctlName[i] + "» как постоянный эффект поверх игры (desktop-эффект), а не только когда его шлёт сама игра.", "Enable “" + ctlName[i] + "” as a constant effect on top of the game (desktop effect), not only when the game itself sends it."));
      titleX = x + 32;
    } else {
      ctlChkX[i] = -1;
    }

    fill(colText); textAlign(LEFT, TOP); textSize(12); text(ctlName[i], titleX, y + 9);
    fill(colAcc); textAlign(RIGHT, TOP); textSize(13);
    String vs = (idx == 0 || idx == 11) ? str(int(g)) : (idx == 10) ? nf(g, 1, 1) : str(int(g * 100));
    String un = (idx == 0) ? "°" : (idx == 11) ? "" : "%";
    text(vs + un, x + w - 12, y + 8);

    float tX = x + 12, tW = w - 24, tY = y + 34, tH = 8;
    ctlTrkX[i] = tX; ctlTrkY[i] = tY; ctlTrkW[i] = tW;
    fill(16); noStroke(); rect(tX, tY, tW, tH, 4);
    fill(colAcc); rect(tX, tY, tW * ratio, tH, 4);
    fill(235); ellipse(tX + tW * ratio, tY + tH / 2, 14, 14);

    fill(colDim); textSize(9); drawWrapped(ctlTip[i], x + 12, y + 50, w - 24, 12);
  }

  // ============ ВВОД ============
  void handlePress() {
    // 0) чекбоксы desktop-эффектов в карточках FFB
    for (int i = 0; i < ctlIdx.length; i++) {
      if (ctlChkX[i] < 0) continue;
      if (mouseX >= ctlChkX[i] - 4 && mouseX <= ctlChkX[i] + ctlChkS + 4 &&
          mouseY >= ctlChkY[i] - 4 && mouseY <= ctlChkY[i] + ctlChkS + 4) {
        int idx = ctlIdx[i];
        effects[idx].userEnabled = !effects[idx].userEnabled;
        applyEffstate();
        Log.info("FFB", effects[idx].name + (effects[idx].userEnabled ? strings.get(" ВКЛ", " ON") : strings.get(" ВЫКЛ", " OFF")));
        return;
      }
    }
    // 1) маркеры калибровки осей (ось 0 без калибровки)
    for (int i = 1; i < 5; i++) {
      float bX = axBarX[i], bW = axBarW[i], bY = axBarY[i];
      if (mouseX >= bX - 8 && mouseX <= bX + bW + 8 && mouseY >= bY - 8 && mouseY <= bY + axBarH + 8) {
        float minX = bX + bW * calMin[i] / adMax, maxX = bX + bW * calMax[i] / adMax;
        dragAxis = i;
        dragMM = (abs(mouseX - minX) <= abs(mouseX - maxX)) ? 0 : 1;
        applyAxisDrag(); return;
      }
    }
    // 2) слайдеры FFB
    for (int i = 0; i < ctlIdx.length; i++) {
      if (mouseX >= ctlCardX[i] && mouseX <= ctlCardX[i] + ctlCardW[i] &&
          mouseY >= ctlCardY[i] && mouseY <= ctlCardY[i] + ctlCardH[i]) {
        dragCtl = i; applyCtlDrag(); return;
      }
    }
  }
  void handleDrag() {
    if (dragAxis >= 0) applyAxisDrag();
    else if (dragCtl >= 0) applyCtlDrag();
  }
  void handleRelease() {
    if (dragAxis >= 0) {
      String cmd = (dragMM == 0) ? cmdMin[dragAxis] : cmdMax[dragAxis];
      float val = (dragMM == 0) ? calMin[dragAxis] : calMax[dragAxis];
      proto.setParam(cmd, int(val));
      Log.info("AXIS", axPhys[dragAxis] + " (" + ROLE_NAMES[axisRole[dragAxis]] + ")" + (dragMM == 0 ? strings.get(" мин=", " min=") : strings.get(" макс=", " max=")) + int(val));
    }
    dragAxis = -1; dragMM = -1; dragCtl = -1;
  }
  void applyAxisDrag() {
    int i = dragAxis;
    float bX = axBarX[i], bW = axBarW[i];
    float v = constrain(round(map(mouseX, bX, bX + bW, 0, adMax)), 0, adMax);
    if (dragMM == 0) calMin[i] = min(v, calMax[i] - 1);
    else calMax[i] = max(v, calMin[i] + 1);
  }
  void applyCtlDrag() {
    int i = dragCtl, idx = ctlIdx[i];
    float rx = ctlTrkX[i], rw = ctlTrkW[i];
    float ratio = constrain((mouseX - rx) / rw, 0, 1);
    float g = ctlMin[i] + ratio * (ctlMax[i] - ctlMin[i]);
    if (idx == 0) g = round(g / 5.0) * 5;
    if (idx == 11) g = round(g);
    effects[idx].gain = g; proto.setEffect(idx, g);
  }

  void handleClick(AxisConfig[] axes, boolean[] axisEn, FFBEffect[] effects) {
    // ЦЕНТР
    if (hov(wheelBtnX, wheelBtnY, wheelBtnW, wheelBtnH)) {
      proto.center(); Log.info("AXIS", strings.get("Центрирование руля", "Wheel centered")); return;
    }
    // сброс калибровки осей
    if (hov(resetBtnX, resetBtnY, resetBtnW, resetBtnH)) {
      for (int i = 0; i < 5; i++) { calMin[i] = 0; calMax[i] = adMax; }
      proto.sendNow("YR"); proto.requestAutosave(); Log.info("AXIS", strings.get("Сброс калибровки осей", "Axis calibration reset")); return;
    }
    // клик по роли оси — сменить функцию (со свопом). Ось 0 (X) пропускаем:
    // это аппаратный энкодер руля, роль «Руль» с неё снимать нельзя — иначе
    // угол руля и вкладка «Энкодер» начнут читать данные с педали вместо
    // настоящего энкодера (см. axisForRole(0) в главном файле).
    for (int i = 1; i < 5; i++) {
      if (mouseX >= axRoleX[i] && mouseX <= axRoleX[i] + axRoleW[i] &&
          mouseY >= axRoleY[i] && mouseY <= axRoleY[i] + axRoleH) {
        int next = (axisRole[i] % 4) + 1;   // цикл 1→2→3→4→1, роль «Руль» (0) сюда никогда не попадает
        int j = axisForRole(next);
        int prev = axisRole[i];
        axisRole[i] = next;
        if (j >= 0 && j != i) axisRole[j] = prev;
        saveAxisRoles();
        Log.info("AXIS", axPhys[i] + strings.get(" назначена как «", " assigned as “") + ROLE_NAMES[next] + strings.get("»", "”"));
        return;
      }
    }
    // dustin's rig, added — invert/disable переключатели (все 5 осей, бит-маска совпадает с прошивкой)
    for (int i = 0; i < 5; i++) {
      if (mouseX >= axInvX[i] && mouseX <= axInvX[i] + axPillW && mouseY >= axInvY[i] && mouseY <= axInvY[i] + axPillH) {
        toggleAxisInvert(i); return;
      }
      if (mouseX >= axDisX[i] && mouseX <= axDisX[i] + axPillW && mouseY >= axDisY[i] && mouseY <= axDisY[i] + axPillH) {
        toggleAxisDisable(i); return;
      }
    }
  }
}
