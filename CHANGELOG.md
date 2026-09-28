# CHANGELOG — 3D AI Designer

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
