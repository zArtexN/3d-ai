# 3D AI Designer V3.0 — AI Destekli 3D Printing Engineering Workstation

Dogal dil / foto / model -> olculere sadik parametrik model -> STL/3MF -> dogrulama ->
printability/orientation -> profil varsa dilimleme -> rapor.
Slicing ayri asama; G-code SADECE gercek printer+filament+process profiliyle (su an kapali, BLOCKED).
V3.0: Workstation UI + otonom orkestrator (text/image/mesh/STEP/project), PRINT_READY kapisi,
registry'ler (printer/filament/process), export/arsiv, guvenlik + tasinabilirlik kilitleri.

## Calistirma (V3)
- Workstation: `powershell -File app\Workstation.ps1` (dashboard, pipeline, 3D onizleme, motorlar, ayarlar, loglar)
- Orkestrator CLI: `powershell -File engine\Invoke-Orchestrator.ps1 -Source "..." -ProjectName demo`
- Dry-run: ayni komut + `-DryRun` (calistirmaz, plan/eksik/artefakt raporu)
- Export: `powershell -File scripts\Export-Project.ps1 -ProjectDir projects\demo -OutDir out`
- Klasik UI: `powershell -File app\DesignerV1.ps1` (korunur)

## Bu program ne yapar / ne yapmaz
YAPAR: dogal dildeki tasarimi olculere sadik DesignSpec'e cevirir, sorulmasi gerekeni sorar, CAD/STL uretir, mesh/printability/orientation/maliyet analizi yapar, OrcaSlicer entegrasyonunu gercek profil varsa kullanir.
YAPMAZ: printer/filament/nozzle/sicaklik/hiz/G-code/kalibrasyon degeri UYDURMAZ; eksikse UNKNOWN/BLOCKED/SORU verir. "Print Ready" / "Print completed" gibi sahte basari yazmaz.

## Calistirma
- Uygulama: `powershell -File app\DesignerV1.ps1` (cift tik icin EXE build et)
- EXE build: `powershell -ExecutionPolicy Bypass -File .\scripts\Build-Exe.ps1` -> `dist/3D-AI-Designer.exe`
- EXE calistirma: `dist` klasorunu kopyala, exe'ye cift tikla.
- OpenSCAD tanitma: Ayarlar > Araclar > OpenSCAD Konum Sec (settings.local.json, git disi).
- Referans link: Referanstan Tasarla > URL yapistir > Analiz Et (http/https, limitli).
- STL/3MF import: Dosya Sec (kopyalanir, orijinal degismez).
- Soru sorarsa: kritik olcu eksiktir, uydurulmaz. Cevapla, DEVAM ET.
- G-code neden yok: printer profili yok. CAD/STL/Validation hazir, G-CODE BLOCKED.

## Uretim hatti (V1.2)

USER -> PROMPT -> PARSER/AI (yalnizca DesignSpec v2) -> QUESTION LOOP ->
VALIDATION -> GEOMETRY ENGINE -> OPENSCAD -> STL -> STL VALIDATION ->
PROJECT RESULT -> [REAL PRINTER PROFILE REQUIRED] -> ORCASLICER -> G-CODE

G-code asamasi AKTIF DEGIL: printer profili gerekli. "Print Ready" ifadesi kullanilmaz.

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
- `powershell -File scripts\Run-AllTests.ps1` (hepsi: syntax+V1+geometry+pipeline+parser+UI+resolver)
- `powershell -File scripts\Run-Tests.ps1` (V1: 7 test, DEGISTIRME)
- `powershell -File scripts\Run-GeometryTests.ps1` (V1.1: TEST 8-20)
- `powershell -File scripts\Run-PipelineTests.ps1` (V1.2: T21-T44 + TA/B/C)
- `powershell -File scripts\Run-ParserTests.ps1` (P1-P27: govde olculeri, delik cap/konum, kose-yerlesimi, kapaksiz, bolme ayirimi)
- `powershell -File scripts\Run-V13Tests.ps1` (V1.3: P17-P20 + R21-R28)
- `powershell -File scripts\Test-QA.ps1` (Q&A cevap parserlari + uctan uca cevap akisi)
- `powershell -File scripts\Run-PrintTests.ps1` (printer profili, filament, printability, orientation, maliyet)
- EXE calisiyorken build: BLOCKED verir (once uygulamayi kapat). `scripts\New-AppIcon.ps1` ikonu yeniden uretir.

## Klasorler
- `.opencode/skills/3d-printing/` — zorunlu is akisi (Faz 3 kurallari)
- `.opencode/agents/` — `@3d-print-engineer` subagent
- `engine/` — V1: `Invoke-DesignEngine.ps1` + `Test-DesignSpec.ps1` (kutu+delik, korunur).
  V1.1: `Geometry.ps1` (geometri kutuphanesi), `Invoke-GeometryEngine.ps1` (cok-parca),
  `Test-GeometrySpec.ps1` (v2 dogrulama), `ConvertTo-GeometrySpec.ps1` (TR parser)
- `app/` — DesignerV1 WinForms prototipi (motoru cagirir, kopyalamaz; parca/validation/uyari/gecmis panelli)
- `schemas/` — `input.schema.json` (V1), `designspec.schema.json` (v2), `printer|material.schema.json` (gelecek)
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

## Parserin anladigi kritik ifadeler (soyleneni tekrar sormaz)
- `160x100x45 mm`, `160x100x45`, `160*100*45`, `160mm x 100mm x 45mm` -> body.dims
- `ustu acik / ustten acik / ust kismi acik / kapaksiz` -> hollow_top=true (kapaksiz lid uretmez)
- `4 adet O4.2 mm gecisli vida deligi` -> 4 delik, cap 4.2, through
- `kenarlardan 8 mm` + kose baglami -> 4 delik deterministik koselere yerlesir (8,8 / 152,8 / 8,92 / 152,92)
- `2 adet bolme` + `bolme kalinligi 2 mm`; `ayri parca degil` -> butunlesik isareti
- `5 mm yaricap`, `1 mm pah`, `20x10 mm kablo acikligi`, `10x10 mm temas`
- Belirsiz ifade (`biraz gevsek`, `saglam olsun`) -> deger uydurmaz, SORAR.

## Kurulumlar (portable resolver sirasi: settings.local > settings > env > tools/ > PATH > bilinen)
- OpenSCAD: ZORUNLU (yoksa CAD calismaz; dost mesaji + Konum Sec). `tools/openscad/` altina da konabilir.
- FreeCAD: OPTIONAL. OpenSCAD ile cozulebilen modelde zorunlu degil.
- OrcaSlicer: OPTIONAL / NOT READY (sadece detection; G-code SONRAKI FAZ).

## Portable kullanim
Tum yollar proje root'una goreceli cozulur; hard-coded makine yolu yok. Baska Windows bilgisayara klasoru kopyala, exe'leri kur, resolverlar bulsun.

## Gelecekteki G-code sistemi
OrcaSlicer'da gercek yazici+filament profili acilip adlari `printers/*.json`'a islenecek, `Slice.ps1`'daki CLI o surume gore tamamlanacak. Tahmini G-code ASLA uretilmeyecek.
