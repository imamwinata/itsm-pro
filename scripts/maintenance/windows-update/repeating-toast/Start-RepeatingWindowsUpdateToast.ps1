<#
.SYNOPSIS
    Menampilkan native Windows toast berulang selama restart Windows Update tertunda.

.DESCRIPTION
    Script ini berdiri terpisah dari notifier berbasis tombol. Setelah dijalankan
    pada sesi user interaktif, ia memeriksa status Restart required Windows Update
    dan menampilkan toast segera. Selama status tersebut masih ada, toast akan
    muncul lagi sesuai interval yang ditentukan.

    Script berhenti otomatis apabila restart pending sudah tidak ada, atau jika
    file stop dibuat oleh Stop-RepeatingWindowsUpdateToast.ps1.

.NOTES
    Jalankan sebagai user yang sedang login, bukan SYSTEM. Native toast memakai
    AppUserModelID yang didaftarkan oleh
    Install-WindowsUpdateNotificationTask.ps1. Jalankan installer tersebut sekali
    per user sebelum memakai script ini.
#>

[CmdletBinding()]
param(
    # Default pilot: ulangi toast setiap 10 menit.
    [ValidateRange(1, 1440)]
    [int]$IntervalMinutes = 10
)

$ErrorActionPreference = 'Stop'
$rebootRequiredPath =
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
$stateDirectory = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'ITSM-PRO\State'
$stopFile = Join-Path -Path $stateDirectory -ChildPath 'Stop-RepeatingWindowsUpdateToast.flag'

function Get-WindowsUpdatePolicyValue {
    param([Parameter(Mandatory)][string]$Name)

    # Policy dapat berasal dari Policy CSP Intune atau registry Windows Update.
    foreach ($path in @(
        'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update',
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    )) {
        try {
            $value = Get-ItemPropertyValue -Path $path -Name $Name -ErrorAction Stop
            if ($null -ne $value) {
                return [int]$value
            }
        }
        catch {
            # Coba lokasi policy berikutnya.
        }
    }

    return $null
}

function Convert-RegistryDateValue {
    param([object]$Value)

    if ($Value -is [DateTime]) {
        return $Value
    }

    $date = [DateTime]::MinValue
    if ($Value -is [string] -and [DateTime]::TryParse($Value, [ref]$date)) {
        return $date
    }

    try {
        $number = if ($Value -is [byte[]] -and $Value.Length -eq 8) {
            [BitConverter]::ToInt64($Value, 0)
        }
        else {
            [Int64]$Value
        }

        if ($number -ge 116444736000000000) {
            return [DateTime]::FromFileTimeUtc($number).ToLocalTime()
        }
    }
    catch {
        # Format waktu tidak dapat dikonversi.
    }

    return $null
}

function Get-ScheduledRestartTime {
    foreach ($path in @(
        'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings',
        'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\Schedule'
    )) {
        try {
            $value = Get-ItemPropertyValue -Path $path -Name 'ScheduleRestartTime' -ErrorAction Stop
            $date = Convert-RegistryDateValue -Value $value
            if ($null -ne $date) {
                return $date
            }
        }
        catch {
            # ScheduleRestartTime tidak tersedia pada lokasi ini.
        }
    }

    return $null
}

function Get-UpdateTypeEstimate {
    # Windows tidak menyediakan hubungan eksplisit antara key RebootRequired dan
    # update tertentu. Klasifikasi di bawah adalah estimasi berdasarkan update
    # yang sedang ditawarkan, lalu riwayat update terbaru sebagai fallback.
    $titles = [System.Collections.Generic.List[string]]::new()

    try {
        $session = New-Object -ComObject 'Microsoft.Update.Session'
        $searcher = $session.CreateUpdateSearcher()
        $available = $searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
        foreach ($update in $available.Updates) {
            $titles.Add([string]$update.Title)
        }

        if ($titles.Count -eq 0) {
            $historyCount = [Math]::Min($searcher.GetTotalHistoryCount(), 20)
            if ($historyCount -gt 0) {
                foreach ($entry in $searcher.QueryHistory(0, $historyCount)) {
                    # ResultCode 2 berarti instalasi update berhasil.
                    if ($entry.ResultCode -eq 2) {
                        $titles.Add([string]$entry.Title)
                    }
                }
            }
        }
    }
    catch {
        return 'Tidak dapat ditentukan (Windows Update Agent tidak tersedia)'
    }

    foreach ($title in $titles) {
        if ($title -match '(?i)feature update|version\s+\d{2}H\d|enablement package') {
            return 'Feature Update (perkiraan)'
        }
    }

    foreach ($title in $titles) {
        if ($title -match '(?i)cumulative update|security update|quality update|update for') {
            return 'Quality Update (perkiraan)'
        }
    }

    return 'Tidak dapat ditentukan'
}

function Get-RestartDetails {
    $updateType = Get-UpdateTypeEstimate
    $graceDays = Get-WindowsUpdatePolicyValue -Name 'ConfigureDeadlineGracePeriod'
    $qualityDeadlineDays = Get-WindowsUpdatePolicyValue -Name 'ConfigureDeadlineForQualityUpdates'
    $featureDeadlineDays = Get-WindowsUpdatePolicyValue -Name 'ConfigureDeadlineForFeatureUpdates'
    $scheduledRestart = Get-ScheduledRestartTime

    $scheduleText = 'Jadwal restart Windows belum tersedia.'
    if ($null -ne $scheduledRestart) {
        $remaining = $scheduledRestart - (Get-Date)
        if ($remaining.TotalSeconds -gt 0) {
            $remainingMinutes = [Math]::Ceiling($remaining.TotalMinutes)
            $scheduleText = "Scheduled restart: $($scheduledRestart.ToString('HH:mm')) (sekitar $remainingMinutes menit lagi)."
        }
        else {
            $scheduleText = "Scheduled restart: $($scheduledRestart.ToString('HH:mm')) (waktunya telah lewat)."
        }
    }

    return [PSCustomObject]@{
        UpdateType          = $updateType
        GraceDays           = $graceDays
        QualityDeadlineDays = $qualityDeadlineDays
        FeatureDeadlineDays = $featureDeadlineDays
        ScheduleText        = $scheduleText
    }
}

function Show-RepeatingWindowsUpdateToast {
    param([Parameter(Mandatory)][object]$Details)

    # Windows Runtime membuat native toast di Notification Center/pojok layar.
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] > $null

    $updateType = [System.Security.SecurityElement]::Escape("Jenis update: $($Details.UpdateType)")
    $scheduleText = [System.Security.SecurityElement]::Escape($Details.ScheduleText)

    $toastXml = @"
<toast scenario="reminder">
  <visual>
    <binding template="ToastGeneric">
      <text>Windows Update restart required</text>
      <text>Restart diperlukan untuk menyelesaikan Windows Update. Simpan pekerjaan Anda dan lakukan restart sesegera mungkin.</text>
      <text>$updateType</text>
      <text>$scheduleText</text>
    </binding>
  </visual>
  <actions>
    <action content="Open Windows Update" activationType="protocol" arguments="ms-settings:windowsupdate" />
  </actions>
</toast>
"@

    $xmlDocument = [Windows.Data.Xml.Dom.XmlDocument]::new()
    $xmlDocument.LoadXml($toastXml)
    $toast = [Windows.UI.Notifications.ToastNotification]::new($xmlDocument)
    $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('ITSM-PRO.WindowsUpdateNotification')
    $notifier.Show($toast)
}

if (-not [Environment]::UserInteractive) {
    Write-Error 'Script harus dijalankan pada sesi user interaktif, bukan SYSTEM.'
    exit 1
}

try {
    # Hapus sinyal stop lama agar satu eksekusi baru selalu dapat dimulai.
    if (Test-Path -Path $stopFile) {
        Remove-Item -Path $stopFile -Force
    }

    while ($true) {
        if (Test-Path -Path $stopFile) {
            Write-Output 'Sinyal stop ditemukan. Repeating toast dihentikan.'
            break
        }

        if (-not (Test-Path -Path $rebootRequiredPath)) {
            Write-Output 'Restart Windows Update tidak lagi tertunda. Repeating toast dihentikan.'
            break
        }

        $details = Get-RestartDetails
        Show-RepeatingWindowsUpdateToast -Details $details
        $graceText = if ($null -ne $details.GraceDays) { "$($details.GraceDays) hari" } else { 'tidak terdeteksi' }
        $qualityText = if ($null -ne $details.QualityDeadlineDays) { "$($details.QualityDeadlineDays) hari" } else { 'tidak terdeteksi' }
        $featureText = if ($null -ne $details.FeatureDeadlineDays) { "$($details.FeatureDeadlineDays) hari" } else { 'tidak terdeteksi' }
        Write-Output "Jenis update: $($details.UpdateType). Grace policy: $graceText. Quality deadline: $qualityText. Feature deadline: $featureText. $($details.ScheduleText)"
        Write-Output 'Sisa grace period aktual tidak selalu diekspos Windows; waktu scheduled restart di atas adalah estimasi waktu yang tersedia.'
        Write-Output "Toast restart Windows Update dikirim. Pemeriksaan berikutnya dalam $IntervalMinutes menit."

        # Sleep dibagi per menit agar perintah stop diproses maksimal sekitar satu
        # menit setelah dijalankan, bukan menunggu seluruh interval selesai.
        for ($minute = 1; $minute -le $IntervalMinutes; $minute++) {
            Start-Sleep -Seconds 60

            if (Test-Path -Path $stopFile) {
                break
            }
        }
    }

    exit 0
}
catch {
    Write-Error "Gagal menjalankan repeating Windows Update toast: $($_.Exception.Message)"
    exit 1
}
