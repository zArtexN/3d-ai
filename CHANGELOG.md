# CHANGELOG â€” 3D AI Designer

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

## V3.1.0 (final)
- Design Planner v2: organizer/phone_stand/pen_holder/tray/caddy/box(+lid)/bracket/cable_clip/wall_plate/wall_station
  niyetleri; tum varsayimlar spec.planner.assumptions'da; belirli telefon modelinde NEEDS_INPUT.
- Caddy: sunger/firca + drenaj slotlu mutfak organizeri (varsayimli tam spec, gercek STL).
  Planner eslesmezse PLANNER-SKIP logu (sessiz gecis yok).
- Soru akisi repro'su wall_plate niyetine tasindi (wall_station artik planner ile PASS).
- Gercek radius: rounded_box hollow govde (minkowski, OpenSCAD 2021.01); chamfer uygulanmaz (WARNING).
- Aci-gudumlu kama (angle_driven wedge); delik cikis duzlemi plaka ustu (yukari buyuyen parcalar).
- NL editing: delta (mm genislet/kucult), yuzde olcek, aci atama, kama/bolme tasima+kaldirma;
  tek-eleman cozunurluk duzeltmesi; undo/redo spec.json'u gercekten geri yukler.
- UI: async pipeline (donma yok, 10 dk timeout), workflow asamalari, varsayim ozeti, HISTORY
  (Geri Al/Yinele), viewer tooltip/kisayol/facet 20000, fade-in.
- Guvenlik: path-safe ayirac duzeltmesi, Export-Stl timeout+quote guard, edit op-log.
- Test: Test-DesignPlanner (8) + Test-ProductDesigns (F-P, 11) suitleri runner'a bagli.
- Semver: VERSION 3.1.0 final (RC kapatildi).

## V3.1.0-RC (Release Candidate)
- Phase 10 QA/Release Hardening tamamlandi.
- Q&A leftover projelerin temizligi (UQA-03-no-leftover) duzeltildi (sadece test artifactleri hedeflenir).
- C# EXE (Build-Exe.ps1) Smoke test ve portability dogrulamasi aktif.
- Local-first ve guvenlik (path traversal engelleme, EXE-only G-Code uretimi vb.) kalici olarak test edildi.
- Negative intent: lid/hole/slot/fillet/chamfer acik reddi uretilmez; disabled_features spec kokunde korunur.
- Ciplak "kenardan" tek basina delik kaniti sayilmaz.
- Cutout Q&A: tek sayi / yatay / dikey / konum-bosluk formlari ($handled duzeltmesi).
- Divider hole pattern: body.divider_pattern (spec 2.1); delik cikis duzlemi floor (hollow+acik).
- Printer no-fake: template null kritikler, fallback kaldirildi, Slice BLOCKED.
- Knowledge boundary: provenance metadata + leakage testleri.
- Stale div artifakt uyarisi (silme yok).

## V2.1.0
- Parser hardening: 4 delik kosegen-yerlesimi (deterministik corner_pattern + placement metadata).
- Delik capi: O/o/Ã§ap-oneki/`N mm Ã§apÄ±nda` kalÄ±plarÄ±; Ã§ekimli `deliÄŸi/delikler` gÃ¶vdeleri; counterbore `Ã˜8` ana Ã§ap sanÄ±lmÄ±yor.
- Tip eÅŸleme: `geÃ§iÅŸli/geÃ§sin`â†’through, `kÃ¶r` kelime-sÄ±nÄ±rlÄ± (korunarak blind sanÄ±lmÄ±yor).
- Ãœst-yÃ¶n eÅŸanlamlÄ±lar: `Ã¼stten aÃ§Ä±k`, `Ã¼st kÄ±smÄ± aÃ§Ä±k`, `kapaksÄ±z` (kapaksÄ±z lid Ã¼retmez).
- BÃ¶lme ayrÄ±mÄ±: `role=partition` + `integrated` bayraÄŸÄ± (bÃ¼tÃ¼nleÅŸik/ayrÄ±).
- Kenar: ters `5 mm yarÄ±Ã§ap`, ters `1 mm pah`, ÅŸartlÄ± (`gerekiyorsa`) pah elenmesi.
- Kablo aÃ§Ä±klÄ±ÄŸÄ±: `alt kenarÄ± tabandan N` ofseti; slot Ã¶lÃ§Ã¼sÃ¼ gÃ¶vde Ã¼Ã§lÃ¼sÃ¼nden Ã§alÄ±nmÄ±yor.
- EXE: `assets/app.ico` (7 boyut) Ã¼retimi (`scripts\New-AppIcon.ps1`), EXE + pencere ikonuna gÃ¶mÃ¼lÃ¼.
- Build: Ã§alÄ±ÅŸan uygulama tespiti (BLOCKED), yeniden denemeli swap, bayat staging temizliÄŸi.
- Testler: P23â€“P27 (kÃ¶ÅŸe, kapaksÄ±z, bÃ¼tÃ¼nleÅŸik), parser 29 test; full suite 0 FAIL.

## V2.0.0
- Printability / orientation / mesh-quality / cost-estimate analizÃ¶rleri (PowerShell 5.1 uyumlu).
- Filament ÅŸemasÄ± + bilgi bankasÄ± (materials/fits/threads/inserts/troubleshooting/guidelines).
- Printer profili ÅŸablonu (generic-fdm; fake sÄ±caklÄ±k yok).
- Q&A cevap parser geniÅŸlemesi (Ã¼Ã§lÃ¼ Ã¶lÃ§Ã¼ varyantlarÄ±, hata mesajlarÄ±).

## V1.3
- Dark UI, referanstan tasarla, EXE build, kenar-konum parser.

