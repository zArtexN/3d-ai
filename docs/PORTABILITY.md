# PORTABILITY — 3D-AI

## Kurallar
- `C:\Users\...` gibi sabit kullanıcı yolu YOK (`Test-Portability`).
- Sabit sürücü yolu yalnızca çözümleyici aday listelerinde
  (`C:\Program Files\...`, derleyici sondası) veya bilerek-yok fixture
  işareti (`C:\yok\`) olabilir.
- `settings.json` taşınabilir (null/otomatik veya göreceli). Makineye özel
  yollar `settings.local.json`'a yazılır ve GİTLENMEZ (.gitignore).
- Profiller (`printers/`, `filaments/`, `processes/`) mutlak yol içermez.
- Geçici dosyalar: `GetTempPath()`/`$env:TEMP`, proje-altı veya çıktı dizini.

## Kopya proje
Proje dizini `{spec,measurements,models,reports,repro-config}` taşır;
mutlak kök referansı içermez. Arşiv: `Export-Project.ps1` → `project-archive.zip`
(secrets, credentials, `.cache`, gereksiz ağırlıklar HARİÇ).

## Çalıştırma
Repo kökünden göreceli çağrı: `powershell -File engine\Invoke-Orchestrator.ps1 ...`
Python env varsayılanı kök-kardeş `3D-AI-External` (`THREE_D_AI_EXTERNAL` ile ezilir).
