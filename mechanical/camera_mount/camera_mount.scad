// Prototype only. Units: mm. Inspect fit before installing electronics.
// Change part to camera_mount, hole_coupon or ring_coupon.
part = "camera_mount"; // [camera_mount,hole_coupon,ring_coupon]
pcb_size = 34.0;
hole_pitch_x = 31.0;
hole_pitch_y = 31.0;
pcb_hole_measured = 2.0;
ring_id = 42.0;
ring_height = 18.0;
diametral_clearance = 0.6;
lens_clearance_diameter = 30.0;
flange_diameter = 52.0;
flange_thickness = 3.0;
boss_height = 6.0;
boss_diameter = 6.5;
printed_screw_hole = 2.3;
nut_across_flats = 4.2;
nut_pocket_depth = 2.0;
coupon_thickness = 2.0;
segments = 128;

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
