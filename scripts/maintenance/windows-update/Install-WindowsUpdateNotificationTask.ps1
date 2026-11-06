<#
.SYNOPSIS
    Menginstal Scheduled Task user untuk menjalankan notifikasi Windows Update.

.DESCRIPTION
    Script ini menyalin Show-WindowsUpdateNotification.ps1 ke profil user saat
    ini, kemudian membuat task bernama ITSM-PRO-WindowsUpdateNotification.
    Task berjalan satu jam setelah user login. Script notifikasi tetap melakukan
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

$taskName = 'ITSM-PRO-WindowsUpdateNotification'
$sourceNotificationScript = Join-Path -Path $PSScriptRoot -ChildPath 'Show-WindowsUpdateNotification.ps1'
$targetDirectory = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'ITSM-PRO\Scripts'
$targetNotificationScript = Join-Path -Path $targetDirectory -ChildPath 'Show-WindowsUpdateNotification.ps1'

try {
    if (-not [Environment]::UserInteractive) {
        throw 'Installer harus dijalankan pada sesi user interaktif, bukan SYSTEM.'
    }

    if (-not (Test-Path -Path $sourceNotificationScript)) {
        throw "Script notifikasi tidak ditemukan: $sourceNotificationScript"
    }

    # Simpan salinan lokal agar scheduled task tidak bergantung pada cache atau
    # lokasi temporary Intune setelah script deployment selesai.
    New-Item -Path $targetDirectory -ItemType Directory -Force | Out-Null
    Copy-Item -Path $sourceNotificationScript -Destination $targetNotificationScript -Force

    $powerShellPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $escapedScriptPath = [System.Security.SecurityElement]::Escape($targetNotificationScript)
    $escapedPowerShellPath = [System.Security.SecurityElement]::Escape($powerShellPath)

    # LogonTrigger dengan Delay PT1H memastikan pemeriksaan pertama terjadi satu
    # jam setelah user login. Trigger ini berjalan kembali pada login berikutnya.
    # Notifikasi tidak akan muncul bila script tidak mendeteksi update/restart.
    $taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Menampilkan notifikasi ITSM-PRO apabila Windows Update membutuhkan tindakan.</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <Delay>PT1H</Delay>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="InteractiveUser">
      <UserId>$userSid</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>false</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT10M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="InteractiveUser">
    <Exec>
      <Command>$escapedPowerShellPath</Command>
      <Arguments>-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File &quot;$escapedScriptPath&quot;</Arguments>
    </Exec>
  </Actions>
</Task>
"@

    # -Force memperbarui task lama, misalnya ketika script notifikasi diperbarui.
    Register-ScheduledTask -TaskName $taskName -Xml $taskXml -Force | Out-Null

    Write-Output "Scheduled Task '$taskName' berhasil dibuat untuk user saat ini."
    Write-Output "Script notifikasi tersimpan di: $targetNotificationScript"
    Write-Output 'Notifikasi akan diperiksa satu jam setelah login berikutnya.'
    exit 0
}
catch {
    Write-Error "Gagal menginstal Windows Update notification task: $($_.Exception.Message)"
    exit 1
}
