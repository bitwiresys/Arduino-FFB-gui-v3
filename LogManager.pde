// ============================================================
// LogManager — structured logging with timestamps, levels,
// categories, ring buffer, and UI panel support
// ============================================================

class LogManager {
  int maxEntries = 2000;
  ArrayList<LogEntry> entries = new ArrayList<LogEntry>();
  int[] levelCounts = new int[4]; // DEBUG, INFO, WARN, ERROR
  boolean[] categoryFilter = new boolean[20];
  boolean[] levelFilter = {true, true, true, true}; // all enabled by default
  String[] categories = {
    "SERIAL", "FFB", "AXIS", "PROFILE", "SYSTEM",
    "SENSOR", "ENCODER", "SHIFTER", "PWM", "CALIBRATION"
  };
  int numCategories = 10;

  // Auto-export
  boolean autoExport = true;
  String exportPath = "data/session_log.txt";
  int exportInterval = 30000; // ms
  long lastExportTime = 0;

  LogManager() {
    for (int i = 0; i < numCategories; i++) {
      categoryFilter[i] = true;
    }
  }

  void debug(String category, String message) {
    addEntry(0, category, message);
  }

  void info(String category, String message) {
    addEntry(1, category, message);
  }

  void warn(String category, String message) {
    addEntry(2, category, message);
  }

  void error(String category, String message) {
    addEntry(3, category, message);
  }

  private void addEntry(int level, String category, String message) {
    if (entries.size() >= maxEntries) {
      LogEntry old = entries.remove(0);
      levelCounts[old.level]--;
    }

    LogEntry e = new LogEntry();
    e.timestamp = millis();
    e.wallTime = getWallTime();
    e.level = level;
    e.category = category;
    e.message = message;
    entries.add(e);
    levelCounts[level]++;

    // Print to console too
    String prefix = levelPrefix(level);
    println("[" + e.wallTime + "] " + prefix + " [" + category + "] " + message);
  }

  String levelPrefix(int level) {
    switch (level) {
      case 0: return "D";
      case 1: return "I";
      case 2: return "W";
      case 3: return "E";
      default: return "?";
    }
  }

  String levelName(int level) {
    switch (level) {
      case 0: return strings.get("ОТЛ", "DBG");
      case 1: return strings.get("ИНФО", "INFO");
      case 2: return strings.get("ПРЕД", "WARN");
      case 3: return strings.get("ОШИБ", "ERR");
      default: return "?";
    }
  }

  color levelColor(int level) {
    switch (level) {
      case 0: return color(150, 150, 150);  // gray
      case 1: return color(100, 200, 100);   // green
      case 2: return color(220, 180, 50);    // yellow
      case 3: return color(220, 70, 70);     // red
      default: return color(200);
    }
  }

  String getWallTime() {
    int s = millis() / 1000;
    int m = s / 60;
    int h = m / 60;
    return nf(h, 2) + ":" + nf(m % 60, 2) + ":" + nf(s % 60, 2);
  }

  // Get filtered entries for display
  ArrayList<LogEntry> getFilteredEntries() {
    ArrayList<LogEntry> result = new ArrayList<LogEntry>();
    for (int i = entries.size() - 1; i >= 0; i--) {
      LogEntry e = entries.get(i);
      if (!levelFilter[e.level]) continue;
      int catIdx = getCategoryIndex(e.category);
      if (catIdx >= 0 && !categoryFilter[catIdx]) continue;
      result.add(e);
      if (result.size() >= 500) break; // limit display
    }
    return result;
  }

  int getCategoryIndex(String cat) {
    for (int i = 0; i < numCategories; i++) {
      if (categories[i].equals(cat)) return i;
    }
    return -1;
  }

  void toggleLevel(int level) {
    levelFilter[level] = !levelFilter[level];
  }

  void toggleCategory(int idx) {
    if (idx >= 0 && idx < numCategories) {
      categoryFilter[idx] = !categoryFilter[idx];
    }
  }

  void clear() {
    entries.clear();
    for (int i = 0; i < 4; i++) levelCounts[i] = 0;
  }

  void exportToFile() {
    int count = entries.size();
    String[] lines = new String[count];
    for (int i = 0; i < count; i++) {
      LogEntry e = entries.get(i);
      lines[i] = e.wallTime + " " + levelName(e.level) + " [" + e.category + "] " + e.message;
    }
    saveStrings(exportPath, lines);
  }

  // Auto-export check — call from draw()
  void update() {
    if (autoExport && millis() - lastExportTime > exportInterval) {
      lastExportTime = millis();
      exportToFile();
    }
  }

  String getStatsString() {
    return "D:" + levelCounts[0] + " I:" + levelCounts[1] +
           " W:" + levelCounts[2] + " E:" + levelCounts[3] +
           " Total:" + entries.size();
  }
}

class LogEntry {
  int timestamp;
  String wallTime;
  int level; // 0=DEBUG, 1=INFO, 2=WARN, 3=ERROR
  String category;
  String message;
}

// Global log instance
LogManager Log;
