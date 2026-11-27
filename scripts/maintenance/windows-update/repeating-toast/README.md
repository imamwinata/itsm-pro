# Repeating Windows Update toast

Komponen ini terpisah dari `Show-WindowsUpdateNotification.ps1`. Ia menampilkan
native toast berulang selama Windows Update memiliki status **Restart required**.
Tidak ada policy yang diubah dan script tidak melakukan restart.

## Prasyarat

Jalankan `..\Install-WindowsUpdateNotificationTask.ps1` sekali dari sesi user
agar AppUserModelID native toast didaftarkan.

## Menjalankan

Jalankan dari PowerShell user yang sedang login:

```powershell
.\Start-RepeatingWindowsUpdateToast.ps1
```

Default interval adalah 10 menit. Untuk interval pilot lain:

```powershell
.\Start-RepeatingWindowsUpdateToast.ps1 -IntervalMinutes 5
```

Script menampilkan toast segera pada awal eksekusi, lalu mengulangi sesuai
interval selama restart pending masih ada.

Toast dan output PowerShell juga menampilkan klasifikasi update sebagai
**perkiraan**, nilai policy grace period/deadline bila tersedia, serta waktu
scheduled restart bila Windows menyediakannya. Windows tidak selalu mengekspos
sisa grace period absolut; waktu scheduled restart bukan pengganti pasti untuk
sisa grace period tersebut.

## Menghentikan

Buka PowerShell lain pada user yang sama, lalu jalankan:

```powershell
.\Stop-RepeatingWindowsUpdateToast.ps1
```
