// proje-20260928-232228 / body
// 3D AI Designer V1.1 Geometry Engine uretimi - tum olculer mm.

// ============ PARAMETERS ============
width = 50;
depth = 50;
height = 10;
$fn = 96;  // dairesel yuzey cozunurlugu (bbox dogrulugu icin)
hole_h1_dia = 10;
hole_h1_x = 15;
hole_h1_y = 15;

// ============ GEOMETRY + BOOLEAN OPERATIONS ============
difference() { cube([50, 50, 10]); translate([15, 15, -1]) cylinder(d = 10, h = 12); }

// ============ EXPORT ============
// Export harici arac ile yapilir (Export-Stl.ps1).
