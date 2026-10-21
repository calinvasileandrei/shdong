"""Interactive 3D preview of the keychain with both RP2040-Zero boards mounted.

Run: .venv/bin/python preview.py  ->  out/preview.html (open in a browser)
Board details are approximate (PCB, USB-C, buttons, LED, chips) for fit checks.
"""
import base64
import json
import tempfile
from pathlib import Path

from build123d import *

g = __import__("runpy").run_path(str(Path(__file__).with_name("enclosure.py")))
PCB_L, PCB_W, PCB_T, USB_H = g["PCB_L"], g["PCB_W"], g["PCB_T"], g["USB_H"]


def board():
    """RP2040-Zero, USB edge at x=0, PCB bottom at z=0, components up."""
    parts = {"pcb": Pos(PCB_L / 2, 0, PCB_T / 2) * Box(PCB_L, PCB_W, PCB_T)}
    usb = Pos(0, 0, PCB_T + USB_H / 2) * Rot(0, 90, 0) * extrude(SlotOverall(8.94, USB_H, rotation=90), 7.35)
    parts["metal"] = usb
    parts["button"] = Pos(14.5, 4.2, PCB_T + 0.8) * Box(3.4, 4.2, 1.6) + Pos(17.5, -3.5, PCB_T + 0.8) * Box(3.4, 4.2, 1.6)
    chips = Pos(10.5, -1.5, PCB_T + 0.45) * Box(3.9, 3.0, 0.9)  # flash
    chips += Pos(13, 0, -0.45) * Box(7, 7, 0.9)  # RP2040, underside
    parts["chip"] = chips
    parts["led"] = Pos(14.5, -0.5, PCB_T + 0.5) * Box(1.6, 1.6, 1.0)
    pads = None
    for i in range(9):
        for sy in (-1, 1):
            p = Pos(1.5 + 2.54 * i, sy * (PCB_W / 2 - 0.6), PCB_T + 0.02) * Cylinder(0.55, 0.04)
            pads = p if pads is None else pads + p
    parts["pad"] = pads
    return parts


cav_x0 = g["cav_x0"]
c_pcb, t_pcb, TAPE = g["c_pcb"], g["t_pcb"], g["TAPE"]
board_c = {k: Pos(cav_x0, 0, c_pcb + PCB_T) * Rot(180, 0, 0) * v for k, v in board().items()}  # components down
board_t = {k: Pos(cav_x0, 0, t_pcb) * v for k, v in board().items()}  # components up
foam = sum(
    (Pos(cav_x0 + x, 0, c_pcb + PCB_T + TAPE / 2) * Box(4, 14, TAPE) for x in (3.5, PCB_L - 3)),
    start=Part(),
)

# Fit check: boards must not touch the case
for name, b in (("C", board_c), ("T", board_t)):
    for k, v in b.items():
        for case_name in ("bottom", "top"):
            hit = v & g[case_name]
            vol = 0 if hit is None or not hit.solids() else hit.volume
            if vol > 1e-3:
                print(f"COLLISION board {name} {k} with {case_name}: {vol:.3f} mm3")

# Link wires (30 AWG) soldered to the castellated edge pads, routed through the gap between
# the boards. Pads (x from the USB edge): GP0 = 1st, GP1 = 2nd on one side, GND = 2nd on the
# other. Board C is flipped, so its sides are mirrored: every wire crosses over, in the free
# band between the USB-end foam pad and the RP2040s.
def wire(pts, r=0.25):
    w = Part()
    for a, b in zip(pts, pts[1:]):
        a, b = Vector(*a), Vector(*b)
        w += Solid.make_cylinder(r, (b - a).length, Plane(a, z_dir=b - a))
    for p in pts:
        w += Pos(*p) * Sphere(r)
    return w


edge = PCB_W / 2
split = g["split"]
pad1, pad2 = cav_x0 + 1.5, cav_x0 + 1.5 + 2.54
t_mid, c_mid = t_pcb + PCB_T / 2, c_pcb + PCB_T / 2


def link(x_from, y_from, z_from, x_to, y_to, z_to, cross_x, lane):
    s_from, s_to = (1 if y_from > 0 else -1), (1 if y_to > 0 else -1)
    return wire([
        (x_from, y_from, z_from), (x_from, s_from * (edge + 0.3), split),
        (x_from, s_from * lane, split), (cross_x, s_from * lane, split),
        (cross_x, s_to * lane, split), (x_to, s_to * lane, split),
        (x_to, s_to * (edge + 0.3), split), (x_to, y_to, z_to),
    ])


band = cav_x0 + 7.5 - 1.0  # between foam (ends at 5.5) and RP2040 (starts at 9.5)
wires = {
    "wire_tx": link(pad1, edge, t_mid, pad2, -edge, c_mid, band, 8.4),  # T GP0 -> C GP1
    "wire_rx": link(pad1, -edge, c_mid, pad2, edge, t_mid, band + 0.9, 7.8),  # C GP0 -> T GP1
    "wire_gnd": link(pad2, -edge, t_mid, pad2, edge, c_mid, band + 1.8, 7.2),  # T GND -> C GND
}
for k, v in wires.items():
    for case_name in ("bottom", "top"):
        hit = v & g[case_name]
        if hit is not None and hit.solids() and hit.volume > 1e-3:
            print(f"COLLISION {k} with {case_name}: {hit.volume:.3f} mm3")

groups = {"base": [g["bottom"]], "lid": [g["top"]], "foam": [foam]} | {k: [v] for k, v in wires.items()}
groups |= {f"c_{k}": [v] for k, v in board_c.items()}
groups |= {f"t_{k}": [v] for k, v in board_t.items()}
blobs = {}
with tempfile.TemporaryDirectory() as tmp:
    for name, shapes in groups.items():
        f = Path(tmp) / f"{name}.stl"
        export_stl(Compound(shapes), str(f), tolerance=0.02, angular_tolerance=0.15)
        blobs[name] = base64.b64encode(f.read_bytes()).decode()

dims = f'{g["outer_l"]:.1f} × {g["outer_w"]:.1f} × {g["outer_h"]:.1f} mm'
html = (Path(__file__).with_name("preview_template.html").read_text()
        .replace("__DATA__", json.dumps(blobs)).replace("__DIMS__", dims)
        .replace("__SPLIT__", f'{g["split"]:.3f}'))
out = Path(__file__).parent / "out" / "preview.html"
out.write_text(html)
print("wrote", out)
