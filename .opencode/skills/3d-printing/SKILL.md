---
name: 3d-printing
description: Dogal dildeki 3D baski isteklerinden olculere sadik parametrik model, STL/3MF ve README uretir. Eksik kritik olcuyu sorar, basilabilirlik kontrolu yapar, STL'yi otomatik dogrular, G-code uretmez.
license: MIT
compatibility: opencode
metadata:
  workflow: 3d-print-ai-automation
  tech: openscad-freecad-orcaslicer
---

# 3D Printing Skill

Tek giris: kullanicinin dogal dildeki tasarim promptu. Tek cikti: `projects/<proje>/` altinda parametrik kaynak + STL/3MF + README.

Uretim akisi (Faz 3): prompt -> gereksinim analizi -> eksik kritik olcu tespiti -> soru -> parametrik OpenSCAD -> SCAD->STL -> STL dogrulama -> olcu karsilastirma -> final cikti. G-code YOK.

## Zorunlu is akisi (sirasi degismez)

### 1. Olcu cikarma (parse, degistirme yok)
- Prompttan tum olculeri mm cinsinden tabloya dok.
- Acikca verilen olcuyu aynen kullan. Donusum/yuvarlama yapma.
- Olcu verilmemis kritik degerleri UYDURMA.

### 2. Eksik kritik olcu varsa SOR
Kritik = baskinin sonucunu etkileyen, verilmeden modelin uretilemeyecegi olcu. Ornekler:
- delik merkezi (`hole_x`, `hole_y`)
- duvar kalinligi (`wall_thickness`)
- parca araligi
- tolerans / gecme boslugu (`tolerance`)
- vida olcusu
- uzunluk / ic cap / et kalinligi (borm tipi parcalarda)
- `question` araciyla sor. Tahminle devam etme. Cevap gelmeden model OLUSTURMA.
- Kritik bir problem kullanici kararini gerektiriyorsa OTOMATIK KARAR VERME; sor.
- Kritik olmayan estetik/teknik detaylar (or. `$fn` cozunurlugu) icin varsayilan secebilirsin ama README'de `Varsayilanlar` basliginda yaz. Kritik geometrik olculer ASLA varsayilmasin.

### 3. Parametrik model kur
- Oncelik: OpenSCAD (`projects/<proje>/cad/model.scad`). OpenSCAD ile cozulebilen modelde FreeCAD ZORUNLU DEGIL.
- Tum olculer dosyanin basinda `// PARAM` olarak tanimli olsun. Acik ve duzenli adlar kullan:
  `width`, `depth`, `height`, `wall_thickness`, `hole_diameter`, `hole_x`, `hole_y`, `tolerance`
- Her PARAM satirinda kaynagi belirt: `(kullanici)` veya `(sorularak)`.
- Karmasik yuzey/parca gerekiyorsa FreeCAD'e gec, kaynagi `cad/` altinda sakla (`*.FCStd` + export edilen `*.step` varsa).
- Organik model istenirse: bu skill ile yapma, basamayacagini acikca soyle (Blender entegrasyonu ileride).

### 4. Basilabilirlik kontrolu (her modelde zorunlu)
`printers/<yazici>.json` limitlerine gore kontrol et:
- Duvar kalinligi >= `min_wall_mm`
- Minimum ozellik >= `min_feature_mm`
- Delikler: basim yonundeki delik capi >= `min_hole_mm`; kopru/cap uyumu
- Toleranslar: gecme payi belirtilmemisse sor (varsayilan uydurma)
- Overhang: `max_overhang_deg` ustu yuzey varsa destek veya yon degisikligi oner
- Baski yonu: tablaya oturan en genis duz yuzeyi sec, nedenini README'ye yaz
- Gecemezse: modeli sessizce "duzeltme", durumu acikca belirt.
- Profil placeholder ise formal onay VERILMEZ; sadece sanity kontrol yapilir ve README'ye yazilir.

### 5. Malzeme kurali
- Kullanici malzeme verdiyse: sadece o malzemeye uygun notlari README'ye yaz (`materials/README.md` kurallarina gore).
- Vermediyse: kritik baski parametresi UYDURMA (sicaklik, hiz, fan, mukavemet iddiasi yok). README'ye `Malzeme: belirtilmedi` yaz.
- Gecerli yazici profili olmadan baski ayari UYDURMA.

### 6. Export (modelleme) — `scripts/Export-Stl.ps1`
- Kaynak `cad/` altinda durur, cikti `output/` altina gider: `model.stl`, mumkunse `model.3mf`.
- OpenSCAD yolu icin `scripts/Resolve-OpenScad.ps1` ile coz, `-OpenScadExe` olarak ver. PATH sorununu cozulmus VARSAYMA.
- `scripts/Export-Stl.ps1` mekanizmasini BOZMA (duzenleme yok, sadece cagir).
- OpenSCAD yoksa/cozulemezse script hata verir; .scad'i elle STL'ye cevirmis gibi davranma.

### 7. STL dogrulama (otomatik, her modelde zorunlu) — `scripts/Verify-Stl.ps1`
- STL olustuktan sonra calistir: bounding box'i prompttaki olculerle KARSILASTIR.
- Delik gibi kritik geometrileri `-CheckHole` ile AYRI CA dogrula (alt + ust rim = tam gecis).
- Sonuc `VERIFY: PASS` degilse:
  1. hatayi tespit et,
  2. mumkunse SCAD'i duzelt,
  3. yeniden STL olustur (adim 6),
  4. tekrar dogrula (en fazla 3 tur; cozulmezse kullaniciya sor).
- Dogrulama sonuclarini README'de `Dogrulama sonuclari` basliginda yaz.

### 8. Slicing (ayri asama, onayli) — `scripts/Slice.ps1`
- G-code'u ASLA dogrudan uretme/uydurma.
- Sadece OrcaSlicer yazici + filament profiliyle dilimle.
- Profil adi ve yolu slicing komutunda ve README'de aynen yazsin.
- Model asamasi bitmeden slicing'e gecme.

### 9. README yaz (her proje zorunlu)
`sablon: templates/README-template.md` icerik:
- kullanilan olculer (kullanici verilenler ayri isaretli)
- sorular ve cevaplar
- yapilan varsayimlar
- dogrulama sonuclari
- malzeme, baski yonu + gerekcesi, destek gereksinimi, bilinen riskler
- model dosyalarinin konumlari

## Klasor sozlesmesi

```text
projects/<proje>/
  input.md        # kullanicinin orijinal promptu (degistirilmeden)
  cad/model.scad  # parametrik kaynak (veya FreeCAD kaynagi)
  output/model.stl
  output/model.3mf  # mumkunse
  slice/          # sadece Slice.ps1 ciktisi (.gcode/.3mf + kullanilan profil notu)
  README.md       # sablona uygun
```

## Yasaklar
- Olcu degistirme, eksik olcu uydurma, gereksinim degistirme yok.
- Kritik geometrik olcu varsayma; kullanici karari gerektiren durumda otomatik karar verme.
- Basamayacak modeli "oldu" gibi gosterme.
- AI uretimi G-code yok.
