// Keyboard presets for hardware whose physical keys don't match the stock
// layout the installer picks. Each preset names its xkb layouts
// ("layout:variant"), the console keymap that types the same thing on a TTY,
// and the translation keys for its title and explanation.

var PRESETS = [
  { id: "br-thinkpad", layouts: ["br:thinkpad"], console: "br-abnt2", icon: "󰌌" },
  { id: "br-abnt2", layouts: ["br"], console: "br-abnt2", icon: "󰌌" },
  { id: "br-thinkpad-us", layouts: ["br:thinkpad", "us:intl"], console: "br-abnt2", icon: "󰗊" },
  { id: "br-us", layouts: ["br", "us:intl"], console: "br-abnt2", icon: "󰗊" },
  { id: "us-intl", layouts: ["us:intl"], console: "us-acentos", icon: "󰌌" },
  { id: "us-altintl", layouts: ["us:alt-intl"], console: "us", icon: "󰅩" },
  { id: "us", layouts: ["us"], console: "us", icon: "󰌌" },
  { id: "pt", layouts: ["pt"], console: "pt-latin1", icon: "󰌌" }
]

// Options toggled on top of any preset. omarchy:shift_caps_compose is
// Omarchy's own default and stays on unless switched off here.
var OPTIONS = [
  { id: "omarchy:shift_caps_compose", key: "compose" },
  { id: "kpdl:dot", key: "kpdot" },
  { id: "caps:escape", key: "capsEsc", excludes: ["ctrl:nocaps", "ctrl:swapcaps"] },
  { id: "ctrl:nocaps", key: "capsCtrl", excludes: ["caps:escape", "ctrl:swapcaps"] },
  { id: "ctrl:swapcaps", key: "swapCaps", excludes: ["caps:escape", "ctrl:nocaps"] },
  { id: "altwin:swap_alt_win", key: "swapAltWin" }
]

function sameLayouts(a, b) {
  if (!a || !b || a.length !== b.length) return false
  for (var i = 0; i < a.length; i++) if (a[i] !== b[i]) return false
  return true
}

function activePresetId(layouts) {
  for (var i = 0; i < PRESETS.length; i++)
    if (sameLayouts(PRESETS[i].layouts, layouts)) return PRESETS[i].id
  return ""
}

// The option list after flipping one toggle. grp:* is the helper's business
// (added when more than one layout is active), so it never reaches here.
function toggledOptions(current, optionId) {
  var list = (current || []).filter(function (o) { return o.indexOf("grp:") !== 0 })
  var idx = list.indexOf(optionId)
  if (idx >= 0) {
    list.splice(idx, 1)
    return list
  }
  var def = OPTIONS.filter(function (o) { return o.id === optionId })[0]
  var excludes = (def && def.excludes) || []
  list = list.filter(function (o) { return excludes.indexOf(o) < 0 })
  list.push(optionId)
  return list
}

function presetOptions(current) {
  return (current || []).filter(function (o) { return o.indexOf("grp:") !== 0 })
}

function layoutsLabel(layouts) {
  return (layouts || []).map(function (l) {
    var p = l.split(":")
    return p[0] + (p[1] ? " (" + p[1] + ")" : "")
  }).join(" + ")
}

if (typeof module !== "undefined") {
  module.exports = {
    PRESETS: PRESETS, OPTIONS: OPTIONS, activePresetId: activePresetId,
    toggledOptions: toggledOptions, presetOptions: presetOptions, layoutsLabel: layoutsLabel
  }
}
