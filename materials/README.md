# materials/

Malzeme belirtilirse dikkate alinir, belirtilmezse uydurulmaz.

## Kural
- Kullanici malzeme verdiyse (or. PLA, PETG, ASA): agent sadece o malzemeye
  ozgu notlari ilgili projenin README'sine yazar (or. "PETG icin verilen
  tolerans bu modele uygulandi").
- Kullanici malzeme VERMEDIYSE: agent sicaklik, hiz, fan, mukavemet gibi
  kritik baski parametrelerini UYDURMAZ. README'ye `Malzeme: belirtilmedi` yazar.
- Buraya malzeme profili eklemek ileriki asama; su an klasor bilerek bos.
  Ileride or. `materials/pla.json` gibi dosyalar eklenebilir ama OrcaSlicer
  filament profili her zaman tek dogruluk kaynagi kalir.
