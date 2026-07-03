/* ============================================================
   Arduino FFB Wheel Control Panel v3.0
   ============================================================ */

static public void main(String[] args) {
  PApplet.main("wheel_control_v3");
}

import processing.serial.*;
import controlP5.*;
import java.util.*;

String cpVer = "v3.0.0";
int WIN_W = 1280;
int WIN_H = 800;

SerialManager serial;
WheelProtocol proto;
FirmwareParser fw;
PImage wheelImg;
SelfUpdater selfUpdater;           // dustin's rig, added — control-panel auto-update
FirmwareUpdater firmwareUpdater;   // dustin's rig, added — wheel firmware auto-update

FFBEffect[] effects = new FFBEffect[12];
AxisConfig[] axes = new AxisConfig[5];
boolean[] axisEnabled = {true, true, true, true, true};

// ---- Привязка физических осей (X/Y/Z/RX/RY) к логическим функциям ----
// (аналог "Steering axis / Brake / Accelerator / Clutch / Handbrake" в старом GUI,
// только без отдельного Swing-окна — всё прямо на вкладке "Обзор").
// axisRole[i] = роль, назначенная физической оси i (индекс в ROLE_NAMES).
// По умолчанию совпадает со старой конвенцией прошивки: X=Руль,Y=Тормоз,Z=Газ,RX=Сцепление,RY=Ручник.
// ВАЖНО: заполняется в refreshGlobalLabels(), а не здесь — этот массив виден
// до setup() (strings ещё не создан), и без пересчёта на каждой смене языка
// названия ролей осей навсегда остались бы на языке, активном при старте.
String[] ROLE_NAMES = new String[5];
int[] axisRole = {0, 1, 2, 3, 4};
int lastLangVer = -1;

// Пересобрать все глобальные, зависящие от языка тексты (роли осей, вкладки,
// заголовок окна). Вызывается из setup() и из draw(), когда меняется язык.
void refreshGlobalLabels() {
  ROLE_NAMES[0] = strings.get("Руль", "Steering");
  ROLE_NAMES[1] = strings.get("Тормоз", "Brake");
  ROLE_NAMES[2] = strings.get("Газ", "Throttle");
  ROLE_NAMES[3] = strings.get("Сцепление", "Clutch");
  ROLE_NAMES[4] = strings.get("Ручник", "Handbrake");
  if (tabBar != null) {
    tabBar.tabs.get(TAB_DASHBOARD).label = strings.get("Обзор", "Dashboard");
    tabBar.tabs.get(TAB_SHIFTER).label   = strings.get("Шифтер", "Shifter");
    tabBar.tabs.get(TAB_ENCODER).label   = strings.get("Энкодер", "Encoder");
    tabBar.tabs.get(TAB_LOG).label       = strings.get("Журнал", "Log");
    tabBar.tabs.get(TAB_SETTINGS).label  = strings.get("Настройки", "Settings");
  }
  surface.setTitle(strings.get("Управление рулём ", "Wheel Control ") + cpVer);
  lastLangVer = strings.version;
}

// Найти индекс физической оси, которой назначена роль role (-1 если нет такой)
int axisForRole(int role) {
  for (int i = 0; i < axisRole.length; i++) if (axisRole[i] == role) return i;
  return -1;
}

void loadAxisRoles() {
  File f = new File(dataPath("axis_roles.txt"));
  if (!f.exists()) return;
  String[] lines = loadStrings("axis_roles.txt");
  if (lines == null || lines.length < 5) return;
  int[] tmp = new int[5];
  for (int i = 0; i < 5; i++) tmp[i] = int(trim(lines[i]));
  // валидация: должна получиться перестановка 0..4
  boolean[] seen = new boolean[5];
  boolean ok = true;
  for (int v : tmp) { if (v < 0 || v > 4 || seen[v]) { ok = false; break; } seen[v] = true; }
  if (!ok) return;
  // Физическая ось 0 (X) — аппаратный энкодер руля (см. DashboardTab: "ось 0 —
  // энкодер/руль, мин/макс не применяется"). Угол руля и все данные на вкладке
  // «Энкодер» считаются с axes[axisForRole(0)] — если роль «Руль» окажется не
  // на оси 0, угол руля и энкодер начнут показывать сырые данные с педали.
  // Если файл сохранён до этого фикса и роль «Руль» не на оси 0 — чиним.
  if (tmp[0] != 0) {
    int j = -1;
    for (int i = 1; i < 5; i++) if (tmp[i] == 0) { j = i; break; }
    if (j >= 0) { tmp[j] = tmp[0]; tmp[0] = 0; }
  }
  axisRole = tmp;
}

void saveAxisRoles() {
  String[] lines = new String[5];
  for (int i = 0; i < 5; i++) lines[i] = str(axisRole[i]);
  saveStrings(dataPath("axis_roles.txt"), lines);
}

int xFFBAxisIndex = 0;
int yFFBAxisIndex = 1;
boolean ffbMonitorActive = false;
int ffbX = 0, ffbY = 0;
byte effstate = 0;
byte pwmstate = 0;
int maxTorque = 2047;
// dustin's rig, added — per-axis invert/disable bitmasks (bit0=X,1=Y,2=Z,3=RX,4=RY), matches firmware 'I'/'D' commands
byte axisInvertMask = 0;
byte axisDisableMask = 0;

// dustin's rig, added — сторожевой детектор срыва привода (прошивка ≥ v254, команда 'T'):
// прошивка сама отсекла FFB, потому что мотор долго крутился под нагрузкой при
// неподвижном энкодере (сорвана шестерня/муфта). Снимается только перезапуском платы.
boolean ffbFaultLatched = false;
int lastFaultPoll = 0;

ControlIO control;
ControlDevice gpad;
boolean[] hidButtons = new boolean[24];
int hidHatValue = 0;
float[] hidAxes = new float[5];

TabBar tabBar;
DashboardTab dashboardTab;
ShifterTab shifterTab;
LogTab logTab;
EncoderTab encoderTab;
SettingsTab settingsTab;
SetupWizard wizard;

int activeTab = 0;
PFont fontMain;

final int TAB_DASHBOARD = 0;
final int TAB_SHIFTER = 1;
final int TAB_ENCODER = 2;
final int TAB_LOG = 3;
final int TAB_SETTINGS = 4;

AppState appState;
class AppState {
}

void settings() {
  size(WIN_W, WIN_H);
}

void setup() {
  surface.setResizable(false);
  // NB: остаёмся в RGB (по умолчанию). Раньше тут был colorMode(HSB),
  // из-за чего все RGB-литералы color(r,g,b) трактовались как HSB → неверные цвета.
  frameRate(60);

  Log = new LogManager();
  Log.info("SYSTEM", "Wheel Control " + cpVer + strings.get(" — запуск", " — starting"));

  wheelImg = decodeWheelImage();   // встроена в код, см. WheelImage.pde
  if (wheelImg != null) {
    wheelImg.resize(200, 200);
    Log.info("SYSTEM", strings.get("Картинка руля загружена", "Wheel image loaded"));
  }

  serial = new SerialManager(this);
  proto = new WheelProtocol(serial);
  fw = new FirmwareParser();
  appState = new AppState();
  selfUpdater = new SelfUpdater();
  firmwareUpdater = new FirmwareUpdater();

  // Оси — generic, без привязки к семантике (ось может быть чем угодно)
  String[] axisNames = {strings.get("Ось 0 (X)", "Axis 0 (X)"), strings.get("Ось 1 (Y)", "Axis 1 (Y)"), strings.get("Ось 2 (Z)", "Axis 2 (Z)"), strings.get("Ось 3 (RX)", "Axis 3 (RX)"), strings.get("Ось 4 (RY)", "Axis 4 (RY)")};
  String[] physNames = {"Xaxis", "Yaxis", "Zaxis", "RXaxis", "RYaxis"};
  for (int i = 0; i < 5; i++) {
    axes[i] = new AxisConfig(i, axisNames[i], physNames[i]);
  }
  loadAxisRoles();

  effects[0] = new FFBEffect("Rotation", "G", 0);
  effects[1] = new FFBEffect("General Gain", "FG", 1);
  effects[2] = new FFBEffect("Damper", "FD", 2);
  effects[3] = new FFBEffect("Friction", "FF", 3);
  effects[4] = new FFBEffect("Constant", "FC", 4);
  effects[5] = new FFBEffect("Periodic", "FS", 5);
  effects[6] = new FFBEffect("Spring", "FM", 6);
  effects[7] = new FFBEffect("Inertia", "FI", 7);
  effects[8] = new FFBEffect("Centering", "FA", 8);
  effects[9] = new FFBEffect("Stop", "FB", 9);
  effects[10] = new FFBEffect("Min Torque", "FJ", 10);
  effects[11] = new FFBEffect("Brake/Balance", "B", 11);

  initUI();
  refreshGlobalLabels();
  wizard = new SetupWizard();

  // Check if first run — no COM_cfg.txt means we need setup wizard
  File f = new File(dataPath("COM_cfg.txt"));
  if (!f.exists()) {
    // Wizard handles everything — no initHID/initSerial here
    wizard.start();
  } else {
    // Normal startup — load saved config
    try { initHID(); } catch (Throwable t) { Log.error("SYSTEM", "HID init: " + t.getMessage()); }
    try { initSerial(); } catch (Throwable t) { Log.error("SERIAL", "Serial init: " + t.getMessage()); }
  }
  Log.info("SYSTEM", strings.get("Инициализация завершена", "Initialization complete"));
  selfUpdater.checkForUpdate(); // dustin's rig, added — runs in a background thread, non-blocking
}

void initUI() {
  float tabH = 30;
  float contentY = tabH;
  float contentH = WIN_H - tabH;

  tabBar = new TabBar(0, 0, WIN_W, tabH);
  tabBar.addTab(strings.get("Обзор", "Dashboard"), TAB_DASHBOARD);
  tabBar.addTab(strings.get("Шифтер", "Shifter"), TAB_SHIFTER);
  tabBar.addTab(strings.get("Энкодер", "Encoder"), TAB_ENCODER);
  tabBar.addTab(strings.get("Журнал", "Log"), TAB_LOG);
  tabBar.addTab(strings.get("Настройки", "Settings"), TAB_SETTINGS);

  dashboardTab = new DashboardTab(0, contentY, WIN_W, contentH);
  shifterTab = new ShifterTab(0, contentY, WIN_W, contentH);
  encoderTab = new EncoderTab(0, contentY, WIN_W, contentH);
  logTab = new LogTab(0, contentY, WIN_W, contentH);
  settingsTab = new SettingsTab(0, contentY, WIN_W, contentH);
}

void initHID() {
  // NB: НЕ используем control.getMatchedDevice(String) — этот метод GameControlPlus
  // сам открывает старое Swing-окно "Select device for Wheel" / KConfigDeviceUI,
  // если не находит точного совпадения сохранённого конфига. Вместо этого ищем
  // устройство вручную (как в SetupWizard) — никаких сторонних окон не появляется.
  try {
    control = ControlIO.getInstance(this);
    gpad = null;
    for (ControlDevice dev : control.getDevices()) {
      String n = trim(dev.getName());
      if (n.toLowerCase().contains("arduino")) {
        gpad = dev;
        break;
      }
    }
    if (gpad == null) {
      Log.warn("SYSTEM", strings.get("HID-устройство не найдено", "HID device not found"));
    } else {
      gpad.open();
      Log.info("SYSTEM", "HID: " + trim(gpad.getName()));
    }
  } catch (Exception e) {
    Log.error("SYSTEM", "HID init: " + e.getMessage());
  }
}

void initSerial() {
  File f = new File(dataPath("COM_cfg.txt"));
  if (f.exists()) {
    String[] port = loadStrings("COM_cfg.txt");
    if (port != null && port.length > 0) {
      if (serial.connect(trim(port[0]), 115200)) {
        requestDeviceState();
      }
      // если подключиться не удалось (порт сменился/платы нет) —
      // авто-реконнект в draw() сам найдёт плату по всем портам
    }
  }
  // конфига нет — этим занимается мастер первого запуска
}

// ============================================================
// Умный реконнект и поиск платы.
// - Пока нет связи, раз в 3 секунды: пробуем прежний порт, если он есть в системе;
//   иначе опрашиваем все COM-порты протокольным рукопожатием 'V' (ищем "fw-v").
// - Порт может менять номер (COM5→COM7 и т.п.) — найденный сохраняем в COM_cfg.txt.
// - Ничего не блокирует UI: вся работа в фоновом потоке.
// ============================================================
int lastReconnectAt = 0;
boolean reconnectBusy = false;

void updateAutoReconnect() {
  if (serial.isConnected() || wizard.active || firmwareUpdater.flashing || reconnectBusy) return;
  File f = new File(dataPath("COM_cfg.txt"));
  if (!f.exists()) return; // первичной настройкой занимается мастер
  if (millis() - lastReconnectAt < 3000) return;
  lastReconnectAt = millis();
  reconnectBusy = true;
  Thread t = new Thread(new Runnable() {
    public void run() {
      try {
        String saved = null;
        String[] cfg = loadStrings("COM_cfg.txt");
        if (cfg != null && cfg.length > 0) saved = trim(cfg[0]);
        String[] ports = jssc.SerialPortList.getPortNames();
        // 1) прежний порт снова появился — подключаемся сразу
        if (saved != null && saved.length() > 0) {
          for (String p : ports) {
            if (p.equals(saved)) {
              if (serial.connect(saved, 115200)) { requestDeviceState(); }
              return;
            }
          }
        }
        // 2) прежнего порта нет — ищем плату по всем портам рукопожатием
        for (String p : ports) {
          if (probePortForWheel(p)) {
            if (serial.connect(p, 115200)) {
              saveStrings(dataPath("COM_cfg.txt"), new String[]{p});
              Log.info("SERIAL", strings.get("Плата найдена на новом порту: ", "Board found on a new port: ") + p);
              requestDeviceState();
            }
            return;
          }
        }
      } catch (Throwable tt) {
        Log.debug("SERIAL", "reconnect: " + errText(tt));
      } finally {
        reconnectBusy = false;
      }
    }
  });
  t.setDaemon(true);
  t.start();
}

// Проверить, отвечает ли на порту наша прошивка: открыть, послать 'V',
// подождать "fw-v". Открытие CDC-порта на 115200 НЕ перезагружает 32u4
// (в бутлоадер уводит только 1200 бод), так что это безопасно.
boolean probePortForWheel(String portName) {
  return probeFwVersionLine(portName) != null;
}

// То же, но возвращает полную строку "fw-vNNN<буквы>" (null — не наша плата/нет ответа).
// Мастеру настройки она нужна целиком: по буквам-опциям он подбирает вариант прошивки.
String probeFwVersionLine(String portName) {
  if (serial.isConnected() && portName.equals(serial.portName)) return null;
  jssc.SerialPort sp = new jssc.SerialPort(portName);
  try {
    sp.openPort();
    sp.setParams(115200, 8, 1, 0);
    try { Thread.sleep(120); } catch (InterruptedException ie) {}
    sp.writeBytes("V\r".getBytes());
    long deadline = System.currentTimeMillis() + 900;
    StringBuilder sb = new StringBuilder();
    while (System.currentTimeMillis() < deadline) {
      byte[] b = sp.readBytes();
      if (b != null && b.length > 0) sb.append(new String(b));
      int at = sb.indexOf("fw-v");
      if (at >= 0) {
        int eol = sb.indexOf("\n", at);
        if (eol >= 0) return sb.substring(at, eol).trim();
      }
      try { Thread.sleep(30); } catch (InterruptedException ie) {}
    }
    int at = sb.indexOf("fw-v");
    return at >= 0 ? sb.substring(at).trim() : null;
  } catch (Throwable t) {
    return null; // занят/чужой/умер — значит не наша плата
  } finally {
    try { sp.closePort(); } catch (Throwable t) {}
  }
}

void readFWVersion() {
  // через очередь, а не sendImmediate: внеочередная запись при живом запросе
  // сдвигала соответствие «команда → ответ» на один (см. parseResponse)
  serial.enqueueCommand("V");
}

public void draw() {
  if (lastLangVer != strings.version) refreshGlobalLabels();
  background(20);
  hoverTip = null;
  serial.update();
  proto.update();
  updateAutoReconnect();
  // dustin's rig, added — опрос сторожевого детектора срыва привода (команда 'T').
  // Только для прошивок ≥ v254 — старые не знают команду и молчали бы до таймаута.
  if (serial.isConnected() && !firmwareUpdater.flashing && fw != null && fw.versionNumber >= 254
      && millis() - lastFaultPoll > 1000) {
    lastFaultPoll = millis();
    serial.enqueueCommand("T");
  }
  readHIDInputs();
  for (int i = 0; i < 5; i++) {
    if (axisEnabled[i]) {
      axes[i].process(hidAxes[i]);
    }
  }
  int wheelAx = axisForRole(0); // роль 0 = "Руль"
  if (wheelAx < 0) wheelAx = 0;
  encoderTab.update(axes[wheelAx].rawValue * max(effects[0].gain, 1) / 2.0);  // реальный угол руля в градусах

  tabBar.draw();
  switch (tabBar.activeTab) {
    case TAB_DASHBOARD: dashboardTab.draw(axes, axisEnabled, ffbX, ffbY, ffbMonitorActive); break;
    case TAB_SHIFTER: shifterTab.draw(); break;
    case TAB_ENCODER: encoderTab.draw(fw); break;
    case TAB_LOG: logTab.draw(Log); break;
    case TAB_SETTINGS: settingsTab.draw(fw); break;
  }
  fill(60);
  textAlign(LEFT, BOTTOM);
  textSize(9);
  text(str(int(frameRate)) + " fps | " + serial.getStatsString(), 8, WIN_H - 4);

  drawTooltip();   // подсказки рисуем последними, поверх всего
  Log.update();    // auto-export check
  wizard.draw();   // оверлей настройки — самый верхний слой

  // dustin's rig, added — update toasts/modals draw above everything, including the wizard
  selfUpdater.update();
  selfUpdater.draw();
  firmwareUpdater.update();
  firmwareUpdater.draw();
}

// ============================================================
// Глобальная система всплывающих подсказок
// tipZone(...) вызывается во время отрисовки; если курсор над зоной —
// текст запоминается и рисуется поверх всего в конце кадра.
// ============================================================
String hoverTip = null;

void tipZone(float x, float y, float w, float h, String t) {
  if (mouseX >= x && mouseX <= x + w && mouseY >= y && mouseY <= y + h) hoverTip = t;
}

void drawTooltip() {
  if (hoverTip == null || hoverTip.length() == 0) return;
  pushStyle();
  textSize(12);
  float maxW = 300;
  // перенос по словам
  String[] words = split(hoverTip, ' ');
  ArrayList<String> lines = new ArrayList<String>();
  String cur = "";
  for (String w : words) {
    String test = cur.length() == 0 ? w : cur + " " + w;
    if (textWidth(test) > maxW && cur.length() > 0) { lines.add(cur); cur = w; }
    else cur = test;
  }
  if (cur.length() > 0) lines.add(cur);

  float pad = 8, lh = 16;
  float boxW = 0;
  for (String l : lines) boxW = max(boxW, textWidth(l));
  boxW += pad * 2;
  float boxH = lines.size() * lh + pad * 2;

  float bx = mouseX + 16, by = mouseY + 16;
  if (bx + boxW > WIN_W - 4) bx = mouseX - boxW - 8;
  if (by + boxH > WIN_H - 4) by = mouseY - boxH - 8;
  if (bx < 4) bx = 4;
  if (by < 4) by = 4;

  fill(18, 20, 28, 245); stroke(90, 150, 220); strokeWeight(1);
  rect(bx, by, boxW, boxH, 5);
  fill(220, 225, 235); noStroke(); textAlign(LEFT, TOP);
  for (int i = 0; i < lines.size(); i++) text(lines.get(i), bx + pad, by + pad + i * lh);
  popStyle();
}

void readHIDInputs() {
  if (gpad == null) return;
  // ВАЖНО: читаем по ИНДЕКСУ (getSlider(0..4) / getButton(0..23)), а НЕ по имени.
  // Именованный доступ getSlider("Xaxis") требует загруженной конфигурации
  // GameControlPlus (которая открывает старое окно «Select device»); без неё он
  // падает и оси замирают на 0. Индексное чтение работает всегда — как в мастере.
  int ns = 0;
  try { ns = gpad.getNumberOfSliders(); } catch (Throwable t) {}
  for (int i = 0; i < 5; i++) {
    try { hidAxes[i] = (i < ns) ? gpad.getSlider(i).getValue() : 0; }
    catch (Throwable t) { hidAxes[i] = 0; }
  }
  for (int i = 0; i < 24; i++) {
    try { hidButtons[i] = gpad.getButton(i).pressed(); }
    catch (Throwable t) { hidButtons[i] = false; }
  }
  // Hat/POV: раньше hidHatValue нигде не обновлялся и индикатор на «Обзоре»
  // всегда показывал центр. GameControlPlus отдаёт его через getHat(0).getPos().
  try { hidHatValue = gpad.getHat(0).getPos(); }
  catch (Throwable t) { hidHatValue = 0; }
  dashboardTab.buttonStates = hidButtons;
  dashboardTab.hatValue = hidHatValue;
}

public void serialEvent(Serial p) {
  String data = p.readStringUntil(10);
  if (data == null) return;
  data = data.trim();
  if (data.length() == 0) return;
  // ВАЖНО: запоминаем, какой команде отвечает эта строка, ДО onSerialData() —
  // onSerialData() сразу отправляет следующую команду из очереди и перезаписывает
  // serial.lastWrite, из-за чего ответ приписывался бы не той команде.
  String cmd = serial.lastWrite;
  serial.onSerialData(data);
  parseResponse(data, cmd);
}

// есть ли у подключённой прошивки данная буква-опция (из ответа 'V')
boolean fwHas(String letter) {
  return fw != null && fw.optionLetters != null && fw.optionLetters.contains(letter);
}

// Маршрутизация ответов по команде-источнику (протокол строго запрос→ответ).
// Раньше ответы различались по содержимому, и любые «голые» числа (эхо "1" от FG/FC/...,
// бинарные эхо E/I/D вида "10110") принимались за build id ('X') или ток мотора ('J') —
// из-за этого появлялись ложные предложения обновить прошивку и мусор в показаниях тока.
void parseResponse(String data, String cmd) {
  if (data.startsWith("fw-v")) {
    fw.parse(data);
    // дочитываем состояние платы командами, которые её прошивка ТОЧНО знает:
    // YR только при ручной калибровке (без 'a'), HG только при XY-шифтере ('f') —
    // на прошивке без опции эти двухбуквенные команды раньше оставляли «хвост»
    // в буфере, и он исполнялся как посторонняя команда (исправлено и в прошивке)
    if (!fw.pedalAutoCalib) serial.enqueueCommand("YR");
    if (fw.xyShifter)       serial.enqueueCommand("HG");
    firmwareUpdater.checkForUpdate(); // dustin's rig, added — runs in a background thread, non-blocking
    return;
  }
  if (cmd == null) cmd = "";
  if (cmd.equals("X") && data.matches("[0-9]+")) { firmwareUpdater.onLocalBuildId(int(data)); return; }
  if (cmd.equals("T") && data.matches("[0-9]+")) {
    boolean f = int(data) != 0;
    if (f && !ffbFaultLatched) Log.error("SYSTEM", strings.get("СРЫВ ПРИВОДА: энкодер неподвижен под нагрузкой — FFB остановлен прошивкой. Перезапустите плату.", "DRIVETRAIN FAULT: encoder frozen under load — FFB stopped by the firmware. Restart the board."));
    ffbFaultLatched = f;
    return;
  }
  if (cmd.equals("U"))  { parseWheelParams(data); return; }
  if (cmd.equals("YR")) { parsePedalCal(data); return; }
  if (cmd.equals("HG")) { parseShifterCal(data); return; }
  if (cmd.equals("HR")) { parseShifterPos(data); return; }
  // незапрошенные строки (например, поток FFB-монитора) — игнорируем;
  // на всякий случай распознаём полный ответ 'U', если lastWrite не сохранился
  if (split(data, ' ').length >= 16 && data.matches("[0-9 .\\-]+")) parseWheelParams(data);
}

void parseWheelParams(String data) {
  float[] t = float(split(data, ' '));
  if (t.length < 16) return;
  for (int i = 0; i < 10; i++) effects[i].gain = (i == 0) ? t[i] : t[i] / 100.0;
  effects[11].gain = t[11];
  effstate = byte(int(t[12])); decodeEffstate(effstate);
  maxTorque = int(t[13]);
  // min torque (idx10): прошивка шлёт MM_MIN_MOTOR_TORQUE в сырых единицах момента
  // (доля от maxTorque), а не %*10 — восстанавливаем проценты через максимум.
  // Старое деление на 10 давало, например, 10.2% вместо реальных 5%.
  effects[10].gain = maxTorque > 0 ? t[10] / maxTorque * 100.0 : 0;
  encoderTab.cpr = int(t[14]);
  pwmstate = byte(int(t[15]));
  // dustin's rig, added — хвостовые inv/dis-маски присутствуют только на прошивках с опцией 'v'
  if (fwHas("v") && t.length > 17) {
    axisInvertMask = byte(int(t[16]));
    axisDisableMask = byte(int(t[17]));
  }
}

// Ответ 'YR' — ручная калибровка педалей: "brakeMin brakeMax accelMin accelMax
// clutchMin clutchMax hbrakeMin hbrakeMax" (или "0" при автокалибровке).
// Синхронизирует маркеры на «Обзоре» с реальным состоянием платы при подключении.
void parsePedalCal(String data) {
  String[] t = split(trim(data), ' ');
  if (t.length < 8) return;
  int[] axByField = {1, 2, 3, 4};  // Y=тормоз, Z=газ, RX=сцепление, RY=ручник — порядок прошивки
  for (int i = 0; i < 4; i++) {
    dashboardTab.calMin[axByField[i]] = float(t[i * 2]);
    dashboardTab.calMax[axByField[i]] = float(t[i * 2 + 1]);
  }
}

// Ответ 'HG' — калибровка и конфиг шифтера: "cal0 cal1 cal2 cal3 cal4 cfg" (или "0")
void parseShifterCal(String data) {
  String[] t = split(trim(data), ' ');
  if (t.length < 6) return;
  for (int i = 0; i < 5; i++) shifterTab.cal[i] = float(t[i]);
  int cfg = int(t[5]);
  shifterTab.revInverted  = (cfg & 1) != 0;
  shifterTab.reverseIn8th = (cfg & 2) != 0;
  shifterTab.xInverted    = (cfg & 4) != 0;
  shifterTab.yInverted    = (cfg & 8) != 0;
}

// Ответ 'HR' — живое положение рычага шифтера: "x y" (сырые АЦП с пинов шифтера).
// До этого вкладка «Шифтер» показывала HID-оси RX/RY (сцепление/ручник) вместо шифтера.
void parseShifterPos(String data) {
  String[] t = split(trim(data), ' ');
  if (t.length < 2) return;
  shifterTab.liveX = float(t[0]);
  shifterTab.liveY = float(t[1]);
  shifterTab.livePolled = true;
}

// Запросить полное состояние платы после (пере)подключения.
// YR/HG дозапрашиваются после ответа 'V' (см. parseResponse) — когда уже известно,
// какие опции есть у прошивки и какие команды ей можно слать.
void requestDeviceState() {
  ffbFaultLatched = false;         // сторож: после ребута платы латч в прошивке сброшен
  readFWVersion();                 // 'V' — версия и буквы-опции
  serial.enqueueCommand("U");      // все настройки FFB
}

// dustin's rig, added — flip one bit of the axis invert mask and push it to the firmware (command 'I')
void toggleAxisInvert(int axisIdx) {
  if (!fwHas("v")) return; // прошивка без USE_AXIS_TWEAKS не знает команд I/D
  axisInvertMask = byte((int(axisInvertMask) & 0xFF) ^ (1 << axisIdx));
  proto.setParam("I ", int(axisInvertMask) & 0xFF);
  Log.info("AXIS", strings.get("Инверсия оси ", "Axis invert ") + dashboardTab.axPhys[axisIdx] + ": " + (bitReadByte(axisInvertMask, axisIdx) == 1 ? "ON" : "OFF"));
}

// dustin's rig, added — flip one bit of the axis disable mask and push it to the firmware (command 'D')
void toggleAxisDisable(int axisIdx) {
  if (!fwHas("v")) return; // прошивка без USE_AXIS_TWEAKS не знает команд I/D
  axisDisableMask = byte((int(axisDisableMask) & 0xFF) ^ (1 << axisIdx));
  proto.setParam("D ", int(axisDisableMask) & 0xFF);
  Log.info("AXIS", strings.get("Отключение оси ", "Axis disable ") + dashboardTab.axPhys[axisIdx] + ": " + (bitReadByte(axisDisableMask, axisIdx) == 1 ? "ON" : "OFF"));
}

public void mousePressed() {
  // dustin's rig, added — update toasts/modals take click priority over everything else
  if (selfUpdater.handleClick()) return;
  if (firmwareUpdater.handleClick()) return;
  if (wizard.active) { wizard.handleClick(); return; }
  int clickedTab = tabBar.handleClick();
  if (clickedTab >= 0) return;
  switch (tabBar.activeTab) {
    case TAB_DASHBOARD: dashboardTab.handleClick(axes, axisEnabled, effects); break;
    case TAB_SHIFTER: shifterTab.handleClick(); break;
    case TAB_ENCODER: encoderTab.handleClick(); break;
    case TAB_LOG: logTab.handleClick(Log); break;
    case TAB_SETTINGS: settingsTab.handleClick(); break;
  }
  if (tabBar.activeTab == TAB_DASHBOARD) dashboardTab.handlePress();
  if (tabBar.activeTab == TAB_SHIFTER) shifterTab.handlePress();
}

public void mouseReleased() {
  if (wizard.active) { wizard.handleRelease(); return; }
  if (tabBar.activeTab == TAB_DASHBOARD) dashboardTab.handleRelease();
  if (tabBar.activeTab == TAB_SHIFTER) shifterTab.handleRelease();
}

public void mouseDragged() {
  if (wizard.active) return;
  if (tabBar.activeTab == TAB_DASHBOARD) dashboardTab.handleDrag();
  else if (tabBar.activeTab == TAB_SHIFTER) shifterTab.handleDrag();
}

public void mouseWheel(MouseEvent event) {
  if (tabBar.activeTab == TAB_LOG) logTab.handleScroll(event.getCount());
}

public void keyPressed() {
  // ESC во время ввода CPR/поиска в журнале/мастера должен отменять ввод,
  // а не закрывать всё приложение (поведение Processing по умолчанию)
  boolean escConsumed = (key == ESC) && (wizard.active || encoderTab.cprEditing || logTab.searchActive);
  switch (tabBar.activeTab) {
    case TAB_ENCODER: encoderTab.handleKey(key); break;
    case TAB_LOG: logTab.handleKey(key); break;
  }
  if (escConsumed) key = 0;
}

int bitReadByte(byte b, int bitPos) {
  return (b & (1 << bitPos)) == 0 ? 0 : 1;
}

// ---- effstate: упаковка тогглов desktop-эффектов + FFB-оси ----
// bit0=Spring(idx6) bit1=Damper(idx2) bit2=Inertia(idx7) bit3=Friction(idx3)
// bit4=FFB-монитор  bits5-7=индекс FFB-оси
int buildEffstate() {
  int e = 0;
  if (effects[6].userEnabled) e |= (1 << 0);
  if (effects[2].userEnabled) e |= (1 << 1);
  if (effects[7].userEnabled) e |= (1 << 2);
  if (effects[3].userEnabled) e |= (1 << 3);
  if (ffbMonitorActive)        e |= (1 << 4);
  e |= (xFFBAxisIndex & 0x07) << 5;
  return e;
}

// Применить (отправить) текущее состояние тогглов в Arduino
void applyEffstate() {
  effstate = byte(buildEffstate());
  proto.setEffstate(int(effstate) & 0xFF);
}

// Раскодировать пришедший от Arduino effstate обратно в GUI-тогглы
void decodeEffstate(byte e) {
  effects[6].userEnabled = bitReadByte(e, 0) == 1;
  effects[2].userEnabled = bitReadByte(e, 1) == 1;
  effects[7].userEnabled = bitReadByte(e, 2) == 1;
  effects[3].userEnabled = bitReadByte(e, 3) == 1;
  ffbMonitorActive = bitReadByte(e, 4) == 1;
  xFFBAxisIndex = (int(e) & 0xFF) >> 5;
}

public void exit() {
  Log.info("SYSTEM", strings.get("Завершение работы", "Shutting down"));
  Log.exportToFile();
  if (serial.isConnected()) serial.disconnect();
  super.exit();
}
