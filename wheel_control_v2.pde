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
// dustin's rig, added — motor NTC thermistor: live raw reading, current critical threshold, tripped (FFB cut) state
int ntcRaw = -1;
int ntcThreshold = 1023;
boolean ntcTripped = false;

// dustin's rig, added — fixed-formula NTC raw<->Celsius conversion. No calibration UI: known hardware
// (100k NTC, B3950 — the standard 3D-printer-style thermistor used here) with a 330-ohm fixed resistor
// in the divider (NTC between 5V and the sense pin, resistor from sense pin to GND — see firmware).
float NTC_R_FIXED = 330;     // ohms — actual fixed resistor installed
float NTC_R0 = 100000;       // ohms at 25C
float NTC_T0K = 298.15;      // 25C in Kelvin
float NTC_BETA = 3950;       // standard B-value for this thermistor family

float NTC_THRESH_MIN_C = 80, NTC_THRESH_MAX_C = 200, NTC_THRESH_DEFAULT_C = 120; // dustin's rig, added — slider range/default
boolean ntcGotFirstReading = false, ntcDefaultApplied = false;

float ntcRawToOhms(float raw) {
  raw = constrain(raw, 1, 1022); // избегаем деления на 0 (raw=0) и вырождения (raw=1023)
  return NTC_R_FIXED * (1023.0 - raw) / raw;
}
float rawToTempC(float raw) {
  float r = ntcRawToOhms(raw);
  float invT = 1.0 / NTC_T0K + (1.0 / NTC_BETA) * log(r / NTC_R0);
  return (1.0 / invT) - 273.15;
}
float tempCToRaw(float tempC) {
  float tK = tempC + 273.15;
  float r = NTC_R0 * exp(NTC_BETA * (1.0 / tK - 1.0 / NTC_T0K));
  return 1023.0 * NTC_R_FIXED / (r + NTC_R_FIXED);
}
float ntcThreshC() { return ntcThreshold >= 1023 ? NTC_THRESH_DEFAULT_C : constrain(rawToTempC(ntcThreshold), NTC_THRESH_MIN_C, NTC_THRESH_MAX_C); }

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
      if (serial.connect(port[0], 115200)) {
        readFWVersion();
        serial.enqueueCommand("U");
      }
    }
  } else {
    String[] ports = Serial.list();
    if (ports.length > 0) {
      if (serial.connect(ports[0], 115200)) {
        saveStrings("data/COM_cfg.txt", new String[]{ports[0]});
        readFWVersion();
        serial.enqueueCommand("U");
      }
    } else {
      Log.warn("SERIAL", strings.get("COM-порты не найдены", "No COM ports found"));
    }
  }
}

void readFWVersion() {
  serial.sendImmediate("V");
}

public void draw() {
  if (lastLangVer != strings.version) refreshGlobalLabels();
  background(20);
  hoverTip = null;
  serial.update();
  proto.update();
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
  serial.onSerialData(data);
  parseResponse(data);
}

void parseResponse(String data) {
  if (data.startsWith("fw-v")) {
    fw.parse(data);
    firmwareUpdater.checkForUpdate(); // dustin's rig, added — runs in a background thread, non-blocking
    return;
  }
  // dustin's rig, added — the 'N' command reply is exactly 3 space-separated ints ("raw threshold tripped"),
  // distinct from every other bare numeric reply in the protocol (U has 18 fields, HR/HG have 2/6).
  String[] parts = split(data, ' ');
  if (parts.length == 3 && data.matches("[0-9 ]+")) {
    parseNtcResponse(data);
    return;
  }
  if (data.length() > 11) {
    parseWheelParams(data);
  }
}

void parseWheelParams(String data) {
  float[] t = float(split(data, ' '));
  if (t.length < 16) return;
  for (int i = 0; i < 10; i++) effects[i].gain = (i == 0) ? t[i] : t[i] / 100.0;
  if (t.length > 11) effects[11].gain = t[11];
  if (t.length > 12) { effstate = byte(int(t[12])); decodeEffstate(effstate); }
  if (t.length > 13) maxTorque = int(t[13]);
  // min torque (idx10): firmware sends raw * 10, so divide by 10 to recover
  if (t.length > 10) effects[10].gain = t[10] / 10.0;
  if (t.length > 14) encoderTab.cpr = int(t[14]);
  if (t.length > 15) pwmstate = byte(int(t[15]));
  // dustin's rig, added — trailing fields appended to the 'U' response by the updated firmware
  if (t.length > 16) axisInvertMask = byte(int(t[16]));
  if (t.length > 17) axisDisableMask = byte(int(t[17]));
}

// dustin's rig, added — response to the 'N' command: "<raw> <threshold> <tripped 0/1>"
void parseNtcResponse(String data) {
  String[] t = split(data, ' ');
  if (t.length < 3) return;
  ntcRaw = int(t[0]);
  ntcThreshold = int(t[1]);
  ntcTripped = int(t[2]) != 0;
  // dustin's rig, added — first time we hear from a wheel whose threshold is still at the firmware's
  // "1023 = disabled" sentinel, push our own real default (120C) once, so the feature is live out of the box.
  if (!ntcGotFirstReading) {
    ntcGotFirstReading = true;
    if (ntcThreshold >= 1023 && !ntcDefaultApplied) {
      ntcDefaultApplied = true;
      ntcThreshold = int(constrain(tempCToRaw(NTC_THRESH_DEFAULT_C), 0, 1023));
      proto.setParam("M ", ntcThreshold);
      Log.info("SAFETY", strings.get("Порог NTC по умолчанию: ", "Default NTC threshold: ") + int(NTC_THRESH_DEFAULT_C) + "°C");
    }
  }
}

// dustin's rig, added — flip one bit of the axis invert mask and push it to the firmware (command 'I')
void toggleAxisInvert(int axisIdx) {
  axisInvertMask = byte((int(axisInvertMask) & 0xFF) ^ (1 << axisIdx));
  proto.setParam("I ", int(axisInvertMask) & 0xFF);
  Log.info("AXIS", strings.get("Инверсия оси ", "Axis invert ") + dashboardTab.axPhys[axisIdx] + ": " + (bitReadByte(axisInvertMask, axisIdx) == 1 ? "ON" : "OFF"));
}

// dustin's rig, added — flip one bit of the axis disable mask and push it to the firmware (command 'D')
void toggleAxisDisable(int axisIdx) {
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
  if (tabBar.activeTab == TAB_SETTINGS) settingsTab.handleRelease(); // dustin's rig, added — NTC slider
}

public void mouseDragged() {
  if (wizard.active) return;
  if (tabBar.activeTab == TAB_DASHBOARD) dashboardTab.handleDrag();
  else if (tabBar.activeTab == TAB_SHIFTER) shifterTab.handleDrag();
  else if (tabBar.activeTab == TAB_SETTINGS) settingsTab.handleDrag(); // dustin's rig, added — NTC slider
}

public void mouseWheel(MouseEvent event) {
  if (tabBar.activeTab == TAB_LOG) logTab.handleScroll(event.getCount());
}

public void keyPressed() {
  switch (tabBar.activeTab) {
    case TAB_ENCODER: encoderTab.handleKey(key); break;
    case TAB_LOG: logTab.handleKey(key); break;
  }
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
