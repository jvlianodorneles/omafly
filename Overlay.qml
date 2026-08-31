import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs.Commons

// Ambed Fly Overlay: Spawns a lightweight animated fly that roams across your desktop,
// interacts with the mouse pointer, and perches on moving windows.
Item {
  id: root

  // -------------------------------------------------------------
  // Settings & Configuration
  // -------------------------------------------------------------
  property bool flyEnabled: true
  property string speedScale: "normal" // "lazy" | "normal" | "fast" | "hyper"
  property string flyScale: "normal"   // "small" | "normal" | "large" | "giant"
  property bool reactToCursor: true
  property bool reactToWindows: true
  property bool startleOnClick: true
  property bool randomStops: true
  property bool isWingTwitching: false

  // State persistence path
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/omafly"
  readonly property string stateFilePath: stateDir + "/config.json"
  readonly property string dirFs: Qt.resolvedUrl(".").toString().replace("file://", "")

  // Multipliers
  readonly property real speedMultiplier: {
    switch (root.speedScale) {
      case "lazy": return 0.65;
      case "fast": return 1.6;
      case "hyper": return 2.6;
      case "normal":
      default: return 1.0;
    }
  }

  readonly property real sizeScaleFactor: {
    switch (root.flyScale) {
      case "small": return 0.75;
      case "large": return 1.45;
      case "giant": return 2.2;
      case "normal":
      default: return 1.0;
    }
  }

  // Base bounding size and fly graphic size (from GNOME extension: SIZE=45, FLY_SIZE=35)
  readonly property real flyContainerSize: Math.round(45 * root.sizeScaleFactor)
  readonly property real flyGraphicSize: Math.round(35 * root.sizeScaleFactor)

  // Frames from assets
  readonly property var frameSources: [
    Qt.resolvedUrl("assets/fly_frame1.png"),
    Qt.resolvedUrl("assets/fly_frame2.png"),
    Qt.resolvedUrl("assets/fly_frame3.png")
  ]
  property int currentFrame: 0

  // -------------------------------------------------------------
  // Fly Physics State (port of extension.js)
  // -------------------------------------------------------------
  property real posX: 300
  property real posY: 250
  property real angle: Math.random() * 360
  property real speed: 1.5
  property real targetSpeed: 2.0
  property real angularVelocity: 0
  property real wanderForce: 0

  property string mode: "wander" // "wander" | "idle" | "cursor" | "window" | "shoo"
  property double modeUntil: 0
  property double nextStopAllowed: 0

  property real pointerX: 0
  property real pointerY: 0
  property real lastPointerX: 0
  property real lastPointerY: 0
  property real pointerVelocityX: 0
  property real pointerVelocityY: 0

  property real windowTargetX: 0
  property real windowTargetY: 0

  property real wanderTargetX: 0
  property real wanderTargetY: 0
  property double nextWanderChange: 0

  property int totalShoos: 0
  property int flightSeconds: 0

  // -------------------------------------------------------------
  // Config Persistence
  // -------------------------------------------------------------
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

  // -------------------------------------------------------------
  // Helpers & Physics
  // -------------------------------------------------------------
  function angleDiff(target, current) {
    var diff = (target - current) % 360
    if (diff > 180) diff -= 360
    if (diff < -180) diff += 360
    return diff
  }

  function updatePointer(x, y) {
    root.pointerVelocityX = (x - root.lastPointerX) * 0.35 + root.pointerVelocityX * 0.65
    root.pointerVelocityY = (y - root.lastPointerY) * 0.35 + root.pointerVelocityY * 0.65
    root.pointerX = x
    root.pointerY = y
    root.lastPointerX = x
    root.lastPointerY = y

    // If fly is idle / landed and pointer moves very close, startle it back into flight
    if (root.mode === "idle" && root.flyEnabled) {
      var dx = x - (root.posX + root.flyContainerSize / 2)
      var dy = y - (root.posY + root.flyContainerSize / 2)
      if (Math.hypot(dx, dy) < 85) {
        root.shoo()
      }
    }
  }

  function onWindowMoved(rect) {
    if (!root.reactToWindows || !root.flyEnabled) return
    var now = Date.now()
    root.mode = "window"
    root.modeUntil = now + 650
    root.windowTargetX = rect.x + rect.width * (0.2 + Math.random() * 0.6)
    root.windowTargetY = rect.y - 15
  }

  function onScreenClick(btn, clickX, clickY) {
    if (!root.startleOnClick || !root.flyEnabled) return
    var dx = clickX - (root.posX + root.flyContainerSize / 2)
    var dy = clickY - (root.posY + root.flyContainerSize / 2)
    var dist = Math.hypot(dx, dy)
    // If click happened within 220px of the fly, startle it!
    if (dist < 220) {
      shoo()
    }
  }

  function shoo() {
    var now = Date.now()
    root.mode = "shoo"
    root.modeUntil = now + 850
    root.nextStopAllowed = now + 2500 + Math.random() * 2000
    root.totalShoos++
    // Turn away from pointer or current heading with random perturbation
    var awayAngle = Math.atan2(root.posY - root.pointerY, root.posX - root.pointerX) * 180 / Math.PI
    root.angle = awayAngle + (Math.random() - 0.5) * 60
    root.angularVelocity = (Math.random() - 0.5) * 8.0
    root.wanderForce = (Math.random() - 0.5) * 2.5
  }

  function updateBehavior() {
    var now = Date.now()
    if (now > root.modeUntil) {
      if (root.mode !== "wander") {
        root.mode = "wander"
        root.modeUntil = now + 2000 + Math.random() * 3500
        root.nextStopAllowed = now + 1500 + Math.random() * 2500
      } else {
        // In wander mode: check if it's time to pause/land or track cursor
        if (root.randomStops && now > root.nextStopAllowed && Math.random() < 0.007) {
          root.mode = "idle"
          // Stop duration: quick pauses (1.2s - 2.5s) or longer rests (3.0s - 6.0s)
          var stopDuration = Math.random() < 0.65
            ? (1200 + Math.random() * 1600)
            : (2800 + Math.random() * 3200)
          root.modeUntil = now + stopDuration
          root.speed = 0
          root.angularVelocity = 0
        } else if (root.reactToCursor && Math.random() < 0.0035) {
          root.mode = "cursor"
          root.modeUntil = now + 1800 + Math.random() * 2600
        }
      }
    }
  }

  function isInsideAnyScreen(x, y) {
    var screens = Quickshell.screens
    if (!screens || screens.length === 0) return true
    for (var i = 0; i < screens.length; i++) {
      var s = screens[i]
      if (x >= s.x && x < s.x + s.width && y >= s.y && y < s.y + s.height) {
        return true
      }
    }
    return false
  }

  function pickNewWanderTarget() {
    var screens = Quickshell.screens
    if (!screens || screens.length === 0) return
    var sc = screens[0]
    for (var i = 0; i < screens.length; i++) {
      var s = screens[i]
      if (root.posX >= s.x && root.posX <= s.x + s.width) { sc = s; break }
    }

    // Dynamic balancing to ensure full screen coverage without right/left bias:
    // If the fly is on the right half, bias next waypoint to the left half (70% probability)
    // If the fly is on the left half, bias next waypoint to the right half (70% probability)
    var currentXRatio = (root.posX - sc.x) / Math.max(1, sc.width)
    var targetXRatio = 0.5
    if (currentXRatio > 0.52) {
      targetXRatio = Math.random() < 0.70
        ? (0.10 + Math.random() * 0.40)
        : (0.50 + Math.random() * 0.40)
    } else if (currentXRatio < 0.48) {
      targetXRatio = Math.random() < 0.70
        ? (0.50 + Math.random() * 0.40)
        : (0.10 + Math.random() * 0.40)
    } else {
      targetXRatio = 0.10 + Math.random() * 0.80
    }

    var targetYRatio = 0.10 + Math.random() * 0.80

    root.wanderTargetX = sc.x + targetXRatio * sc.width
    root.wanderTargetY = sc.y + targetYRatio * sc.height
    root.nextWanderChange = Date.now() + 1400 + Math.random() * 2600
  }

  function checkBounds() {
    var screens = Quickshell.screens
    if (!screens || screens.length === 0) return

    var s = screens[0]
    var half = root.flyContainerSize / 2
    var nextCenterX = root.posX + half
    var nextCenterY = root.posY + half

    // Find bounding edges for single screen or nearest screen
    var minX = s.x
    var minY = s.y
    var maxX = s.x + s.width - root.flyContainerSize
    var maxY = s.y + s.height - root.flyContainerSize

    // If multi-monitor, find active screen
    for (var i = 0; i < screens.length; i++) {
      var sc = screens[i]
      if (nextCenterX >= sc.x && nextCenterX < sc.x + sc.width &&
          nextCenterY >= sc.y && nextCenterY < sc.y + sc.height) {
        minX = sc.x
        minY = sc.y
        maxX = sc.x + sc.width - root.flyContainerSize
        maxY = sc.y + sc.height - root.flyContainerSize
        break
      }
    }

    var bounced = false
    if (root.posX < minX) {
      root.posX = minX
      root.angle = (180 - root.angle) + (Math.random() - 0.5) * 60
      root.angularVelocity = (Math.random() - 0.5) * 6.0
      bounced = true
    } else if (root.posX > maxX) {
      root.posX = maxX
      root.angle = (180 - root.angle) + (Math.random() - 0.5) * 60
      root.angularVelocity = (Math.random() - 0.5) * 6.0
      bounced = true
    }

    if (root.posY < minY) {
      root.posY = minY
      root.angle = (-root.angle) + (Math.random() - 0.5) * 60
      root.angularVelocity = (Math.random() - 0.5) * 6.0
      bounced = true
    } else if (root.posY > maxY) {
      root.posY = maxY
      root.angle = (-root.angle) + (Math.random() - 0.5) * 60
      root.angularVelocity = (Math.random() - 0.5) * 6.0
      bounced = true
    }

    root.angle = ((root.angle % 360) + 360) % 360
    if (bounced) {
      pickNewWanderTarget()
    }
  }

  function moveFly() {
    var now = Date.now()
    var steer = 0
    var speedBoost = 0

    if (root.mode === "idle") {
      // Stationary when landed/resting: gently damp any residual angular velocity
      root.angularVelocity *= 0.75
      root.speed = 0
      return
    }

    if (root.mode === "shoo") {
      steer = (Math.random() - 0.5) * 2.8
      speedBoost = 4.0
    } else if (root.mode === "cursor") {
      var targetX = root.pointerX + root.pointerVelocityX * 6
      var targetY = root.pointerY + root.pointerVelocityY * 6
      var dx = targetX - root.posX
      var dy = targetY - root.posY
      var distance = Math.hypot(dx, dy)
      var targetAngle = Math.atan2(dy, dx) * 180 / Math.PI

      if (distance < 110) {
        targetAngle += Math.sin(root.angle * Math.PI / 180) * 55
      }

      steer = root.angleDiff(targetAngle, root.angle) * 0.06
      speedBoost = Math.min(1.5, distance / 120)

      // Break off cursor pursuit after a moment so it doesn't get glued to cursor area
      if (distance < 75 && Math.random() < 0.04) {
        root.mode = "wander"
        root.modeUntil = now + 2000 + Math.random() * 3500
        pickNewWanderTarget()
      }
    } else if (root.mode === "window") {
      var targetAngle = Math.atan2(root.windowTargetY - root.posY, root.windowTargetX - root.posX) * 180 / Math.PI
      steer = root.angleDiff(targetAngle, root.angle) * 0.065
      speedBoost = 1.2
    } else {
      // --- WANDER MODE ---
      var distToTarget = Math.hypot(root.wanderTargetX - root.posX, root.wanderTargetY - root.posY)
      if (now > root.nextWanderChange || distToTarget < 90 || root.wanderTargetX === 0) {
        pickNewWanderTarget()
      }

      var wpAngle = Math.atan2(root.wanderTargetY - root.posY, root.wanderTargetX - root.posX) * 180 / Math.PI
      var wpDiff = root.angleDiff(wpAngle, root.angle)
      var waypointSteer = wpDiff * 0.032

      root.wanderForce += (Math.random() - 0.5) * 0.85
      root.wanderForce *= 0.94
      root.wanderForce = Math.max(-2.5, Math.min(2.5, root.wanderForce))

      steer = waypointSteer + root.wanderForce

      // Saccadic burst: sudden unpredictable sharp darting turn
      if (Math.random() < 0.032) {
        root.angularVelocity += (Math.random() - 0.5) * 10.0
        root.wanderForce = (Math.random() - 0.5) * 3.0
      }
    }

    // Angular damping & update
    root.angularVelocity += steer + (Math.random() - 0.5) * 0.75
    root.angularVelocity *= 0.89
    root.angularVelocity = Math.max(-7.5, Math.min(7.5, root.angularVelocity))

    root.angle += root.angularVelocity
    root.angle = ((root.angle % 360) + 360) % 360

    // Random speed shifts (flitting, hovering, and quick darting)
    if (Math.random() < 0.04) {
      root.targetSpeed = 0.8 + Math.random() * 3.8
    }
    root.speed += (root.targetSpeed - root.speed) * 0.055

    var turnFactor = 1 - Math.min(0.35, Math.abs(root.angularVelocity) / 22)
    var currentSpeed = (root.speed + speedBoost) * turnFactor * root.speedMultiplier

    root.posX += Math.cos(root.angle * Math.PI / 180) * currentSpeed
    root.posY += Math.sin(root.angle * Math.PI / 180) * currentSpeed

    checkBounds()
  }

  // -------------------------------------------------------------
  // Timers: Wing-flap (33ms) & Movement (16ms)
  // -------------------------------------------------------------
  Timer {
    id: frameTimer
    interval: 33
    running: root.flyEnabled
    repeat: true
    onTriggered: {
      if (root.mode === "idle") {
        if (root.isWingTwitching) {
          root.currentFrame = 1
        } else {
          root.currentFrame = 0
        }
      } else {
        root.currentFrame = (root.currentFrame + 1) % root.frameSources.length
      }
    }
  }

  // Occasional grooming twitch while stopped (quick wing flick / grooming pose)
  Timer {
    id: groomTimer
    interval: 400
    running: root.flyEnabled && root.mode === "idle"
    repeat: true
    onTriggered: {
      if (Math.random() < 0.18) {
        root.isWingTwitching = true
        twitchEndTimer.restart()
      }
    }
  }

  Timer {
    id: twitchEndTimer
    interval: 85
    repeat: false
    onTriggered: {
      root.isWingTwitching = false
    }
  }

  Timer {
    id: moveTimer
    interval: 16
    running: root.flyEnabled
    repeat: true
    onTriggered: {
      root.updateBehavior()
      root.moveFly()
    }
  }

  Timer {
    id: statTimer
    interval: 1000
    running: root.flyEnabled
    repeat: true
    onTriggered: root.flightSeconds++
  }

  // -------------------------------------------------------------
  // Background Tracker Process
  // -------------------------------------------------------------
  Process {
    id: trackerProc
    command: ["python3", root.dirFs + "tracker.py"]
    running: root.flyEnabled

    stdout: SplitParser {
      onRead: function(line) {
        var raw = String(line || "").trim()
        if (!raw.startsWith("{")) return
        try {
          var data = JSON.parse(raw)
          if (data.cursor) {
            root.updatePointer(data.cursor.x, data.cursor.y)
          }
          if (data.window_moved && data.rect) {
            root.onWindowMoved(data.rect)
          }
          if (data.click) {
            root.onScreenClick(data.btn, data.x, data.y)
          }
        } catch (e) {}
      }
    }

    onExited: function(exitCode, exitStatus) {
      if (root.flyEnabled) trackerRestartTimer.restart()
    }
  }

  Timer {
    id: trackerRestartTimer
    interval: 1500
    repeat: false
    onTriggered: {
      if (root.flyEnabled && !trackerProc.running) trackerProc.running = true
    }
  }

  // -------------------------------------------------------------
  // Public IPC Handler
  // -------------------------------------------------------------
  IpcHandler {
    target: "dorneles.omafly"

    function toggle(): string {
      root.flyEnabled = !root.flyEnabled
      root.saveConfig()
      return root.flyEnabled ? "on" : "off"
    }

    function on(): string {
      root.flyEnabled = true
      root.saveConfig()
      return "ok"
    }

    function off(): string {
      root.flyEnabled = false
      root.saveConfig()
      return "ok"
    }

    function shoo(): string {
      root.shoo()
      return "bzzz"
    }

    function setSpeed(val: string): string {
      if (["lazy", "normal", "fast", "hyper"].indexOf(val) !== -1) {
        root.speedScale = val
        root.saveConfig()
        return "ok"
      }
      return "invalid speed (choose lazy, normal, fast, hyper)"
    }

    function setScale(val: string): string {
      if (["small", "normal", "large", "giant"].indexOf(val) !== -1) {
        root.flyScale = val
        root.saveConfig()
        return "ok"
      }
      return "invalid scale (choose small, normal, large, giant)"
    }

    function setRandomStops(val: string): string {
      root.randomStops = (val === "true" || val === "1" || val === "on")
      root.saveConfig()
      return "ok"
    }

    function status(): string {
      return JSON.stringify({
        enabled: root.flyEnabled,
        mode: root.mode,
        speedScale: root.speedScale,
        flyScale: root.flyScale,
        speedMultiplier: root.speedMultiplier,
        randomStops: root.randomStops,
        pos: [Math.round(root.posX), Math.round(root.posY)],
        angle: Math.round(root.angle),
        flightSeconds: root.flightSeconds,
        totalShoos: root.totalShoos
      })
    }
  }

  // -------------------------------------------------------------
  // Desktop Layer-Shell Overlay Windows (Per Screen)
  // -------------------------------------------------------------
  Variants {
    model: Quickshell.screens

    Scope {
      id: screenScope
      required property var modelData

      readonly property real localX: root.posX - modelData.x
      readonly property real localY: root.posY - modelData.y

      readonly property bool onThisScreen: root.flyEnabled &&
        (root.posX + root.flyContainerSize >= modelData.x) &&
        (root.posX <= modelData.x + modelData.width) &&
        (root.posY + root.flyContainerSize >= modelData.y) &&
        (root.posY <= modelData.y + modelData.height)

      PanelWindow {
        id: win
        screen: screenScope.modelData
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }

        WlrLayershell.namespace: "omafly"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // 100% click-through mask so desktop and windows remain fully interactive
        mask: Region {}

        Item {
          anchors.fill: parent

          Item {
            id: flyContainer
            visible: screenScope.onThisScreen
            x: screenScope.localX
            y: screenScope.localY
            width: root.flyContainerSize
            height: root.flyContainerSize
            transformOrigin: Item.Center
            rotation: root.angle + 90

            Image {
              id: flyImage
              anchors.centerIn: parent
              width: root.flyGraphicSize
              height: root.flyGraphicSize
              source: root.frameSources[root.currentFrame]
              smooth: true
              mipmap: true
              fillMode: Image.PreserveAspectFit
            }
          }
        }
      }
    }
  }

  Component.onCompleted: {
    var screens = Quickshell.screens
    if (screens && screens.length > 0) {
      var sc = screens[0]
      root.posX = sc.x + sc.width * 0.25 + Math.random() * (sc.width * 0.5)
      root.posY = sc.y + sc.height * 0.25 + Math.random() * (sc.height * 0.5)
    }
    root.pickNewWanderTarget()
  }
}
