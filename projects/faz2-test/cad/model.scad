// Faz 2 test modeli — parametrik, tum olculer mm cinsinden.
// KURAL: kullanicinin verdigi olcu degistirilmedi; delik konumu sorularak tamamlandi.

// PARAM: kullanicidan / sorularak tamamlanan olculer
plaka_genislik = 50;    // mm (kullanici: prizma X)
plaka_derinlik = 50;    // mm (kullanici: prizma Y)
plaka_yukseklik = 10;   // mm (kullanici: prizma Z)
delik_cap = 10;         // mm (kullanici: tam delik capi)
delik_x = 15;           // mm (sorularak: delik merkezi X, referans koseden)
delik_y = 15;           // mm (sorularak: delik merkezi Y, referans koseden)

$fn = 64;

difference() {
    // Govde: tablaya oturan en genis yuz altta (Z=0)
    cube([plaka_genislik, plaka_derinlik, plaka_yukseklik]);
    // Tam delik: Z ekseni boyunca, govdeyi iki yonden de tasarak keser
    translate([delik_x, delik_y, -1])
        cylinder(d = delik_cap, h = plaka_yukseklik + 2);
}
