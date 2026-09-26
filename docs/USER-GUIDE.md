# USER-GUIDE — 3D AI Designer V1 (basit dil)

## Bu program ne yapiyor?
Yazdigin olculerden 3 boyutlu yazdirilabilir model dosyasi (STL) hazirliyor.
Sen olcu verirsin, program cizer, olcer, kontrol eder, klasore koyar.

## Nasil kullanilir? (kolay yol)
1. `app\DesignerV1.ps1` dosyasini PowerShell ile calistir.
2. Buyuk kutuya ne istedigini yaz. Ornek: `80x40x20 mm kutu yap, delik 25, duvar 2`
3. MODEL OLUSTUR'a bas.
4. Program anlamadigi bir olcu varsa sorar (ornek: delik merkezi). Cevabi yaz, DEVAM ET'e bas.
5. Yesil tikler cikarsa model hazirdir: SCAD'I AC, STL'YI AC, PROJE KLASORU butonlarini kullan.

## Projelerim nerede?
`projects` klasorunde, her modelin kendi klasoru var. Icinde:
- Ne istedigin (input.md)
- Cizim (cad/model.scad)
- Yazdirmalik dosya (output/model.stl)
- Kontrol raporu (validation/validation.json)
- Aciklama (README.md)

## Dikkat edilecekler
- Olculeri tam yaz (ornek: deligin nerede olacagi). Eksik olcuyu program UYDURMAZ, sorar.
- G-code (yazici dosyasi) butonu YOK. O is sonraki asamada eklenecek.
- Duvar cok inceyse program UYARI verir ama senin olcunu degistirmez.
