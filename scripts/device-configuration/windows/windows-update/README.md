# Windows Update deadline policy

`Set-WindowsUpdateDeadlinePolicy.ps1` mengatur policy deadline Windows Update
secara lokal melalui registry policy.

## Nilai default

| Policy | Nilai |
| --- | --- |
| Quality update deadline | 7 hari |
| Feature update deadline | 14 hari |
| Grace period restart | 2 hari |

## Contoh pemakaian

Jalankan dari PowerShell Administrator untuk menggunakan nilai default:

```powershell
.\Set-WindowsUpdateDeadlinePolicy.ps1
```

Atau tentukan nilai lain:

```powershell
.\Set-WindowsUpdateDeadlinePolicy.ps1 -QualityUpdateDeadlineDays 7 -FeatureUpdateDeadlineDays 14 -GracePeriodDays 2
```

Script harus dijalankan sebagai `SYSTEM` atau Administrator bila dideploy lewat
Intune. Jangan kelola setting yang sama melalui script dan Intune Update Ring
secara bersamaan, karena policy pusat dapat menimpa nilai registry ini.

Script juga menyimpan target konfigurasi di
`HKLM\SOFTWARE\ITSM-PRO\WindowsUpdateRestartNotification`. Nilai ini dibaca
oleh `detect.ps1` pada solusi Proactive Remediation untuk memeriksa compliance.

## Reset konfigurasi

Jalankan `Reset-WindowsUpdateDeadlinePolicy.ps1` sebagai Administrator untuk
menghapus tiga nilai policy yang dikelola script dan konfigurasi ITSM-PRO:

```powershell
.\Reset-WindowsUpdateDeadlinePolicy.ps1
```

Gunakan `-WhatIf` untuk melihat perubahan tanpa menghapus apa pun:

```powershell
.\Reset-WindowsUpdateDeadlinePolicy.ps1 -WhatIf
```

Unassign atau nonaktifkan Proactive Remediation/Intune policy terlebih dahulu;
jika tidak, policy dapat diterapkan lagi pada sync berikutnya.
