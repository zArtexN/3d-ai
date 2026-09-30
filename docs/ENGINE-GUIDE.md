# ENGINE-GUIDE — 3D-AI Motor Kılavuzu

Kayıt: `engine/Engines/engines.json`. Sağlık: `Get-EngineHealth` (Phase 5).
Lisans sınıfları: PERMISSIVE / LGPL_FAMILY / GPL_FAMILY / AGPL_FAMILY / CUSTOM /
PROPRIETARY. GPL/AGPL ailesi ASLA linklenmez/gömülmez; yalnızca harici binary
olarak çağrılır (OrcaSlicer emsali).

## Motor tablosu (bu makine)

| Motor | Kategori | Durum | Not |
|---|---|---|---|
| trimesh | mesh | READY | izole python312, +lxml (3MF) |
| orcaslicer | slicer | READY (binary) | profil yoksa slice BLOCKED |
| openscad | cad | OPTIONAL | resolver ile bulunur |
| freecad | cad | BINARY VAR | STEP dönüştürücü bağlı değil |
| cadquery/build123d/occt/open3d | cad/mesh | MACHINE_LIMITED | toolchain yok |
| trellis/triposr/hunyuan | ai-recon | MACHINE_LIMITED | GPU/ağırlık yok |
| pymeshfix/prusa/cura/blender/meshlab | çeşitli | LICENSE_REVIEW/MACHINE_LIMITED | karar verilmedi |
| text-to-cad | cad | NOT_INTEGRATED | asla bağımlılık olmaz |

MACHINE_LIMITED bir sürüm kusuru DEĞİLDİR: mimari motoru `NOT_READY` raporlar,
hat yapısal BLOCKED döner, uydurma yapılmaz.

## Yeni motor ekleme

1. `engines.json`'a kayıt (id, kategori, lisans, adapter, capabilities).
2. `engine/Engines/adapters/<Ad>.ps1`: `<Ad>-Health` + `<Ad>-Invoke` fonksiyonları.
3. Sağlık `READY` dönmeden hat kullanmaz (orkestratör `Select-StageEngine`).
4. Test: `scripts/Test-Engines.ps1` deseninde sağlık + op testi.
