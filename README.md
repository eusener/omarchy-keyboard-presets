# Keyboard presets for Omarchy

A bar widget for keyboards whose physical keys don't match the layout the
installer picked. One click fixes the classic cases, starting with the
Brazilian ThinkPad whose `/ ?` key does nothing on the stock `br` layout.

| Preset | XKB | When to use it |
|---|---|---|
| ThinkPad ABNT2 | `br:thinkpad` | Brazilian ThinkPads: the `/ ?` key next to Right Shift sends Right Ctrl |
| ABNT2 | `br` | Standard Brazilian keyboard |
| ThinkPad ABNT2 + US intl | `br:thinkpad,us:intl` | Both, switch with Left Alt + Right Alt |
| ABNT2 + US intl | `br,us:intl` | ABNT2 laptop with an external US keyboard |
| US international | `us:intl` | US keyboard, dead-key accents, AltGr + , = ç |
| US alt-intl | `us:alt-intl` | Programmers: quotes type directly, accents via AltGr |
| US | `us` | Plain US |
| Portugal | `pt` | Portuguese keyboard |

Toggles on top of any preset: Shift + Caps Lock as Compose (Omarchy's
default), keypad `.` instead of `,` (`kpdl:dot`), Caps Lock as Esc or Ctrl,
swap Ctrl and Caps Lock, swap Alt and Super for Mac keyboards.

UI in English and Brazilian Portuguese; follows Setup > Language live.

## Install

```bash
omarchy plugin add https://github.com/eusener/omarchy-keyboard-presets --enable
```

Requires `python3` (present on every Omarchy install). No other dependencies.

## Usage

Click the keyboard icon on the bar, pick a preset or flip an option. The
change applies immediately; if Hyprland reports a config error the plugin
rolls every file back. Arrow keys + Enter navigate, Escape closes, right
click re-reads the current state.

IPC: `omarchy-shell eusener.keyboard-presets toggle` / `status`.

## What it changes

**Nothing is written until you agree.** The first time you apply a preset,
toggle an option or reset, the panel lists the files below and asks for
confirmation; the helper itself refuses to write without it. Before every
change, each existing file is copied to
`~/.config/omarchy/keyboard-presets/backups/<timestamp>/` (last 20 kept).

All writes are made by `keyboard_presets.py`, run as your user:

- `~/.config/omarchy/keyboard-layouts` – layouts and variants. This is the same
  file `omarchy setup keyboard` writes, so the two stay interchangeable.
- `~/.config/hypr/keyboard_options.lua` – XKB options (`kb_options`).
- `~/.config/hypr/input.lua` – one line is appended once:
  `pcall(require, "hypr.keyboard_options")`.
- The running fcitx5 input group is pointed at the new first layout (over
  the session D-Bus), as Omarchy's own keyboard setup does.

Every layout, variant and option is checked against
`/usr/share/X11/xkb/rules/evdev.lst` before anything is written.

If `hypr/input.lua` already sets `kb_layout` / `kb_variant` itself, that wins
over any preset; the panel shows a warning and the helper refuses to apply.

### Privilege boundary

Only **Apply to TTY too** needs root. It runs
`pkexec localectl set-keymap --no-convert <keymap>` (keymap checked against
`localectl list-keymaps`), so polkit asks for your password. Nothing else
leaves your home directory. No network access.

## Configure

No `shell.json` settings. The preset list lives in `Presets.js`; add an entry
with `layouts` and a console `keymap`, plus `preset.<id>` strings in `i18n/`.

## Remove

```bash
omarchy plugin remove eusener.keyboard-presets
```

Your keyboard keeps the last preset you applied. To return to the install
default first, click **Back to install default** (removes
`keyboard-layouts` and `keyboard_options.lua`). The `pcall(require, ...)` line
left in `hypr/input.lua` is harmless when the file is gone; delete it if you
like. Backups and the consent marker live in `~/.config/omarchy/keyboard-presets/`;
copy a backup back to restore, or delete the folder.

## License

MIT
