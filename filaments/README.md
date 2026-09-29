# filaments/

Filament profilleri (`filaments/<filament-id>.json`, sema: `schemas/filament.schema.json`).

Kurallar:
- Degerler SADECE kullanicidan veya OrcaSlicer filament profilinden alinir. UYDURMA YOK.
- Bilinmeyen alan `null` birakilir.
- `_template.json` SABLONDUR; dilimlemeye uygun degildir (`profile_source=template`).
- `Test-FilamentProfile` (engine/Test-Profiles.ps1) dogrulama yapar.

OFFLINE MOD (gercek yazici yok):
- profil hazirlamaya izin verilir (dosya olustur + dogrula),
- dry-run'a izin verilir (readiness gate calisir, eksikler raporlanir),
- baski isi GONDERILMEZ (gonderme kodu yoktur).
