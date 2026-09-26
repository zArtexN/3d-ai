// Faz 3 test modeli — parametrik, tum olculer mm cinsinden.
// KURAL: kullanicinin verdigi olcu degistirilmedi; delik merkezi sorularak tamamlandi.

// PARAM: olculer (kaynak her satirda belirtilir)
width = 80;             // mm (kullanici: govde X)
depth = 40;             // mm (kullanici: govde Y)
height = 20;            // mm (kullanici: govde Z)
wall_thickness = 2;     // mm (kullanici: en az kenar boslugu sarti)
hole_diameter = 25;     // mm (kullanici: tam gecisli delik capi, Z ekseni)
hole_x = 15;            // mm (sorularak: delik merkezi X, referans koseden)
hole_y = 15;            // mm (sorularak: delik merkezi Y, referans koseden)

$fn = 96;

difference() {
    // Govde: tablaya oturan en genis yuz altta (Z=0)
    cube([width, depth, height]);
    // Tam gecisli delik: Z ekseni boyunca, govdeyi iki yonden de tasarak keser
    translate([hole_x, hole_y, -1])
        cylinder(d = hole_diameter, h = height + 2);
}
