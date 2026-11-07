#!/usr/bin/env python3
"""Apply keyboard layout presets for the eusener.keyboard-presets plugin.

  keyboard_presets.py status
  keyboard_presets.py apply '{"layouts": ["br:thinkpad"], "options": ["kpdl:dot"]}' [--consent]
  keyboard_presets.py reset [--consent]
  keyboard_presets.py console br-abnt2

apply and reset refuse to touch any file until the user has agreed once in
the panel (--consent records that). Every file is backed up before it is
changed, under ~/.config/omarchy/keyboard-presets/backups/<timestamp>/.

Layouts and variants go to ~/.config/omarchy/keyboard-layouts, the file
Omarchy's own `omarchy setup keyboard` writes, and the live fcitx5 group is
kept in step. XKB options, which that file cannot carry, go to
~/.config/hypr/keyboard_options.lua, loaded from hypr/input.lua.
"""

import json
import os
import re
import subprocess
import sys
import shutil
import tempfile
import time
from pathlib import Path

CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
LAYOUTS_FILE = CONFIG / "omarchy/keyboard-layouts"
OPTIONS_FILE = CONFIG / "hypr/keyboard_options.lua"
INPUT_LUA = CONFIG / "hypr/input.lua"
STATE_DIR = CONFIG / "omarchy/keyboard-presets"
CONSENT_FILE = STATE_DIR / "consent"
BACKUP_DIR = STATE_DIR / "backups"
REQUIRE_LINE = 'pcall(require, "hypr.keyboard_options")'
FCITX = ["busctl", "--user", "call", "org.fcitx.Fcitx5", "/controller", "org.fcitx.Fcitx.Controller1"]
NON_LATIN = set("af am ara bd bg by et ge gr il in iq ir kg kh kz la lk mk mm mn mv np rs ru sy th tj ua".split())
BASE_OPTION = "omarchy:shift_caps_compose"
TOKEN = re.compile(r"^[a-z0-9_()+-]+$")


def run(args):
  return subprocess.run(args, check=True, text=True, capture_output=True).stdout.strip()


def atomic_write(path, text):
  path = path.resolve()
  path.parent.mkdir(parents=True, exist_ok=True)
  fd, tmp = tempfile.mkstemp(prefix=".kbd-presets-", dir=path.parent)
  try:
    with os.fdopen(fd, "w") as f:
      f.write(text)
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)
  finally:
    if os.path.exists(tmp):
      os.unlink(tmp)


def read(path):
  return path.read_text() if path.exists() else None


def restore(path, original):
  if original is None:
    path.unlink(missing_ok=True)
  else:
    atomic_write(path, original)


def require_consent(given):
  if given:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    CONSENT_FILE.write_text(time.strftime("%Y-%m-%dT%H:%M:%S") + "\n")
  if not CONSENT_FILE.exists():
    raise PermissionError("Confirme no painel antes de alterar a configuração")


def backup(paths):
  """Copy every existing file about to change into a timestamped folder."""
  existing = [p for p in paths if p.exists()]
  if not existing:
    return None
  target = BACKUP_DIR / time.strftime("%Y%m%d-%H%M%S")
  target.mkdir(parents=True, exist_ok=True)
  for path in existing:
    shutil.copy2(path.resolve(), target / path.name)
  # Keep the twenty most recent backups.
  for old in sorted(BACKUP_DIR.iterdir())[:-20]:
    shutil.rmtree(old, ignore_errors=True)
  return target


def xkb_catalog():
  """Layouts, variants (per layout) and options known to xkeyboard-config."""
  layouts, variants, options = set(), set(), set()
  section = None
  for line in Path("/usr/share/X11/xkb/rules/evdev.lst").read_text().splitlines():
    if line.startswith("! "):
      section = line[2:].strip()
      continue
    fields = line.split()
    if not fields:
      continue
    if section == "layout":
      layouts.add(fields[0])
    elif section == "variant" and len(fields) > 1:
      variants.add(fields[1].rstrip(":") + ":" + fields[0])
    elif section == "option":
      options.add(fields[0])
  options.add(BASE_OPTION)
  return layouts, variants, options


def getoption(name):
  return json.loads(run(["hyprctl", "-j", "getoption", name]))["str"]


def live_layouts():
  layouts = getoption("input:kb_layout").split(",")
  variants = getoption("input:kb_variant").split(",")
  return [l + (":" + variants[i] if i < len(variants) and variants[i] else "") for i, l in enumerate(layouts)]


def status():
  opts = [o for o in getoption("input:kb_options").split(",") if o]
  print(json.dumps({
    "layouts": live_layouts(),
    "options": opts,
    "managed": OPTIONS_FILE.exists(),
    "consented": CONSENT_FILE.exists(),
    "inputOverride": input_override(),
  }))


def input_override():
  """True when hypr/input.lua sets kb_layout itself, which would win over us."""
  text = read(INPUT_LUA) or ""
  return any(re.match(r"^\s*kb_(layout|variant)\s*=", line) for line in text.splitlines())


def ensure_require():
  text = read(INPUT_LUA) or ""
  if REQUIRE_LINE in text:
    return
  block = "\n-- Opções XKB gerenciadas pelo plugin eusener.keyboard-presets.\n" + REQUIRE_LINE + "\n"
  atomic_write(INPUT_LUA, text.rstrip("\n") + "\n" + block)


def options_lua(options):
  return (
    "-- Gerado pelo plugin eusener.keyboard-presets. Não edite à mão:\n"
    "-- use o painel de teclado na barra ou apague este arquivo.\n"
    "hl.config({\n"
    "  input = {\n"
    f'    kb_options = "{",".join(options)}",\n'
    "  },\n"
    "})\n"
  )


def sync_fcitx(first):
  """Point the live fcitx5 group at the new first layout, as Omarchy does."""
  try:
    group = run(["fcitx5-remote", "-q"])
  except (OSError, subprocess.CalledProcessError):
    return
  info = json.loads(run(FCITX[:1] + ["--json=short"] + FCITX[1:] + ["InputMethodGroupInfo", "s", group]))["data"]
  _, items = info[:2]
  layout = first.replace(":", "-")
  keyboard = "keyboard-" + layout
  after = [[keyboard, ""]] + [[n, o] for n, o in items if not n.startswith("keyboard-")]
  args = [group, layout, str(len(after))]
  for name, override in after:
    args += [name, override]
  run(FCITX + ["SetInputMethodGroupInfo", "ssa(ss)"] + args)
  run(FCITX + ["Save"])


def reload_checked(previous_errors):
  run(["hyprctl", "reload"])
  errors = run(["hyprctl", "configerrors"])
  if errors and errors != previous_errors and errors != "no errors":
    raise RuntimeError(errors)


def apply(payload, consent=False):
  require_consent(consent)
  data = json.loads(payload)
  layouts = data.get("layouts") or []
  options = data.get("options") or []
  if not isinstance(layouts, list) or not layouts or len(layouts) > 4:
    raise ValueError("Escolha entre 1 e 4 layouts")
  if not isinstance(options, list) or len(options) > 16:
    raise ValueError("Opções inválidas")

  known_layouts, known_variants, known_options = xkb_catalog()
  parts = []
  for item in layouts:
    if not isinstance(item, str):
      raise ValueError("Layout inválido")
    layout, _, variant = item.partition(":")
    if layout not in known_layouts or not TOKEN.match(layout):
      raise ValueError(f"Layout desconhecido: {layout}")
    if variant and (item not in known_variants or not TOKEN.match(variant)):
      raise ValueError(f"Variante desconhecida: {item}")
    parts.append((layout, variant))
  if parts[0][0] in NON_LATIN:
    parts = [("us", "")] + [p for p in parts if p != ("us", "")]

  clean = []
  for opt in options:
    if not isinstance(opt, str) or opt not in known_options or not re.match(r"^[a-z0-9_]+:[a-z0-9_]+$", opt):
      raise ValueError(f"Opção desconhecida: {opt}")
    if opt not in clean:
      clean.append(opt)
  if len(parts) > 1 and not any(o.startswith("grp:") for o in clean):
    clean.append("grp:alts_toggle")
  if len(parts) == 1:
    clean = [o for o in clean if not o.startswith("grp:")]

  if input_override():
    raise RuntimeError("hypr/input.lua define kb_layout/kb_variant e tem prioridade; remova essas linhas")

  originals = {p: read(p) for p in (LAYOUTS_FILE, OPTIONS_FILE, INPUT_LUA)}
  backup(list(originals))
  previous_errors = run(["hyprctl", "configerrors"])
  try:
    atomic_write(LAYOUTS_FILE, "XKBLAYOUT={}\nXKBVARIANT={}\n".format(
      ",".join(p[0] for p in parts), ",".join(p[1] for p in parts)))
    atomic_write(OPTIONS_FILE, options_lua(clean))
    ensure_require()
    reload_checked(previous_errors)
    expected = [l + (":" + v if v else "") for l, v in parts]
    if live_layouts() != expected:
      raise RuntimeError("O Hyprland não aceitou o layout (outra configuração tem prioridade)")
  except BaseException:
    for path, text in originals.items():
      restore(path, text)
    try:
      run(["hyprctl", "reload"])
    finally:
      raise

  try:
    sync_fcitx(parts[0][0] + (":" + parts[0][1] if parts[0][1] else ""))
  except (OSError, subprocess.CalledProcessError, ValueError, KeyError) as error:
    print(f"fcitx5 não sincronizado: {error}", file=sys.stderr)
  status()


def reset(consent=False):
  """Back to the layout picked at install time (/etc/vconsole.conf)."""
  require_consent(consent)
  originals = {p: read(p) for p in (LAYOUTS_FILE, OPTIONS_FILE)}
  backup(list(originals))
  previous_errors = run(["hyprctl", "configerrors"])
  try:
    LAYOUTS_FILE.unlink(missing_ok=True)
    OPTIONS_FILE.unlink(missing_ok=True)
    reload_checked(previous_errors)
  except BaseException:
    for path, text in originals.items():
      restore(path, text)
    run(["hyprctl", "reload"])
    raise
  status()


def console(keymap):
  if not re.match(r"^[A-Za-z0-9_-]+$", keymap):
    raise ValueError("Keymap inválido")
  known = run(["localectl", "list-keymaps"]).splitlines()
  if keymap not in known:
    raise ValueError(f"Keymap de console desconhecido: {keymap}")
  run(["pkexec", "localectl", "set-keymap", "--no-convert", keymap])
  print(json.dumps({"console": keymap}))


def main():
  args = sys.argv[1:]
  try:
    if args == ["status"]:
      status()
    elif args[:1] == ["apply"] and len(args) in (2, 3) and args[2:] in ([], ["--consent"]):
      apply(args[1], consent=len(args) == 3)
    elif args[:1] == ["reset"] and args[1:] in ([], ["--consent"]):
      reset(consent=len(args) == 2)
    elif len(args) == 2 and args[0] == "console":
      console(args[1])
    else:
      raise ValueError(__doc__.strip())
  except subprocess.CalledProcessError as error:
    print((error.stderr or str(error)).strip(), file=sys.stderr)
    sys.exit(1)
  except (OSError, ValueError, RuntimeError, PermissionError, json.JSONDecodeError) as error:
    print(str(error), file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
  main()
