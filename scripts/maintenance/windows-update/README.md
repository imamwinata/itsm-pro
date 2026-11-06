# Windows Update user notification

## File

- `Show-WindowsUpdateNotification.ps1` — mengecek update/restart pending dan
  menampilkan native Windows toast **Update now** atau **Remind me (in 1 hour)**.
- `Install-WindowsUpdateNotificationTask.ps1` — menyalin script notifikasi ke
  profil user dan membuat Scheduled Task dengan delay satu jam setelah login.

## Test manual

Jalankan installer dari PowerShell user biasa, dengan kedua file berada pada
folder yang sama:

```powershell
.\Install-WindowsUpdateNotificationTask.ps1
```

Untuk langsung menguji dialog tanpa menunggu task:

```powershell
.\Show-WindowsUpdateNotification.ps1
```

Untuk memaksa dialog muncul saat pilot, walaupun tidak ada update pending:

```powershell
.\Show-WindowsUpdateNotification.ps1 -ForceDisplay
```

## Deployment Intune

Kedua file harus dideploy bersama melalui metode yang mempertahankan file sumber
(misalnya Win32 app). Installer harus berjalan sebagai user yang login. Intune
Platform Script tidak membawa file pendamping secara otomatis, sehingga tidak
cocok digunakan sendirian untuk installer ini.

Task hanya memunculkan native toast bila update Windows tersedia atau restart pending.
Task berjalan satu jam setelah user login; tidak ada UI yang dijalankan dalam
konteks SYSTEM.
