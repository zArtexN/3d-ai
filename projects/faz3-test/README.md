# Faz 3 Test — Govde + Tam Gecisli Delik (uretim akisi testi)

## Kaynak prompt (degistirilmeden)
> Ana govde: 80 x 40 x 20 mm. Duvar kalinligi: 2 mm. Ust yuzeyde tam gecisli 25 mm capinda delik. Delik merkezi kullanicinin ayrica belirtecegi bir deger olarak ele alinmali. Model parametrik olacak. Tum olculer milimetre.

## Kullanilan olculer (mm)
| Olcu | Deger | Kaynak |
| ---- | ----- | ------ |
| Govde X (`width`) | 80 | kullanici |
| Govde Y (`depth`) | 40 | kullanici |
| Govde Z (`height`) | 20 | kullanici |
| Duvar kalinligi (`wall_thickness`, en az kenar boslugu) | 2 | kullanici |
| Delik capi (`hole_diameter`, tam gecisli, Z ekseni) | 25 | kullanici |
| Delik merkezi X (`hole_x`, referans koseden) | 15 | sorularak tamamlandi |
| Delik merkezi Y (`hole_y`, referans koseden) | 15 | sorularak tamamlandi |

## Sorular ve Cevaplar
- Soru: Delik merkezi promptta yok ve kritik olcu oldugu icin uydurulamaz. Duvar kalinligi 2 mm oldugundan merkez kenarlardan en az 14.5 mm iceride olmali (12.5 yaricap + 2 duvar). Delik merkezi nereye koyulsun? (Secenekler: Merkez (40,20) / Kose yakin (25,20) / Kose yakin (20,20) / serbest deger)
- Cevap: "Delik merkezini kenarlardan 15 mm iceride yap." (kullanici) -> `hole_x = 15`, `hole_y = 15` olarak uygulandi.
- Kenar boslugu kontrolu: 15 - 12.5 = 2.5 mm >= 2 mm sarti saglaniyor.

## Varsayilanlar (kritik olmayan, uydurulmayan)
- `$fn = 96` (delik yuvarlaklik cozunurlugu, teknik detay — baski olcusu degil)

## Dogrulama sonuclari
- `scripts/Verify-Stl.ps1` ciktisi: VERIFY: PASS (ilk tur, exit 0)
- bbox gercek: X [0, 80] Y [0, 40] Z [0, 20] / beklenen: 80 x 40 x 20 — eslesiyor
- Kritik geometri (delik): rim alt=484 ust=484 (merkez 15,15 cap 25) — tam gecis dogrulandi
- facet: 400
- Duzeltme turu: gerekmedi

## Malzeme
- belirtilmedi

## Baski yonu + gerekce
- Yon: 80 x 40 yuzeyi altta (Z=0).
- Gerekce: tablaya oturan en genis duz yuzey; govde desteksiz durur, 25 mm dikey delik koprusuz basilir.

## Destek gereksinimi
- Destek: gerekli degil
- Neden: tum yuzeyler yatay/dikey; overhang yok, delik ekseni Z ile ayni.

## Bilinen riskler
- `printers/generic-fdm.json` placeholder profildir; gercek yazici profili eklenmeden formal basilabilirlik onayi ve slicing YAPILMAZ (bu fazda G-code yok).
- 25 mm capli dikey delik genis bir acikliktir; gercek profil ile kopru/delik tolerans kurali tekrar degerlendirilmeli.

## Dosyalar
- `cad/model.scad` (parametrik kaynak)
- `output/model.stl` (64.965 bayt, 400 facet, bbox 80 x 40 x 20)
- `output/model.3mf` (5.636 bayt, Export-Stl.ps1 ile birlikte uretildi)
- `slice/` — yok (Faz 3 kapsaminda G-code uretilmedi)

## Basilabilirlik kontrolu
- Yazici profili: `printers/generic-fdm.json` (placeholder — formal onay yerine gecer)
- Sanity kontrol (placeholder limitlere gore): en dar duvar 2.5 mm >= 1.2 ✅ · delik 25 mm >= 2.0 ✅ · olcu 80 x 40 x 20 tabla 220 x 220 x 250 icinde ✅
- Sonuc: gecti (sanity; gercek profil ile tekrarlanmali)
