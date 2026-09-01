import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// CPU: the panel, and the owner of all state.
//
// Loaded by BarWidget.qml (the manifest entry point), which injects bar,
// anchorItem and hostWidget and forwards open/close/toggle to us. IPC is
// left to the bar widget so the target is registered once.
Panel {
  id: root
  moduleName: "dansmith888.cpu"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace("file://", "")
  readonly property string themeColorsPath: (Quickshell.env("HOME") || "")
    + "/.local/state/omarchy/current/theme/colors.toml"

  // A stalled command must not wedge polling. Each Process gets a deadline;
  // if it is still running when the timer fires, it is killed and the next
  // poll starts clean. bin/cpustatus reads /proc directly and never shells
  // out, so its own output is bounded by the caps in the backend.
  property int watchdogSeconds: 10
  Timer {
    id: watchdog
    interval: root.watchdogSeconds * 1000
    repeat: true
    running: true
    onTriggered: {
      if (statusProc.running) statusProc.running = false
      if (themeProc.running) themeProc.running = false
    }
  }

  // ---- Readings. null means "this machine doesn't report it" and hides
  // the control rather than showing a made-up zero.
  property bool devicePresent: false
  property bool stale: false
  property string model: ""
  property int cores: 0
  property int threads: 0
  property real usage: 0
  property var perCore: []
  property var freqMhz: null
  property var maxFreqMhz: null
  property var temps: []
  property string sensor: ""
  property var loadAvg: null
  property var packageW: null
  property bool powerPresent: false
  property var powerLimitW: null
  property var memUsedPct: null
  property var memUsedGiB: null
  property var memTotalGiB: null
  property var topProcs: []
  // Recent load, oldest first, for the sparkline. Sampled on every poll so
  // the graph keeps filling in while the panel is closed.
  property var usageHistory: []

  property var themeColors: ({})
  readonly property var colorChoices: Model.themePalette(root.themeColors)

  // ---- Settings.
  readonly property int pollIntervalMs: Model.clampInt(setting("pollIntervalMs", 2000), 500, 60000, 2000)
  readonly property bool showUsage: Model.asBool(setting("showUsage", true), true)
  readonly property bool showTemp: Model.asBool(setting("showTemp", true), true)
  readonly property bool showClock: Model.asBool(setting("showClock", false), false)
  readonly property bool showPower: Model.asBool(setting("showPower", false), false)
  readonly property bool showIcon: Model.asBool(setting("showIcon", true), true)
  readonly property string tempSensor: String(setting("tempSensor", "auto"))
  // warnFrom/alertFrom were once busyFrom/hotFrom: read the old key as the
  // fallback so an existing bar entry keeps its thresholds and colours, and
  // snap to the stepper's marks (an old 16 lands on 15, not 16).
  readonly property int warnFrom: Model.clampStep(setting("warnFrom", setting("busyFrom", 50)), 5, 100, 5, 50)
  readonly property int alertFrom: Model.clampStep(setting("alertFrom", setting("hotFrom", 85)), 5, 100, 5, 85)
  readonly property string warnColor: String(setting("warnColor", setting("busyColor", "")))
  readonly property string alertColor: String(setting("alertColor", setting("hotColor", "")))
  // Package Power Tracking: the sustained package power the chip is allowed
  // to draw, which is what a power reading should be measured against. It is
  // not the TDP — a 3900X is 105 W TDP but 142 W PPT — so scaling to TDP
  // would peg the bar at 100% well before the chip is actually at its limit.
  // 0 = power is off entirely: no bar, no hover row, no readings.
  // tdpWatts is the old key, read once so an existing bar entry carries over.
  readonly property int pptWatts: Model.clampInt(setting("pptWatts", setting("tdpWatts", 0)), 0, 1000, 0)
  readonly property int pillWidth: Model.clampInt(setting("pillWidth", 0), 0, 400, 0)
  // "total" = share of the whole CPU (all threads at 100% reads 100%).
  // "core"  = share of one core, the top(1) convention.
  readonly property int topCount: Model.clampInt(setting("topCount", 5), 1, 10, 5)
  readonly property string temperatureUnit: Model.normalizeUnit(setting("temperatureUnit", "C"))
  readonly property int historySamples: Model.clampInt(setting("historySamples", 60), 20, 240, 60)

  // ---- Derived.
  readonly property string shortModel: Model.shortModel(root.model)
  readonly property var headlineTemp: Model.pickTemp(root.temps, root.tempSensor)
  readonly property string usageText: Model.pct(root.usage)
  readonly property string tempText: Model.degrees(root.headlineTemp, root.temperatureUnit)
  readonly property string clockText: Model.ghz(root.freqMhz)
  readonly property string vramLikeMemoryText: Model.gib(root.memUsedGiB) + " / " + Model.gib(root.memTotalGiB)
  readonly property string loadAvgText: root.loadAvg
    ? Model.load(root.loadAvg[0]) + "  " + Model.load(root.loadAvg[1]) + "  " + Model.load(root.loadAvg[2])
    : ""
  // Power is shown only when the CPU's energy counter is actually readable.
  // No counter, no power: a load-based estimate was wrong by ~10x at idle
  // (a chip drawing 45 W doing nothing reads near zero), so there is none.
  readonly property bool powerEnabled: root.packageW !== null
  // PPT is optional and only AMD needs it: Intel's RAPL reports its own
  // limit, AMD's reports none. Without it the reading stands on its own.
  readonly property real powerScale: root.pptWatts > 0
    ? root.pptWatts
    : (root.powerLimitW !== null ? root.powerLimitW : 0)
  readonly property bool powerHasScale: root.powerEnabled && root.powerScale > 0
  readonly property real powerW: root.packageW !== null ? root.packageW : 0
  readonly property string powerText: !root.powerEnabled
    ? ""
    : (root.powerHasScale
        ? Model.watts(root.powerW) + " / " + Model.watts(root.powerScale)
        : Model.watts(root.powerW))
  readonly property string coreSummary: root.cores > 0 ? root.cores + " cores / " + root.threads + " threads" : ""
  readonly property string barText: Model.barText([
    root.showUsage ? Model.pct(root.usage) : "",
    root.showTemp && root.headlineTemp !== null ? Model.degreesShort(root.headlineTemp, root.temperatureUnit) : "",
    root.showClock && root.freqMhz !== null ? Model.ghzShort(root.freqMhz) : "",
    root.showPower && root.powerEnabled ? Model.wattsShort(root.powerW) : ""
  ])
  // Same shape as barText but with every field at its widest, so the pill
  // can reserve a stable column and stop shuffling its neighbours every
  // time a reading crosses 9 -> 10 -> 100.
  readonly property string barWidest: Model.barText([
    root.showUsage ? "100%" : "",
    root.showTemp && root.headlineTemp !== null ? "100\u00b0" : "",
    root.showClock && root.freqMhz !== null ? "9.9GHz" : "",
    root.showPower && root.powerEnabled ? "999W" : ""
  ])
  readonly property string tierColor: Model.loadColor(root.usage, root.warnFrom, root.alertFrom,
                                                      root.warnColor, root.alertColor)
  readonly property var refreshChips: [
    { value: "500", label: "0.5s" },
    { value: "1000", label: "1s" },
    { value: "2000", label: "2s" },
    { value: "3000", label: "3s" },
    { value: "5000", label: "5s" }
  ]
  readonly property var sensorChips: Model.sensorChips(root.temps, root.temperatureUnit)
  readonly property var unitChips: [
    { value: "C", label: "°C" },
    { value: "F", label: "°F" }
  ]
  readonly property var historyChips: [
    { value: "30", label: "30" },
    { value: "60", label: "60" },
    { value: "120", label: "120" },
    { value: "240", label: "240" }
  ]
  readonly property string metaText: {
    var bits = []
    if (root.cores > 0) bits.push(root.cores + " cores")
    if (root.threads > 0) bits.push(root.threads + " threads")
    if (root.maxFreqMhz !== null) bits.push("up to " + Model.ghz(root.maxFreqMhz, 1))
    return bits.join(" · ")
  }

  function persistSettings(patch) {
    var next = Object.assign({}, root.settings, patch)
    root.settings = next
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = next
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, next)
  }

  function setPollIntervalMs(v) { persistSettings({ pollIntervalMs: Model.clampInt(v, 500, 60000, 2000) }) }
  function setShowUsage(v) { persistSettings({ showUsage: !!v }) }
  function setShowTemp(v) { persistSettings({ showTemp: !!v }) }
  function setShowClock(v) { persistSettings({ showClock: !!v }) }
  function setShowPower(v) { persistSettings({ showPower: !!v }) }
  function setShowIcon(v) { persistSettings({ showIcon: !!v }) }
  function setTempSensor(v) { persistSettings({ tempSensor: String(v || "auto") }) }
  function setWarnFrom(v) { persistSettings({ warnFrom: Model.clampStep(v, 5, 100, 5, 50) }) }
  function setAlertFrom(v) { persistSettings({ alertFrom: Model.clampStep(v, 5, 100, 5, 85) }) }
  function setWarnColor(hex) { persistSettings({ warnColor: String(hex) }) }
  function setAlertColor(hex) { persistSettings({ alertColor: String(hex) }) }
  function setPptWatts(v) { persistSettings({ pptWatts: Model.clampInt(v, 0, 1000, 0) }) }
  function setPillWidth(v) { persistSettings({ pillWidth: Model.clampInt(v, 0, 400, 0) }) }
  function setTopCount(v) { persistSettings({ topCount: Model.clampInt(v, 1, 10, 5) }) }
  function setTemperatureUnit(v) { persistSettings({ temperatureUnit: Model.normalizeUnit(v) }) }
  function setHistorySamples(v) { persistSettings({ historySamples: Model.clampInt(v, 20, 240, 60) }) }

  function refresh() { if (!statusProc.running) statusProc.running = true }
  function refreshThemeColors() { if (!themeProc.running) themeProc.running = true }

  // Reopening should always land at the top of the panel, not wherever the
  // last visit left the scroll.
  onOpenedChanged: {
    if (!opened) return
    refresh()
    refreshThemeColors()
    flick.contentY = 0
  }
  Component.onCompleted: {
    refreshThemeColors()
  }

  Process {
    id: statusProc
    command: [root.pluginDir + "bin/cpustatus"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var out = String(this.text).trim()
        if (out === "" || out === "{}") { root.devicePresent = false; return }
        try {
          var d = JSON.parse(out)
          if (d.present !== true) { root.devicePresent = false; return }
          root.devicePresent = true
          root.stale = false
          root.model = d.model || ""
          root.cores = Number(d.cores) || 0
          root.threads = Number(d.threads) || 0
          root.usage = Number(d.usage) || 0
          root.perCore = d.perCore || []
          root.freqMhz = (typeof d.freqMhz === "number") ? d.freqMhz : null
          root.maxFreqMhz = (typeof d.maxFreqMhz === "number") ? d.maxFreqMhz : null
          root.temps = d.temps || []
          root.sensor = d.sensor || ""
          root.loadAvg = d.load || null
          root.packageW = (typeof d.packageW === "number") ? d.packageW : null
          root.powerPresent = d.powerPresent === true
          root.powerLimitW = (typeof d.powerLimitW === "number") ? d.powerLimitW : null
          root.memUsedPct = (typeof d.memUsedPct === "number") ? d.memUsedPct : null
          root.memUsedGiB = (typeof d.memUsedGiB === "number") ? d.memUsedGiB : null
          root.memTotalGiB = (typeof d.memTotalGiB === "number") ? d.memTotalGiB : null
          root.topProcs = d.top || []
          root.usageHistory = Model.pushHistory(root.usageHistory, root.usage, root.historySamples)
        } catch (e) {
          // Keep the last good reading rather than blanking the pill.
          root.stale = root.devicePresent
        }
      }
    }
  }

  Process {
    id: themeProc
    // No shell, no tilde expansion, no glob: an explicit absolute path built
    // from $HOME, read through head so the size is capped whatever the path
    // turns out to point at.
    command: ["head", "-c", "65536", root.themeColorsPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.themeColors = Model.parseThemeColors(text)
    }
  }

  // Steady state while closed; the configured cadence, floored, while open.
  Timer {
    interval: root.opened ? root.pollIntervalMs : Math.max(root.pollIntervalMs, 3000)
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(760))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: flick
        // No margins here: KeyboardPanel.padding already insets the content,
        // the way the first-party tailscale and agents panels do it.
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        Column {
          id: column
          width: flick.width
          spacing: Style.space(12)
          opacity: root.stale ? 0.55 : 1.0

          // ---------- Hero: chip mark · model · cores/threads ----------
          PanelHero {
            width: parent.width
            title: root.shortModel
            meta: root.metaText
            detail: root.usageText
            foreground: root.barForeground
            fontFamily: Style.font.family
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: "󰍛"
                color: root.tierColor !== "" ? root.tierColor : root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.display
              }
            }
          }

          Sparkline {
            width: parent.width
            height: Style.space(46)
            values: root.usageHistory
            ceiling: 100
            lineColor: root.tierColor !== "" ? root.tierColor : Color.accent
          }

          // ---------- Load, memory ----------
          MeterRow {
            width: parent.width
            label: "Load"
            value: root.usage
            valueText: Model.pct1(root.usage)
            fill: root.tierColor !== "" ? root.tierColor : Color.accent
          }

          MeterRow {
            width: parent.width
            visible: root.powerHasScale
            label: "Power"
            value: root.powerScale > 0 ? 100 * root.powerW / root.powerScale : 0
            valueText: root.powerText
            fill: Color.accent
          }

          // No limit to measure against — AMD reports none — so the reading
          // stands on its own rather than inventing a bar.
          Row {
            width: parent.width
            visible: root.powerEnabled && !root.powerHasScale
            spacing: Style.space(8)

            Text {

              textFormat: Text.PlainText
              width: parent.width - powerOnly.width - parent.spacing
              text: "Power"
              color: Qt.darker(root.barForeground, 1.4)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Text {

              textFormat: Text.PlainText
              id: powerOnly
              text: root.powerText
              color: root.barForeground
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
          }

          MeterRow {
            width: parent.width
            visible: root.memUsedPct !== null
            label: "Memory"
            value: root.memUsedPct === null ? 0 : root.memUsedPct
            valueText: Model.gib(root.memUsedGiB) + " / " + Model.gib(root.memTotalGiB)
            fill: Color.accent
          }

          Text {

            textFormat: Text.PlainText
            width: parent.width
            visible: root.loadAvg !== null
            text: root.loadAvg
              ? "Load average  " + Model.load(root.loadAvg[0]) + "   " + Model.load(root.loadAvg[1])
                + "   " + Model.load(root.loadAvg[2])
              : ""
            color: Qt.darker(root.barForeground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }


          PanelSeparator { width: parent.width; foreground: root.barForeground }

          // ---------- Per-core bars ----------
          PanelSectionHeader { text: "CORES"; foreground: root.barForeground }

          Flow {
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: root.perCore
              delegate: Item {
                id: coreCell
                required property var modelData
                required property int index
                readonly property real load: Number(modelData) || 0
                width: Math.max(Style.space(8), (column.width - Style.space(4) * 11) / 12)
                height: Style.space(34)

                Rectangle {
                  anchors.fill: parent
                  radius: Style.cornerRadius > 0 ? Style.space(2) : 0
                  color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.10)
                }

                Rectangle {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  height: Math.max(1, coreCell.height * Math.min(1, coreCell.load / 100))
                  radius: Style.cornerRadius > 0 ? Style.space(2) : 0
                  color: {
                    var c = Model.loadColor(coreCell.load, root.warnFrom, root.alertFrom,
                                            root.warnColor, root.alertColor)
                    return c !== "" ? c : Color.accent
                  }
                  Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }

                PanelToolTip {
                  visible: coreMouse.containsMouse
                  text: "Thread " + coreCell.index + " · " + Math.round(coreCell.load) + "%"
                  fontFamily: Style.font.family
                }

                MouseArea {
                  id: coreMouse
                  anchors.fill: parent
                  hoverEnabled: true
                }
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.barForeground }

          // ---------- Temperatures ----------
          PanelSectionHeader {
            text: "TEMPERATURE"
            foreground: root.barForeground
            visible: root.temps.length > 0
          }

          Repeater {
            model: root.temps
            delegate: Row {
              required property var modelData
              width: column.width
              spacing: Style.space(8)

              Text {

                textFormat: Text.PlainText
                width: parent.width - valueText.width - parent.spacing
                text: modelData.label
                color: Qt.darker(root.barForeground, 1.4)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {

                textFormat: Text.PlainText
                id: valueText
                text: Model.degrees(modelData.c, root.temperatureUnit)
                color: root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: modelData.c === root.headlineTemp
              }
            }
          }

          Text {

            textFormat: Text.PlainText
            width: parent.width
            visible: root.temps.length === 0
            text: "No CPU temperature sensor found on this machine."
            color: Qt.darker(root.barForeground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator { width: parent.width; foreground: root.barForeground }

          // ---------- Top processes ----------
          PanelSectionHeader { text: "TOP PROCESSES"; foreground: root.barForeground }

          Text {

            textFormat: Text.PlainText
            width: parent.width
            visible: root.topProcs.length === 0
            text: "Nothing measurable since the last sample."
            color: Qt.darker(root.barForeground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          Repeater {
            model: root.topProcs.slice(0, root.topCount)
            delegate: Row {
              required property var modelData
              width: column.width
              spacing: Style.space(8)

              Text {

                textFormat: Text.PlainText
                width: parent.width - procValue.width - parent.spacing
                text: modelData.name + "  (" + modelData.pid + ")"
                color: Qt.darker(root.barForeground, 1.3)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {

                textFormat: Text.PlainText
                id: procValue
                text: Model.pctSmall(modelData.cpu)
                color: root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.barForeground }

          // ---------- Bar pill ----------
          PanelSectionHeader { text: "IN THE BAR"; foreground: root.barForeground }

          Text {

            textFormat: Text.PlainText
            width: parent.width
            text: "Pick what the pill shows. Everything stays visible in here either way."
            color: Qt.darker(root.barForeground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Toggle {
            width: parent.width
            label: "Chip icon"
            description: "󰍛 in front of the readings."
            checked: root.showIcon
            foreground: root.barForeground
            accent: Color.accent
            fontFamily: Style.font.family
            onClicked: root.setShowIcon(!root.showIcon)
          }

          Toggle {
            width: parent.width
            label: "Load"
            description: "Total CPU load as a percentage."
            checked: root.showUsage
            foreground: root.barForeground
            accent: Color.accent
            fontFamily: Style.font.family
            onClicked: root.setShowUsage(!root.showUsage)
          }

          Toggle {
            width: parent.width
            visible: root.temps.length > 0
            label: "Temperature"
            description: "The sensor picked below, in whole degrees."
            checked: root.showTemp
            foreground: root.barForeground
            accent: Color.accent
            fontFamily: Style.font.family
            onClicked: root.setShowTemp(!root.showTemp)
          }

          Toggle {
            width: parent.width
            visible: root.freqMhz !== null
            label: "Clock"
            description: "Average core clock in GHz."
            checked: root.showClock
            foreground: root.barForeground
            accent: Color.accent
            fontFamily: Style.font.family
            onClicked: root.setShowClock(!root.showClock)
          }

          Toggle {
            width: parent.width
            visible: root.powerEnabled
            label: "Power"
            description: "Power against the TDP you set."
            checked: root.showPower
            foreground: root.barForeground
            accent: Color.accent
            fontFamily: Style.font.family
            onClicked: root.setShowPower(!root.showPower)
          }

          Text {

            textFormat: Text.PlainText
            width: parent.width
            text: "Refresh interval"
            color: Qt.darker(root.barForeground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          ButtonGroup {
            value: String(root.pollIntervalMs)
            options: root.refreshChips
            foreground: root.barForeground
            background: Color.background
            accent: Color.accent
            fontFamily: Style.font.family
            onChanged: function(value) { root.setPollIntervalMs(value) }
          }

          Text {

            textFormat: Text.PlainText
            width: parent.width
            visible: root.temps.length > 1
            text: "Temperature sensor"
            color: Qt.darker(root.barForeground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          ButtonGroup {
            visible: root.temps.length > 1
            value: root.tempSensor
            options: root.sensorChips
            foreground: root.barForeground
            background: Color.background
            accent: Color.accent
            fontFamily: Style.font.family
            onChanged: function(value) { root.setTempSensor(value) }
          }

          Text {

            textFormat: Text.PlainText
            width: parent.width
            visible: root.temps.length > 0
            text: "Temperature unit"
            color: Qt.darker(root.barForeground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          ButtonGroup {
            visible: root.temps.length > 0
            value: root.temperatureUnit
            options: root.unitChips
            foreground: root.barForeground
            background: Color.background
            accent: Color.accent
            fontFamily: Style.font.family
            onChanged: function(value) { root.setTemperatureUnit(value) }
          }

          Text {

            textFormat: Text.PlainText
            width: parent.width
            text: "Graph history (samples)"
            color: Qt.darker(root.barForeground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          ButtonGroup {
            value: String(root.historySamples)
            options: root.historyChips
            foreground: root.barForeground
            background: Color.background
            accent: Color.accent
            fontFamily: Style.font.family
            onChanged: function(value) { root.setHistorySamples(value) }
          }

          PanelSeparator {
            width: parent.width
            foreground: root.barForeground
            visible: root.powerEnabled
          }

          PanelSectionHeader {
            text: "POWER"
            foreground: root.barForeground
            visible: root.powerEnabled
          }

          Text {

            textFormat: Text.PlainText
            width: parent.width
            visible: root.powerEnabled
            text: root.powerHasScale
              ? "Measured from the CPU's energy counter, against the limit below."
              : "Measured from the CPU's energy counter. AMD reports no power limit, so there is nothing to measure it against — enter your CPU's PPT below for a bar and a total, or leave it at 0 to just show the wattage."
            color: Qt.darker(root.barForeground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Row {
            width: parent.width
            visible: root.powerEnabled
            spacing: Style.space(8)

            Text {

              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: "PPT"
              color: Qt.darker(root.barForeground, 1.4)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            NumberField {
              label: ""
              value: root.pptWatts
              from: 0
              to: 1000
              stepSize: 1
              foreground: root.barForeground
              accent: Color.accent
              field.editable: false
              onModified: function(value) { root.setPptWatts(value) }
            }

            Text {

              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: "W  (0 = no total)"
              color: Qt.darker(root.barForeground, 1.4)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }

          PanelSeparator { width: parent.width; foreground: root.barForeground }

          PanelSectionHeader { text: "LAYOUT"; foreground: root.barForeground }

          Text {

            textFormat: Text.PlainText
            width: parent.width
            text: "Width of the reading in pixels. 0 fits the reading and holds that width so the bar stays still."
            color: Qt.darker(root.barForeground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          NumberField {
            label: ""
            value: root.pillWidth
            from: 0
            to: 400
            stepSize: 2
            foreground: root.barForeground
            accent: Color.accent
            field.editable: false
            onModified: function(value) { root.setPillWidth(value) }
          }

          PanelSeparator { width: parent.width; foreground: root.barForeground }

          // ---------- Load colours ----------
          PanelSectionHeader { text: "WARNING & ALERT"; foreground: root.barForeground }

          Text {

            textFormat: Text.PlainText
            width: parent.width
            text: "The pill, the hero mark and the core bars change color once load passes the warning and alert marks. ∅ keeps the normal bar color."
            color: Qt.darker(root.barForeground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {

              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: "Warning from"
              color: Qt.darker(root.barForeground, 1.4)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            NumberField {
              label: ""
              value: root.warnFrom
              // Steps land on multiples of 5, not 1/6/11.
              from: 5
              to: 100
              stepSize: 5
              foreground: root.barForeground
              accent: Color.accent
              field.editable: false
              onModified: function(value) { root.setWarnFrom(value) }
            }

            Text {

              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: "%"
              color: Qt.darker(root.barForeground, 1.4)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }

          SwatchRow {
            width: parent.width
            choices: root.colorChoices
            selected: root.warnColor
            foreground: root.barForeground
            onPicked: function(hex) { root.setWarnColor(hex) }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {

              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: "Alert from"
              color: Qt.darker(root.barForeground, 1.4)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            NumberField {
              label: ""
              value: root.alertFrom
              from: 5
              to: 100
              stepSize: 5
              foreground: root.barForeground
              accent: Color.accent
              field.editable: false
              onModified: function(value) { root.setAlertFrom(value) }
            }

            Text {

              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: "%"
              color: Qt.darker(root.barForeground, 1.4)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }

          SwatchRow {
            width: parent.width
            choices: root.colorChoices
            selected: root.alertColor
            foreground: root.barForeground
            onPicked: function(hex) { root.setAlertColor(hex) }
          }
        }
      }
    }
  }

  // A labelled bar: name on the left, reading on the right, fill underneath.
  component MeterRow: Column {
    id: meter
    property string label: ""
    property string valueText: ""
    property real value: 0
    property color fill: Color.accent
    spacing: Style.space(4)

    Row {
      width: meter.width
      spacing: Style.space(8)

      Text {

        textFormat: Text.PlainText
        // Floor it: a fractional remainder rounds the value text past the
        // panel edge and clips its last character.
        width: Math.floor(meter.width - meterValue.width - parent.spacing)
        text: meter.label
        color: Qt.darker(root.barForeground, 1.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }

      Text {

        textFormat: Text.PlainText
        id: meterValue
        text: meter.valueText
        color: root.barForeground
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }
    }

    Rectangle {
      width: meter.width
      height: Style.space(6)
      radius: height / 2
      color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.10)

      Rectangle {
        width: Math.round(parent.width * Math.max(0, Math.min(1, meter.value / 100)))
        height: parent.height
        radius: parent.radius
        color: meter.fill
        Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
      }
    }
  }

  // One row of theme swatches; "" is the ∅ "leave it alone" choice.
  component SwatchRow: Row {
    id: swatches
    property var choices: []
    property string selected: ""
    property color foreground: Color.foreground
    signal picked(string hex)
    spacing: Style.space(6)

    Repeater {
      model: swatches.choices.length
      delegate: Rectangle {
        id: dot
        required property int index
        readonly property string swatch: swatches.choices[index]
        width: Style.space(22)
        height: Style.space(22)
        radius: width / 2
        color: dot.swatch === "" ? "transparent" : dot.swatch
        border.width: swatches.selected === dot.swatch ? 2 : 1
        border.color: swatches.selected === dot.swatch ? Color.accent : Qt.darker(swatches.foreground, 1.6)

        Text {

          textFormat: Text.PlainText
          visible: dot.swatch === ""
          anchors.centerIn: parent
          text: "∅"
          color: swatches.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: swatches.picked(dot.swatch)
        }
      }
    }
  }
}
