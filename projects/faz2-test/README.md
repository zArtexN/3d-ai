# Faz 2 Test — Prizma + Delik

## Kaynak prompt (degistirilmeden)
> 50 × 50 × 10 mm dikdörtgen prizma, bir köşesinde 10 mm çapında tam delik. Tüm ölçüler milimetre. Parametrik OpenSCAD modeli. Sadece zincir testi: Prompt → OpenSCAD → SCAD → STL. Henüz OrcaSlicer ile G-code oluşturma.

## Kullanilan olculer (mm)
| Olcu | Deger | Kaynak |
| ---- | ----- | ------ |
| Prizma X (genislik) | 50 | kullanici |
| Prizma Y (derinlik) | 50 | kullanici |
| Prizma Z (yukseklik) | 10 | kullanici |
| Delik capi (tam delik, Z ekseni) | 10 | kullanici |
| Delik merkezi X (referans koseden) | 15 | sorularak tamamlandi |
| Delik merkezi Y (referans koseden) | 15 | sorularak tamamlandi |

## Varsayilanlar (kritik olmayan, uydurulmayan)
- `$fn = 64` (delik yuvarlaklik cozunurlugu, teknik detay — baski olcusu degil)

## Malzeme
- belirtilmedi

## Baski yonu + gerekce
- Yon: 50 × 50 yuzeyi altta (Z=0).
- Gerekce: tablaya oturan en genis duz yuzey; prizma desteksiz durur, 10 mm dikey delik koprusuz basilir.

## Destek gereksinimi
- Destek: gerekli degil
- Neden: tum yuzeyler yatay/dikey; overhang yok, delik ekseni Z ile ayni.

## Bilinen riskler
- `printers/generic-fdm.json` placeholder profildir; gercek yazici profili eklenmeden formal basilabilirlik onayi ve slicing YAPILMAZ (bu testte slicing yok).
- OpenSCAD 2021.01 eski surumdur; karmasik modellerde guncel surum gerekebilir.

## Dosyalar
- `cad/model.scad` (parametrik kaynak)
- `output/model.stl` (43.982 bayt, 272 facet, bbox 50 × 50 × 10)
- `output/model.3mf` (4.249 bayt, Export-Stl.ps1 ile birlikte uretildi)
- `slice/` — yok (Faz 2 kapsaminda G-code uretilmedi)

## Basilabilirlik kontrolu
- Yazici profili: `printers/generic-fdm.json` (placeholder — formal onay yerine gecer)
- Sanity kontrol (placeholder limitlere gore): duvar 10 mm >= 1.2 ✅ · delik 10 mm >= 2.0 ✅ · olcu 50 × 50 × 10 tabla 220 × 220 × 250 icinde ✅
- Sonuc: gecti (sanity; gercek profil ile tekrarlanmali)
