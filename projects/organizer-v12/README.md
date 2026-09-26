# organizer-v12 (Geometry Engine V1.1)

## Kaynak prompt (degistirilmeden)
> 120x80x40 mm ölçülerinde masaüstü organizer yap. Duvar kalınlığı 2 mm olsun. İçinde iki bölme olsun. Kapak ayrı parça olsun. Kapak ile gövde arasında 0.2 mm boşluk bırak. Kapakta 5 mm çapında iki delik olsun ve delikler yan kenarlardan 15 mm içeride bulunsun.

## Parcalar
| Parca | Durum | bbox min | bbox max | STL |
| ----- | ----- | -------- | -------- | --- |
| body | PASS | 0, 0, 0 | 120, 80, 40 | output/body.stl |
| div1 | PASS | 0, 0, 0 | 50, 70, 30 | output/div1.stl |
| div2 | PASS | 0, 0, 0 | 30, 70, 30 | output/div2.stl |
| lid | PASS | 0, 0, 0 | 119,6, 79,6, 5 | output/lid.stl |

## Dogrulama
- Proje status: PASS
- WARNING: (div1) tolerans belirtilmedi
- WARNING: (div2) tolerans belirtilmedi

## Montaj (metadata, simulasyon yok)
- j1: sliding_fit (body + lid, clearance 0.2)

## Dosyalar
- input.md / input.json, project.json
- cad/<parca>.scad, output/<parca>.stl, validation/<parca>.validation.json
- slice/ : yok (G-code uretilmedi)

## Malzeme
- belirtilmedi
