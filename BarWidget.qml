import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Ambed Fly Bar Widget: Shows a cute animated fly icon in the bar, reflects live status,
// and opens the Ambed Fly control panel.
BarWidget {
  id: root
  moduleName: "dorneles.omafly"

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/omafly"
  readonly property string stateFilePath: stateDir + "/config.json"

  // Mirrored state
  property bool flyEnabled: true
  property string speedScale: "normal"
  property string flyScale: "normal"
  property string currentMode: "wander"
  property int frameIndex: 0

  readonly property var frameSources: [
    Qt.resolvedUrl("assets/fly_frame1.png"),
    Qt.resolvedUrl("assets/fly_frame2.png"),
    Qt.resolvedUrl("assets/fly_frame3.png")
  ]

  // Panel lifecycle forwarding (Omarchy popout coordinator contract)
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property real openPanelIndicatorWidth: content.implicitWidth
  readonly property real openPanelIndicatorHeight: content.implicitHeight

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function open() {
    root.injectPanel()
    if (panelLoader.item) panelLoader.item.open()
  }
  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }
  function toggle() {
    root.injectPanel()
    if (panelLoader.item) panelLoader.item.toggle()
  }
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  IpcHandler {
    target: "dorneles.omafly-panel"

    function toggle(): void { root.toggle() }
    function open(): void { root.open() }
    function close(): void { root.close() }
  }

  onBarChanged: Qt.callLater(injectPanel)
  onSettingsChanged: Qt.callLater(injectPanel)
  Component.onCompleted: Qt.callLater(injectPanel)

  // Watch state file for changes
  FileView {
    id: configFile
    path: root.stateFilePath
    watchChanges: true
    printErrors: false

    onFileChanged: reload()
    onLoaded: {
      try {
        var raw = text()
        if (raw && raw.trim().length > 0) {
          var cfg = JSON.parse(raw)
          if (cfg) {
            if (cfg.enabled !== undefined) root.flyEnabled = Boolean(cfg.enabled)
            if (cfg.speedScale !== undefined) root.speedScale = String(cfg.speedScale)
            if (cfg.flyScale !== undefined) root.flyScale = String(cfg.flyScale)
          }
        }
      } catch (e) {}
    }
  }

  function toggleFly() {
    var willEnable = !root.flyEnabled
    root.flyEnabled = willEnable
    if (willEnable) {
      Quickshell.execDetached(["omarchy-shell", "dorneles.omafly", "on"])
    } else {
      Quickshell.execDetached(["omarchy-shell", "dorneles.omafly", "off"])
    }
  }

  function shooFly() {
    Quickshell.execDetached(["omarchy-shell", "dorneles.omafly", "shoo"])
  }

  // Wing flapping animation in the bar icon when fly is active
  Timer {
    id: wingTimer
    interval: 80
    running: root.flyEnabled
    repeat: true
    onTriggered: {
      root.frameIndex = (root.frameIndex + 1) % root.frameSources.length
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: " "
    labelVisible: false
    hasVisualContent: true
    active: root.opened

    tooltipText: root.flyEnabled
      ? "Omafly \u2014 Roaming\n\u2022 Click: Open Control Panel\n\u2022 Right-click: Turn Off\n\u2022 Speed: " + root.speedScale.toUpperCase()
      : "Omafly \u2014 Paused\n\u2022 Click: Open Control Panel\n\u2022 Right-click: Turn On"

    fixedWidth: root.vertical ? -1 : Math.round(content.implicitWidth + scaledHorizontalMargin * 2)
    fixedHeight: root.vertical ? Math.round(content.implicitHeight + scaledVerticalPadding * 2) : -1

    onPressed: function(btnCode) {
      if (btnCode === Qt.RightButton) {
        root.toggleFly()
      } else {
        root.toggle()
      }
    }

    Item {
      id: content
      anchors.centerIn: parent
      implicitWidth: Style.space(22)
      implicitHeight: Style.space(22)

      Image {
        id: flyIcon
        anchors.centerIn: parent
        width: Style.space(20)
        height: Style.space(20)
        source: root.flyEnabled ? root.frameSources[root.frameIndex] : root.frameSources[0]
        opacity: root.flyEnabled ? 1.0 : 0.4
        smooth: true
        mipmap: true
        fillMode: Image.PreserveAspectFit

        Behavior on opacity {
          NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
        }
      }
    }
  }

  // Panel Loader
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
}
