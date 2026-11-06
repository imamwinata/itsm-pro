# ITSM-PRO

Koleksi script dan paket pendukung untuk dikelola melalui Microsoft Intune.

## Struktur utama

- `platform-scripts/` — script Intune yang dijalankan satu kali atau sesuai jadwal.
- `proactive-remediations/` — pasangan script deteksi dan perbaikan.
- `win32-apps/` — source dan script aplikasi Win32 per aplikasi.
- `scripts/` — script operasional yang dikelompokkan berdasarkan kebutuhan.
- `shared/` — fungsi, modul, dan aset yang dapat dipakai ulang.
- `docs/` — standar dan panduan deployment.

Lihat [docs/standards.md](docs/standards.md) sebelum menambahkan script baru.

## Pola penambahan solusi

1. Pilih folder berdasarkan tujuan script dan platformnya.
2. Tambahkan README di folder solusi yang menjelaskan tujuan, target, requirement, rollback, dan owner.
3. Untuk Proactive Remediations, gunakan `detect.ps1` dan `remediate.ps1` dalam satu folder solusi.
4. Untuk Win32 app, simpan `install.ps1`, `uninstall.ps1`, `detect.ps1`, source package, dan metadata bersama-sama.

Jangan menyimpan password, token, sertifikat privat, atau rahasia lain di repository.
