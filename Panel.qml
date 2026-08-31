import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Cpu: the panel, and the owner of all state.
//
// Loaded by BarWidget.qml (the manifest entry point), which injects bar,
// anchorItem and hostWidget and forwards open/close/toggle to us. IPC is
// left to the bar widget so the target is registered once.
Panel {
  id: root
  moduleName: "dansmith888.cpu"
  manageIpc: false

  // Injected by BarWidget.qml. The bar tracks the widget mounted in its slot,
  // not this nested panel, so everything the bar identifies a panel by has to
  // be that widget.
  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // ---- State. null means "unsupported / no answer" and hides the control.
  property bool devicePresent: false
  property string label: ""            // TODO: replace with real fields
  property var value: null
  property bool busy: false
  property bool stale: false           // last poll failed; readings are old

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace("file://", "")

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function apply(args) {
    if (root.busy) return
    root.busy = true
    actionProc.command = [root.pluginDir + "bin/cpuctl"].concat(args)
    actionProc.running = true
  }

  Process {
    id: statusProc
    command: [root.pluginDir + "bin/cpustatus"]
    stdout: StdioCollector {
      onStreamFinished: {
        var out = String(this.text).trim()
        if (out === "") { root.devicePresent = false; return }
        try {
          var d = JSON.parse(out)
          root.devicePresent = d.present === true
          if (!root.devicePresent) return
          // Present but no data: another client holds it, or the probe timed
          // out. Keep last-good readings rather than blanking everything.
          if (d.value === null && root.label !== "") { root.stale = true; return }
          root.stale = false
          root.label = d.label || ""
          root.value = (typeof d.value === "number") ? d.value : null
          // TODO: copy further fields; keep null for unsupported ones.
        } catch (e) {
          root.devicePresent = false
        }
      }
    }
  }

  Process {
    id: actionProc
    onExited: { root.busy = false; root.refresh() }
  }

  // Poll quickly while nothing is present and slowly once something is.
  Timer {
    interval: root.devicePresent ? 60000 : 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // Poll faster while the popup is open so the readout tracks reality.
  Timer {
    interval: 5000
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!root.busy) root.refresh()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(300))
    // implicitHeight excludes anchors.margins, so add the padding back or
    // the last row clips.
    contentHeight: panel.fittedContentHeight(
      panelColumn.implicitHeight + Style.spacing.panelPadding * 2, Style.space(900))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: panelColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.spacing.panelPadding
        spacing: Style.spacing.sm
        enabled: !root.stale
        opacity: root.stale ? 0.55 : 1.0

        PanelSectionHeader { text: "Cpu" }

        Text {
          text: root.label !== "" ? root.label : "Nothing to show yet"
          color: root.barForeground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        // TODO: controls. Each write goes through root.apply(["verb", ...]).
      }
    }
  }
}
