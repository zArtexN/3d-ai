# ARCHITECTURE — 3D AI Designer V1.2 (teknik)

## Uretim hatti (V1.2, §27)

```text
USER -> PROMPT -> PARSER/AI (yalnizca DesignSpec v2)
  -> QUESTION LOOP (kritik eksik -> soru -> cevap -> spec guncelle)
  -> VALIDATION (gate: schema + required + numeric + missing + impossible + tolerance)
  -> GEOMETRY ENGINE -> OPENSCAD -> STL -> STL VALIDATION
  -> PROJECT RESULT (project.json + README)
  -> [REAL PRINTER PROFILE REQUIRED] -> ORCASLICER -> G-CODE (kapali)
```

AI katmani (`engine/AIProvider.ps1`): arayuz `GenerateDesignSpec(prompt, context)` ->
DesignSpec v2. Su an yalnizca MOCK (parser) bagli; OPENAI/CLAUDE/LOCAL/OLLAMA
arayuze uygun eklenir. AI ciktisi guvenilmez kabul edilir, gate'ten gecer.

## Akis (§23)

```text
Prompt
  v
DesignSpec (input.json v1 / spec.json v2 + ConvertTo-GeometrySpec parser)
  v
Geometry Engine (engine/Invoke-GeometryEngine.ps1; V1 motoru ayri korunur)
  |-- Geometry.ps1 (box/cylinder/sphere/cone/tube/rounded_box/hole/slot/cutout/hollow)
  |-- boolean: union/difference/intersection + translate/rotate/mirror
  |-- Test-GeometrySpec.ps1 (geometry/feature/assembly/manufacturability)
  v
OpenSCAD (resolver ile; bolumlu SCAD: PARAMETERS/GEOMETRY/BOOLEAN/ASSEMBLY/EXPORT)
  v
STL (parca basi: output/<id>.stl)
  v
Validation (Verify-Stl bbox+delik; validation/<id>.validation.json)
  v
Project (project.json + README parca listesi; slice YOK, G-code YOK)
```

## V1 katmani (korunur, degismez)

- `engine/Invoke-DesignEngine.ps1` (kutu+delik), `Test-DesignSpec.ps1`, `Run-Tests.ps1` (TEST 1-7)
- `projects/faz2-test`, `faz3-test`, `demo-kutu` ciktilari referans olarak kalir.

## V1.1 baglantilari

- `schemas/designspec.schema.json` -> spec v2 (components/features/cutouts/operations/transforms/tolerances/assembly)
- `engine/ConvertTo-GeometrySpec.ps1` -> TR prompt'tan v2 spec + soru listesi (missing uydurmaz)
- `engine/Invoke-GeometryEngine.ps1` -> `cad/<id>.scad`, `output/<id>.stl`, `validation/<id>.validation.json`, `project.json`
- `scripts/Run-GeometryTests.ps1` -> TEST 8-20; `scripts/Run-AllTests.ps1` -> hepsi (TOTAL/PASS/FAIL + WARNING/BLOCKED gozlem)
- `app/DesignerV1.ps1` -> ayni pencere + parca/validation/uyari/gecmis panelleri (G-code butonu yok)

## Durum makinesi

`OK / OK_WITH_WARNINGS` -> parca basi `PASS / WARNING` (cikis 0)
`BLOCKED` (eksik kritik/tolerans/imkansiz geometri, model URETILMEZ, cikis 2)
`FAIL` (tur ici) -> retry (max 3) -> `FAILED_AFTER_RETRIES` (cikis 2)

## Kritik kararlar (V1 + V1.1)

- `$Spec`/`$specObj` (V1), `$SpecFile`/`$gspecObj` (V1.1) ayrimi zorunlu.
- SCAD BOM-SUZ; Verify hashtable splat; `@($null).Count`=1 korunmasi.
- YENI (V1.1): cok elemanli array literal icinde aritmetik HER ZAMAN parantezli
  (`@(($a - $b), ($c - $d))`); parantezsiz form bu ortamda op_Subtraction hatasi verir.
- YENI (V1.1): `[pscustomobject]@{...}` cast icine `List<T>` konmaz; once `.ToArray()`.
- YENI (V1.1): dairesel yuzeylerde `$fn = 96` sart (faset bbox kaymasin).
- WARNING asla FAIL yapmaz; kullanici degeri asla otomatik degismez.
- YENI (V3.1): `@($list).Count` / `@($list)` kalibi `List<T>` degiskenlerde ArgumentException
  verir (dizi degiskenlerde sorunsuz). `List<T>` icin `.Count` / `.ToArray()` dogrudan
  kullanilir; `@()` yalnizca skaler ve gercek dizilere uygulanir.
- YENI (V3.1): ConvertFrom-Json nesnelerinde mevcut olmayan ozellige dogrudan atama
  (`$o.yeniOzellik = ...`) PS5.1'de patlayabilir; taze `[pscustomobject]$hash` kurulumu
  veya mevcut ozellige atama kullanilir.

## V3.1 katmani (design planner + urun geometrisi + async UI)

- engine/Invoke-DesignPlanner.ps1 v2.0: parser sonrasi calisir; organizer/phone_stand/
  pen_holder/tray/caddy/box(+lid)/bracket/cable_clip/wall_plate/wall_station niyetleri. Govde olcusu varsa
  calismaz (hassas istek korunur). Tum varsayimlar spec.planner.assumptions'da.
- Yeni spec alanlari (schemas/designspec.schema.json): partitions (ozel konumlu ic duvar),
  wedges (aci-gudumlu kama prizmasi, angle_driven), planner (karar kaydi).
- Geometry.ps1: New-GWedge (polyhedron, 2021.01), New-GHollowRoundedBox (gercek radius,
  minkowski). Chamfer geometrik uygulanmaz (WARNING).
- Delik cikis duzlemi: hollow+acik tabanda (floor), hollow'suz kutuda govde ustunde,
  kapali kutuda parca tepesinde (birlesim bbox degil).
- NL editing (EditIntent.ps1 + DesignSpecPatch.ps1): delta/yuzde/aci/tasima/kaldirma;
  kama+bolme hedefleri; undo/redo spec.json'u geri yukler (ProjectVersions.ps1).
- app/DesignerV1.ps1: async pipeline (Start-Job + Timer, 10 dk timeout), WORKFLOW
  asamalari (gercek artefaktlardan), HISTORY (Geri Al/Yinele), viewer tooltip/kisayol,
  facet limiti 20000, fade-in. Test modlari (-UITest/-ValidateUI/-SelfTest) senkron
  yolda kalir.

## V3.0 katmani (orkestrator + workstation)

- engine/Invoke-Orchestrator.ps1: giris turu (text/image/stl/obj/3mf/step/project) -> plan -> asama kayitlari -> checkpoint (.json, atomik tmp+rename) -> resume/retry -> dry-run -> PRINT_READY kapisi (engine/Test-PrintReady.ps1).
- Alt-sistemler: Test-Profiles/Test-SliceReadiness/New-PrintJob (P8), Analyze-Printability (P7), Invoke-Reconstruction (P6, mock test-disi), engine registry+adapterler (P5).
- app/Workstation.ps1: yalnizca cagirir (dashboard/pipeline/viewer/diagnostics/settings/logs); uzun isler Start-Job + Timer ile. Gonderme kodu YOK.
- Guvenlik: Test-PathSafe (traversal), string-komut yok, secret yok, AI ciktisi parse->validate zinciri. Log: ops.jsonl. Cache: Get-CacheKey (girdi-hash+motor+config+spec).
