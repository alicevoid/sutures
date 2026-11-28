"""Fit VPinballX.ini to one monitor, then exec the given command."""
import os
import re
import subprocess
import sys
from pathlib import Path

REF_W, REF_H = 3456, 2160
GUTTER, TOP = 24, 64
# Overlay inner edge to screen center, in screen heights. Measured on BK SoR.
CLEAR = 0.315

# (prefix, x anchor, y, width, height) in athreos pixels.
OVERLAYS = [
    ("PUPBackglassWindow", "left", TOP, 1024, 576),
    ("PUPDMDWindow", "left", 664, 896, 504),
    ("B2SBackglass", "right", TOP, 1000, 614),
]
SIDE = GUTTER + max(ow for *_, ow, _ in OVERLAYS)

# Table inis override VPinballX.ini.
MANAGED = {
    f"{p}{k}".lower()
    for p, *_ in OVERLAYS
    for k in ("X", "Y", "Width", "Height")
}

STATE = Path(os.environ.get("PINBALL_STATE_DIR")
             or Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "pinball")
INI = Path.home() / ".vpinball/VPinballX.ini"


def monitors():
    out = subprocess.run(["xrandr", "--query"], capture_output=True, text=True, check=True).stdout
    mons = []
    for m in re.finditer(r"^(\S+) connected (primary )?(\d+)x(\d+)\+(\d+)\+(\d+)", out, re.M):
        name, prim, w, h, x, y = m.groups()
        mons.append((name, int(x), int(y), int(w), int(h), bool(prim)))
    return mons


def pick(mons):
    forced = os.environ.get("VPX_LAYOUT_OUTPUT")
    if forced:
        return next(m for m in mons if m[0] == forced)
    external = [m for m in mons if not m[0].startswith(("eDP", "LVDS", "DSI"))]
    return (external or mons)[0]


def sdl_index(mons, chosen):
    # SDL on X11 lists the primary output first, then the others in xrandr order.
    order = sorted(mons, key=lambda m: not m[5])
    return order.index(chosen)


def set_keys(path, section, values):
    # configparser drops the ini comments.
    lines = path.read_text().splitlines(keepends=True)
    todo = dict(values)
    out, in_sec = [], False
    for line in lines:
        s = line.strip()
        if s.startswith("["):
            if in_sec:
                out += [f"{k} = {v}\n" for k, v in todo.items()]
                todo = {}
            in_sec = s == f"[{section}]"
        elif in_sec and "=" in s and not s.startswith((";", "#")):
            key = s.split("=", 1)[0].strip()
            if key in todo:
                line = f"{key} = {todo.pop(key)}\n"
        out.append(line)
    if todo:
        if not in_sec:
            out.append(f"\n[{section}]\n")
        out += [f"{k} = {v}\n" for k, v in todo.items()]
    path.write_text("".join(out))


def drop_managed(path):
    lines = path.read_text().splitlines(keepends=True)
    keep = [l for l in lines
            if not ("=" in l and l.split("=", 1)[0].strip().lower() in MANAGED
                    and not l.lstrip().startswith((";", "#")))]
    if keep != lines:
        path.write_text("".join(keep))


def main():
    mons = monitors()
    chosen = pick(mons)
    _, ox, oy, w, h, _ = chosen
    s = min(h / REF_H, (w / 2 - CLEAR * h) / SIDE)

    values = {}
    for prefix, anchor, y, ow, oh in OVERLAYS:
        sw, sh = round(ow * s), round(oh * s)
        x = round(GUTTER * s) if anchor == "left" else w - round(GUTTER * s) - sw
        values.update({f"{prefix}X": ox + x, f"{prefix}Y": oy + round(y * s),
                       f"{prefix}Width": sw, f"{prefix}Height": sh})

    if INI.exists():
        # Copied read-only from the store.
        INI.chmod(0o644)
        # 1 (threaded) breaks the ImGui menu shaders.
        set_keys(INI, "Standalone", {**values, "WindowRenderMode": 0})
        # 1 can leave the window under the GNOME top bar.
        set_keys(INI, "Player", {"Display": sdl_index(mons, chosen), "FullScreen": 0,
                                 "WindowPosX": ox, "WindowPosY": oy, "Width": w, "Height": h})
        print(f"vpx-layout: {chosen[0]} {w}x{h}+{ox}+{oy}, scale {s:.3f}", file=sys.stderr)
    # A table's first launch still uses its own geometry.
    for table_ini in STATE.glob("*/*.ini"):
        drop_managed(table_ini)

    if len(sys.argv) > 1:
        os.execvp(sys.argv[1], sys.argv[1:])


if __name__ == "__main__":
    main()
