# ARCHITECTURE — 3D AI Designer V1 (teknik)

## Katmanlar

```text
UI (app/DesignerV1.ps1, WinForms)
        |  cagri (relative path), kopya yok
        v
Design Engine (engine/Invoke-DesignEngine.ps1)
   |-- Test-DesignSpec.ps1 (tasarim dogrulama: ERROR/WARNING, degisiklik yok)
   |-- SCAD uretici (kutu + tam gecisli delikler; // PARAM standardi)
   |-- scripts/Resolve-OpenScad.ps1 (OPENSCAD_EXE > bilinen yollar > PATH)
   |-- scripts/Export-Stl.ps1 (DEGISMEZ sozlesme: -Scad -OutDir -OpenScadExe)
   |-- scripts/Verify-Stl.ps1 (ASCII/binary, bbox, delik rim, PASS/WARNING/FAIL)
        v
OpenSCAD CLI (openscad.com) -> model.stl / model.3mf
        v
validation/validation.json (makine raporu) + README.md (insan raporu)
```

## Dosya baglantilari (§1 analizi)

- `SKILL.md` is akisini tanimlar; `3d-print-engineer.md` uygular (izinler: 3 resolver + 3 script).
- `settings.json` (null = resolver dene) -> engine + UI okur; env degiskenleri ezer.
- `schemas/input.schema.json` -> `projects/<ad>/input.json` formatini sabitler; `input.md` orijinal promptu korur.
- `schemas/printer|material.schema.json` -> gelecek profiller; `printers/generic-fdm.json` placeholder (degistirilmedi).
- `templates/README-template.md` -> tum README'ler (Sorular ve Cevaplar + Dogrulama sonuclari bolumleri Faz 3'te eklendi).
- `scripts/Slice.ps1` placeholder: bilerek throw eder (profil eslesmesi yok).
- `scripts/Run-Tests.ps1` -> TEST 1-7; Faz 2/3 ciktiarini sadece OKUR.

## Durum makinesi (validation.json status)

`OK / OK_WITH_WARNINGS` (design) -> `PASS / WARNING` (stl, cikis 0)
`BLOCKED` (eksik olcu / desteklenmeyen geometri, model URETILMEZ, cikis 2)
`FAIL` (tur ici) -> retry (max 3) -> `FAILED_AFTER_RETRIES` (cikis 2)

## Kritik kararlar

- `$Spec` (yol) / `$specObj` (veri) ayrimi: PowerShell case-insensitive oldugu icin ayni ad YASAK (bulunan bug sinifi).
- SCAD dosyasi BOM-SUZ UTF-8 yazilir (OpenSCAD 2021.01 BOM'da "syntax error line 1" verir).
- Verify cagrilarinda hashtable splat kullanilir (array splat pozisyonel baglar ve bozar).
- `@($x | Where-Object {...})` bos-ozellik kontrolunde zorunlu (`@($null).Count` = 1 tuzagina karsi).
- WARNING asla FAIL yapmaz; kullanici degeri asla otomatik degismez.
- Test gecici dizinleri (`_test*-tmp`) test sonunda silinir; gercek projeler silinmez.
