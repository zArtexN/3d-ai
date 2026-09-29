# processes/

Process profilleri (`processes/<process-id>.json`, sema: `schemas/process.schema.json`).

Kurallar:
- Process yazici ve filamentten AYRIDIR (hiz/katman/destek ayarlari burada).
- Degerler SADECE kullanicidan veya OrcaSlicer process profilinden alinir. UYDURMA YOK.
- Bilinmeyen alan `null` birakilir.
- `_template.json` SABLONDUR; `orca_profile` eslestirilmeden dilimleme YAPILMAZ.
- `Test-ProcessProfile` (engine/Test-Profiles.ps1) dogrulama yapar.

OFFLINE MOD (gercek yazici yok):
- profil hazirlamaya izin verilir (dosya olustur + dogrula),
- dry-run'a izin verilir (readiness gate calisir, eksikler raporlanir),
- baski isi GONDERILMEZ (gonderme kodu yoktur).

Slicer notu: birincil slicer OrcaSlicer'dir (Phase 5 adapter). PrusaSlicer/CuraEngine
entegre DEGILDIR (kaynak/lisans karari verilmedi, ikili program da yok); readiness
gate slicer bulamazsa `slicer_unavailable` ile BLOCKED doner.
