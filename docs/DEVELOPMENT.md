# DEVELOPMENT — 3D AI Designer V1 (gelistirici)

## Calistirma
- Testler: `powershell -File scripts\Run-Tests.ps1` (7/7 sart)
- UI selftest (penceresiz): `powershell -File app\DesignerV1.ps1 -SelfTest`
- Engine: `powershell -File engine\Invoke-DesignEngine.ps1 -Spec projects\<ad>\input.json`
- Tum yollar root'a goreceli; `settings.json` null birakilirsa resolver calisir.

## Kod kurallari (aci tecrubelerden)
1. PowerShell case-insensitive: `$Spec`/`$spec` AYNI degiskendir. Yol `$Spec`, veri `$specObj`.
2. `.ps1` dosyalarinda Turkce karakter + backtick KULLANMA (cift tirnak icinde backtick kacistir; `"```"` stringi kapatir).
3. OpenSCAD'a giden `.scad` BOM-SUZ yazilir (`Write-Utf8NoBom` yardimcisi).
4. Verify cagrilarinda HASHTABLE splat (`@{...}`); array splat pozisyonel baglar.
5. `Verify/Design` throw eder (try/catch ile yakala); `Engine` exit kodu verir (`$LASTEXITCODE`).
6. `@($null).Count` = 1'dir; bos-alan kontrolunde `Where-Object { $_ -ne $null }` sart.
7. `Export-Stl.ps1` ve Faz 2/3 ciktilari DEGISTIRILMEZ; testler onlari sadece okur.
8. Yeni script eklersen `Run-Tests.ps1`'e testini ekle; gecici dizinleri temizle.

## Yeni geometri ekleme
`engine/Invoke-DesignEngine.ps1` adim 2 (destek kontrolu) + adim 3 (SCAD uretici) genisletilir;
`schemas/input.schema.json` guncellenir; `Test-DesignSpec.ps1`'e hata/uyari kurali eklenir.
Desteklenmeyen geometri BLOCKED dondurur, sessizce atlanmaz.

## Siradaki faz (G-code)
`printers/*.json` gercek profiller + `Slice.ps1` CLI tamamlama + OrcaSlicer profil eslestirme.
Tahmini G-code yasak; sadece OrcaSlicer ciktisi gecerli.
