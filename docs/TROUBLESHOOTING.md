# TROUBLESHOOTING — 3D-AI

## NEEDS_INPUT + sorular
Kritik ölçü eksik. Soruyu cevaplayın (`-AnswersJson`) veya DEVAM ET. Uydurma yok.

## NOT_PRINT_READY
`orchestration.json` → `gate_reasons` tam listeyi verir. Tipik nedenler:
- `printer/filament/process/slicer hazır değil` → `printers/`, `filaments/`,
  `processes/` altına GERÇEK profil ekleyin (şablonla dilimleme yasak).
- `mesh invalid` → repair aşaması kaydına bakın; UNSAFE ise harici CAD'de düzeltin.
- `slicer successful değil` → Orca yolu + profil ad eşleşmesi (`Resolve-OrcaSlicer`).

## G-code yok
Kapı kapalı: `slice_readiness.missing[]` eksikleri söyler. Sahte G-code üretilmez.

## Reconstruction BLOCKED
Gerçek AI motoru bu makinede yok. `-AllowMock` yalnızca test akışı içindir;
üretimde mock geometri KULLANILMAZ (uyarı etiketi zorunlu).

## STEP import FAILED
FreeCAD binary olsa bile dönüştürücü bağlı değil. STEP'i harici CAD'de
STL/3MF'e çevirip mesh hattını kullanın.

## UI donuyor
Uzun hatlar (pipeline/dilim) arka planda koşar; bitince tablo yenilenir.
Toplu iş için CLI kullanın: `engine/Invoke-Orchestrator.ps1`.

## Build BLOCKED (uygulama çalışıyor)
`Build-Exe.ps1` çalışan EXE'yi kilitler; önce uygulamayı kapatın.

## Checkpoint bozulması
`checkpoints/<asama>.json` bozuksa ilgili aşama otomatik yeniden koşar
(crash recovery testi: T-ORCH-13).
