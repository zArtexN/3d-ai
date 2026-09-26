# USER-GUIDE — 3D AI Designer V1.3 (basit dil)

## Hizli baslangic (EXE)
1. `dist/3D-AI-Designer.exe` dosyasina cift tikla (yoksa: `scripts\Build-Exe.ps1` calistir).
2. Ilk acilista ARACLAR denetlenir; OpenSCAD yoksa Ayarlar'dan bir kez goster.
3. Tasarla sekmesinde yaz, TASARLA'ya bas; soru gelirse cevapla.

## Referanstan tasarla
1. Referanstan Tasarla sekmesi: URL yapistir veya Dosya Sec (STL/3MF/STEP).
2. Referansi Analiz Et: olculer mesh'ten okunur; bilinmeyenler listelenir.
3. Degisiklik komutunu yaz (orn: "aynisini yap ama deligi 8 mm olsun") ve Uret.
4. Eksik olcu varsa SORULUR, uydurulmaz.

## Bu program ne yapiyor?
Yazdigin olculerden 3 boyutlu yazdirilabilir model dosyasi (STL) hazirliyor.
Sen olcu verirsin, program cizer, olcer, kontrol eder, klasore koyar.
V1.1: kutu disinda silindir, boru, ici-bos kutu, kapak, kanal/kesik de yapabilir.

## Nasil kullanilir? (kolay yol)
1. `app\DesignerV1.ps1` dosyasini PowerShell ile calistir.
2. Buyuk kutuya ne istedigini yaz. Ornek: `80x40x20 mm kutu yap, delik 25, duvar 2`
3. MODEL OLUSTUR'a bas.
4. Program anlamadigi bir olcu varsa sorar (ornek: delik merkezi). Cevabi yaz, DEVAM ET'e bas.
5. Yesil tikler cikarsa model hazirdir: SCAD'I AC, STL'YI AC, PROJE KLASORU butonlarini kullan.

## Neler yazabilirsin? (ornekler)
- `80x40x20 kutu, delik 25 merkez 15,15`
- `100x80x50 kutu, icini bosalt duvar 2.5, ustu acik`
- `dis cap 30 ic cap 20 boy 40 boru`
- `60x40x20 kutu, kapak yukseklik 5, 0.2 mm bosluk`
- `onde 20x10 kanal` (konumunu da yaz: `konum 5,5 derinlik 8`)
- Anlasilmayan kritik olcude program SORAR; "biraz gevsek" gibi ifadelere deger uydurmaz, sorar.

## Soru sorarsa ne yapmalisin?
Program eksik kritik olcuyu UYDURMAZ, sorar. Ornek: delik merkezi, duvar yonü
(acik/kapali), kapak boslugu. Cevabi yaz, DEVAM ET'e bas. Tum soru/cevaplar
SORU/CEVAP GECMISI panelinde saklanir.

## Sonuc ekrani nasil okunur?
- PROJECT: proje adi · DESIGN: parca sayisi · CAD/STL: PASS (dosya uretildi)
- VALIDATION: PASS / WARNING / BLOCKED (kategori detaylari listede)
- PARTS: her parca ve durumu
- G-CODE: NOT AVAILABLE yazar. "Print Ready" yazmaz; yazici profili gerekir.
- PARCALAR: cok parcali urunde her parca ve durumu
- VALIDATION: her parcanin kontrol sonucu
- UYARILAR: riskli ama engel olmayan durumlar (olcun degistirilmez)
- SORU/CEVAP GECMISI: ne soruldu, ne cevapladin

## Projelerim nerede?
`projects` klasorunde, her modelin kendi klasoru var. Icinde:
- Ne istedigin (input.md)
- Cizim (cad/<parca>.scad — cok parcalida parca basi dosya)
- Yazdirmalik dosya (output/<parca>.stl)
- Kontrol raporu (validation/<parca>.validation.json + project.json)
- Aciklama (README.md)

## Baska bilgisayarda kullanma (portable)
1. `3D-AI` klasorunu kopyala (kurulum yok).
2. Uygulamayi ac; ARACLAR paneli exe'leri otomatik arar.
3. "OpenSCAD BULUNAMADI" yazarsa: kur veya "OpenSCAD Konum Sec" ile bir kez goster.
   Secim `settings.local.json` dosyasina kaydolur (bu dosya Git'e gitmez).
4. FreeCAD/OrcaSlicer yoksa sorun degil (OPTIONAL); CAD/STL calisir.

## Dikkat edilecekler
- Olculeri tam yaz (ornek: deligin nerede olacagi). Eksik olcuyu program UYDURMAZ, sorar.
- G-code (yazici dosyasi) butonu YOK. O is sonraki asamada eklenecek.
- Duvar cok inceyse program UYARI verir ama senin olcunu degistirmez.
