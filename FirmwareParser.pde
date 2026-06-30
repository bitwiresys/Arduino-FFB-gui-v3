// ============================================================
// FirmwareParser вЂ” decode firmware version and option bytes
// Extracted from the monolithic setup() in original code
// ============================================================

class FirmwareParser {
  String fullVersionString = "";
  String versionString = "";
  int versionNumber = 0;
  byte opt1 = 0; // options byte 1: a z h i s m t f
  byte opt2 = 0; // options byte 2: e x w c r b d p
  byte opt3 = 0; // options byte 3: n l g u k

  // Decoded features
  boolean pedalAutoCalib = false;
  boolean encoderZIndex = false;
  boolean hatSwitch = false;
  boolean pedalAveraging = false;
  boolean externalADC = false;
  boolean proMicroPins = false;
  boolean buttonMatrix = false;
  boolean xyShifter = false;
  boolean extraButtons = false;
  boolean analogFFB = false;
  boolean magneticEncoder = false;
  boolean hardwareCenter = false;
  boolean noOpticalEncoder = false;
  boolean noEEPROm = false;
  boolean twoFFB = false;
  boolean splitAxis = false;
  boolean buttonBox = false;
  boolean loadCell = false;
  boolean externalDAC = false;
  boolean tca9548 = false;

  void parse(String fwString) {
    fullVersionString = fwString;
    versionString = fwString;
    String opts = "0";

    // First 4 chars are always "fw-v", followed by digits then option chars
    if (fwString.length() > 4) {
      int end = 4;
      while (end < fwString.length() && Character.isDigit(fwString.charAt(end))) end++;
      versionString = fwString.substring(4, end);
      opts = (end < fwString.length()) ? fwString.substring(end) : "0";
    }

    versionNumber = parseInt(versionString);
    opt1 = decodeByte1(opts);
    opt2 = decodeByte2(opts);
    opt3 = decodeByte3(opts);

    decodeFeatures();
    logFeatures();
  }

  byte decodeByte1(String opts) {
    byte b = 0;
    if (opts.equals("0")) return b;
    for (int i = 0; i < opts.length(); i++) {
      char c = opts.charAt(i);
      if (c == 'a') b |= (1 << 0);
      if (c == 'z') b |= (1 << 1);
      if (c == 'h') b |= (1 << 2);
      if (c == 'i') b |= (1 << 3);
      if (c == 's') b |= (1 << 4);
      if (c == 'm') b |= (1 << 5);
      if (c == 't') b |= (1 << 6);
      if (c == 'f') b |= (1 << 7);
    }
    return b;
  }

  byte decodeByte2(String opts) {
    byte b = 0;
    if (opts.equals("0")) return b;
    for (int i = 0; i < opts.length(); i++) {
      char c = opts.charAt(i);
      if (c == 'e') b |= (1 << 0);
      if (c == 'x') b |= (1 << 1);
      if (c == 'w') b |= (1 << 2);
      if (c == 'c') b |= (1 << 3);
      if (c == 'r') b |= (1 << 4);
      if (c == 'b') b |= (1 << 5);
      if (c == 'd') b |= (1 << 6);
      if (c == 'p') b |= (1 << 7);
    }
    return b;
  }

  byte decodeByte3(String opts) {
    byte b = 0;
    if (opts.equals("0")) return b;
    for (int i = 0; i < opts.length(); i++) {
      char c = opts.charAt(i);
      if (c == 'n') b |= (1 << 0);
      if (c == 'l') b |= (1 << 1);
      if (c == 'g') b |= (1 << 2);
      if (c == 'u') b |= (1 << 3);
      if (c == 'k') b |= (1 << 4);
    }
    return b;
  }

  void decodeFeatures() {
    pedalAutoCalib = bitReadByte(opt1, 0) == 1;
    encoderZIndex = bitReadByte(opt1, 1) == 1;
    hatSwitch = bitReadByte(opt1, 2) == 1;
    pedalAveraging = bitReadByte(opt1, 3) == 1;
    externalADC = bitReadByte(opt1, 4) == 1;
    proMicroPins = bitReadByte(opt1, 5) == 1;
    buttonMatrix = bitReadByte(opt1, 6) == 1;
    xyShifter = bitReadByte(opt1, 7) == 1;

    extraButtons = bitReadByte(opt2, 0) == 1;
    analogFFB = bitReadByte(opt2, 1) == 1;
    magneticEncoder = bitReadByte(opt2, 2) == 1;
    hardwareCenter = bitReadByte(opt2, 3) == 1;

    noOpticalEncoder = bitReadByte(opt2, 6) == 1;
    noEEPROm = bitReadByte(opt2, 7) == 1;

    buttonBox = bitReadByte(opt3, 0) == 1;
    loadCell = bitReadByte(opt3, 1) == 1;
    externalDAC = bitReadByte(opt3, 2) == 1;
    tca9548 = bitReadByte(opt3, 3) == 1;
    splitAxis = bitReadByte(opt3, 4) == 1;

    // 2FFB depends on option "b" (opt2 bit5)
    twoFFB = bitReadByte(opt2, 5) == 1;

    // Button box also from version number for fw < v250
    if (versionNumber < 250) {
      String ver = str(versionNumber);
      int lastDigit = ver.charAt(ver.length() - 1) - '0';
      if (lastDigit == 1 || lastDigit == 2 || lastDigit == 3) buttonBox = true;
      if (lastDigit == 2 || lastDigit == 3) loadCell = true;
      if (lastDigit == 3) externalDAC = true;
    }
  }

  int getDefaultADMax() {
    if (pedalAveraging) return 4095;
    if (externalADC) return 2047;
    return 1023;
  }

  void logFeatures() {
    Log.info("SYSTEM", "FW Version: " + fullVersionString + " (v" + versionNumber + ")");
    StringBuilder sb = new StringBuilder("Features: ");
    if (pedalAutoCalib) sb.append("auto-cal ");
    if (encoderZIndex) sb.append("z-index ");
    if (hatSwitch) sb.append("hat ");
    if (pedalAveraging) sb.append("avg ");
    if (externalADC) sb.append("ADS1105 ");
    if (proMicroPins) sb.append("proMicro ");
    if (buttonMatrix) sb.append("btn-matrix ");
    if (xyShifter) sb.append("XY-shifter ");
    if (extraButtons) sb.append("extra-btn ");
    if (analogFFB) sb.append("analog-FFB ");
    if (magneticEncoder) sb.append("AS5600 ");
    if (hardwareCenter) sb.append("hw-center ");
    if (buttonBox) sb.append("button-box ");
    if (loadCell) sb.append("load-cell ");
    if (externalDAC) sb.append("MCP4725 ");
    if (tca9548) sb.append("TCA9548 ");
    if (twoFFB) sb.append("2-FFB ");
    if (splitAxis) sb.append("split-axis ");
    Log.info("SYSTEM", sb.toString());
  }

  String getSummary() {
    return "FW:" + fullVersionString +
           " | EN:" + (magneticEncoder ? "AS5600" : (noOpticalEncoder ? "POT" : "OPT")) +
           " | FFB:" + (twoFFB ? "2axis" : "1axis") +
           " | OUT:" + (externalDAC ? "DAC" : "PWM") +
           " | LC:" + (loadCell ? "YES" : "no");
  }
}
