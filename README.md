# 3D AI Designer V1 — 3D Printing AI Automation

Dogal dil -> olculere sadik parametrik model -> STL/3MF -> dogrulama -> README.
Slicing ayri asama; G-code SADECE OrcaSlicer profilleriyle (su an kapali).

## Hizli kullanim

Agent ile (onerilen):
1. `@3d-print-engineer <tasarim istegin>` (skill: `3d-printing`)
2. Eksik kritik olcu varsa agent sorar — cevapla (uydurma yapilmaz).
3. Cikti: `projects/<proje>/` (kaynak + output + validation + README).

Masaustu prototip ile:
1. `powershell -File app\DesignerV1.ps1`
2. Promptu yaz, MODEL OLUSTUR'a bas; soru cikarsa cevapla, DEVAM ET.
3. G-code butonu bilerek YOK.

Otomatik testler:
- `powershell -File scripts\Run-Tests.ps1` (7 test, hepsi gecmeli)

## Klasorler
- `.opencode/skills/3d-printing/` — zorunlu is akisi (Faz 3 kurallari)
- `.opencode/agents/` — `@3d-print-engineer` subagent
- `engine/` — Design Engine: `Invoke-DesignEngine.ps1` (orkestrasyon, max 3 tur retry), `Test-DesignSpec.ps1` (tasarim dogrulama; hata/uyari, asla otomatik degistirmez)
- `app/` — DesignerV1 WinForms prototipi (motoru cagirir, kopyalamaz)
- `schemas/` — `input.schema.json` (normalize tasarim verisi), `printer.schema.json`, `material.schema.json` (gelecek)
- `printers/` — yazici limitleri + Orca profil adlari. `generic-fdm.json` PLACEHOLDER'dir; gercek profil eklenmeden slicing yapilmaz
- `materials/` — kural dosyasi (profil ekleme ileride; deger uydurma yok)
- `scripts/` — `Resolve-*.ps1` (exe bulucular), `Export-Stl.ps1` (modelleme), `Verify-Stl.ps1` (STL dogrulama PASS/WARNING/FAIL), `Slice.ps1` (placeholder, calismaz), `Run-Tests.ps1`
- `templates/` — `model.scad` + README sablonu
- `projects/<proje>/` — `input.md` (orijinal prompt), `input.json` (normalize veri), `cad/`, `output/`, `validation/validation.json`, `slice/`, `README.md`
- `docs/` — mimari, kullanici kilavuzu, gelistirici notlari
- `settings.json` — yol ayarlari (null = otomatik resolver)

## Model uretim akisi
prompt -> gereksinim analizi -> eksik kritik olcu -> soru -> parametrik OpenSCAD
-> SCAD->STL -> STL dogrulama (bbox + delik) -> olcu karsilastirma -> final cikti.
FAIL ise: teshis -> duzelt -> yeniden uret (max 3 tur) -> cozulmezse FAILED_AFTER_RETRIES.

## Kurulumlar
- OpenSCAD: `scripts\Resolve-OpenScad.ps1` bulur (bu makinede dogrulandi). Yoksa kur, PATH'e ekle veya `OPENSCAD_EXE` yaz.
- FreeCAD: `scripts\Resolve-FreeCad.ps1` bulur. OpenSCAD ile cozulebilen modelde zorunlu degil.
- OrcaSlicer: `scripts\Resolve-OrcaSlicer.ps1` sadece VARLIGI dogrular. Profil eslestirme + G-code SONRAKI FAZ.

## Portable kullanim
Tum yollar proje root'una goreceli cozulur; hard-coded makine yolu yok. Baska Windows bilgisayara klasoru kopyala, exe'leri kur, resolverlar bulsun.

## Gelecekteki G-code sistemi
OrcaSlicer'da gercek yazici+filament profili acilip adlari `printers/*.json`'a islenecek, `Slice.ps1`'daki CLI o surume gore tamamlanacak. Tahmini G-code ASLA uretilmeyecek.
