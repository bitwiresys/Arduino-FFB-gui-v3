// ============================================================
// UIWidgets вЂ” reusable UI components
// TabBar, TabButton, UISlider, UICheckbox, UIGauge, etc.
// ============================================================

// ---- TabBar ----
class TabBar {
  float x, y, w, h;
  ArrayList<TabButton> tabs = new ArrayList<TabButton>();
  int activeTab = 0;

  TabBar(float x, float y, float w, float h) {
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
  }

  void addTab(String label, int id) {
    float tabW = w / max(tabs.size() + 1, 1);
    TabButton btn = new TabButton(label, id);
    tabs.add(btn);
    recalcPositions();
  }

  void recalcPositions() {
    float tabW = w / max(tabs.size(), 1);
    for (int i = 0; i < tabs.size(); i++) {
      tabs.get(i).x = x + i * tabW;
      tabs.get(i).y = y;
      tabs.get(i).w = tabW;
      tabs.get(i).h = h;
    }
  }

  void draw() {
    // Background
    fill(30);
    noStroke();
    rect(x, y, w, h);

    for (int i = 0; i < tabs.size(); i++) {
      TabButton btn = tabs.get(i);
      boolean isActive = (i == activeTab);
      boolean isHover = mouseX >= btn.x && mouseX <= btn.x + btn.w &&
                        mouseY >= btn.y && mouseY <= btn.y + btn.h;

      if (isActive) {
        fill(50, 120, 180);
      } else if (isHover) {
        fill(60, 60, 70);
      } else {
        fill(40, 40, 48);
      }

      noStroke();
      rect(btn.x, btn.y, btn.w, btn.h);

      // Active indicator line
      if (isActive) {
        fill(80, 180, 255);
        noStroke();
        rect(btn.x, btn.y + btn.h - 3, btn.w, 3);
      }

      // Label
      fill(isActive ? 255 : 160);
      textAlign(CENTER, CENTER);
      textSize(h * 0.45);
      text(btn.label, btn.x + btn.w * 0.5, btn.y + btn.h * 0.45);
    }
  }

  int handleClick() {
    for (int i = 0; i < tabs.size(); i++) {
      TabButton btn = tabs.get(i);
      if (mouseX >= btn.x && mouseX <= btn.x + btn.w &&
          mouseY >= btn.y && mouseY <= btn.y + btn.h) {
        activeTab = i;
        return btn.id;
      }
    }
    return -1;
  }
}

class TabButton {
  String label;
  int id;
  float x, y, w, h;

  TabButton(String label, int id) {
    this.label = label;
    this.id = id;
  }
}
