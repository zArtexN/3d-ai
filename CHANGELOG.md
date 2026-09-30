# CHANGELOG — 3D AI Designer

## V3.0.0 (final release)
- Orkestrator (Phase 9): text/image/STL/OBJ/3MF/STEP/project yonlendirme, asama izleme,
  checkpoint+resume+retry, fallback kaydi, dry-run, PRINT_READY kapisi (16/16 test).
- Slicer+printer (Phase 8): process registry, profil dogrulama, slice-readiness gate,
  print-job yapisi, offline mod (10/10 test).
- Printability pro (Phase 7): bilesen-bazli duvar, delik detayi, overhang siddeti,
  onarim politikasi fill_holes+fix_normals (10/10 test).
- Workstation (Phase 10): tek masaustu yuzeyi (dashboard, pipeline, wireframe viewer,
  engine diagnostics, settings, logs), Export-Project, guvenlik/tasinabilirlik/temiz-makine
  testleri, yapisal ops.jsonl logu, cache anahtari, path traversal korumasi.
- Duvar/malzeme bilinmiyorsa NEEDS_INPUT; profil yoksa G-code BLOCKED (degismedi).

## UNRELEASED (adim-holefix)
- Negative intent: lid/hole/slot/fillet/chamfer acik reddi uretilmez; disabled_features spec kokunde korunur.
- Ciplak "kenardan" tek basina delik kaniti sayilmaz.
- Cutout Q&A: tek sayi / yatay / dikey / konum-bosluk formlari ($handled duzeltmesi).
- Divider hole pattern: body.divider_pattern (spec 2.1); delik cikis duzlemi floor (hollow+acik).
- Printer no-fake: template null kritikler, fallback kaldirildi, Slice BLOCKED.
- Knowledge boundary: provenance metadata + leakage testleri.
- Stale div artifakt uyarisi (silme yok).

## V2.1.0
- Parser hardening: 4 delik kosegen-yerlesimi (deterministik corner_pattern + placement metadata).
- Delik capi: O/o/çap-oneki/`N mm çapında` kalıpları; çekimli `deliği/delikler` gövdeleri; counterbore `Ø8` ana çap sanılmıyor.
- Tip eşleme: `geçişli/geçsin`→through, `kör` kelime-sınırlı (korunarak blind sanılmıyor).
- Üst-yön eşanlamlılar: `üstten açık`, `üst kısmı açık`, `kapaksız` (kapaksız lid üretmez).
- Bölme ayrımı: `role=partition` + `integrated` bayrağı (bütünleşik/ayrı).
- Kenar: ters `5 mm yarıçap`, ters `1 mm pah`, şartlı (`gerekiyorsa`) pah elenmesi.
- Kablo açıklığı: `alt kenarı tabandan N` ofseti; slot ölçüsü gövde üçlüsünden çalınmıyor.
- EXE: `assets/app.ico` (7 boyut) üretimi (`scripts\New-AppIcon.ps1`), EXE + pencere ikonuna gömülü.
- Build: çalışan uygulama tespiti (BLOCKED), yeniden denemeli swap, bayat staging temizliği.
- Testler: P23–P27 (köşe, kapaksız, bütünleşik), parser 29 test; full suite 0 FAIL.

## V2.0.0
- Printability / orientation / mesh-quality / cost-estimate analizörleri (PowerShell 5.1 uyumlu).
- Filament şeması + bilgi bankası (materials/fits/threads/inserts/troubleshooting/guidelines).
- Printer profili şablonu (generic-fdm; fake sıcaklık yok).
- Q&A cevap parser genişlemesi (üçlü ölçü varyantları, hata mesajları).

## V1.3
- Dark UI, referanstan tasarla, EXE build, kenar-konum parser.
