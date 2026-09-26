// demo-kutu - Design Engine uretimi, tum olculer mm.
// Kaynak: input.json (kullanici degerleri degistirilmedi).

// PARAM
width = 80;
depth = 40;
height = 20;
wall_thickness = 2;
hole_diameter = 25;
hole_x = 15;
hole_y = 15;

$fn = 96;

difference() {
    cube([width, depth, height]);
    translate([15, 15, -1])
        cylinder(d = 25, h = height + 2);
}
