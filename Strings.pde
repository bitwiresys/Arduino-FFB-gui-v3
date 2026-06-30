// Localization strings вЂ” EN (default) / RU
// Usage: strings.get("Р СѓСЃСЃРєРёР№ С‚РµРєСЃС‚", "English text")
Strings strings = new Strings();

class Strings {
  String lang = "en";
  // version растёт при каждой смене языка — экраны, которые кешируют
  // локализованные массивы (названия вкладок, FFB-эффектов и т.п.),
  // сверяются с ним и пересобирают тексты, а не держат их "замороженными"
  // с момента создания объекта.
  int version = 0;
  String get(String ru, String en) { return lang.equals("ru") ? ru : en; }
  void setLang(String l) {
    if (!l.equals(lang)) { lang = l; version++; }
  }
}
