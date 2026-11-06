# Windows Update restart notification — pilot

Pasangan script ini dipakai sebagai **Intune Proactive Remediation**.

## Alur

1. `detect.ps1` memeriksa pending restart Windows Update dan membandingkan
   policy Windows yang aktif dengan target konfigurasi solusi.
2. Jika restart pending atau policy tidak sesuai, script keluar dengan kode `1`.
3. Intune menjalankan `remediate.ps1`, yang menerapkan target berikut:
   - Quality update deadline: 7 hari
   - Feature update deadline: 14 hari
   - Grace period restart: 2 hari
4. Target solusi disimpan pada
   `HKLM\SOFTWARE\ITSM-PRO\WindowsUpdateRestartNotification`; detection
   membacanya kembali sebagai sumber compliance.

## Deployment Intune

Upload `detect.ps1` sebagai Detection script dan `remediate.ps1` sebagai
Remediation script. Jalankan dengan PowerShell 64-bit dalam konteks SYSTEM.

> Belum ada toast notification di remediation ini. Toast dengan tombol harus
> dijalankan pada konteks user dan akan dideploy sebagai komponen terpisah.

## Script notifikasi user

Script terpisah tersedia di
`scripts/maintenance/windows-update/Show-WindowsUpdateNotification.ps1`.
Ia menampilkan dialog dengan pilihan **Update now** dan **Remind me (in 1 hour)**
bila update tersedia atau restart Windows Update tertunda. Jangan memanggilnya
langsung dari `detect.ps1` atau `remediate.ps1`, karena kedua script tersebut
dijalankan oleh Intune sebagai SYSTEM dan tidak dapat menampilkan UI user.
