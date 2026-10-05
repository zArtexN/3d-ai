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

## Soylemen yeterli, tekrar sormaz
- `160x100x45 mm` -> govde olcusu otomatik (160, 100, 45).
- `ustu acik` / `ustten acik` / `kapaksiz` -> ust acik sayilir, tekrar sorulmaz.
- `4 adet O4.2 mm gecisli vida deligi, kenarlardan 8 mm` -> 4 delik cap 4.2 olarak acilir; koselerdeyse dort koseye otomatik yerlesir.
- `2 adet bolme, bolme kalinligi 2 mm` -> bolmeler ve kalinlik otomatik.
- `5 mm yaricap`, `1 mm pah`, `20x10 mm kablo acikligi` -> otomatik.
- `biraz gevsek` / `saglam olsun` gibi belirsiz ifadelerde program DEGER UYDURMAZ, net sayi sorar.

## Bilinen sinirlamalar
- `ayri`, `cikarilabilir` veya `bagimsiz bolme` yazsan da bolmeler govde-ici panel olarak uretilir (body.divider_pattern); ayri parca STL verilmez. Cikarilabilir bolme destegi sonraki faz.
- `taban` kalinligi verildiginde govde tabani o kalinlikta kurulur (duvar kalinligindan farkli olabilir); bolmeler taban ustune oturur.

## Dikkat edilecekler
- Olculeri tam yaz (ornek: deligin nerede olacagi). Eksik olcuyu program UYDURMAZ, sorar.
- G-code (yazici dosyasi) butonu YOK. Gercek yazici+filament profili eklenmeden slicing yapilmaz.
- Duvar cok inceyse program UYARI verir ama senin olcunu degistirmez.
- EXE acikken yeniden build calistirma: once uygulamayi kapat (build kilitliyse BLOCKED yazar).
- Yazici/filament eklemeden sicaklik/hiz/nozzle degeri gostermez; UNKNOWN yazar.

## V3.0: Workstation + orkestrator

- Workstation ac: powershell -File app\Workstation.ps1. Proje yaz/sec, Import/Text/Photo ile baslat, Analyze ile hatti kos, Export ile cikti+arsiv al.
- Komut satiri: powershell -File engine\Invoke-Orchestrator.ps1 -Source '50x50x20 kutu' -ProjectName demo (-DryRun, -Resume, -RetryStage).
- Print (offline) yalnizca hazirlik kaydi acar; yaziciya GONDERMEZ.
- 3D onizleme: wireframe; surukle=dondur, sag-surukle=tasi, tekerlek=zoom, cift-tik=sifirla. Olculer bbox+ucgen sayisi olarak yazilir.

## V3.1: dogal dille urun tasarimi

- Olcusuz urun tarifi yazabilirsin; Design Planner guvenli varsayimlarla tam spec kurar.
  Ornek: "Masam icin organizer tasarla. Kalemler icin bolum, telefon icin egimli yuva,
  sarj kablosu icin kanal olsun. Ustu acik, desteksiz basilsin."
- Desteklenen niyetler: organizer, telefon standi, kalemlik, tepsi, mutfak caddy
  (sunger/firca + drenaj), kapakli/kapaksiz kutu,
  L-braket, kablo tutucu, duvar plakasi, duvar istasyonu.
- Tum varsayimlar sonuc ekraninda WORKFLOW altinda ve projenin planner.json dosyasinda
  listelenir. Belirli telefon modeli yazarsan (orn. iPhone 15) olcu sorulur, uydurulmaz.
- Pipeline artik arka planda calisir (arayuz donmaz); ilerleme rozetlerin yaninda gorunur.
- HISTORY paneli: Geri Al / Yinele ile surumler arasi gecis (spec.json gercekten geri yuklenir).

## V3.1: dogal dille duzenleme

- Model olustuktan sonra cumleyle degistirebilirsin (ornekler):
  "Telefon yuvasini 5 mm sola kaydir." / "Telefon acisini 15 derece yap." /
  "Kablo kanalini 2 mm genislet." / "Tabani 3 mm kalinlastir." /
  "Organizeri %10 kucult." / "p1 bolmesini kaldir."
- Her degisiklik spec patch -> dogrulama -> aday geometri -> QA yolundan gecer;
  basarisizsa REDDEDILIR, mevcut model bozulmaz.
