// Pure helpers for the CPU plugin: formatting, colours, settings parsing.
// No Qt objects in here so the logic stays testable with plain node.

// Theme palette for the swatch rows, read from the live Omarchy theme.
function parseThemeColors(raw) {
  var keys = ["accent", "muted", "foreground", "red", "yellow", "orange", "green", "cyan", "blue", "magenta"]
  var out = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
    if (!match) continue
    if (keys.indexOf(match[1]) !== -1) out[match[1]] = match[2]
  }
  return out
}

// "" first: keeps the normal bar colour.
function themePalette(theme) {
  var t = theme || {}
  return [
    "",
    t.red || "#e06c75",
    t.orange || t.yellow || "#d19a66",
    t.yellow || "#e5c07b",
    t.green || "#98c379",
    t.cyan || "#56b6c2",
    t.blue || t.accent || "#61afef",
    t.magenta || "#c678dd",
    t.muted || "#abb2bf",
    t.foreground || "#ffffff"
  ]
}

function num(v, fallback) {
  var n = Number(v)
  return isFinite(n) ? n : fallback
}

function clampInt(v, lo, hi, fallback) {
  var n = Math.round(num(v, fallback))
  if (!isFinite(n)) n = fallback
  return Math.max(lo, Math.min(hi, n))
}

// Clamp and snap to a step, so a value carried over from an older config
// (or typed by hand) lands on the same marks the stepper walks.
function clampStep(v, lo, hi, step, fallback) {
  var n = num(v, fallback)
  if (!isFinite(n)) n = fallback
  var st = Math.max(1, Math.round(num(step, 1)))
  n = Math.round(n / st) * st
  return Math.max(lo, Math.min(hi, n))
}

function asBool(v, fallback) {
  if (v === true || v === "true" || v === 1) return true
  if (v === false || v === "false" || v === 0) return false
  return fallback
}

function isNum(v) { return typeof v === "number" && isFinite(v) }

// ---- formatting ---------------------------------------------------------

function pct(v) { return isNum(v) ? Math.round(v) + "%" : "–" }

// ---- temperature units --------------------------------------------------

function toUnit(c, unit) {
  if (!isNum(c)) return null
  return unit === "F" ? c * 9 / 5 + 32 : c
}
function unitSuffix(unit) { return unit === "F" ? "°F" : "°C" }
function normalizeUnit(unit) { return String(unit) === "F" ? "F" : "C" }
function pct1(v) { return isNum(v) ? v.toFixed(1) + "%" : "–" }
function degrees(v, unit) {
  var t = toUnit(v, unit)
  return isNum(t) ? Math.round(t) + unitSuffix(unit) : "–"
}
function degreesShort(v, unit) {
  var t = toUnit(v, unit)
  return isNum(t) ? Math.round(t) + "°" : "–"
}
function ghz(mhz, decimals) {
  if (!isNum(mhz)) return "–"
  var d = decimals === undefined ? 2 : decimals
  return (mhz / 1000).toFixed(d) + " GHz"
}
function ghzShort(mhz) { return isNum(mhz) ? (mhz / 1000).toFixed(1) + "GHz" : "–" }
function watts(v) { return isNum(v) ? Math.round(v) + " W" : "–" }
function wattsShort(v) { return isNum(v) ? Math.round(v) + "W" : "–" }
function gib(v) { return isNum(v) ? v.toFixed(1) + " GiB" : "–" }
function load(v) { return isNum(v) ? v.toFixed(2) : "–" }

// "AMD Ryzen 9 3900X 12-Core Processor" -> "AMD Ryzen 9 3900X"
// "Intel(R) Core(TM) i7-8700K CPU @ 3.70GHz" -> "Intel Core i7-8700K"
function shortModel(name) {
  var s = String(name || "")
  s = s.replace(/\((R|TM|C)\)/gi, "")
  s = s.replace(/\s*@.*$/, "")
  s = s.replace(/\b\d+-Core\b/gi, "")
  s = s.replace(/\b(Processor|CPU|with Radeon Graphics)\b/gi, "")
  s = s.replace(/\s{2,}/g, " ").trim()
  return s || "CPU"
}

// Bar pill text: only the parts the user switched on.
function barText(parts) {
  var out = []
  for (var i = 0; i < parts.length; i++) if (parts[i]) out.push(parts[i])
  return out.join(" ")
}

// ---- colours ------------------------------------------------------------

// Load band colour: "" (normal) below the warning mark, warnColor from the
// warning mark, alertColor from the alert mark. Either colour may be "" to
// keep the bar's own colour.
function loadColor(usage, warnFrom, alertFrom, warnColor, alertColor) {
  if (!isNum(usage)) return ""
  if (usage >= alertFrom) return alertColor
  if (usage >= warnFrom) return warnColor
  return ""
}

// Headline temperature: preferred label if present, else the sensible
// default for the platform, else the hottest reading.
var TEMP_PREFERENCE = ["Tctl", "Tdie", "Package id 0", "Composite", "CPU", "temp1"]
function pickTemp(temps, preferred) {
  var list = temps || []
  if (!list.length) return null
  var i
  if (preferred && preferred !== "auto")
    for (i = 0; i < list.length; i++) if (list[i].label === preferred) return list[i].c
  for (var p = 0; p < TEMP_PREFERENCE.length; p++)
    for (i = 0; i < list.length; i++) if (list[i].label === TEMP_PREFERENCE[p]) return list[i].c
  var best = list[0].c
  for (i = 1; i < list.length; i++) if (list[i].c > best) best = list[i].c
  return best
}

function sensorChips(temps, unit) {
  var out = [{ value: "auto", label: "Auto", tooltip: "Tctl / package temperature when available" }]
  var list = temps || []
  for (var i = 0; i < list.length; i++)
    out.push({ value: list[i].label, label: list[i].label, tooltip: degrees(list[i].c, unit) })
  return out
}

// ---- history ------------------------------------------------------------

// Append one sample and keep the last `size`. Returns a new array so QML
// property bindings actually fire.
function pushHistory(history, value, size) {
  var out = (history || []).slice()
  out.push(isNum(value) ? value : 0)
  var cap = Math.max(2, Math.round(num(size, 60)))
  while (out.length > cap) out.shift()
  return out
}

// ---- tooltips -----------------------------------------------------------

function padRight(s, w) {
  var out = String(s)
  while (out.length < w) out += " "
  return out
}

// Title line, then one aligned "label  value" line per row. Rows whose value
// is null/empty are dropped, so a machine that doesn't report something
// simply has no line for it rather than a dash.
function tooltip(title, rows) {
  var list = (rows || []).filter(function(r) {
    return r && r[1] !== null && r[1] !== undefined && r[1] !== "" && r[1] !== "-"
  })
  var w = 0
  for (var i = 0; i < list.length; i++) w = Math.max(w, String(list[i][0]).length)
  var out = [title]
  for (var j = 0; j < list.length; j++)
    out.push(padRight(list[j][0], w) + "   " + String(list[j][1]))

  // Bar.qml centres each line of a tooltip (Text.AlignHCenter), so the only
  // way to get a left-aligned block is to make every line the same rendered
  // width. Ordinary trailing spaces cannot do it: Qt trims trailing
  // whitespace when laying a line out, so the padding is discarded and the
  // line re-centres. A non-breaking space is not trimmed, and is the same
  // width as a space in the bar's monospace font.
  var line = 0
  for (var k = 0; k < out.length; k++) line = Math.max(line, out[k].length)
  for (var n = 0; n < out.length; n++) {
    while (out[n].length < line) out[n] += "\u00a0"
  }
  return out.join("\n")
}
