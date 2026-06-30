// ============================================================
// LogTab — structured log viewer with filters and search
// ============================================================

class LogTab {
  float contentX, contentY, contentW, contentH;

  // Viewport
  int scrollOffset = 0;
  int lineHeight = 18;
  int maxVisibleLines;

  // Filters
  boolean showDebug = true;
  boolean showInfo = true;
  boolean showWarn = true;
  boolean showError = true;
  boolean[] showCategory = new boolean[10];

  // Search
  String searchQuery = "";
  boolean searchActive = false;

  LogTab(float cx, float cy, float cw, float ch) {
    contentX = cx;
    contentY = cy;
    contentW = cw;
    contentH = ch;
    maxVisibleLines = int(ch / lineHeight) - 5;

    for (int i = 0; i < 10; i++) showCategory[i] = true;
  }

  void draw(LogManager log) {
    pushStyle();

    // Title bar
    fill(30, 30, 38);
    noStroke();
    rect(contentX, contentY, contentW, 36);

    fill(180);
    textAlign(LEFT, CENTER);
    textSize(14);
    text(strings.get("Журнал событий", "Event Log"), contentX + 10, contentY + 18);

    // Stats
    fill(100);
    textSize(10);
    text(log.getStatsString(), contentX + contentW - 300, contentY + 18);

    // Filter buttons
    drawFilterButtons(log);

    // Search bar
    drawSearchBar();

    // Log entries
    drawLogEntries(log);

    // Scroll bar
    drawScrollBar(log);

    popStyle();
  }

  void drawFilterButtons(LogManager log) {
    float fy = contentY + 40;
    float fx = contentX + 10;

    // Level filters
    String[] levelNames = {strings.get("ОТЛАДКА", "DEBUG"), strings.get("ИНФО", "INFO"), strings.get("ПРЕДУПР", "WARN"), strings.get("ОШИБКА", "ERROR")};
    boolean[] levelStates = {showDebug, showInfo, showWarn, showError};
    color[] levelColors = {
      color(100, 100, 100),
      color(80, 160, 80),
      color(200, 160, 40),
      color(200, 60, 60)
    };

    fill(80);
    textAlign(LEFT, CENTER);
    textSize(10);
    text(strings.get("Уровни:", "Levels:"), fx, fy + 9);
    fx += 50;

    for (int i = 0; i < 4; i++) {
      float bw = textWidth(levelNames[i]) + 12;
      boolean hover = mouseX >= fx && mouseX <= fx + bw &&
                      mouseY >= fy && mouseY <= fy + 18;

      if (levelStates[i]) {
        fill(levelColors[i]);
      } else {
        fill(45, 45, 52);
      }
      noStroke();
      rect(fx, fy, bw, 18, 3);

      fill(levelStates[i] ? 0 : 120);
      textAlign(CENTER, CENTER);
      textSize(9);
      text(levelNames[i], fx + bw / 2, fy + 9);

      fx += bw + 4;
    }

    // Category filters
    fx += 15;
    fill(80);
    textAlign(LEFT, CENTER);
    textSize(10);
    text(strings.get("Категории:", "Categories:"), fx, fy + 9);
    fx += 65;

    String[] cats = {"SERIAL", "FFB", "AXIS", "PROFILE", "SYSTEM"};
    for (int i = 0; i < 5; i++) {
      float bw = textWidth(cats[i]) + 10;
      boolean hover = mouseX >= fx && mouseX <= fx + bw &&
                      mouseY >= fy && mouseY <= fy + 18;

      fill(showCategory[i] ? color(60, 80, 60) : color(45, 45, 52));
      noStroke();
      rect(fx, fy, bw, 18, 3);

      fill(showCategory[i] ? 180 : 100);
      textAlign(CENTER, CENTER);
      textSize(9);
      text(cats[i], fx + bw / 2, fy + 9);

      fx += bw + 3;
    }

    // Clear button
    float clearX = contentX + contentW - 70;
    boolean clearHover = mouseX >= clearX && mouseX <= clearX + 60 &&
                         mouseY >= fy && mouseY <= fy + 18;
    fill(clearHover ? 120 : 80, 40, 40);
    noStroke();
    rect(clearX, fy, 60, 18, 3);
    fill(200);
    textAlign(CENTER, CENTER);
    textSize(9);
    text(strings.get("Очистить", "Clear"), clearX + 30, fy + 9);
  }

  void drawSearchBar() {
    float sx = contentX + 10;
    float sy = contentY + 65;
    float sw = 250;
    float sh = 22;

    fill(20);
    stroke(searchActive ? color(80, 180, 255) : color(60));
    strokeWeight(1);
    rect(sx, sy, sw, sh, 3);

    // Search icon
    fill(100);
    noStroke();
    textSize(11);
    textAlign(LEFT, CENTER);
    text(strings.get("Поиск:", "Search:"), sx + 4, sy + sh / 2);

    // Input
    fill(200);
    text(searchQuery + (searchActive ? "|" : ""), sx + 50, sy + sh / 2);
  }

  void drawLogEntries(LogManager log) {
    float logX = contentX + 10;
    float logY = contentY + 95;
    float logW = contentW - 30;
    float logH = contentH - 110;

    // Clip area background
    fill(12, 12, 18);
    stroke(40);
    strokeWeight(1);
    rect(logX, logY, logW, logH, 3);

    // Get filtered entries
    ArrayList<LogEntry> filtered = getFilteredEntries(log);

    // Draw entries
    int startIdx = scrollOffset;
    int endIdx = min(startIdx + maxVisibleLines, filtered.size());

    for (int i = startIdx; i < endIdx; i++) {
      LogEntry e = filtered.get(i);
      float ey = logY + (i - startIdx) * lineHeight + 2;

      if (ey + lineHeight > logY + logH) break;

      // Highlight on hover
      if (mouseY >= ey && mouseY <= ey + lineHeight &&
          mouseX >= logX && mouseX <= logX + logW) {
        fill(30, 30, 40);
        noStroke();
        rect(logX + 1, ey, logW - 2, lineHeight);
      }

      // Level color indicator
      fill(log.levelColor(e.level));
      noStroke();
      rect(logX + 3, ey + 2, 3, lineHeight - 4);

      // Timestamp
      fill(80);
      textAlign(LEFT, TOP);
      textSize(10);
      text(e.wallTime, logX + 10, ey + 3);

      // Level
      fill(log.levelColor(e.level));
      text(log.levelName(e.level), logX + 80, ey + 3);

      // Category
      fill(100, 140, 180);
      text("[" + e.category + "]", logX + 125, ey + 3);

      // Message (truncate if needed)
      fill(180);
      String msg = e.message;
      float maxMsgW = logW - 250;
      while (textWidth(msg) > maxMsgW && msg.length() > 10) {
        msg = msg.substring(0, msg.length() - 4) + "...";
      }
      text(msg, logX + 200, ey + 3);
    }

    // No entries message
    if (filtered.size() == 0) {
      fill(80);
      textAlign(CENTER, CENTER);
      textSize(12);
      text(strings.get("Нет записей", "No entries"), logX + logW / 2, logY + logH / 2);
    }

    // Entry count
    fill(80);
    textAlign(RIGHT, TOP);
    textSize(9);
    text(filtered.size() + " " + strings.get("записей", "entries") + (searchQuery.length() > 0 ? " (" + strings.get("фильтр", "filtered") + ")" : ""),
         logX + logW - 5, logY + logH + 5);
  }

  ArrayList<LogEntry> getFilteredEntries(LogManager log) {
    ArrayList<LogEntry> result = new ArrayList<LogEntry>();
    for (int i = log.entries.size() - 1; i >= 0; i--) {
      LogEntry e = log.entries.get(i);
      if (e.level == 0 && !showDebug) continue;
      if (e.level == 1 && !showInfo) continue;
      if (e.level == 2 && !showWarn) continue;
      if (e.level == 3 && !showError) continue;

      int catIdx = log.getCategoryIndex(e.category);
      if (catIdx >= 0 && catIdx < 10 && !showCategory[catIdx]) continue;

      if (searchQuery.length() > 0) {
        if (!e.message.toLowerCase().contains(searchQuery.toLowerCase()) &&
            !e.category.toLowerCase().contains(searchQuery.toLowerCase())) {
          continue;
        }
      }

      result.add(e);
    }
    return result;
  }

  void drawScrollBar(LogManager log) {
    ArrayList<LogEntry> filtered = getFilteredEntries(log);
    int totalEntries = filtered.size();

    if (totalEntries <= maxVisibleLines) return;

    float sbX = contentX + contentW - 20;
    float sbY = contentY + 95;
    float sbH = contentH - 110;
    float thumbH = max(30, (float(maxVisibleLines) / totalEntries) * sbH);
    float thumbY = sbY + (float(scrollOffset) / totalEntries) * sbH;

    // Track
    fill(30);
    noStroke();
    rect(sbX, sbY, 8, sbH, 4);

    // Thumb
    fill(80);
    rect(sbX, thumbY, 8, thumbH, 4);
  }

  void handleClick(LogManager log) {
    // Check level filter buttons
    float fy = contentY + 40;
    float fx = contentX + 55;

    String[] levelNames = {strings.get("ОТЛАДКА", "DEBUG"), strings.get("ИНФО", "INFO"), strings.get("ПРЕДУПР", "WARN"), strings.get("ОШИБКА", "ERROR")};
    for (int i = 0; i < 4; i++) {
      float bw = textWidth(levelNames[i]) + 12;
      if (mouseX >= fx && mouseX <= fx + bw && mouseY >= fy && mouseY <= fy + 18) {
        switch (i) {
          case 0: showDebug = !showDebug; break;
          case 1: showInfo = !showInfo; break;
          case 2: showWarn = !showWarn; break;
          case 3: showError = !showError; break;
        }
        return;
      }
      fx += bw + 4;
    }

    // Check category filter buttons
    fx += 80;
    String[] cats = {"SERIAL", "FFB", "AXIS", "PROFILE", "SYSTEM"};
    for (int i = 0; i < 5; i++) {
      float bw = textWidth(cats[i]) + 10;
      if (mouseX >= fx && mouseX <= fx + bw && mouseY >= fy && mouseY <= fy + 18) {
        showCategory[i] = !showCategory[i];
        return;
      }
      fx += bw + 3;
    }

    // Check clear button
    float clearX = contentX + contentW - 70;
    if (mouseX >= clearX && mouseX <= clearX + 60 && mouseY >= fy && mouseY <= fy + 18) {
      log.clear();
      return;
    }

    // Check search bar
    float sx = contentX + 10;
    float sy = contentY + 65;
    searchActive = (mouseX >= sx && mouseX <= sx + 250 &&
                    mouseY >= sy && mouseY <= sy + 22);
  }

  void handleScroll(float delta) {
    ArrayList<LogEntry> filtered = getFilteredEntries(Log);
    int totalEntries = filtered.size();
    int maxScroll = max(0, totalEntries - maxVisibleLines);

    scrollOffset = constrain(scrollOffset + int(-delta * 3), 0, maxScroll);
  }

  void handleKey(char k) {
    if (!searchActive) return;

    if (k == BACKSPACE) {
      if (searchQuery.length() > 0) {
        searchQuery = searchQuery.substring(0, searchQuery.length() - 1);
      }
    } else if (k == ENTER || k == RETURN) {
      searchActive = false;
    } else if (k == ESCAPE) {
      searchQuery = "";
      searchActive = false;
    } else if (k != DELETE && k != TAB) {
      searchQuery += k;
    }
    scrollOffset = 0; // reset on search change
  }
}
