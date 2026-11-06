# Logs

Folder ini mendokumentasikan lokasi log untuk solusi dalam repository. Jangan
commit file log runtime karena isinya berasal dari perangkat dan dapat bertambah
terus-menerus.

Untuk `windows-update-restart-notification`, log deteksi pada perangkat target
dipilih otomatis berdasarkan cara script dijalankan:

| Kondisi | Konteks | Lokasi log |
| --- | --- | --- |
| Test manual dari laptop target | User yang menjalankan PowerShell | `%LOCALAPPDATA%\ITSM-PRO\Logs\WindowsUpdateRestartNotification-detect.log` |
| Pilot dari Intune | SYSTEM | `C:\ProgramData\ITSM-PRO\Logs\WindowsUpdateRestartNotification-detect.log` |
| Rollout dari Intune | SYSTEM | `C:\ProgramData\ITSM-PRO\Logs\WindowsUpdateRestartNotification-detect.log` |

Output script juga dikirim ke laporan Intune. Folder repository `logs/` hanya
menjadi dokumentasi; log runtime tidak ditulis ke sini karena repository tidak
tersedia pada perangkat target saat Intune menjalankan script.
