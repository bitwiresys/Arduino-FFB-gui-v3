// ============================================================
// FFBEffect вЂ” single force feedback effect model
// Each effect has gain, enable state, and effect-specific params
// ============================================================

class FFBEffect {
  String name;
  int commandIndex;        // index into the command array for serial protocol
  String commandPrefix;    // e.g. "FG", "FD", "FF"
  boolean enabled = false;
  float gain = 0.0;        // 0.0 - 2.0 (maps to 0-200%)
  boolean userEnabled = false; // user toggle state

  FFBEffect(String name, String cmdPrefix, int cmdIndex) {
    this.name = name;
    this.commandPrefix = cmdPrefix;
    this.commandIndex = cmdIndex;
  }

  void setGain(float g) {
    gain = g;
  }

  float getGainPercent() {
    return gain * 100.0;
  }

  void toggle() {
    userEnabled = !userEnabled;
    enabled = userEnabled;
  }

  // Build serial command for this effect
  String buildCommand() {
    int val = int(round(gain * 100.0));
    return commandPrefix + " " + str(val);
  }

  boolean hasChanged(float[] prevParms) {
    float prevGain = prevParms[commandIndex];
    return abs(gain - prevGain) > 0.001;
  }
}
