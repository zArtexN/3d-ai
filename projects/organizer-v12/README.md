# organizer-v12 (Geometry Engine V1.1)

## Kaynak prompt (degistirilmeden)
> 120x80x40 mm ölçülerinde masaüstü organizer yap. Duvar kalınlığı 2 mm olsun. İçinde iki bölme olsun. Kapak ayrı parça olsun. Kapak ile gövde arasında 0.2 mm boşluk bırak. Kapakta 5 mm çapında iki delik olsun ve delikler yan kenarlardan 15 mm içeride bulunsun.

## Parcalar
| Parca | Durum | bbox min | bbox max | STL |
| ----- | ----- | -------- | -------- | --- |
| body | PASS | 0, 0, 0 | 120, 80, 40 | output/body.stl |
| divider_001 | PASS | 39,3333333333333, 2, 2 | 41,3333333333333, 78, 40 | output/body.stl (govde-ici) |
| divider_002 | PASS | 78,6666666666667, 2, 2 | 80,6666666666667, 78, 40 | output/body.stl (govde-ici) |
| lid | PASS | 0, 0, 0 | 119,6, 79,6, 5 | output/lid.stl |

## Dogrulama
- Proje status: PASS

## Montaj (metadata, simulasyon yok)
- j1: sliding_fit (body + lid, clearance 0.2)

## Dosyalar
- input.md / input.json, project.json
- cad/<parca>.scad, output/<parca>.stl, validation/<parca>.validation.json
- slice/ : yok (G-code uretilmedi)

## Malzeme
- belirtilmedi
