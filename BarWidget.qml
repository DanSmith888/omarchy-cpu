import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// CPU: the pill in the bar, and the host for the panel.
//
// This is the manifest entry point. It owns nothing but the pill and the IPC
// target; all state lives in Panel.qml, loaded here and read through
// panelLoader.item. The shell routes on this shape — Bar.findPanelWidget
// looks for open/close/opened on the widget mounted in the bar slot — so the
// pill must be the thing the bar sees.
BarWidget {
  id: root
  moduleName: "dansmith888.cpu"

  readonly property var panel: panelLoader.item

  // Mirrors of the panel's state, so the pill has nothing to compute.
  readonly property bool devicePresent: panel ? panel.devicePresent === true : false
  readonly property bool showIcon: panel ? panel.showIcon === true : true
  readonly property string readings: panel ? panel.barText : ""
  readonly property string tierColor: panel ? panel.tierColor : ""
  readonly property string pillText: {
    if (!root.devicePresent) return ""
    if (!root.showIcon) return root.readings
    return root.readings === "" ? "󰘚" : "󰘚 " + root.readings
  }
  readonly property string tooltip: {
    if (!panel) return "CPU"
    var bits = [panel.shortModel, "Load " + panel.usageText]
    if (panel.headlineTemp !== null) bits.push(panel.tempText)
    if (panel.freqMhz !== null) bits.push(panel.clockText)
    return bits.join("  ·  ")
  }

  // ---- Panel lifecycle contract (shell.summon/hide/toggle routing).
  readonly property bool opened: panel ? panel.opened === true : false
  readonly property bool popoutSwitchClosing: panel ? panel.popoutSwitchClosing === true : false

  function open() { if (panel) panel.open() }
  function close() { if (panel) panel.close() }
  function togglePanel() { if (panel) panel.toggle() }
  function closeForPopoutSwitch() { if (panel) panel.closeForPopoutSwitch() }
  function refresh() { if (panel) panel.refresh() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  // Hidden, not removed, when there is nothing to show: the slot stays in
  // shell.json and the pill reappears on its own.
  visible: root.devicePresent
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // Single IPC target for the plugin; Panel.qml sets manageIpc: false.
  //   omarchy-shell shell toggle dansmith888.cpu
  IpcHandler {
    target: "dansmith888.cpu"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): void { root.broadcast("refresh") }
  }

  // WidgetButton, not BarIconButton: the latter is glyph-only and clips text.
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.pillText
    hasVisualContent: text !== ""
    tooltipText: root.tooltip
    // The load bands recolour the whole pill; "" leaves the bar's own colour.
    foreground: root.tierColor !== ""
      ? root.tierColor
      : (root.bar ? root.bar.barForeground : Color.foreground)

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
  }
}
