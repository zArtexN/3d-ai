# printers/

Her yazici bir JSON dosyasi: `printers/<yazici-id>.json`.

## Yeni yazici ekleme (ileride farkli yazicilar icin)
1. `generic-fdm.json` dosyasini kopyala: `printers/<yeni-id>.json`
2. Gercek degerleri gir: `nozzle_mm`, `bed_mm`, `min_wall_mm`,
   `min_feature_mm`, `min_hole_mm`, `max_overhang_deg`.
3. `orca_profiles` alanina OrcaSlicer'daki BIREBIR profil adlarini yaz
   (yazici + filament + process). Uydurma isim yazma.
4. `default_clearance_mm` alanini bos birak (`null`) — gecme payi
   kullanicidan sorulur, kafadan yazilmaz.

## Kural
- Agent basilabilirlik kontrolunde ve `scripts/Slice.ps1` calisirken
  SADECE bu klasordeki dosyayi referans alir.
- `generic-fdm.json` placeholder'dir; gercek profil eklenmeden
  slicing yapilmaz.
