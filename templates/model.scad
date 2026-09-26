// Parametrik model sablonu — tum olculer burada, mm cinsinden.
// KURAL: kullanicinin verdigi olcuyu degistirme; eksik kritik olcuyu uydurma, sor.

// PARAM: ornek — gercek projede kullanicinin olculeriyle degistir.
ornek_genislik = 20;   // mm (kullanicidan)
ornek_derinlik = 30;   // mm (kullanicidan)
ornek_yukseklik = 10;  // mm (kullanicidan)
duvar = 1.2;           // mm (printers/<yazici>.json -> min_wall_mm ile kontrol et)

$fn = 64;

module govde() {
    cube([ornek_genislik, ornek_derinlik, ornek_yukseklik]);
}

// Baski yonu: en genis duz yuz altta (Z=0). Nedeni README'ye yazilir.
govde();
