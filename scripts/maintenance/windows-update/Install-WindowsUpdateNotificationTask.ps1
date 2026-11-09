<#
.SYNOPSIS
    Menginstal startup notifier user untuk Windows Update.

.DESCRIPTION
    Script ini menyalin Show-WindowsUpdateNotification.ps1 ke profil user saat
    ini, kemudian membuat startup entry pada profil user. Startup entry berjalan
    satu jam setelah user login. Script notifikasi tetap melakukan
    pengecekan update/restart sendiri, sehingga dialog hanya tampil bila Windows
    Update memerlukan tindakan.

.NOTES
    Jalankan script ini sebagai user yang sedang login, bukan SYSTEM. Kedua file
    harus dideploy bersama melalui Win32 app atau metode lain yang menjaga file
    sumber tetap berada dalam folder yang sama saat installer dijalankan.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$sourceNotificationScript = Join-Path -Path $PSScriptRoot -ChildPath 'Show-WindowsUpdateNotification.ps1'
$targetDirectory = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'ITSM-PRO\Scripts'
$targetNotificationScript = Join-Path -Path $targetDirectory -ChildPath 'Show-WindowsUpdateNotification.ps1'
$startupBootstrapScript = Join-Path -Path $targetDirectory -ChildPath 'Start-WindowsUpdateNotificationAfterDelay.ps1'

# Nilai pilot: jalankan pemeriksaan 15 menit setelah user login.
# Tombol "Remind me (in 1 hour)" pada toast tetap menggunakan 60 menit.
$startupDelaySeconds = 900

try {
    if (-not [Environment]::UserInteractive) {
        throw 'Installer harus dijalankan pada sesi user interaktif, bukan SYSTEM.'
    }

    if (-not (Test-Path -Path $sourceNotificationScript)) {
        throw "Script notifikasi tidak ditemukan: $sourceNotificationScript"
    }

    # Simpan salinan lokal agar startup notifier tidak bergantung pada cache atau
    # lokasi temporary Intune setelah script deployment selesai.
    New-Item -Path $targetDirectory -ItemType Directory -Force | Out-Null
    Copy-Item -Path $sourceNotificationScript -Destination $targetNotificationScript -Force

    $powerShellPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'

    # Daftarkan protocol handler untuk tombol "Remind me (in 10 minutes)" pada
    # native toast. Handler berada di HKCU sehingga tidak memerlukan admin.
    $protocolPath = 'HKCU:\Software\Classes\itsm-pro-windowsupdate'
    $protocolCommandPath = Join-Path -Path $protocolPath -ChildPath 'shell\open\command'
    New-Item -Path $protocolCommandPath -Force | Out-Null
    New-ItemProperty -Path $protocolPath -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null

    $protocolCommand = "`"$powerShellPath`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$targetNotificationScript`" -ActionUri `"%1`""
    Set-Item -Path $protocolCommandPath -Value $protocolCommand

    # Startup entry user menjalankan bootstrap tanpa hak Administrator. Bootstrap
    # menunggu sesuai nilai pilot lalu memanggil notifier yang disalin ke profil user.
    $escapedNotificationPath = $targetNotificationScript.Replace("'", "''")
    $bootstrapContent = "Start-Sleep -Seconds $startupDelaySeconds`r`n& '$escapedNotificationPath'"
    Set-Content -Path $startupBootstrapScript -Value $bootstrapContent -Encoding UTF8 -Force

    $runKeyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $runValueName = 'ITSM-PRO-WindowsUpdateNotification'
    $runCommand = "`"$powerShellPath`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$startupBootstrapScript`""
    New-ItemProperty -Path $runKeyPath -Name $runValueName -Value $runCommand -PropertyType String -Force | Out-Null

    Write-Output "Startup entry '$runValueName' berhasil dibuat untuk user saat ini."
    Write-Output "Script notifikasi tersimpan di: $targetNotificationScript"
    Write-Output 'Protocol handler toast berhasil didaftarkan untuk user saat ini.'
    Write-Output 'Notifikasi akan diperiksa 15 menit setelah login berikutnya.'
    exit 0
}
catch {
    Write-Error "Gagal menginstal Windows Update startup notifier: $($_.Exception.Message)"
    exit 1
}
