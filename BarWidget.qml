import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Presets.js" as Presets

// Keyboard presets for hardware whose keys don't match the stock layout
// (ThinkPad ABNT2's / ? key on Right Ctrl, ABNT2 + US, US intl, ...) plus
// XKB option toggles. All writes go through keyboard_presets.py, which keeps
// Omarchy's keyboard-layouts file and fcitx5 in step and rolls back when
// Hyprland rejects the result.
Panel {
  id: root
  moduleName: "eusener.keyboard-presets"
  ipcTarget: "eusener.keyboard-presets"
  manageIpc: false

  readonly property string pluginDir: decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")).replace(/\/$/, "")
  readonly property string helperPath: pluginDir + "/keyboard_presets.py"

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property Item panelFlick: panel.loadedContent ? panel.loadedContent.panelFlick : null

  // Live state read back from Hyprland through the helper.
  property var layouts: []
  property var options: []
  property bool inputOverride: false
  // Nothing under ~/.config changes until the user has agreed once.
  property bool consented: false
  property var pendingArgs: null
  property string pendingSuccess: ""
  property bool busy: false
  property string message: ""
  property bool messageIsError: false

  readonly property string activePreset: Presets.activePresetId(layouts)
  readonly property var activePresetDef: Presets.PRESETS.filter(function (p) { return p.id === root.activePreset })[0] || null

  // Keyboard cursor over one flat list: presets, then options, then actions.
  property int cursorIndex: 0
  property bool cursorActive: false
  readonly property int presetCount: Presets.PRESETS.length
  readonly property int optionCount: Presets.OPTIONS.length
  readonly property int actionCount: 2
  readonly property int rowCount: presetCount + optionCount + actionCount

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (statusProc.running) return
    statusProc.running = true
  }

  // apply/reset write user config: the first time, ask before touching it.
  function runConfigChange(args, successText) {
    if (busy) return
    if (!consented) {
      pendingArgs = args
      pendingSuccess = successText
      cursorActive = false
      return
    }
    runHelper(args, successText)
  }

  function confirmPending() {
    var args = pendingArgs
    pendingArgs = null
    if (args) runHelper(args.concat(["--consent"]), pendingSuccess)
  }

  function cancelPending() {
    pendingArgs = null
  }

  function runHelper(args, successText) {
    if (busy) return
    busy = true
    messageIsError = false
    message = strings.t("applying")
    applyProc.successText = successText
    applyProc.command = ["python3", root.helperPath].concat(args)
    applyProc.running = true
  }

  function readStatus(text) {
    try {
      const data = JSON.parse(String(text || "").trim().split("\n").pop())
      if (data.layouts) root.layouts = data.layouts
      if (data.options) root.options = data.options
      if (data.inputOverride !== undefined) root.inputOverride = data.inputOverride
      if (data.consented !== undefined) root.consented = data.consented
      return true
    } catch (e) {
      return false
    }
  }

  function applyPreset(preset) {
    runConfigChange(["apply", JSON.stringify({ layouts: preset.layouts, options: Presets.presetOptions(root.options) })],
              strings.t("applied").arg(strings.t("preset." + preset.id)))
  }

  function toggleOption(option) {
    var layouts = root.layouts.length ? root.layouts : ["us"]
    runConfigChange(["apply", JSON.stringify({ layouts: layouts, options: Presets.toggledOptions(root.options, option.id) })],
              strings.t("applied").arg(strings.t("option." + option.key)))
  }

  function resetDefault() {
    runConfigChange(["reset"], strings.t("applied").arg(strings.t("reset")))
  }

  function applyConsole() {
    var keymap = activePresetDef ? activePresetDef.console : ""
    if (!keymap) return
    runHelper(["console", keymap], strings.t("consoleDone").arg(keymap))
  }

  function activateRow(index) {
    if (index < presetCount) applyPreset(Presets.PRESETS[index])
    else if (index < presetCount + optionCount) toggleOption(Presets.OPTIONS[index - presetCount])
    else if (index === presetCount + optionCount) resetDefault()
    else applyConsole()
  }

  function moveCursor(dy) {
    if (!cursorActive) { cursorActive = true; return }
    cursorIndex = Math.max(0, Math.min(rowCount - 1, cursorIndex + dy))
  }

  function hover(index) {
    cursorActive = true
    cursorIndex = index
  }

  onOpenedChanged: if (opened) {
    pendingArgs = null
    cursorActive = false
    cursorIndex = Math.max(0, Presets.PRESETS.findIndex(function (p) { return p.id === root.activePreset }))
    if (panelFlick) panelFlick.contentY = 0
    refresh()
    Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus() })
  }

  Component.onCompleted: refresh()

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && event.name === "configreloaded") root.refresh()
    }
  }

  Process {
    id: statusProc
    command: ["python3", root.helperPath, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.readStatus(text)
    }
  }

  Process {
    id: applyProc
    property string successText: ""
    property string out: ""
    property string err: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: applyProc.out = text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: applyProc.err = String(text || "").trim() }
    onExited: function(exitCode) {
      // Exit and stream completion have no guaranteed order; settle once both
      // collectors have had a chance to land.
      Qt.callLater(function() {
        root.busy = false
        if (exitCode === 0) {
          root.readStatus(applyProc.out)
          root.messageIsError = false
          root.message = applyProc.successText
        } else {
          root.messageIsError = true
          root.message = strings.t("failed").arg(applyProc.err.split("\n").pop() || ("exit " + exitCode))
        }
        root.refresh()
      })
    }
  }

  Commons.ShellIpc {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function status(): string { return Presets.layoutsLabel(root.layouts) + " | " + root.options.join(",") }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌌"
    tooltipText: ""
    onPressed: function(b) {
      if (b === Qt.RightButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(620))

    content: PanelKeyCatcher {
      property alias panelFlick: panelFlick
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (consentDialog.opened) { if (dx !== 0) consentDialog.selectedIndex = consentDialog.selectedIndex === 0 ? 1 : 0; return }
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: {
        if (consentDialog.opened) {
          if (consentDialog.selectedIndex === 0) root.cancelPending()
          else root.confirmPending()
          return
        }
        if (root.cursorActive) root.activateRow(root.cursorIndex)
      }
      onCloseRequested: consentDialog.opened ? root.cancelPending() : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") root.refresh() }

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
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: strings.t("title")
            meta: root.activePreset
              ? strings.t("preset." + root.activePreset)
              : strings.t("custom").arg(Presets.layoutsLabel(root.layouts))
            detail: root.layouts.length > 1 ? strings.t("switchHint") : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              PlainText {
                text: "󰌌"
                font.pixelSize: Style.font.display
                color: root.foreground
              }
            }
          }

          PlainText {
            visible: root.inputOverride
            width: parent.width
            text: strings.t("override")
            color: root.urgent
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PlainText {
            visible: root.message !== ""
            width: parent.width
            text: root.message
            color: root.messageIsError ? root.urgent : root.dim
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSectionHeader {
            text: strings.t("presets")
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Column {
            width: parent.width
            spacing: Style.space(4)
            Repeater {
              model: Presets.PRESETS
              Row2 {
                required property var modelData
                required property int index
                width: parent.width
                rowIndex: index
                glyph: modelData.icon
                title: strings.t("preset." + modelData.id)
                subtitle: strings.t("preset." + modelData.id + ".help")
                selected: root.activePreset === modelData.id
                onActivated: root.applyPreset(modelData)
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          PanelSectionHeader {
            text: strings.t("options")
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Column {
            width: parent.width
            spacing: Style.space(4)
            Repeater {
              model: Presets.OPTIONS
              OptionRow {
                required property var modelData
                required property int index
                width: parent.width
                rowIndex: root.presetCount + index
                title: strings.t("option." + modelData.key)
                code: modelData.id
                checked: root.options.indexOf(modelData.id) >= 0
                onActivated: root.toggleOption(modelData)
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          Row2 {
            width: parent.width
            rowIndex: root.presetCount + root.optionCount
            glyph: "󰑓"
            title: strings.t("reset")
            subtitle: strings.t("resetHelp")
            onActivated: root.resetDefault()
          }

          Row2 {
            width: parent.width
            visible: root.activePresetDef !== null
            rowIndex: root.presetCount + root.optionCount + 1
            glyph: "󰆍"
            title: strings.t("console")
            subtitle: strings.t("consoleHelp").arg(root.activePresetDef ? root.activePresetDef.console : "")
            onActivated: root.applyConsole()
          }

          PlainText {
            width: parent.width
            text: strings.t("tip")
            color: root.dim
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }

      ConfirmDialog {
        id: consentDialog
        anchors.fill: parent
        z: 10
        opened: root.pendingArgs !== null
        message: strings.t("consent")
        confirmText: strings.t("consentConfirm")
        foreground: root.foreground
        fontFamily: root.fontFamily
        onCanceled: root.cancelPending()
        onConfirmed: root.confirmPending()
      }
    }
  }

  component PlainText: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  // A clickable row with a glyph, title and one-line explanation.
  component Row2: CursorSurface {
    id: row
    property int rowIndex: 0
    property string glyph: ""
    property string title: ""
    property string subtitle: ""
    property bool selected: false
    signal activated()

    hasCursor: root.cursorActive && root.cursorIndex === rowIndex
    current: selected
    foreground: root.foreground
    implicitHeight: rowLayout.implicitHeight + Style.spacing.rowPaddingX
    opacity: root.busy ? 0.6 : 1

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      enabled: !root.busy
      cursorShape: Qt.PointingHandCursor
      onEntered: root.hover(row.rowIndex)
      onClicked: row.activated()
    }

    RowLayout {
      id: rowLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(10)

      PlainText {
        text: row.glyph
        font.pixelSize: Style.font.icon
        horizontalAlignment: Text.AlignHCenter
        Layout.preferredWidth: Math.round(Style.font.icon * 1.4)
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)
        PlainText {
          Layout.fillWidth: true
          text: row.title
          elide: Text.ElideRight
        }
        PlainText {
          Layout.fillWidth: true
          text: row.subtitle
          color: root.dim
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }

      PlainText {
        visible: row.selected
        text: "󰄬"
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }

  // An XKB option with an on/off switch.
  component OptionRow: CursorSurface {
    id: opt
    property int rowIndex: 0
    property string title: ""
    property string code: ""
    property bool checked: false
    signal activated()

    hasCursor: root.cursorActive && root.cursorIndex === rowIndex
    foreground: root.foreground
    implicitHeight: optLayout.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      enabled: !root.busy
      cursorShape: Qt.PointingHandCursor
      onEntered: root.hover(opt.rowIndex)
      onClicked: opt.activated()
    }

    RowLayout {
      id: optLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(4)
      spacing: Style.space(10)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)
        PlainText {
          Layout.fillWidth: true
          text: opt.title
          elide: Text.ElideRight
        }
        PlainText {
          Layout.fillWidth: true
          text: opt.code
          color: root.dim
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      ToggleSwitch {
        checked: opt.checked
        busy: root.busy
        cursorRing: false
        foreground: root.foreground
        Layout.alignment: Qt.AlignVCenter
        onToggled: opt.activated()
      }
    }
  }
}
