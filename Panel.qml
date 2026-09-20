import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Omaglow bar widget. All state lives in bin/omaglow, which answers every
// command with the full state as JSON. This file only shows it.
Panel {
  id: root
  moduleName: "io.github.gabbe2312.omaglow"
  ipcTarget: "io.github.gabbe2312.omaglow"
  manageIpc: false

  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")
  readonly property var helper: [root.pluginDir + "bin/omaglow"]

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color hairline: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.25)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property var info: ({})
  property bool busy: false
  property var queue: []
  property string lastError: ""

  property string tab: "colour"
  property string page: ""
  property string expanded: ""
  onTabChanged: page = ""

  // Empty string means all devices, otherwise a device id.
  property string target: ""

  property string sharedColor: "#ffffff"
  property string pickerColor: "#ffffff"
  property string pickerKey: "accent"
  property bool shownFollow: false
  // Follow theme has two patterns, the general one and an optional profile
  // for the current theme. Both are kept here so the dots update right away.
  property var general: ({ themeKey: "accent", themeKeys: ({}) })
  property var profilePattern: null
  property bool profileOn: false
  readonly property bool hasProfile: profilePattern !== null
  readonly property string themeName: info.themeName || "this theme"
  readonly property var profiles: info.profiles instanceof Array ? info.profiles : []
  property string shownFixed: "#ffffff"
  property bool shownVivid: true
  property bool shownStartup: true
  property real shownBrightness: 100

  readonly property var devices: info.devices instanceof Array ? info.devices : []
  readonly property var themeSwatches: info.theme instanceof Array ? info.theme : []
  readonly property var savedColors: info.config && info.config.saved instanceof Array ? info.config.saved : []
  readonly property var ignoredDevices: info.config && info.config.ignored instanceof Array ? info.config.ignored : []
  readonly property bool needsSetup: info.config !== undefined && info.setup === false
  readonly property bool missingOpenRgb: info.config !== undefined && info.openrgb === false
  readonly property bool ready: info.config !== undefined && !needsSetup && !missingOpenRgb

  readonly property var presets: [
    "#ffffff", "#ffd9a8", "#ff2020", "#ff7a00", "#ffd000", "#30e030",
    "#00d0c0", "#2080ff", "#7040ff", "#e040ff"
  ]

  // Queue key. A newer command with the same key replaces the waiting one.
  // Commands with different keys all run, in order.
  function subject(args) {
    if (args[0] === "profile") return "profile:" + args[1] + ":" + (args[3] || "")
    if (args.length > 1) return args[0] + ":" + args[1]
    return args[0]
  }

  function run(args) {
    if (!helperProcess.running) { launch(args); return }
    var key = subject(args)
    var next = []
    for (var i = 0; i < root.queue.length; i++)
      if (subject(root.queue[i]) !== key) next.push(root.queue[i])
    if (key !== "status" || next.length === 0) next.push(args)
    root.queue = next
  }

  function launch(args) {
    root.lastError = ""
    root.busy = true
    helperProcess.command = root.helper.concat(args)
    helperProcess.running = true
  }

  // Reads root.info directly. Derived bindings are stale inside change handlers.
  function findDevice(id) {
    var list = root.info && root.info.devices instanceof Array ? root.info.devices : []
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
    return null
  }

  function themeColor(key) {
    if (String(key).charAt(0) === "#") return String(key)
    var list = root.info && root.info.theme instanceof Array ? root.info.theme : []
    for (var i = 0; i < list.length; i++) if (list[i].key === key) return list[i].color
    return "#ffffff"
  }

  function activePattern() {
    return (root.profilePattern !== null && root.profileOn) ? root.profilePattern : root.general
  }

  function keyFor(device) {
    var pattern = activePattern()
    return (pattern.themeKeys && pattern.themeKeys[device.id]) || pattern.themeKey
  }

  function wearing(device) {
    return root.shownFollow ? themeColor(keyFor(device)) : (device.fixed || "#ffffff")
  }

  function copyPattern(pattern) {
    return { themeKey: pattern.themeKey, themeKeys: Object.assign({}, pattern.themeKeys || {}) }
  }

  function adoptPatterns(payload) {
    if (payload.general) root.general = copyPattern(payload.general)
    root.profilePattern = payload.profilePattern ? copyPattern(payload.profilePattern) : null
    root.profileOn = !!(payload.profile && payload.profile.enabled)
  }

  function isOff(hex) { return String(hex).toLowerCase() === "#000000" }

  function recolour() {
    var device = findDevice(root.target)
    if (root.target !== "" && !device && root.info.config) root.target = ""
    root.sharedColor = root.shownFollow ? themeColor(activePattern().themeKey) : root.shownFixed
    root.pickerColor = device ? wearing(device) : root.sharedColor
    root.pickerKey = device ? keyFor(device) : activePattern().themeKey
    if (!hexField.activeFocus) hexField.text = root.pickerColor.toUpperCase()
  }

  function adopt(payload) {
    if (!payload || !payload.config) return
    if (root.queue.length > 0 && root.info.config !== undefined) return
    root.info = payload
    root.shownFollow = payload.config.follow === true
    adoptPatterns(payload)
    root.shownFixed = payload.config.color || "#ffffff"
    root.shownVivid = payload.config.vivid !== false
    root.shownStartup = payload.startup === true
    root.shownBrightness = Number(payload.config.brightness || 100)
    if (root.page === "removed" && (!(payload.config.ignored instanceof Array) || payload.config.ignored.length === 0)) root.page = ""
    if (root.page === "profiles" && (!(payload.profiles instanceof Array) || payload.profiles.length === 0)) root.page = ""
    recolour()
  }

  function adoptPalette(payload) {
    if (!payload || !(payload.theme instanceof Array) || root.info.config === undefined) return
    var copy = Object.assign({}, root.info)
    copy.theme = payload.theme
    copy.themeName = payload.themeName
    copy.profiles = payload.profiles
    root.info = copy
    if (root.queue.length === 0 && !helperProcess.running) adoptPatterns(payload)
    recolour()
  }

  function select(id) {
    root.target = id
    recolour()
  }

  function chipColor(device) {
    return root.target === device.id ? root.pickerColor : wearing(device)
  }

  function paint(id, choice) {
    if (root.shownFollow) {
      var pattern = copyPattern(activePattern())
      if (id === "") { pattern.themeKey = choice; pattern.themeKeys = ({}) }
      else pattern.themeKeys[id] = choice
      if (root.profilePattern !== null && root.profileOn) root.profilePattern = pattern
      else root.general = pattern
      return
    }
    if (!(root.info.devices instanceof Array)) return
    var next = []
    for (var i = 0; i < root.info.devices.length; i++) {
      var d = Object.assign({}, root.info.devices[i])
      if (id === "" || d.id === id) d.fixed = choice
      next.push(d)
    }
    var copy = Object.assign({}, root.info)
    copy.devices = next
    root.info = copy
  }

  function chipLabel(device) {
    var names = { "GPU": "GPU", "Motherboard": "Board", "Cooler": "Fans", "DRAM": "RAM",
                  "Keyboard": "Keyboard", "Mouse": "Mouse", "LEDStrip": "Strip" }
    var label = names[device.type]
    if (!label) return device.name
    var same = 0
    for (var i = 0; i < devices.length; i++) if (devices[i].type === device.type) same++
    return same > 1 ? device.name : label
  }

  function pickColor(hex) {
    paint(root.target, hex)
    if (root.target === "" && !root.shownFollow) root.shownFixed = hex
    recolour()
    run(root.target !== "" ? ["device-color", root.target, hex] : ["set", "color", hex])
  }

  function pickThemeKey(key) {
    root.shownFollow = true
    paint(root.target, key)
    recolour()
    run(root.target !== "" ? ["device-color", root.target, "theme:" + key] : ["set", "themeKey", key])
  }

  function saveProfile() {
    root.profilePattern = copyPattern(activePattern())
    root.profileOn = true
    recolour()
    run(["profile", "save"])
  }

  function useProfile(on) {
    root.profileOn = on
    recolour()
    run(["profile", "use", on ? "on" : "off"])
  }

  function setFollow(on) {
    if (root.shownFollow === on) return
    root.shownFollow = on
    recolour()
    run(["set", "follow", on ? "on" : "off"])
  }

  readonly property var ownSwatches: {
    var out = []
    for (var i = 0; i < presets.length; i++) out.push({ hex: presets[i], saved: false })
    for (var j = 0; j < savedColors.length; j++) {
      var hex = String(savedColors[j]).toLowerCase()
      if (hex !== "#000000" && presets.indexOf(hex) < 0) out.push({ hex: hex, saved: true })
    }
    out.push({ hex: "#000000", saved: false })
    return out
  }

  // Items per row so that rows come out even (13 items, max 11 gives 7 + 6).
  function perRow(count, most) {
    if (count <= 0 || most <= 0) return 1
    return Math.ceil(count / Math.ceil(count / most))
  }

  function removedLabel(name) { return name === "fury" ? "Kingston FURY RAM" : name }

  function submitHex() {
    var text = hexField.text.trim()
    if (text.charAt(0) !== "#") text = "#" + text
    if (!/^#[0-9a-fA-F]{6}$/.test(text)) { root.lastError = "Write a colour like #12A870"; return }
    keyCatcher.forceActiveFocus()
    pickColor(text.toLowerCase())
  }

  function toHex(c) {
    function pair(v) { var s = Math.round(v * 255).toString(16); return s.length < 2 ? "0" + s : s }
    return "#" + pair(c.r) + pair(c.g) + pair(c.b)
  }

  function iconFor(type) {
    if (type === "GPU") return "󰢮"
    if (type === "Keyboard") return "󰌌"
    if (type === "Motherboard") return "󰘚"
    if (type === "Cooler") return "󰈐"
    if (type === "DRAM") return "󰍛"
    if (type === "Mouse") return "󰍽"
    return "󰌵"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    run(["status"])
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Connections {
    target: Color
    function onAccentChanged() { root.themeChanged() }
    function onForegroundChanged() { root.themeChanged() }
  }

  function themeChanged() {
    // Fetch the palette now and the full state after the hook has applied it.
    paletteProcess.running = false
    paletteProcess.running = true
    paletteAgain.restart()
    themeSettled.restart()
  }

  // theme.name is written slightly after colors.toml.
  Timer {
    id: paletteAgain
    interval: 400
    onTriggered: { paletteProcess.running = false; paletteProcess.running = true }
  }

  Process {
    id: paletteProcess
    command: root.helper.concat(["palette"])
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var payload = null
        try { payload = JSON.parse(String(text || "null")) } catch (e) { payload = null }
        root.adoptPalette(payload)
      }
    }
  }

  Timer {
    id: themeSettled
    interval: 2500
    onTriggered: if (root.opened) root.run(["status"])
  }

  Process {
    id: helperProcess
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var message = String(text || "").trim()
        if (message !== "") root.lastError = message.split("\n").pop()
      }
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var payload = null
        try { payload = JSON.parse(String(text || "null")) } catch (e) { payload = null }
        root.adopt(payload)
      }
    }
    onExited: {
      if (root.queue.length > 0) {
        var next = root.queue[0]
        root.queue = root.queue.slice(1)
        root.launch(next)
      } else {
        root.busy = false
      }
    }
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function color(hex: string): string { root.target = ""; root.pickColor(hex); return "ok" }
    function follow(state: string): string { root.setFollow(state === "on"); return "ok" }
    function pick(hex: string): string { root.pickColor(hex); return root.target === "" ? "all" : root.target }
    function pickKey(key: string): string { root.pickThemeKey(key); return root.target === "" ? "all" : root.target }
    function state(): string {
      return JSON.stringify({ target: root.target, follow: root.shownFollow, picker: root.pickerColor, key: root.pickerKey,
        shared: root.sharedColor, queue: root.queue.length, busy: root.busy,
        profile: root.hasProfile ? (root.profileOn ? "on" : "off") : "none", theme: root.themeName,
        chips: root.devices.map(function(d) { return [root.chipLabel(d), root.chipColor(d), root.keyFor(d), d.fixed] }) })
    }
    function select(device: string): void { root.open(); root.tab = "colour"; root.select(device) }
    function strips(device: string): void { root.open(); root.tab = "settings"; root.page = ""; root.expanded = device }
    function profile(action: string): string {
      if (action === "save") root.saveProfile()
      else if (action === "on" || action === "off") root.useProfile(action === "on")
      else if (action === "page") { root.open(); root.tab = "settings"; root.page = "profiles" }
      return root.hasProfile ? (root.profileOn ? "on" : "off") : "none"
    }
    function removed(): void { root.open(); root.tab = "settings"; root.page = "removed" }
    function restore(name: string): void { root.run(["remember", name]) }
    function settings(): void { root.open(); root.tab = root.tab === "settings" ? "colour" : "settings" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌵"
    tooltipText: "RGB lighting"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.setFollow(!root.shownFollow)
      else root.toggle()
    }
  }

  component Slash: Rectangle {
    anchors.centerIn: parent
    width: parent.width * 0.82
    height: Math.max(2, Math.round(parent.width / 12))
    radius: height / 2
    rotation: -45
    color: root.foreground
    antialiasing: true
  }

  component Swatch: Rectangle {
    id: swatch
    property string hex: "#ffffff"
    property bool selected: false
    property bool removable: false
    signal picked()
    signal removed()

    width: Style.space(30)
    height: width
    radius: width / 2
    color: root.isOff(hex) ? "transparent" : hex
    border.width: root.isOff(hex) ? 2 : 1
    border.color: root.isOff(hex) ? root.foreground : root.hairline
    scale: swatchMouse.containsMouse ? 1.12 : 1.0

    Slash { visible: root.isOff(swatch.hex) }

    Rectangle {
      visible: swatch.selected
      anchors.fill: parent
      anchors.margins: -Style.space(4)
      radius: width / 2
      color: "transparent"
      border.width: 2
      border.color: root.foreground
    }
    Behavior on scale { NumberAnimation { duration: 90 } }

    MouseArea {
      id: swatchMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) { if (swatch.removable) swatch.removed() }
        else swatch.picked()
      }
    }
  }

  component Chip: Rectangle {
    id: chip
    property string label: ""
    property string glyph: ""
    property string dot: "#ffffff"
    property bool selected: false
    property bool faded: false
    signal picked()

    height: Style.space(36)
    width: chipRow.implicitWidth + Style.space(20)
    radius: height / 2
    color: selected ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
      : (chipMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07) : "transparent")
    border.width: selected ? 2 : 1
    border.color: selected ? root.foreground : root.hairline
    opacity: faded ? 0.45 : 1.0

    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: Style.space(7)

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(12)
        height: width
        radius: width / 2
        color: root.isOff(chip.dot) ? "transparent" : chip.dot
        border.width: 1
        border.color: root.isOff(chip.dot) ? root.foreground : root.hairline
        Behavior on color { ColorAnimation { duration: 160 } }

        Slash { visible: root.isOff(chip.dot) }
      }

      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: chip.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.picked()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(780))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: hexField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "t" || t === "T") root.setFollow(!root.shownFollow)
        else if (t === "s" || t === "S") root.tab = root.tab === "settings" ? "colour" : "settings"
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(16)

          Item {
            width: parent.width
            height: tabs.implicitHeight

            Rectangle {
              id: headerDot
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(26)
              height: width
              radius: width / 2
              color: root.isOff(root.sharedColor) ? "transparent" : root.sharedColor
              border.width: root.isOff(root.sharedColor) ? 2 : 1
              border.color: root.isOff(root.sharedColor) ? root.foreground : root.hairline
              Behavior on color { ColorAnimation { duration: 160 } }

              Slash { visible: root.isOff(root.sharedColor) }
            }

            Text {
              textFormat: Text.PlainText
              anchors.left: headerDot.right
              anchors.leftMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              text: "Glow"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            ButtonGroup {
              id: tabs
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              focusable: false
              options: [{ value: "colour", label: "Colour" }, { value: "settings", label: "Settings" }]
              value: root.tab
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onChanged: function(value) { root.tab = value }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.lastError !== ""
            width: parent.width
            text: root.lastError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            visible: root.needsSetup || root.missingOpenRgb
            width: parent.width
            spacing: Style.space(12)

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: root.missingOpenRgb
                ? "Omaglow needs OpenRGB: omarchy pkg add openrgb"
                : "Find your RGB devices and keep their colour across restarts."
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Button {
              visible: !root.missingOpenRgb
              width: parent.width
              text: root.busy ? "Setting up…" : "Set up"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: if (!root.busy) root.run(["setup"])
            }
          }

          Column {
            visible: root.ready && root.tab === "colour"
            width: parent.width
            spacing: Style.space(16)

            Item {
              width: parent.width
              height: modeGroup.implicitHeight

              ButtonGroup {
                id: modeGroup
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                focusable: false
                options: [{ value: "theme", label: "Follow theme" }, { value: "custom", label: "Own colour" }]
                value: root.shownFollow ? "theme" : "custom"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onChanged: function(value) { root.setFollow(value === "theme") }
              }

              Button {
                visible: root.shownFollow && !root.hasProfile
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰃅"
                tooltipText: "Keep this look for " + root.themeName
                foreground: root.foreground
                fontFamily: root.fontFamily
                iconSize: Style.font.subtitle * 1.2
                onClicked: root.saveProfile()
              }

              Row {
                visible: root.shownFollow && root.hasProfile
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(8)

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.min(implicitWidth, Style.space(96))
                  text: "󰃀  " + root.themeName
                  color: root.foreground
                  opacity: root.profileOn ? 1.0 : 0.5
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }

                ToggleSwitch {
                  anchors.verticalCenter: parent.verticalCenter
                  checked: root.profileOn
                  foreground: root.foreground
                  onToggled: root.useProfile(!root.profileOn)
                }
              }
            }

            Flow {
              width: parent.width
              spacing: Style.space(8)

              Repeater {
                model: root.devices

                Chip {
                  required property var modelData
                  label: root.chipLabel(modelData)
                  dot: root.chipColor(modelData)
                  selected: root.target === modelData.id
                  faded: !modelData.enabled
                  onPicked: root.select(modelData.id)
                }
              }

              Chip {
                label: "All"
                dot: root.sharedColor
                selected: root.target === ""
                onPicked: root.select("")
              }
            }

            PanelSeparator { foreground: root.foreground }

            Grid {
              id: themeGrid
              visible: root.shownFollow
              width: parent.width
              readonly property int across: root.perRow(root.themeSwatches.length, 5)
              readonly property real cell: width / across
              columns: across
              rowSpacing: Style.space(14)
              topPadding: Style.space(5)

              Repeater {
                model: root.themeSwatches

                Item {
                  id: themeChoice
                  required property var modelData
                  readonly property bool chosen: root.pickerKey === modelData.key
                  width: themeGrid.cell
                  height: themeStack.implicitHeight

                  Column {
                    id: themeStack
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Style.space(8)

                    Swatch {
                      anchors.horizontalCenter: parent.horizontalCenter
                      width: Style.space(36)
                      hex: themeChoice.modelData.color
                      selected: themeChoice.chosen
                      onPicked: root.pickThemeKey(themeChoice.modelData.key)
                    }

                    Text {
                      textFormat: Text.PlainText
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: themeChoice.modelData.key
                      color: root.foreground
                      opacity: themeChoice.chosen ? 1.0 : 0.6
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                  }
                }
              }
            }

            PanelSeparator { visible: root.shownFollow; foreground: root.foreground }

            Column {
              width: parent.width
              spacing: Style.space(16)

              Grid {
                id: ownGrid
                readonly property real dot: Style.space(30)
                readonly property real room: parent.width - 2 * Style.space(5)
                readonly property int across: root.perRow(root.ownSwatches.length,
                  Math.floor((room + Style.space(6)) / (dot + Style.space(6))))
                readonly property real gap: across > 1 ? Math.min(Style.space(18), (room - across * dot) / (across - 1)) : 0
                columns: across
                columnSpacing: gap
                rowSpacing: Style.space(12)
                padding: Style.space(5)

                Repeater {
                  model: root.ownSwatches

                  Swatch {
                    required property var modelData
                    width: ownGrid.dot
                    hex: modelData.hex
                    removable: modelData.saved
                    selected: root.pickerColor.toLowerCase() === modelData.hex
                    onPicked: root.pickColor(modelData.hex)
                    onRemoved: root.run(["unsave", modelData.hex])
                  }
                }
              }

              Row {
                width: parent.width
                spacing: Style.space(16)

                Item {
                  id: wheel
                  width: Style.space(148)
                  height: width

                  readonly property color current: root.pickerColor
                  readonly property real hue: current.hsvHue < 0 ? 0 : current.hsvHue
                  readonly property real sat: current.hsvSaturation

                  function hexAt(x, y) {
                    var r = width / 2
                    var dx = x - r, dy = y - r
                    var d = Math.min(1, Math.sqrt(dx * dx + dy * dy) / r)
                    var h = (Math.atan2(dy, dx) / (2 * Math.PI) + 1) % 1
                    return root.toHex(Qt.hsva(h, d, 1, 1))
                  }

                  Canvas {
                    anchors.fill: parent
                    onPaint: {
                      var ctx = getContext("2d")
                      var r = width / 2
                      ctx.clearRect(0, 0, width, height)
                      for (var i = 0; i < 360; i++) {
                        ctx.beginPath()
                        ctx.moveTo(r, r)
                        ctx.arc(r, r, r, (i - 0.7) * Math.PI / 180, (i + 0.7) * Math.PI / 180, false)
                        ctx.closePath()
                        ctx.fillStyle = Qt.hsva(i / 360, 1, 1, 1)
                        ctx.fill()
                      }
                      var fade = ctx.createRadialGradient(r, r, 0, r, r, r)
                      fade.addColorStop(0, Qt.rgba(1, 1, 1, 1))
                      fade.addColorStop(1, Qt.rgba(1, 1, 1, 0))
                      ctx.fillStyle = fade
                      ctx.beginPath()
                      ctx.arc(r, r, r, 0, 2 * Math.PI, false)
                      ctx.fill()
                    }
                  }

                  Rectangle {
                    width: Style.space(16)
                    height: width
                    radius: width / 2
                    x: wheel.width / 2 + Math.cos(wheel.hue * 2 * Math.PI) * wheel.sat * wheel.width / 2 - width / 2
                    y: wheel.height / 2 + Math.sin(wheel.hue * 2 * Math.PI) * wheel.sat * wheel.height / 2 - height / 2
                    color: root.pickerColor
                    border.width: 2
                    border.color: "#202020"

                    Rectangle {
                      anchors.fill: parent
                      anchors.margins: 2
                      radius: width / 2
                      color: "transparent"
                      border.width: 1
                      border.color: "#ffffff"
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.CrossCursor
                    onPressed: function(mouse) { root.pickerColor = wheel.hexAt(mouse.x, mouse.y) }
                    onPositionChanged: function(mouse) { if (pressed) root.pickerColor = wheel.hexAt(mouse.x, mouse.y) }
                    onReleased: function(mouse) { root.pickColor(wheel.hexAt(mouse.x, mouse.y)) }
                  }
                }

                Column {
                  width: parent.width - wheel.width - Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(10)

                  TextField {
                    id: hexField
                    width: parent.width
                    placeholderText: "#RRGGBB"
                    foreground: root.foreground
                    Keys.onReturnPressed: function(event) { event.accepted = true; root.submitHex() }
                    Keys.onEnterPressed: function(event) { event.accepted = true; root.submitHex() }
                    Keys.onEscapePressed: function(event) { event.accepted = true; keyCatcher.forceActiveFocus() }
                  }

                  Button {
                    width: parent.width
                    text: "Save colour"
                    iconText: "󰐕"
                    tooltipText: "Right click a saved colour to remove it"
                    leftAlign: true
                    bordered: true
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: root.run(["save", root.pickerColor])
                  }
                }
              }
            }

            PanelSeparator { foreground: root.foreground }

            Item {
              width: parent.width
              height: Style.space(30)

              Text {
                id: brightnessLabel
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(52)
                text: Math.round(root.shownBrightness) + " %"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              PanelSlider {
                bar: root.bar
                anchors.left: brightnessLabel.right
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                minimum: 5
                maximum: 100
                step: 5
                integer: true
                value: root.shownBrightness
                onMoved: function(v) { root.shownBrightness = v }
                onReleased: function(v) {
                  root.shownBrightness = v
                  root.run(["set", "brightness", String(Math.round(v))])
                }
              }

              // PanelSlider reacts to the scroll wheel. Send the wheel to the panel instead
              // so scrolling past the slider does not change brightness.
              MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                onWheel: function(wheel) {
                  var limit = Math.max(0, panelFlick.contentHeight - panelFlick.height)
                  panelFlick.contentY = Math.max(0, Math.min(limit, panelFlick.contentY - wheel.angleDelta.y))
                }
              }
            }
          }

          Column {
            visible: root.ready && root.tab === "settings" && root.page === ""
            width: parent.width
            spacing: Style.space(12)

            Toggle {
              width: parent.width
              label: "Restore at startup"
              checked: root.shownStartup
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: {
                root.shownStartup = !root.shownStartup
                root.run(["set", "startup", root.shownStartup ? "on" : "off"])
              }
            }

            Toggle {
              width: parent.width
              label: "Correct colours for LEDs"
              checked: root.shownVivid
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: {
                root.shownVivid = !root.shownVivid
                root.run(["set", "vivid", root.shownVivid ? "on" : "off"])
              }
            }

            PanelSeparator { foreground: root.foreground }

            Column {
              id: deviceColumn
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: root.devices

                Column {
                  id: deviceRow
                  required property var modelData
                  readonly property var strips: modelData.zones instanceof Array ? modelData.zones : []
                  readonly property bool open: root.expanded === modelData.id
                  width: deviceColumn.width

                  Item {
                    width: parent.width
                    height: Style.space(40)

                    Text {
                      id: deviceIcon
                      textFormat: Text.PlainText
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(30)
                      text: root.iconFor(deviceRow.modelData.type)
                      color: deviceRow.modelData.enabled ? root.foreground : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.subtitle * 1.2
                    }

                    Text {
                      textFormat: Text.PlainText
                      anchors.left: deviceIcon.right
                      anchors.right: stripsButton.visible ? stripsButton.left : deviceSwitch.left
                      anchors.rightMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      text: deviceRow.modelData.name
                      color: deviceRow.modelData.enabled ? root.foreground : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                    }

                    Button {
                      id: stripsButton
                      visible: deviceRow.strips.length > 0
                      anchors.right: deviceSwitch.left
                      anchors.rightMargin: Style.space(4)
                      anchors.verticalCenter: parent.verticalCenter
                      iconText: deviceRow.open ? "󰅃" : "󰅀"
                      tooltipText: "LED strips on the addressable headers"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      onClicked: root.expanded = deviceRow.open ? "" : deviceRow.modelData.id
                    }

                    ToggleSwitch {
                      id: deviceSwitch
                      anchors.right: forgetButton.left
                      anchors.rightMargin: Style.space(4)
                      anchors.verticalCenter: parent.verticalCenter
                      checked: deviceRow.modelData.enabled
                      foreground: root.foreground
                      onToggled: root.run(["device", deviceRow.modelData.id, deviceRow.modelData.enabled ? "off" : "on"])
                    }

                    Button {
                      id: forgetButton
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      iconText: "󰅖"
                      tooltipText: "Not mine: remove and stop talking to it"
                      foreground: root.dim
                      fontFamily: root.fontFamily
                      onClicked: if (!root.busy) root.run(["forget", deviceRow.modelData.id])
                    }
                  }

                  Repeater {
                    model: deviceRow.open ? deviceRow.strips : []

                    Item {
                      id: stripRow
                      required property var modelData
                      width: deviceRow.width
                      height: Style.space(44)

                      Text {
                        textFormat: Text.PlainText
                        anchors.left: parent.left
                        anchors.leftMargin: Style.space(30)
                        anchors.right: stripSize.left
                        anchors.rightMargin: Style.space(8)
                        anchors.verticalCenter: parent.verticalCenter
                        text: stripRow.modelData.name
                        color: root.foreground
                        opacity: 0.8
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        elide: Text.ElideRight
                      }

                      NumberField {
                        id: stripSize
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        from: 0
                        to: stripRow.modelData.max
                        value: stripRow.modelData.size
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        onModified: function(value) {
                          root.run(["zone", deviceRow.modelData.id, String(stripRow.modelData.index), String(value)])
                        }
                      }
                    }
                  }
                }
              }
            }

            PanelSeparator { foreground: root.foreground }

            Button {
              width: parent.width
              text: root.busy && helperProcess.command.indexOf("rescan") >= 0 ? "Scanning…" : "Scan for devices"
              iconText: "󰑐"
              leftAlign: true
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: if (!root.busy) root.run(["rescan"])
            }

            Button {
              visible: root.profiles.length > 0
              width: parent.width
              text: "Theme profiles (" + root.profiles.length + ")"
              iconText: "󰃀"
              leftAlign: true
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.page = "profiles"
            }

            Button {
              visible: root.ignoredDevices.length > 0
              width: parent.width
              text: "Removed devices (" + root.ignoredDevices.length + ")"
              iconText: "󰕌"
              leftAlign: true
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.page = "removed"
            }
          }

          Column {
            visible: root.ready && root.tab === "settings" && root.page === "profiles"
            width: parent.width
            spacing: Style.space(12)

            Item {
              width: parent.width
              height: profilesBack.implicitHeight

              Button {
                id: profilesBack
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Back"
                iconText: "󰁍"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.page = ""
              }

              Text {
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "Theme profiles"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
            }

            PanelSeparator { foreground: root.foreground }

            Column {
              id: profileColumn
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: root.profiles

                Item {
                  id: profileRow
                  required property var modelData
                  width: profileColumn.width
                  height: Style.space(44)

                  Text {
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.right: profileSwitch.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    text: profileRow.modelData.name
                    color: root.foreground
                    opacity: profileRow.modelData.enabled ? 1.0 : 0.5
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }

                  ToggleSwitch {
                    id: profileSwitch
                    anchors.right: profileDelete.left
                    anchors.rightMargin: Style.space(4)
                    anchors.verticalCenter: parent.verticalCenter
                    checked: profileRow.modelData.enabled
                    foreground: root.foreground
                    onToggled: root.run(["profile", "use", profileRow.modelData.enabled ? "off" : "on", profileRow.modelData.slug])
                  }

                  Button {
                    id: profileDelete
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: "󰅖"
                    tooltipText: "Delete this profile"
                    foreground: root.dim
                    fontFamily: root.fontFamily
                    onClicked: root.run(["profile", "delete", profileRow.modelData.slug])
                  }
                }
              }
            }
          }

          Column {
            visible: root.ready && root.tab === "settings" && root.page === "removed"
            width: parent.width
            spacing: Style.space(12)

            Item {
              width: parent.width
              height: backButton.implicitHeight

              Button {
                id: backButton
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Back"
                iconText: "󰁍"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.page = ""
              }

              Text {
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "Removed devices"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
            }

            PanelSeparator { foreground: root.foreground }

            Column {
              id: removedColumn
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: root.ignoredDevices

                Item {
                  id: removedRow
                  required property string modelData
                  width: removedColumn.width
                  height: Style.space(44)

                  Text {
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.right: restoreButton.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.removedLabel(removedRow.modelData)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }

                  Button {
                    id: restoreButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.busy && helperProcess.command.indexOf(removedRow.modelData) >= 0 ? "Restoring…" : "Restore"
                    bordered: true
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: if (!root.busy) root.run(["remember", removedRow.modelData])
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
