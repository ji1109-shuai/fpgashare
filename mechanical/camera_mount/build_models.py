"""Generate prototype SCAD/STL files. Requires numpy, manifold3d and Pillow.

Run from any directory: python build_models.py
Measured dimensions and provisional fit allowances live in parameters.json.
"""
import json
import math
import struct
from pathlib import Path

import numpy as np
from manifold3d import Error, Manifold
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
P = json.loads((ROOT / "parameters.json").read_text(encoding="utf-8"))
N = P["segments"]
POSITIONS = [(sx * P["hole_pitch_x"] / 2, sy * P["hole_pitch_y"] / 2)
             for sx in (-1, 1) for sy in (-1, 1)]
OD = P["ring_id"] - P["diametral_clearance"]
Z = P["ring_height"] + P["flange_thickness"]


def cylinder(d, h, z=0, segments=N):
    return Manifold.cylinder(h, d / 2, circular_segments=segments).translate((0, 0, z))


def annulus(od, inner, h, z=0):
    return cylinder(od, h, z) - cylinder(inner, h + 2, z - 1)


def make_part(part):
    if part == "hole_coupon":
        s = Manifold.cube((40, 40, P["coupon_thickness"])).translate((-20, -20, 0))
        s = s - cylinder(P["lens_clearance_diameter"], 4, -1)
        for x, y in POSITIONS:
            s = s - cylinder(P["printed_screw_hole"], 4, -1).translate((x, y, 0))
        return s
    if part == "ring_coupon":
        return annulus(OD, P["lens_clearance_diameter"], 4) + annulus(
            P["flange_diameter"], P["lens_clearance_diameter"], 2, 4)
    s = annulus(OD, P["lens_clearance_diameter"], P["ring_height"])
    s = s + annulus(P["flange_diameter"], P["lens_clearance_diameter"],
                    P["flange_thickness"], P["ring_height"])
    for x, y in POSITIONS:
        s = s + cylinder(P["boss_diameter"], P["boss_height"], Z).translate((x, y, 0))
    for x, y in POSITIONS:
        s = s - cylinder(P["printed_screw_hole"], Z + P["boss_height"] + 2, -1).translate((x, y, 0))
        # Open-top pockets: insert four M2 nuts before placing the PCB.
        s = s - cylinder(P["nut_across_flats"] / math.cos(math.pi / 6),
                         P["nut_pocket_depth"] + 1,
                         Z + P["boss_height"] - P["nut_pocket_depth"], 6).translate((x, y, 0))
    return s


def export_stl(solid, path):
    assert solid.status() == Error.NoError, solid.status()
    assert solid.volume() > 0 and len(solid.decompose()) == 1
    mesh = solid.to_mesh()
    vertices = np.asarray(mesh.vert_properties)[:, :3].astype(float)
    faces = np.asarray(mesh.tri_verts)
    # Check closed triangle topology independently of the kernel's status.
    edge_counts = {}
    for f in faces:
        for a, b in zip(f, np.roll(f, -1)):
            edge = tuple(sorted((int(a), int(b))))
            edge_counts[edge] = edge_counts.get(edge, 0) + 1
    assert all(count == 2 for count in edge_counts.values()), "Non-manifold triangle edge"
    with path.open("wb") as stream:
        stream.write(b"FPGA camera mount: prototype, millimetres".ljust(80, b" "))
        stream.write(struct.pack("<I", len(faces)))
        for f in faces:
            tri = vertices[f]
            normal = np.cross(tri[1] - tri[0], tri[2] - tri[0])
            norm = np.linalg.norm(normal)
            assert norm > 1e-10
            normal /= norm
            stream.write(struct.pack("<12fH", *normal, *tri.flatten(), 0))
    assert path.stat().st_size == 84 + 50 * len(faces)
    bounds = [round(float(v), 3) for v in solid.bounding_box()]
    return {"file": path.name, "bounds_mm": bounds,
            "triangles": len(faces), "volume_mm3": round(solid.volume(), 2),
            "closed_mesh": True, "connected_components": 1}


def write_scad():
    header = '// Prototype only. Units: mm. Inspect fit before installing electronics.\n'
    header += '// Change part to camera_mount, hole_coupon or ring_coupon.\n'
    header += 'part = "camera_mount"; // [camera_mount,hole_coupon,ring_coupon]\n'
    header += '\n'.join(f'{key} = {json.dumps(value)};' for key, value in P.items())
    body = r'''
$fn = segments;
od = ring_id - diametral_clearance;
base_z = ring_height + flange_thickness;
module ring(outer, inner, h) {
    difference() {
        cylinder(d=outer,h=h);
        translate([0,0,-1]) cylinder(d=inner,h=h+2);
    }
}
module positions() {
    for(x=[-hole_pitch_x/2,hole_pitch_x/2])
        for(y=[-hole_pitch_y/2,hole_pitch_y/2]) translate([x,y,0]) children();
}
module camera_mount() {
    difference() {
        union() {
            ring(od,lens_clearance_diameter,ring_height);
            translate([0,0,ring_height]) ring(flange_diameter,lens_clearance_diameter,flange_thickness);
            positions() translate([0,0,base_z]) cylinder(d=boss_diameter,h=boss_height);
        }
        positions() translate([0,0,-1]) cylinder(d=printed_screw_hole,h=base_z+boss_height+2);
        positions() translate([0,0,base_z+boss_height-nut_pocket_depth])
            cylinder(d=nut_across_flats/cos(30),h=nut_pocket_depth+1,$fn=6);
    }
}
module hole_coupon() {
    difference() {
        translate([-20,-20,0]) cube([40,40,coupon_thickness]);
        translate([0,0,-1]) cylinder(d=lens_clearance_diameter,h=coupon_thickness+2);
        positions() translate([0,0,-1]) cylinder(d=printed_screw_hole,h=coupon_thickness+2);
    }
}
module ring_coupon() {
    ring(od,lens_clearance_diameter,4);
    translate([0,0,4]) ring(flange_diameter,lens_clearance_diameter,2);
}
assert(od > lens_clearance_diameter);
assert(nut_pocket_depth < boss_height);
if(part=="hole_coupon") hole_coupon();
else if(part=="ring_coupon") ring_coupon();
else if(part=="camera_mount") camera_mount();
else assert(false,"Unknown part");
'''
    (ROOT / "camera_mount.scad").write_text(header + '\n' + body, encoding="utf-8")


def preview(solids):
    # Orthographic, depth-sorted triangle illustration; not a load simulation.
    canvas = Image.new("RGB", (1500, 820), "#f3f5f7")
    draw = ImageDraw.Draw(canvas)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 22)
        title = ImageFont.truetype("C:/Windows/Fonts/msyhbd.ttc", 29)
    except OSError:
        font = title = ImageFont.load_default()
    draw.text((32, 24), "摄像头转接件 V0.1｜试装原型，尚未实物验证", font=title, fill="#182739")
    u = np.array([0.819152, -0.573576, 0])
    v = np.array([0.32899, 0.469846, -0.819152])
    depth = np.cross(u, v)
    light = np.array([-0.3, -0.5, 1.0]); light /= np.linalg.norm(light)
    labels = [("摄像头转接座", "外径41.4；插入段18；总高27 mm"),
              ("孔位试装片", "40×40×2；孔距31×31 mm"),
              ("圆环试装件", "外径41.4；短插入段4 mm")]
    for i, (name, solid) in enumerate(solids.items()):
        mesh = solid.to_mesh()
        vertices = np.asarray(mesh.vert_properties)[:, :3].astype(float)
        faces = np.asarray(mesh.tri_verts)
        points = np.stack([vertices @ u, vertices @ v], axis=1)
        center = (points.min(axis=0) + points.max(axis=0)) / 2
        points = (points - center) * 6.4 + np.array([250 + i * 500, 360])
        for f in sorted(faces, key=lambda face: float((vertices[face] @ depth).mean())):
            tri = vertices[f]
            normal = np.cross(tri[1]-tri[0], tri[2]-tri[0]); normal /= np.linalg.norm(normal)
            if float(normal @ depth) <= 1e-6:
                continue
            shade = 0.55 + 0.4 * max(0, float(normal @ light))
            colour = tuple(int(c * shade) for c in (72, 159, 211))
            draw.polygon([tuple(p) for p in points[f]], fill=colour)
        draw.text((35+i*500, 610), labels[i][0], font=title, fill="#182739")
        draw.text((35+i*500, 660), labels[i][1], font=font, fill="#344b60")
    draw.text((35, 740), "镜头通孔30 mm、支撑柱高度6 mm为暂定值；先验证孔位、圆环配合、元件避让和调焦空间。",font=font,fill="#344b60")
    canvas.save(ROOT / "preview.png")


if __name__ == "__main__":
    assert P["hole_pitch_x"] + P["pcb_hole_measured"] < P["pcb_size"]
    assert P["hole_pitch_y"] + P["pcb_hole_measured"] < P["pcb_size"]
    assert P["lens_clearance_diameter"] < OD
    assert P["nut_pocket_depth"] < P["boss_height"]
    solids = {name: make_part(name) for name in ["camera_mount", "hole_coupon", "ring_coupon"]}
    report = {"units": "mm", "status": "PROTOTYPE_NOT_PRINT_VALIDATED",
              "parameters": P, "parts": []}
    for name, solid in solids.items():
        report["parts"].append(export_stl(solid, ROOT / (name + ".stl")))
    write_scad()
    preview(solids)
    (ROOT / "validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n",encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
