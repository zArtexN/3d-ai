// organizer-v12 / body
// 3D AI Designer V1.1 Geometry Engine uretimi - tum olculer mm.

// ============ PARAMETERS ============
width = 120;
depth = 80;
height = 40;
$fn = 96;  // dairesel yuzey cozunurlugu (bbox dogrulugu icin)
wall_thickness = 2;

// ============ GEOMETRY + BOOLEAN OPERATIONS ============
difference() { cube([120, 80, 40]); translate([2, 2, 2]) cube([116, 76, 39]); }

// ============ ASSEMBLY / NOTLAR ============
// NOT: assembly metadata: validation disi (simulasyon yok)

// ============ EXPORT ============
// Export harici arac ile yapilir (Export-Stl.ps1).
