// ============================================================
// AxisConfig вЂ” per-axis configuration model
// Dead zone, saturation, response curve, smoothing, invert
// ============================================================

class AxisConfig {
  String name;           // Display name ("Steering", "Brake", etc.)
  String physicalName;   // HID axis name ("Xaxis", "Yaxis", etc.)
  int axisIndex;         // 0-4

  // Basic settings
  boolean inverted = false;
  float deadZone = 0.0;       // 0.0 - 0.3 (inner insensitive zone)
  float saturation = 1.0;     // 0.7 - 1.0 (zone where output = 100%)
  float gain = 1.0;           // 0.1 - 5.0 (signal multiplier)
  float offset = 0.0;         // -0.5 to 0.5 (center offset)

  // Smoothing
  float smoothingAlpha = 0.0; // 0.0 = off, 0.1 = light, 0.9 = heavy EMA
  float smoothedValue = 0.0;

  // Response curve type
  int curveType = 0;          // 0=linear, 1=log, 2=exp, 3=s-curve, 4=custom
  float curveExponent = 1.0;  // for log/exp curves
  float[] customCurveLUT;     // 256-point lookup table for custom curve

  // Calibration
  float calMin = 0.0;
  float calMax = 1.0;
  float rawMin = -1.0;
  float rawMax = 1.0;

  // State
  float rawValue = 0.0;
  float processedValue = 0.0;
  float velocity = 0.0;       // rate of change
  float prevValue = 0.0;

  AxisConfig(int index, String name, String physName) {
    this.axisIndex = index;
    this.name = name;
    this.physicalName = physName;
    this.customCurveLUT = new float[256];
    initDefaultLUT();
  }

  void initDefaultLUT() {
    for (int i = 0; i < 256; i++) {
      customCurveLUT[i] = i / 255.0;
    }
  }

  // Full processing pipeline
  float process(float raw) {
    rawValue = raw;
    float v = raw;

    // 1. Apply calibration (map raw range to 0-1)
    v = map(v, rawMin, rawMax, 0.0, 1.0);
    v = constrain(v, 0.0, 1.0);

    // 2. Apply inversion
    if (inverted) v = 1.0 - v;

    // 3. Apply dead zone
    if (deadZone > 0.0) {
      float center = 0.5;
      float dist = abs(v - center);
      if (dist < deadZone * 0.5) {
        v = center;
      } else {
        float sign = (v > center) ? 1.0 : -1.0;
        v = center + sign * map(dist, deadZone * 0.5, 0.5, 0.0, 0.5);
      }
    }

    // 4. Apply saturation
    if (saturation < 1.0) {
      if (v > saturation) v = 1.0;
      else if (v < (1.0 - saturation)) v = 0.0;
      else {
        v = map(v, 1.0 - saturation, saturation, 0.0, 1.0);
      }
    }

    // 5. Apply response curve
    v = applyCurve(v);

    // 6. Apply gain
    v = v * gain + offset;
    v = constrain(v, 0.0, 1.0);

    // 7. Apply EMA smoothing
    if (smoothingAlpha > 0.001) {
      smoothedValue = smoothedValue * (1.0 - smoothingAlpha) + v * smoothingAlpha;
      v = smoothedValue;
    }

    // 8. Calculate velocity
    velocity = v - prevValue;
    prevValue = v;

    processedValue = v;
    return v;
  }

  float applyCurve(float v) {
    switch (curveType) {
      case 0: // Linear
        return v;
      case 1: // Logarithmic
        if (v <= 0) return 0;
        return pow(v, 1.0 / max(curveExponent, 0.1));
      case 2: // Exponential
        return pow(v, max(curveExponent, 0.1));
      case 3: // S-curve (smoothstep)
        return v * v * (3.0 - 2.0 * v);
      case 4: // Custom LUT
        int idx = constrain(int(v * 255), 0, 255);
        return customCurveLUT[idx];
      default:
        return v;
    }
  }

  // Serialize to string for profile storage
  String serialize() {
    return name + "|" + inverted + "|" + nf(deadZone, 1, 3) + "|" +
           nf(saturation, 1, 3) + "|" + nf(gain, 1, 2) + "|" +
           nf(offset, 1, 3) + "|" + nf(smoothingAlpha, 1, 3) + "|" +
           curveType + "|" + nf(curveExponent, 1, 2);
  }

  void deserialize(String s) {
    String[] parts = split(s, "|");
    if (parts.length < 9) return;
    name = parts[0];
    inverted = parts[1].equals("true");
    deadZone = float(parts[2]);
    saturation = float(parts[3]);
    gain = float(parts[4]);
    offset = float(parts[5]);
    smoothingAlpha = float(parts[6]);
    curveType = int(parts[7]);
    curveExponent = float(parts[8]);
  }
}
