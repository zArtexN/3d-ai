# DEVELOPMENT — 3D AI Designer V1.1 (gelistirici)

## Calistirma
- Hepsi: `powershell -File scripts\Run-AllTests.ps1` (TOTAL 40/40 sart)
- V1: `powershell -File scripts\Run-Tests.ps1` (7/7, DEGISTIRME)
- Geometri: `powershell -File scripts\Run-GeometryTests.ps1` (TEST 8-20)
- UI selftest (penceresiz): `powershell -File app\DesignerV1.ps1 -SelfTest`
- V1 engine: `powershell -File engine\Invoke-DesignEngine.ps1 -Spec projects\<ad>\input.json`
- V1.1 engine: `powershell -File engine\Invoke-GeometryEngine.ps1 -SpecFile projects\<ad>\spec.json`
- Parser: `powershell -File engine\ConvertTo-GeometrySpec.ps1 -Prompt "..." -ProjectName x -OutPath ...`
- Tum yollar root'a goreceli; `settings.json` null birakilirsa resolver calisir.

## Kod kurallari (aci tecrubelerden)
1. PowerShell case-insensitive: `$Spec`/`$spec` AYNI degiskendir. Yol `$Spec`, veri `$specObj`.
2. `.ps1` dosyalarinda Turkce karakter + backtick KULLANMA (cift tirnak icinde backtick kacistir; `"```"` stringi kapatir).
3. OpenSCAD'a giden `.scad` BOM-SUZ yazilir (`Write-Utf8NoBom` yardimcisi).
4. Verify cagrilarinda HASHTABLE splat (`@{...}`); array splat pozisyonel baglar.
5. `Verify/Design` throw eder (try/catch ile yakala); `Engine` exit kodu verir (`$LASTEXITCODE`).
6. `@($null).Count` = 1'dir; bos-alan kontrolunde `Where-Object { $_ -ne $null }` sart.
7. Cok elemanli array literalde aritmetik MUTLAKA parantezli: `@(($a - $b), ($c - $d))`.
   Parantezsiz `@($a - $b, $c - $d)` bu ortamda op_Subtraction hatasi verir (V1.1 bulgusu).
8. `X | Out-String | ConvertFrom-Json` TEK zincirde KULLANMA (buyuk ciktilar kirpilir).
   Ara degiskene bol: `$t = X | Out-String` sonra `$o = $t | ConvertFrom-Json` (V1.2 bulgusu).
9. Karmasik tek-satir bool ifadelerini ara degiskenlere bol (V1.2 bulgusu).
10. `[pscustomobject]@{...}` icine `List<T>` koyma; once `.ToArray()` cagir (V1.1 bulgusu).
11. Dairesel yuzey ureten SCAD'a `$fn = 96` ekle; dusuk facet bbox'u kucultur, verify FAIL olur.
12. `Export-Stl.ps1` ve Faz 2/3 ciktilari DEGISTIRILMEZ; testler onlari sadece okur.
13. Yeni script eklersen test paketine testini ekle; gecici dizinleri retry-ile temizle.

## Yeni geometry operation ekleme (V1.1)
1. `engine/Geometry.ps1`: `New-G<Ad>` ctor (pozitiflik kontrolu + bbox takibi) + gerekiyorsa boolean/transform destegi.
2. `schemas/designspec.schema.json`: yeni alanlar (missing/null ile; uydurma deger YASAK).
3. `engine/ConvertTo-GeometrySpec.ps1`: TR kalip (belirsizse soru uret, deger uydurma).
4. `engine/Test-GeometrySpec.ps1`: ERROR (BLOCKED) / WARNING kurallari (otomatik duzeltme YOK).
5. `engine/Invoke-GeometryEngine.ps1`: uretim adimi + expected bbox (koseleri donustur).
6. `scripts/Run-GeometryTests.ps1`: en az 1 PASS + 1 basarisizlik (BLOCKED/FAIL) testi.
Desteklenmeyen geometri BLOCKED dondurur, sessizce atlanmaz.

## Siradaki faz (G-code)
`printers/*.json` gercek profiller + `Slice.ps1` CLI tamamlama + OrcaSlicer profil eslestirme.
Tahmini G-code yasak; sadece OrcaSlicer ciktisi gecerli.
