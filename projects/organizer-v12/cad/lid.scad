// organizer-v12 / lid
// 3D AI Designer V1.1 Geometry Engine uretimi - tum olculer mm.

// ============ PARAMETERS ============
clearance = 0.2;  // fit_to body
width = 119.6;
depth = 79.6;
height = 5;
$fn = 96;  // dairesel yuzey cozunurlugu (bbox dogrulugu icin)
hole_h1_dia = 5;
hole_h1_x = 15;
hole_h1_y = 15;
hole_h2_dia = 5;
hole_h2_x = 105;
hole_h2_y = 15;

// ============ GEOMETRY + BOOLEAN OPERATIONS ============
difference() { cube([119.6, 79.6, 5]); translate([15, 15, -1]) cylinder(d = 5, h = 7); translate([105, 15, -1]) cylinder(d = 5, h = 7); }

// ============ ASSEMBLY / NOTLAR ============
// NOT: assembly metadata: validation disi (simulasyon yok)

// ============ EXPORT ============
// Export harici arac ile yapilir (Export-Stl.ps1).
