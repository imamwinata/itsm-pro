# Windows Update user notification

## File

- `Show-WindowsUpdateNotification.ps1` — mengecek update/restart pending dan
  menampilkan native Windows toast **Update now** atau **Remind me (in 10 minutes)**.
- `Install-WindowsUpdateNotificationTask.ps1` — menyalin script notifikasi ke
  profil user dan membuat startup entry dengan delay pilot 15 menit setelah login.

## Test manual

Jalankan installer dari PowerShell user biasa, dengan kedua file berada pada
folder yang sama:

```powershell
.\Install-WindowsUpdateNotificationTask.ps1
```

Untuk langsung menguji native toast tanpa menunggu satu jam:

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

Installer juga mendaftarkan AppUserModelID melalui shortcut Start Menu agar
Windows dapat menampilkan native toast di Notification Center dan pojok layar.

Startup notifier hanya memunculkan native toast bila update Windows tersedia atau restart pending.
Startup notifier pilot berjalan 15 menit setelah user login; tidak ada UI yang dijalankan dalam
konteks SYSTEM.
