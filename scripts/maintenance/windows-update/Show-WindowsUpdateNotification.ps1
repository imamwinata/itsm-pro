<#
.SYNOPSIS
    Menampilkan notifikasi custom kepada user bila Windows Update memerlukan aksi.

.DESCRIPTION
    Script ini dijalankan dalam konteks user, bukan SYSTEM. Ia memeriksa apakah
    Windows Update memiliki update software yang tersedia atau restart pending.
    Bila salah satu kondisi ditemukan, dialog menampilkan dua pilihan:

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
    [switch]$ForceDisplay
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

# Dialog Windows Forms hanya dapat muncul pada sesi user interaktif.
if (-not [Environment]::UserInteractive) {
    Write-Output 'Tidak ada sesi user interaktif; notifikasi tidak ditampilkan.'
    exit 0
}

$updateState = Get-WindowsUpdateActionState
if (-not $ForceDisplay -and -not $updateState.RestartPending -and -not $updateState.UpdatesAvailable) {
    Write-Output 'Tidak ada update atau restart Windows Update yang memerlukan tindakan.'
    exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Windows Update'
$form.Size = New-Object System.Drawing.Size(510, 225)
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false

$message = if ($ForceDisplay) {
    '[PILOT TEST] Ini adalah simulasi notifikasi Windows Update. Tidak ada update atau restart yang dijalankan otomatis.'
}
elseif ($updateState.RestartPending) {
    'Windows Update memerlukan restart untuk menyelesaikan instalasi. Simpan pekerjaan Anda dan lakukan update/restart sesegera mungkin.'
}
else {
    'Windows Update tersedia untuk diinstal. Lakukan update saat pekerjaan Anda sudah siap disimpan.'
}

$label = New-Object System.Windows.Forms.Label
$label.Text = $message
$label.Location = New-Object System.Drawing.Point(25, 25)
$label.Size = New-Object System.Drawing.Size(450, 75)
$label.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$form.Controls.Add($label)

$updateNowButton = New-Object System.Windows.Forms.Button
$updateNowButton.Text = 'Update now'
$updateNowButton.Location = New-Object System.Drawing.Point(105, 125)
$updateNowButton.Size = New-Object System.Drawing.Size(130, 36)
$updateNowButton.Add_Click({
    $form.Tag = 'UpdateNow'
    $form.Close()
})
$form.Controls.Add($updateNowButton)

$remindLaterButton = New-Object System.Windows.Forms.Button
$remindLaterButton.Text = 'Remind me (in 1 hour)'
$remindLaterButton.Location = New-Object System.Drawing.Point(250, 125)
$remindLaterButton.Size = New-Object System.Drawing.Size(155, 36)
$remindLaterButton.Add_Click({
    $form.Tag = 'RemindLater'
    $form.Close()
})
$form.Controls.Add($remindLaterButton)

[void]$form.ShowDialog()

switch ($form.Tag) {
    'UpdateNow' {
        # Halaman Settings adalah jalur yang aman dan didukung untuk user
        # memulai install/restart; script ini sengaja tidak memaksa restart.
        Start-Process 'ms-settings:windowsupdate'
        Write-Output 'User memilih Update now; Windows Update Settings dibuka.'
    }
    'RemindLater' {
        try {
            $reminderTime = Register-OneHourReminder -ScriptPath $PSCommandPath
            Write-Output "User meminta pengingat ulang pada $($reminderTime.ToString('yyyy-MM-dd HH:mm:ss'))."
        }
        catch {
            Write-Error "Gagal membuat pengingat satu jam: $($_.Exception.Message)"
            exit 1
        }
    }
    default {
        # User menutup dialog. Tidak ada restart atau task baru yang dibuat.
        Write-Output 'Notifikasi ditutup tanpa memilih tindakan.'
    }
}
