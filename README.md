# 3D-AI — 3D Printing AI Automation (Faz 1: iskelet)

Dogal dil -> olculere sadik parametrik model -> STL/3MF -> README.
Slicing ayri asama, G-code sadece OrcaSlicer profilleriyle.

## Kullanim
1. `@3d-print-engineer <tasarim istegin>` (skill: `3d-printing`)
2. Eksik kritik olcu varsa agent sorar — cevapla.
3. Cikti: `projects/<proje>/` (kaynak + output + README).

## Klasorler
- `.opencode/skills/3d-printing/` — zorunlu is akisi
- `.opencode/agents/` — `@3d-print-engineer` subagent
- `printers/` — yazici limitleri + Orca profil adlari (yeni yazici buraya JSON ile eklenir)
- `materials/` — kural dosyasi (profil ekleme ileride)
- `scripts/` — `Export-Stl.ps1` (modelleme) / `Slice.ps1` (slicing) — birbirinden ayri
- `templates/` — `model.scad` + README sablonu
- `projects/<proje>/` — her proje: `input.md`, `cad/`, `output/`, `slice/`, `README.md`
