# demo-kutu (Design Engine)

## Kaynak prompt (degistirilmeden)
> 80x40x20 mm kutu govde, duvar 2 mm, ustte tam gecisli 25 mm delik, merkez kenarlardan 15 mm iceride.

## Kullanilan olculer (mm)
| Olcu | Deger | Kaynak |
| ---- | ----- | ------ |
| Govde | 80 x 40 x 20 | kullanici |
| Duvar kalinligi | 2 | kullanici |
| Delik h1 | cap 25, merkez (15,15) | kullanici |

## Dogrulama sonuclari
- Engine status: PASS (tur sayisi: 1)
- Design validation: OK_WITH_WARNINGS
  - WARNING: tolerans belirtilmedi (tolerance_mm null); gecme payi gerekiyorsa sorulmali
- STL verify ciktisi asagida; detay: validation/validation.json
---
format: ascii (64965 bayt)
bbox: X [0, 80]  Y [0, 40]  Z [0, 20]
facet: 400
delik rim: alt=484 ust=484 (merkez 15,15 cap 25)
VERIFY: PASS

---

## Dosyalar
- input.md (orijinal prompt), input.json (normalize veri)
- cad/model.scad (parametrik kaynak)
- output/model.stl, output/model.3mf
- validation/validation.json (makine raporu)
- slice/ : yok (G-code uretilmedi)

## Malzeme
- belirtilmedi
