import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Ambed Fly Control Center Popup Panel
Panel {
  id: root
  moduleName: "dorneles.omafly"
  ipcTarget: "dorneles.omafly"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/omafly"
  readonly property string stateFilePath: stateDir + "/config.json"

  // Live state
  property bool flyEnabled: true
  property string speedScale: "normal"
  property string flyScale: "normal"
  property bool reactToCursor: true
  property bool reactToWindows: true
  property bool startleOnClick: true
  property bool randomStops: true

  property bool shooFeedback: false

  function open() {
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    root.opened ? root.close() : root.open()
  }

  function closeForPopoutSwitch() {
    root.close()
  }

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
            if (cfg.reactToCursor !== undefined) root.reactToCursor = Boolean(cfg.reactToCursor)
            if (cfg.reactToWindows !== undefined) root.reactToWindows = Boolean(cfg.reactToWindows)
            if (cfg.startleOnClick !== undefined) root.startleOnClick = Boolean(cfg.startleOnClick)
            if (cfg.randomStops !== undefined) root.randomStops = Boolean(cfg.randomStops)
          }
        }
      } catch (e) {}
    }
  }

  function saveConfig() {
    try {
      var cfg = {
        enabled: root.flyEnabled,
        speedScale: root.speedScale,
        flyScale: root.flyScale,
        reactToCursor: root.reactToCursor,
        reactToWindows: root.reactToWindows,
        startleOnClick: root.startleOnClick,
        randomStops: root.randomStops
      }
      configFile.setText(JSON.stringify(cfg, null, 2) + "\n")
    } catch (e) {}
  }

  function callFly(cmd, arg) {
    var argv = ["omarchy-shell", "dorneles.omafly", cmd]
    if (arg !== undefined && arg !== null && String(arg).length > 0) {
      argv.push(String(arg))
    }
    Quickshell.execDetached(argv)
  }

  function toggleFly() {
    var willEnable = !root.flyEnabled
    root.flyEnabled = willEnable
    if (willEnable) {
      callFly("on")
    } else {
      callFly("off")
    }
  }

  function triggerShoo() {
    root.shooFeedback = true
    shooTimer.restart()
    callFly("shoo")
  }

  Timer {
    id: shooTimer
    interval: 800
    repeat: false
    onTriggered: root.shooFeedback = false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem || (hostWidget ? hostWidget : null)
    owner: root.barIdentity
    bar: root.bar || (hostWidget ? hostWidget.bar : null)
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight)

    Column {
      id: mainColumn
      width: parent.width
      spacing: Style.space(10)

      // -------------------------------------------------------------
      // Header
      // -------------------------------------------------------------
      Item {
        width: parent.width
        height: Style.space(26)

        RowLayout {
          anchors.fill: parent
          spacing: Style.space(8)

          Image {
            source: Qt.resolvedUrl("assets/icon.svg")
            Layout.preferredWidth: Style.space(22)
            Layout.preferredHeight: Style.space(22)
            fillMode: Image.PreserveAspectFit
            smooth: true
          }

          Text {
            text: "OMAFLY"
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            Layout.alignment: Qt.AlignVCenter
          }

          Item { Layout.fillWidth: true }

          // Status indicator pill
          Rectangle {
            Layout.preferredHeight: Style.space(22)
            Layout.preferredWidth: statusText.implicitWidth + Style.space(16)
            radius: 11
            color: root.flyEnabled ? Util.alpha(Color.accent, 0.15) : Util.alpha(root.foreground, 0.1)
            border.color: root.flyEnabled ? Color.accent : Util.alpha(root.foreground, 0.25)
            border.width: 1

            Text {
              id: statusText
              anchors.centerIn: parent
              text: root.flyEnabled ? "ROAMING" : "PAUSED"
              color: root.flyEnabled ? Color.accent : Util.alpha(root.foreground, 0.6)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          // Close button
          Rectangle {
            Layout.preferredWidth: Style.space(22)
            Layout.preferredHeight: Style.space(22)
            radius: 4
            color: closeMouse.pressed
              ? Util.alpha(root.foreground, 0.18)
              : (closeMouse.containsMouse ? Util.alpha(root.foreground, 0.08) : "transparent")

            Text {
              anchors.centerIn: parent
              text: "✕"
              color: Color.popups.text
              font.pixelSize: 11
            }

            MouseArea {
              id: closeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.close()
            }
          }
        }
      }

      // -------------------------------------------------------------
      // Main Action Card: On/Off & Shoo
      // -------------------------------------------------------------
      Rectangle {
        width: parent.width
        height: actionRow.implicitHeight + Style.space(16)
        radius: Style.cornerRadius > 0 ? Style.cornerRadius : 6
        color: Util.alpha(root.foreground, 0.04)
        border.color: Util.alpha(root.foreground, 0.08)
        border.width: 1

        RowLayout {
          id: actionRow
          anchors.fill: parent
          anchors.margins: Style.space(8)
          spacing: Style.space(8)

          Button {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(34)
            text: root.flyEnabled ? "Pause Fly" : "Activate Fly"
            active: root.flyEnabled
            bordered: true
            onClicked: root.toggleFly()
          }

          Button {
            Layout.preferredWidth: Style.space(95)
            Layout.preferredHeight: Style.space(34)
            text: root.shooFeedback ? "BZZZ! 💨" : "Shoo! 💨"
            accent: "#f59e0b"
            bordered: true
            active: root.shooFeedback
            enabled: root.flyEnabled
            opacity: root.flyEnabled ? 1.0 : 0.5
            onClicked: root.triggerShoo()
          }
        }
      }

      // -------------------------------------------------------------
      // Speed Selection Card
      // -------------------------------------------------------------
      Rectangle {
        width: parent.width
        height: speedCol.implicitHeight + Style.space(16)
        radius: Style.cornerRadius > 0 ? Style.cornerRadius : 6
        color: Util.alpha(root.foreground, 0.04)
        border.color: Util.alpha(root.foreground, 0.08)
        border.width: 1

        ColumnLayout {
          id: speedCol
          anchors.fill: parent
          anchors.margins: Style.space(8)
          spacing: Style.space(6)

          Text {
            text: "FLIGHT SPEED"
            color: Util.alpha(root.foreground, 0.7)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(4)

            Repeater {
              model: [
                { id: "lazy", label: "Lazy" },
                { id: "normal", label: "Normal" },
                { id: "fast", label: "Fast" },
                { id: "hyper", label: "Hyper" }
              ]

              delegate: Button {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(28)
                text: modelData.label
                selected: root.speedScale === modelData.id
                bordered: true
                onClicked: {
                  root.speedScale = modelData.id
                  root.saveConfig()
                  root.callFly("setSpeed", modelData.id)
                }
              }
            }
          }
        }
      }

      // -------------------------------------------------------------
      // Size Selection Card
      // -------------------------------------------------------------
      Rectangle {
        width: parent.width
        height: sizeCol.implicitHeight + Style.space(16)
        radius: Style.cornerRadius > 0 ? Style.cornerRadius : 6
        color: Util.alpha(root.foreground, 0.04)
        border.color: Util.alpha(root.foreground, 0.08)
        border.width: 1

        ColumnLayout {
          id: sizeCol
          anchors.fill: parent
          anchors.margins: Style.space(8)
          spacing: Style.space(6)

          Text {
            text: "FLY SIZE"
            color: Util.alpha(root.foreground, 0.7)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(4)

            Repeater {
              model: [
                { id: "small", label: "Small" },
                { id: "normal", label: "Normal" },
                { id: "large", label: "Large" },
                { id: "giant", label: "Giant" }
              ]

              delegate: Button {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(28)
                text: modelData.label
                selected: root.flyScale === modelData.id
                bordered: true
                onClicked: {
                  root.flyScale = modelData.id
                  root.saveConfig()
                  root.callFly("setScale", modelData.id)
                }
              }
            }
          }
        }
      }

      // -------------------------------------------------------------
      // Behavior Toggles Card
      // -------------------------------------------------------------
      Rectangle {
        width: parent.width
        height: behaviorCol.implicitHeight + Style.space(16)
        radius: Style.cornerRadius > 0 ? Style.cornerRadius : 6
        color: Util.alpha(root.foreground, 0.04)
        border.color: Util.alpha(root.foreground, 0.08)
        border.width: 1

        Column {
          id: behaviorCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(8)
          spacing: Style.space(6)

          Text {
            text: "BEHAVIORS"
            color: Util.alpha(root.foreground, 0.7)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            bottomPadding: Style.space(2)
          }

          Toggle {
            width: behaviorCol.width
            label: "React to Pointer"
            description: "Attracted to mouse movements"
            checked: root.reactToCursor
            onClicked: {
              root.reactToCursor = !root.reactToCursor
              root.saveConfig()
            }
          }

          Toggle {
            width: behaviorCol.width
            label: "Perch on Windows"
            description: "Flies to moving window tops"
            checked: root.reactToWindows
            onClicked: {
              root.reactToWindows = !root.reactToWindows
              root.saveConfig()
            }
          }

          Toggle {
            width: behaviorCol.width
            label: "Startle on Click"
            description: "Spooks away if clicked nearby"
            checked: root.startleOnClick
            onClicked: {
              root.startleOnClick = !root.startleOnClick
              root.saveConfig()
            }
          }

          Toggle {
            width: behaviorCol.width
            label: "Random Pauses"
            description: "Naturally rests and stops moving"
            checked: root.randomStops
            onClicked: {
              root.randomStops = !root.randomStops
              root.saveConfig()
              root.callFly("setRandomStops", root.randomStops ? "1" : "0")
            }
          }
        }
      }
    }
  }
}
