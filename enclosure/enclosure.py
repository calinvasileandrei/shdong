"""shdong keychain: two RP2040-Zero boards stacked back to back, both USB-C at one end.

Board C (controller) lies components-down, board T (target/sharer) components-up,
PCBs joined by 2 mm foam pads at the ends (the RP2040s, on the underside,
face each other in the gap). Clamshell split
between the PCBs; the lid snaps onto a tongue. Lanyard hole in the far corner.
Run: .venv/bin/python enclosure.py [--show]  ->  out/*.stl, out/enclosure.step
"""
import sys
from pathlib import Path

from build123d import *

# --- Board (Waveshare RP2040-Zero) ---
PCB_L, PCB_W, PCB_T = 23.5, 18.0, 1.0
USB_H, USB_W = 3.2, 9.0  # receptacle height above PCB, width
TAPE = 2.0  # foam pads between the PCBs; clears both RP2040s (on the underside, 0.9 mm each)
SIDE_FIT = 0.8  # each side: room for the link wires along the board edges
END_FIT = 0.2

# --- Case ---
WALL, PORT_WALL, SKIN = 1.6, 1.2, 1.0  # side walls, port end wall, floor/roof
END_WALL = 4.0  # far end: thick enough for the diagonal lanyard tunnel
TIP = 0.15  # clearance below/above the receptacles
LANYARD_D, LANYARD_WALL = 1.6, 0.6  # diagonal tunnel through the far corner, for a cord
R_VERT, R_EDGE = 4.0, 1.8

# --- Lid joint ---
TONGUE_T, TONGUE_H, JOINT_FIT = 0.7, 1.4, 0.15

inner_w = PCB_W + 2 * SIDE_FIT
cav_x0 = PORT_WALL
cav_x1 = cav_x0 + PCB_L + END_FIT
cav_l = cav_x1 - cav_x0
cav_mid = (cav_x0 + cav_x1) / 2
outer_l = cav_x1 + END_WALL
outer_w = inner_w + 2 * WALL

c_usb = SKIN + TIP + USB_H / 2  # board C receptacle centre (hangs below its PCB)
c_pcb = SKIN + TIP + USB_H  # board C PCB bottom
split = c_pcb + PCB_T + TAPE / 2
t_pcb = c_pcb + PCB_T + TAPE  # board T PCB bottom
t_usb = t_pcb + PCB_T + USB_H / 2
ceiling = t_pcb + PCB_T + USB_H + TIP
outer_h = ceiling + SKIN

# Outer body: rounded fob
body = Pos(outer_l / 2, 0, 0) * extrude(RectangleRounded(outer_l, outer_w, R_VERT), outer_h)
body = fillet(body.faces().sort_by(Axis.Z)[0].edges() + body.faces().sort_by(Axis.Z)[-1].edges(), R_EDGE)
body -= Pos(cav_mid, 0, SKIN) * extrude(RectangleRounded(cav_l, inner_w, 0.8), ceiling - SKIN)

# Two stacked USB-C openings with a soft flare
for z in (c_usb, t_usb):
    body -= Pos(0, 0, z) * Rot(0, 90, 0) * extrude(SlotOverall(9.3, 3.5, rotation=90), PORT_WALL + 0.6, both=True)
    body -= Pos(0, 0, z) * Rot(0, 90, 0) * extrude(SlotOverall(9.9, 4.1, rotation=90), 0.3, both=True)

# Lanyard tunnel cutting diagonally across the far corner of the base, side face to end face
corner_c = Vector(outer_l - R_VERT, outer_w / 2 - R_VERT)
lanyard_c = corner_c + Vector(1, 1) * ((R_VERT - LANYARD_WALL - LANYARD_D / 2) / 2**0.5)
lanyard_z = (SKIN + split) / 2
body -= Pos(lanyard_c.X, lanyard_c.Y, lanyard_z) * Rot(0, 0, -45) * Rot(0, 90, 0) * Cylinder(LANYARD_D / 2, 2 * R_VERT)

# Fingernail notch across the seam, one long side
body -= Pos(cav_x0 + 12, -outer_w / 2, split) * Rot(0, 90, 0) * Cylinder(0.9, 8)

bottom = body.split(Plane.XY.offset(split), keep=Keep.BOTTOM)
top = body.split(Plane.XY.offset(split), keep=Keep.TOP)

# Supports: cradle under C's receptacle and pads under its far end; mirrored in the lid for T
cradle_x = cav_x0 + 3.5
pad_x = cav_x1 - 2.5
bottom += Pos(cradle_x, 0, SKIN + TIP / 2) * Box(5, USB_W - 1, TIP)
top += Pos(cradle_x, 0, ceiling - TIP / 2) * Box(5, USB_W - 1, TIP)
for sy in (-1, 1):
    bottom += Pos(pad_x, sy * (PCB_W / 2 - 1.5), (SKIN + c_pcb) / 2) * Box(3, 2.5, c_pcb - SKIN)
    top += Pos(pad_x, sy * (PCB_W / 2 - 1.5), (t_pcb + PCB_T + ceiling) / 2) * Box(3, 2.5, ceiling - t_pcb - PCB_T)

# Tongue on the long sides and far end, snap ridges on the long sides
ring_o = RectangleRounded(cav_l + 2 * TONGUE_T, inner_w + 2 * TONGUE_T, 0.8 + TONGUE_T)
tongue = Pos(cav_mid, 0, split) * extrude(ring_o - RectangleRounded(cav_l, inner_w, 0.8), TONGUE_H)
tongue -= Pos(cav_x0, 0, split) * Box(6, outer_w, 10)  # clear the port end
ridge_y = inner_w / 2 + TONGUE_T
ridge_z = split + TONGUE_H * 0.55
for sy in (-1, 1):
    tongue += Pos(cav_mid + 2, sy * ridge_y, ridge_z) * Rot(0, 90, 0) * Cylinder(0.25, 12)
bottom += tongue

groove = RectangleRounded(
    cav_l + 2 * (TONGUE_T + JOINT_FIT), inner_w + 2 * (TONGUE_T + JOINT_FIT), 0.8 + TONGUE_T + JOINT_FIT
)
groove = Pos(cav_mid, 0, split) * extrude(groove, TONGUE_H + JOINT_FIT)
top -= groove - Pos(cav_x0, 0, split) * Box(6 - 2 * JOINT_FIT, outer_w, 10)  # keep the port wall intact
for sy in (-1, 1):
    top -= Pos(cav_mid + 2, sy * ridge_y, ridge_z) * Rot(0, 90, 0) * Cylinder(0.3, 13)

# Labels: top face = upper port (Sharer), bottom face = lower port (Controller)
top -= extrude(Pos(cav_mid, 0, outer_h) * Text("SHARER", font_size=2.6, font_style=FontStyle.BOLD), -0.4)
bottom -= extrude(
    Pos(cav_mid, 0, 0) * Rot(180, 0, 0) * Text("CONTROLLER", font_size=2.6, font_style=FontStyle.BOLD), -0.4
)

out = Path(__file__).parent / "out"
out.mkdir(exist_ok=True)
export_stl(bottom, str(out / "bottom.stl"))
export_stl(Rot(180, 0, 0) * top, str(out / "lid.stl"))  # print roof-down
export_step(Compound([bottom, top]), str(out / "enclosure.step"))
print(f"outer {outer_l:.1f} x {outer_w:.1f} x {outer_h:.1f} mm, split at z={split:.1f}")

if "--show" in sys.argv:
    from ocp_vscode import show  # needs the OCP CAD Viewer extension running

    show(bottom, Pos(0, 0, 15) * top)
