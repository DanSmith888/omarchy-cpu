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
  readonly property bool showIcon: Model.asBool(setting("showIcon", true), true)
  readonly property string tempSensor: String(setting("tempSensor", "auto"))
  readonly property int busyFrom: Model.clampInt(setting("busyFrom", 50), 1, 100, 50)
  readonly property int hotFrom: Model.clampInt(setting("hotFrom", 85), 1, 100, 85)
  readonly property string busyColor: String(setting("busyColor", ""))
  readonly property string hotColor: String(setting("hotColor", ""))
  readonly property int topCount: Model.clampInt(setting("topCount", 5), 1, 10, 5)
  readonly property string temperatureUnit: Model.normalizeUnit(setting("temperatureUnit", "C"))
  readonly property int historySamples: Model.clampInt(setting("historySamples", 60), 20, 240, 60)

  // ---- Derived.
  readonly property string shortModel: Model.shortModel(root.model)
  readonly property var headlineTemp: Model.pickTemp(root.temps, root.tempSensor)
  readonly property string usageText: Model.pct(root.usage)
  readonly property string tempText: Model.degrees(root.headlineTemp, root.temperatureUnit)
  readonly property string clockText: Model.ghz(root.freqMhz)
  readonly property string barText: Model.barText([
    root.showUsage ? Model.pct(root.usage) : "",
    root.showTemp && root.headlineTemp !== null ? Model.degreesShort(root.headlineTemp, root.temperatureUnit) : "",
    root.showClock && root.freqMhz !== null ? Model.ghzShort(root.freqMhz) : ""
  ])
  readonly property string tierColor: Model.loadColor(root.usage, root.busyFrom, root.hotFrom,
                                                      root.busyColor, root.hotColor)
  readonly property var refreshChips: [
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
  function setShowIcon(v) { persistSettings({ showIcon: !!v }) }
  function setTempSensor(v) { persistSettings({ tempSensor: String(v || "auto") }) }
  function setBusyFrom(v) { persistSettings({ busyFrom: Model.clampInt(v, 1, 100, 50) }) }
  function setHotFrom(v) { persistSettings({ hotFrom: Model.clampInt(v, 1, 100, 85) }) }
  function setBusyColor(hex) { persistSettings({ busyColor: String(hex) }) }
  function setHotColor(hex) { persistSettings({ hotColor: String(hex) }) }
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
  Component.onCompleted: refreshThemeColors()

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
    command: ["bash", "-lc", "cat ~/.local/state/omarchy/current/theme/colors.toml 2>/dev/null"]
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
    contentHeight: panel.fittedContentHeight(
      column.implicitHeight + Style.spacing.panelPadding * 2, Style.space(900))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: Style.spacing.panelPadding
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
                text: "󰘚"
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
            visible: root.memUsedPct !== null
            label: "Memory"
            value: root.memUsedPct === null ? 0 : root.memUsedPct
            valueText: Model.gib(root.memUsedGiB) + " / " + Model.gib(root.memTotalGiB)
            fill: Color.accent
          }

          Text {
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
                    var c = Model.loadColor(coreCell.load, root.busyFrom, root.hotFrom,
                                            root.busyColor, root.hotColor)
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
                width: parent.width - valueText.width - parent.spacing
                text: modelData.label
                color: Qt.darker(root.barForeground, 1.4)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {
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
                width: parent.width - procValue.width - parent.spacing
                text: modelData.name + "  (" + modelData.pid + ")"
                color: Qt.darker(root.barForeground, 1.3)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {
                id: procValue
                text: Model.pct1(modelData.cpu)
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
            description: "󰘚 in front of the readings."
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

          Text {
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

          PanelSeparator { width: parent.width; foreground: root.barForeground }

          // ---------- Load colours ----------
          PanelSectionHeader { text: "LOAD COLORS"; foreground: root.barForeground }

          Text {
            width: parent.width
            text: "The pill, the hero mark and the core bars change color once load passes each mark. ∅ keeps the normal bar color."
            color: Qt.darker(root.barForeground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Busy from"
              color: Qt.darker(root.barForeground, 1.4)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            NumberField {
              label: ""
              value: root.busyFrom
              from: 1
              to: 100
              stepSize: 5
              foreground: root.barForeground
              accent: Color.accent
              field.editable: false
              onModified: function(value) { root.setBusyFrom(value) }
            }

            Text {
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
            selected: root.busyColor
            foreground: root.barForeground
            onPicked: function(hex) { root.setBusyColor(hex) }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Hot from"
              color: Qt.darker(root.barForeground, 1.4)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            NumberField {
              label: ""
              value: root.hotFrom
              from: 1
              to: 100
              stepSize: 5
              foreground: root.barForeground
              accent: Color.accent
              field.editable: false
              onModified: function(value) { root.setHotFrom(value) }
            }

            Text {
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
            selected: root.hotColor
            foreground: root.barForeground
            onPicked: function(hex) { root.setHotColor(hex) }
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

      Text {
        width: meter.width - meterValue.width
        text: meter.label
        color: Qt.darker(root.barForeground, 1.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }

      Text {
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
