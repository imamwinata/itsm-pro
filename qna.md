itu log nya untuk pilot melalui intune dan rollout ada di device target atau device sysadmin yang memiliki akses intune?

Log tersebut ada di device target, bukan di laptop sysadmin.

Saat Intune menjalankan script, script dieksekusi sebagai SYSTEM di masing-masing laptop target. Karena itu log tersimpan di:

C:\ProgramData\ITSM-PRO\Logs\

Contoh: jika rollout ke 100 laptop, masing-masing laptop akan memiliki log sendiri.

Sysadmin dapat melihat ringkasan hasil eksekusi dari Intune Admin Center, tetapi isi file log lokal tidak otomatis terkirim ke Intune. Jika ingin sysadmin mengumpulkan log terpusat, perlu mekanisme tambahan, misalnya Microsoft Sentinel/Log Analytics, file share/API internal, atau script upload log yang aman.



jadi log yang sudah kita buat di script tadi tidak akan ada di laptop/device sysadmin?

Betul. Log yang dibuat script hanya ada di laptop/device tempat script dijalankan.

- Test manual di laptop sysadmin → log ada di laptop sysadmin, pada %LOCALAPPDATA%\ITSM-PRO\Logs\.
- Pilot atau rollout via Intune → log ada di setiap laptop target, pada C:\ProgramData\ITSM-PRO\Logs\.
- Intune Admin Center hanya menampilkan output/status eksekusi, bukan otomatis menyalin file log ke device sysadmin.




kalau via Intune dan kita tetap ingin dapat log nya harus bagaimana?

Bisa. Untuk log terpusat dari perangkat target ke sysadmin, pilihan terbaik untuk production adalah Azure Monitor / Log Analytics.

Alurnya:

Laptop target
  → C:\ProgramData\ITSM-PRO\Logs\*.log
  → Azure Monitor Agent + Data Collection Rule
  → Log Analytics Workspace
  → Sysadmin melihat/query melalui Azure Portal atau Microsoft Sentinel

Pilihan implementasi:

1. Cukup gunakan laporan Intune
   Script tetap menulis output singkat dengan Write-Output. Sysadmin melihat status dan output eksekusi dari Intune Admin Center. Cocok untuk pilot kecil, tetapi bukan untuk menyimpan log lengkap.
2. Log Analytics / Microsoft Sentinel — rekomendasi rollout
   Deploy Azure Monitor Agent ke device target, lalu buat Data Collection Rule yang mengambil file log dari:

   C:\ProgramData\ITSM-PRO\Logs\*.log

   Semua log kemudian dapat dicari terpusat berdasarkan hostname, waktu, dan status.
3. Kirim ke API atau storage internal
   Script bisa mengirim log ke API perusahaan, Azure Storage, atau Azure Function. Ini lebih fleksibel, tetapi perlu autentikasi yang aman—jangan menyimpan token langsung di script.

Untuk kondisi Anda, saya sarankan:

- Pilot: gunakan output Intune + file log lokal.
- Rollout: gunakan Azure Monitor Agent + Log Analytics.
- Jangan mengirim file log ke laptop sysadmin secara langsung; gunakan layanan terpusat agar log dari semua device dapat dicari dan diaudit.




Write-Output itu pasti akan bisa dibaca dari Intune?
Ya, Write-Output dari script Intune umumnya dapat dibaca di laporan hasil eksekusi Intune, termasuk untuk Proactive Remediations.

Namun ada batasannya:

- Output bersifat diagnostik ringkas, bukan sistem logging penuh.
- Panjang output dapat dibatasi atau dipotong oleh Intune.
- Tampilan hasilnya bergantung pada jenis script dan halaman laporan Intune yang digunakan.
- exit 0 / exit 1 tetap menentukan status compliant/non-compliant atau sukses/gagal; Write-Output hanya memberi konteks.

Untuk script kita, output seperti ini akan terlihat:

2026-11-06 10:30:00 [INFO] Windows Update membutuhkan restart. Status: non-compliant.

Jadi, gunakan Write-Output untuk pesan status penting yang ingin cepat dilihat dari Intune. Tetap gunakan file log lokal atau Log Analytics bila membutuhkan riwayat lengkap.



cara jalankan file detect.ps1 bagaimana?

Untuk test manual di laptop Windows, buka PowerShell lalu jalankan:

Set-Location "C:\path\ke\itsm-pro\proactive-remediations\windows\windows-update-restart-notification\pilot"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\detect.ps1

$LASTEXITCODE

Hasilnya:

- 0 → tidak ada restart Windows Update yang tertunda.
- 1 → restart Windows Update diperlukan.

Log manual akan dibuat di:

%LOCALAPPDATA%\ITSM-PRO\Logs\WindowsUpdateRestartNotification-detect.log

Untuk menjalankannya melalui Intune:

1. Buka Devices → Scripts and remediations → Remediations.
2. Buat remediation baru.
3. Upload detect.ps1 sebagai Detection script.
4. Upload remediate.ps1 sebagai Remediation script.
5. Aktifkan opsi PowerShell 64-bit.
6. Assign dahulu ke grup pilot device.

Pada Intune, jika detect.ps1 mengembalikan exit code 1, Intune akan melanjutkan menjalankan remediate.ps1.











Urutan yang aman adalah seperti ini.

1. Pilot manual di satu laptop
Jalankan PowerShell sebagai Administrator:
cd "C:\path\ke\itsm-pro\scripts\device-configuration\windows\windows-update"

.\Set-WindowsUpdateDeadlinePolicy.ps1 `
  -QualityUpdateDeadlineDays 7 `
  -FeatureUpdateDeadlineDays 14 `
  -GracePeriodDays 2

Lalu cek hasil detection:
cd "C:\path\ke\itsm-pro\proactive-remediations\windows\windows-update-restart-notification\pilot"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\detect.ps1

$LASTEXITCODE

2. Pilot melalui Intune

Tidak perlu menjalankan Set-WindowsUpdateDeadlinePolicy.ps1 jika memakai Proactive Remediation.

- Upload detect.ps1 sebagai Detection script.
- Upload remediate.ps1 sebagai Remediation script.
- Aktifkan PowerShell 64-bit.
- Assign ke device group pilot.
- Jalankan remediation sesuai jadwal atau gunakan on-demand run bila tersedia.

Alurnya:

detect.ps1
  → Policy belum ada/tidak sesuai atau restart pending
  → exit 1
  → remediate.ps1 dijalankan
  → policy 7 / 14 / 2 hari diterapkan
  → jadwal berikutnya detect.ps1 memverifikasi hasil

3. Rollout production

Setelah pilot berhasil:

- Gunakan pasangan detect.ps1 + remediate.ps1 yang sama.
- Ubah assignment dari grup pilot ke grup production secara bertahap.
- Jangan sekaligus menjalankan Set-WindowsUpdateDeadlinePolicy.ps1 sebagai Intune Platform Script, karena remediation sudah melakukan konfigurasi yang sama.

4. Reset / rollback

Sebelum reset, hapus assignment atau nonaktifkan Proactive Remediation terkait di Intune. Jika tidak, Intune akan menerapkan policy kembali.

Kemudian jalankan sebagai Administrator pada device target:

cd "C:\path\ke\itsm-pro\scripts\device-configuration\windows\windows-update"

.\Reset-WindowsUpdateDeadlinePolicy.ps1

Untuk melihat perubahan lebih dulu:

.\Reset-WindowsUpdateDeadlinePolicy.ps1 -WhatIf

Setelah reset, detect.ps1 akan kembali menghasilkan exit 1 karena target konfigurasi memang sudah dihapus. Itu normal selama remediation sudah tidak lagi di-assign.

Catatan: implementasi saat ini menangani konfigurasi policy dan deteksi restart. Komponen toast notification harian dan force-restart satu jam sebelum deadline belum dibuat, jadi belum perlu dimasukkan dalam urutan deployment ini.










saya hanya ingin uji notifikasinya saja dulu, tidak langsung menjalankan policy nya

Bisa. Untuk uji notifikasi saja, tidak perlu menjalankan detect.ps1, remediate.ps1, atau script policy.

Di laptop target, salin file berikut ke folder yang sama, misalnya C:\Temp\ITSM-PRO:

Show-WindowsUpdateNotification.ps1
Install-WindowsUpdateNotificationTask.ps1

Buka PowerShell sebagai user yang sedang login, lalu jalankan:

Set-Location "C:\Temp\ITSM-PRO"
Set-ExecutionPolicy -Scope Process Bypass -Force

.\Show-WindowsUpdateNotification.ps1 -ForceDisplay

Parameter -ForceDisplay akan memunculkan dialog test meskipun tidak ada update atau restart pending.

Uji dua tombol:

- Update now → membuka halaman Windows Update.
- Remind me (in 1 hour) → membuat scheduled task reminder satu jam kemudian.

Untuk memastikan reminder dibuat:

Get-ScheduledTask -TaskName "ITSM-PRO-WindowsUpdateReminder"

Jika hanya ingin menguji dialog, Anda bahkan tidak perlu menjalankan Install-WindowsUpdateNotificationTask.ps1.
