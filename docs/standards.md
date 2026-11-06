# Standar script

## Penamaan

- PowerShell: gunakan pola `Verb-Noun.ps1`, misalnya `Set-CompanyWallpaper.ps1`.
- Proactive Remediations: selalu gunakan `detect.ps1` dan `remediate.ps1`.
- Folder solusi: gunakan nama `kebab-case`, misalnya `legacy-vpn-client`.

## Perilaku Intune

- Tulis output yang ringkas dan bermakna untuk kebutuhan troubleshooting.
- Gunakan exit code `0` untuk sukses dan selain `0` untuk kegagalan atau kondisi tidak compliant, sesuai jenis deployment.
- Nyatakan dengan jelas apakah script berjalan sebagai `System` atau `User`, serta apakah perangkat perlu restart.
- Uji pada perangkat pilot sebelum assignment yang lebih luas.

## Dokumentasi solusi

Setiap solusi harus mencantumkan tujuan, platform/versi OS yang didukung, target assignment, requirement, cara rollback, owner, dan tanggal perubahan terakhir.

## Rahasia

Jangan commit password, API key, token, private key, atau file `.pfx`. Simpan rahasia pada mekanisme manajemen secret yang disetujui organisasi.
