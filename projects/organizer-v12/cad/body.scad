// organizer-v12 / body
// 3D AI Designer V1.1 Geometry Engine uretimi - tum olculer mm.

// ============ PARAMETERS ============
width = 120;
depth = 80;
height = 40;
$fn = 96;  // dairesel yuzey cozunurlugu (bbox dogrulugu icin)
wall_thickness = 2;
divider_1_x = 39.3333333333333;
divider_1_w = 2;
divider_2_x = 78.6666666666667;
divider_2_w = 2;

// ============ GEOMETRY + BOOLEAN OPERATIONS ============
union() { difference() { cube([120, 80, 40]); translate([2, 2, 2]) cube([116, 76, 39]); } translate([39.3333333333333, 2, 2]) { cube([2, 76, 38]); } translate([78.6666666666667, 2, 2]) { cube([2, 76, 38]); } }

// ============ ASSEMBLY / NOTLAR ============
// NOT: assembly metadata: validation disi (simulasyon yok)

// ============ EXPORT ============
// Export harici arac ile yapilir (Export-Stl.ps1).
