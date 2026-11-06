<#
.SYNOPSIS
    Menampilkan notifikasi custom kepada user bila Windows Update memerlukan aksi.

.DESCRIPTION
    Script ini dijalankan dalam konteks user, bukan SYSTEM. Ia memeriksa apakah
    Windows Update memiliki update software yang tersedia atau restart pending.
    Bila salah satu kondisi ditemukan, Windows native toast di pojok kanan bawah
    menampilkan dua pilihan:

    - Update now: membuka halaman Windows Update agar user dapat memulai update
      atau restart dari antarmuka Windows.
    - Remind me (in 1 hour): membuat Scheduled Task milik user untuk menjalankan
      script ini sekali lagi satu jam kemudian.

    Script tidak memaksa restart dan tidak menutup aplikasi user.

.NOTES
    Untuk deployment Intune, script harus tersedia pada path lokal yang persisten
    di perangkat (contoh: C:\ProgramData\ITSM-PRO\Scripts) dan Scheduled Task
    harus berjalan dalam konteks user. Script Proactive Remediation yang berjalan
    sebagai SYSTEM tidak dapat menampilkan dialog ini secara langsung.
#>

[CmdletBinding()]
param(
    # Khusus pilot/test: tampilkan dialog walaupun update atau restart pending
    # belum ditemukan. Scheduled Task production tidak memakai parameter ini.
    [switch]$ForceDisplay,

    # Dipanggil oleh custom protocol handler saat user menekan tombol pada toast.
    [string]$ActionUri
)

function Get-WindowsUpdateActionState {
    # Key ini ada apabila Windows Update membutuhkan restart untuk menyelesaikan
    # instalasi update yang telah dilakukan.
    $rebootRequiredPath =
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'

    $restartPending = Test-Path -Path $rebootRequiredPath
    $updatesAvailable = $false

    try {
        # Windows Update Agent memberi daftar update software yang tersedia.
        # Query gagal tidak menghentikan notifikasi restart pending.
        $updateSession = New-Object -ComObject 'Microsoft.Update.Session'
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        $searchResult = $updateSearcher.Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
        $updatesAvailable = ($searchResult.Updates.Count -gt 0)
    }
    catch {
        Write-Output "Windows Update Agent tidak dapat di-query: $($_.Exception.Message)"
    }

    return [PSCustomObject]@{
        RestartPending  = $restartPending
        UpdatesAvailable = $updatesAvailable
    }
}

function Register-OneHourReminder {
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath
    )

    # Nama task konsisten agar pilihan "remind" berikutnya mengganti jadwal
    # sebelumnya, bukan membuat banyak notifikasi untuk user yang sama.
    $taskName = 'ITSM-PRO-WindowsUpdateReminder'
    $reminderTime = (Get-Date).AddHours(1)

    if (-not (Get-Command -Name Register-ScheduledTask -ErrorAction SilentlyContinue)) {
        throw 'Register-ScheduledTask tidak tersedia pada perangkat ini.'
    }

    # Gunakan path PowerShell bawaan Windows dan quote path script dengan aman.
    $powerShellPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""
    $action = New-ScheduledTaskAction -Execute $powerShellPath -Argument $arguments
    $trigger = New-ScheduledTaskTrigger -Once -At $reminderTime
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable

    # InteractiveToken memastikan task hanya berjalan pada sesi user saat ini;
    # tidak ada password user yang disimpan oleh task scheduler.
    $userIdentity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $principal = New-ScheduledTaskPrincipal -UserId $userIdentity -LogonType Interactive -RunLevel Limited

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null

    return $reminderTime
}

function Show-WindowsUpdateToast {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    # Windows Runtime digunakan langsung agar notifikasi tampil sebagai native
    # toast Windows, bukan dialog PowerShell di tengah layar.
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] > $null

    # Tombol menggunakan protocol activation. "ms-settings" adalah protocol
    # bawaan Windows; "itsm-pro-windowsupdate" didaftarkan oleh installer.
    $toastXml = @"
<toast scenario="reminder">
  <visual>
    <binding template="ToastGeneric">
      <text>Windows Update</text>
      <text>$([System.Security.SecurityElement]::Escape($Message))</text>
    </binding>
  </visual>
  <actions>
    <action content="Update now" activationType="protocol" arguments="ms-settings:windowsupdate" />
    <action content="Remind me (in 1 hour)" activationType="protocol" arguments="itsm-pro-windowsupdate://remind" />
  </actions>
</toast>
"@

    $xmlDocument = [Windows.Data.Xml.Dom.XmlDocument]::new()
    $xmlDocument.LoadXml($toastXml)
    $toast = [Windows.UI.Notifications.ToastNotification]::new($xmlDocument)

    # App ID PowerShell dipakai agar Windows dapat menampilkan toast dari script
    # tanpa aplikasi tambahan. Ikon/identitas tampil sebagai PowerShell.
    $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Microsoft.Windows.PowerShell')
    $notifier.Show($toast)
}

# Saat tombol "Remind me" di toast ditekan, custom URI handler memanggil script
# ini lagi dengan URI tersebut. Tidak perlu melakukan pengecekan update ulang.
if ($ActionUri) {
    try {
        $uri = [Uri]$ActionUri
        if ($uri.Scheme -eq 'itsm-pro-windowsupdate' -and $uri.Host -eq 'remind') {
            $reminderTime = Register-OneHourReminder -ScriptPath $PSCommandPath
            Write-Output "Reminder satu jam dibuat untuk $($reminderTime.ToString('yyyy-MM-dd HH:mm:ss'))."
            exit 0
        }

        throw "Action URI tidak dikenali: $ActionUri"
    }
    catch {
        Write-Error "Gagal memproses action toast: $($_.Exception.Message)"
        exit 1
    }
}

# Native toast hanya dapat muncul pada sesi user interaktif.
if (-not [Environment]::UserInteractive) {
    Write-Output 'Tidak ada sesi user interaktif; notifikasi tidak ditampilkan.'
    exit 0
}

$updateState = Get-WindowsUpdateActionState
if (-not $ForceDisplay -and -not $updateState.RestartPending -and -not $updateState.UpdatesAvailable) {
    Write-Output 'Tidak ada update atau restart Windows Update yang memerlukan tindakan.'
    exit 0
}

$message = if ($ForceDisplay) {
    '[PILOT TEST] Ini adalah simulasi notifikasi Windows Update. Tidak ada update atau restart yang dijalankan otomatis.'
}
elseif ($updateState.RestartPending) {
    'Windows Update memerlukan restart untuk menyelesaikan instalasi. Simpan pekerjaan Anda dan lakukan update/restart sesegera mungkin.'
}
else {
    'Windows Update tersedia untuk diinstal. Lakukan update saat pekerjaan Anda sudah siap disimpan.'
}

try {
    Show-WindowsUpdateToast -Message $message
    Write-Output 'Native Windows toast berhasil dikirim.'
}
catch {
    Write-Error "Gagal menampilkan native Windows toast: $($_.Exception.Message)"
    exit 1
}
