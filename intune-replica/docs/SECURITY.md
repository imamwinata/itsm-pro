# Security model

Toolkit ini dirancang untuk simulasi lokal dan memiliki batasan berikut:

- Tidak menggunakan Microsoft Graph, jaringan, credential, token, atau secret.
- Tidak menjalankan installer, payload aplikasi, perintah dari JSON, atau script
  yang direferensikan oleh konfigurasi.
- Tidak mengubah registry, Windows Update, driver, aplikasi, atau policy Intune.
- Menolak file JSON yang lebih besar dari 1 MB.
- Menolak konfigurasi yang berisi field bernama password, secret, token, private
  key, atau client secret dengan nilai terisi.
- Driver hanya ditandai eligible bila manufacturer diizinkan, kompatibel, tidak
  ada pada kategori blocklist, dan—bila diwajibkan—telah disetujui.

Laporan simulasi ditulis hanya ke folder `reports/` di bawah `intune-replica`.
Tinjau perubahan konfigurasi dan laporan pilot sebelum memakai data tersebut
sebagai dasar deployment Intune nyata.
