// ============================================================
// WheelProtocol вЂ” РµРґРёРЅС‹Р№ СЃР»РѕР№ РєРѕРјР°РЅРґ Рє РїСЂРѕС€РёРІРєРµ.
// РљР°Р¶РґРѕРµ РёР·РјРµРЅРµРЅРёРµ РІ GUI РёРґС‘С‚ СЃСЋРґР° Рё СЃСЂР°Р·Сѓ СѓС…РѕРґРёС‚ РІ Arduino
// РїРѕ СЂРµР°Р»СЊРЅРѕРјСѓ РїСЂРѕС‚РѕРєРѕР»Сѓ (СЃРј. РѕСЂРёРіРёРЅР°Р»СЊРЅС‹Р№ wheel_control.pde).
//
// РњР°СЃС€С‚Р°Р± Р·РЅР°С‡РµРЅРёР№ FFB-СЌС„С„РµРєС‚РѕРІ (РєР°Рє РІ РїСЂРѕС€РёРІРєРµ):
//   idx 0 (Rotation) Рё 11 (Brake/Balance) вЂ” СЃС‹СЂРѕРµ С†РµР»РѕРµ
//   idx 10 (Min Torque)                   вЂ” *10
//   РѕСЃС‚Р°Р»СЊРЅС‹Рµ                             вЂ” *100 (РїСЂРѕС†РµРЅС‚С‹)
// ============================================================

class WheelProtocol {
  SerialManager s;

  // С‚РѕРєРµРЅС‹ РєРѕРјР°РЅРґ СЌС„С„РµРєС‚РѕРІ (РїСЂРѕР±РµР» вЂ” С‡Р°СЃС‚СЊ С‚РѕРєРµРЅР°, Р·РЅР°С‡РµРЅРёРµ РґРѕРїРёСЃС‹РІР°РµС‚СЃСЏ СЃР»РµРґРѕРј)
  String[] EFFECT_CMD = {
    "G ", "FG ", "FD ", "FF ", "FC ", "FS ",
    "FM ", "FI ", "FA ", "FB ", "FJ ", "B "
  };

  // РѕС‚Р»РѕР¶РµРЅРЅС‹Рµ Р·РЅР°С‡РµРЅРёСЏ РїР°СЂР°РјРµС‚СЂРѕРІ: С‚РѕРєРµРЅ -> Р¶РµР»Р°РµРјРѕРµ С†РµР»РѕРµ
  LinkedHashMap<String, Integer> desired = new LinkedHashMap<String, Integer>();
  LinkedHashMap<String, Integer> sent    = new LinkedHashMap<String, Integer>();

  int throttleMs = 40;   // РЅРµ С‡Р°С‰Рµ РѕРґРЅРѕРіРѕ РїР°СЂР°РјРµС‚СЂР° СЂР°Р· РІ 40 РјСЃ (Р±РµР· С„Р»СѓРґР° РѕС‡РµСЂРµРґРё)
  int lastFlush = 0;

  // Автосохранение в постоянную память: вместо ручных кнопок «Сохранить» —
  // после паузы autosaveDelayMs без новых изменений сами шлём команды сохранения.
  // "A"  — общая EEPROM (FFB-гейны, калибровка осей, CPR, PWM, effstate);
  // "HG" — отдельная команда сохранения калибровки шифтера (см. протокол).
  HashSet<String> pendingSaves = new HashSet<String>();
  int lastChangeAt = 0;
  int autosaveDelayMs = 1200;

  WheelProtocol(SerialManager s) {
    this.s = s;
  }

  boolean ready() {
    return s != null && s.isConnected();
  }

  // --- РјР°СЃС€С‚Р°Р±РёСЂРѕРІР°РЅРёРµ Р·РЅР°С‡РµРЅРёСЏ СЌС„С„РµРєС‚Р° РїРѕ РёРЅРґРµРєСЃСѓ ---
  int scaleEffect(int idx, float val) {
    if (idx == 0 || idx == 11) return int(round(val));
    if (idx == 10)             return int(round(val * 10.0));
    return int(round(val * 100.0));
  }

  // Р—Р°РґР°С‚СЊ Р¶РµР»Р°РµРјРѕРµ Р·РЅР°С‡РµРЅРёРµ СЌС„С„РµРєС‚Р° (СѓР№РґС‘С‚ РІ Arduino РїСЂРё СЃР»РµРґСѓСЋС‰РµРј flush)
  void setEffect(int idx, float val) {
    if (idx < 0 || idx >= EFFECT_CMD.length) return;
    desired.put(EFFECT_CMD[idx], scaleEffect(idx, val));
    markDirty("A");
  }

  // РЈРЅРёРІРµСЂСЃР°Р»СЊРЅРѕ: Р·Р°РґР°С‚СЊ Р·РЅР°С‡РµРЅРёРµ РґР»СЏ РїСЂРѕРёР·РІРѕР»СЊРЅРѕРіРѕ С‚РѕРєРµРЅР° ("O ", "E ", "W ", "YA " ...)
  void setParam(String token, int value) {
    desired.put(token, value);
    markDirty(token.startsWith("H") ? "HG" : "A");
  }

  // РќРµРјРµРґР»РµРЅРЅР°СЏ РѕРґРёРЅРѕС‡РЅР°СЏ РєРѕРјР°РЅРґР° Р±РµР· Р·РЅР°С‡РµРЅРёСЏ ("C", "A", "Z", "U", "V", "S", "R", "P")
  void sendNow(String cmd) {
    if (ready()) {
      s.enqueueCommand(cmd);
      Log.info("PROTO", "TX " + cmd);
    }
  }

  // РќРµРјРµРґР»РµРЅРЅР°СЏ РєРѕРјР°РЅРґР° СЃ С†РµР»С‹Рј Р·РЅР°С‡РµРЅРёРµРј (РґР»СЏ СЂР°Р·РѕРІС‹С… РґРµР№СЃС‚РІРёР№ вЂ” С‚РѕРіРіР»С‹, PWM, CPR)
  void sendNow(String token, int value) {
    desired.put(token, value);          // Р·Р°РїРѕРјРЅРёРј, С‡С‚РѕР±С‹ flush РЅРµ РґСѓР±Р»РёСЂРѕРІР°Р»
    sent.put(token, value);
    if (ready()) {
      s.enqueueCommand(token + value);
      Log.info("PROTO", "TX " + token + value);
    }
    markDirty(token.startsWith("H") ? "HG" : "A");
  }

  // Р’С‹СЃРѕРєРѕСѓСЂРѕРІРЅРµРІС‹Рµ РїРѕРјРѕС‰РЅРёРєРё Рє СЂРµР°Р»СЊРЅС‹Рј РєРѕРјР°РЅРґР°Рј РїСЂРѕС€РёРІРєРё
  void setEffstate(int effstateByte) { sendNow("E ", effstateByte); }
  void setPwmState(int pwmByte)       { sendNow("W ", pwmByte); }
  void setCPR(int cpr)                { sendNow("O ", cpr); }
  void center()                       { sendNow("C"); }
  void resetZIndex()                  { sendNow("Z"); }

  // Отметить настройки «грязными» — автосохранение сработает через autosaveDelayMs
  // после последнего изменения (debounce, чтобы не убивать EEPROM частыми записями).
  void markDirty(String saveCmd) {
    pendingSaves.add(saveCmd);
    lastChangeAt = millis();
  }
  void requestAutosave() { markDirty("A"); }
  void requestAutosave(String saveCmd) { markDirty(saveCmd); }

  // Р’С‹Р·С‹РІР°РµС‚СЃСЏ РєР°Р¶РґС‹Р№ РєР°РґСЂ РёР· draw(): РѕС‚РїСЂР°РІР»СЏРµС‚ РјР°РєСЃРёРјСѓРј РѕРґРёРЅ РёР·РјРµРЅРёРІС€РёР№СЃСЏ
  // РїР°СЂР°РјРµС‚СЂ Р·Р° РёРЅС‚РµСЂРІР°Р» throttleMs вЂ” РґР°С‘С‚ В«СЂРµР°Р»СЊРЅРѕРµ РІСЂРµРјСЏВ» Р±РµР· Р·Р°С‚РѕРїР»РµРЅРёСЏ РѕС‡РµСЂРµРґРё.
  void update() {
    if (!ready()) return;
    if (millis() - lastFlush >= throttleMs) {
      for (String k : desired.keySet()) {
        Integer d = desired.get(k);
        Integer p = sent.get(k);
        if (p == null || !p.equals(d)) {
          s.enqueueCommand(k + d);
          sent.put(k, d);
          lastFlush = millis();
          Log.debug("PROTO", "TX " + k + d);
          break;
        }
      }
    }
    // автосохранение: спустя паузу без изменений шлём отложенные команды сохранения
    if (!pendingSaves.isEmpty() && millis() - lastChangeAt > autosaveDelayMs) {
      for (String saveCmd : pendingSaves) {
        sendNow(saveCmd);
        Log.info("SYSTEM", strings.get("Автосохранение: ", "Auto-save: ") + saveCmd);
      }
      pendingSaves.clear();
    }
  }
}
