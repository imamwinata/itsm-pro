<#
.SYNOPSIS
    Menghapus konfigurasi deadline Windows Update yang dibuat oleh script ITSM-PRO.

.DESCRIPTION
    Script ini membatalkan perubahan yang dibuat oleh
    Set-WindowsUpdateDeadlinePolicy.ps1 dan remediate.ps1 pada solusi restart
    notification. Nilai yang dihapus hanya:

    - ConfigureDeadlineForQualityUpdates
    - ConfigureDeadlineForFeatureUpdates
    - ConfigureDeadlineGracePeriod

    Script juga menghapus key konfigurasi solusi:
    HKLM\SOFTWARE\ITSM-PRO\WindowsUpdateRestartNotification

    Saat dijalankan oleh user yang memasang notifier, script turut menghapus
    startup entry, protocol handler, dan file notifikasi milik user tersebut.

    Key Windows Update induk tidak dihapus agar policy lain yang mungkin dibuat
    oleh organisasi, Group Policy, atau Intune tetap tidak terpengaruh.

.NOTES
    Jalankan sebagai Administrator atau SYSTEM.

    Bila Intune Update Ring, Settings Catalog, atau Proactive Remediation masih
    di-assign ke perangkat, policy dapat diterapkan kembali pada sync berikutnya.
    Unassign atau nonaktifkan deployment tersebut terlebih dahulu bila reset
    dimaksudkan untuk bersifat permanen.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    # Hapus hanya notifier user tanpa mengubah registry policy Windows Update.
    # Opsi ini dapat dijalankan user biasa yang memasang notifier.
    [switch]$NotificationOnly
)

$ErrorActionPreference = 'Stop'

$windowsUpdatePolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$applicationConfigPath = 'HKLM:\SOFTWARE\ITSM-PRO\WindowsUpdateRestartNotification'
$notificationRunKeyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$notificationRunValueName = 'ITSM-PRO-WindowsUpdateNotification'
$notificationProtocolPath = 'HKCU:\Software\Classes\itsm-pro-windowsupdate'
$notificationScriptsPath = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'ITSM-PRO\Scripts'

# Hanya nilai yang sebelumnya dikelola oleh script ITSM-PRO yang dihapus.
$managedPolicyValues = @(
    'ConfigureDeadlineForQualityUpdates',
    'ConfigureDeadlineForFeatureUpdates',
    'ConfigureDeadlineGracePeriod'
)

try {
    if (-not $NotificationOnly -and (Test-Path -Path $windowsUpdatePolicyPath)) {
        foreach ($valueName in $managedPolicyValues) {
            # Ambil nilai lebih dahulu agar output membedakan nilai yang ada
            # dengan nilai yang memang belum pernah diterapkan.
            $existingValue = Get-ItemPropertyValue -Path $windowsUpdatePolicyPath -Name $valueName -ErrorAction SilentlyContinue

            if ($null -ne $existingValue) {
                if ($PSCmdlet.ShouldProcess($windowsUpdatePolicyPath, "Hapus $valueName")) {
                    Remove-ItemProperty -Path $windowsUpdatePolicyPath -Name $valueName -Force
                    Write-Output "Dihapus: $valueName (nilai sebelumnya: $existingValue)."
                }
            }
            else {
                Write-Output "Tidak ada perubahan: $valueName tidak ditemukan."
            }
        }
    }
    elseif (-not $NotificationOnly) {
        Write-Output 'Key policy Windows Update tidak ditemukan; tidak ada nilai policy yang perlu dihapus.'
    }

    # Key ini khusus untuk solusi ITSM-PRO sehingga aman dihapus seluruhnya.
    # Tidak ada key policy Windows atau konfigurasi solusi lain yang dihapus.
    if (-not $NotificationOnly -and (Test-Path -Path $applicationConfigPath)) {
        if ($PSCmdlet.ShouldProcess($applicationConfigPath, 'Hapus konfigurasi solusi ITSM-PRO')) {
            Remove-Item -Path $applicationConfigPath -Recurse -Force
            Write-Output 'Dihapus: konfigurasi ITSM-PRO Windows Update Restart Notification.'
        }
    }
    elseif (-not $NotificationOnly) {
        Write-Output 'Tidak ada perubahan: konfigurasi solusi ITSM-PRO tidak ditemukan.'
    }

    if ($NotificationOnly) {
        Write-Output 'Mode NotificationOnly: registry policy Windows Update tidak diubah.'
    }

    # Komponen notifikasi berada di profil user (HKCU dan LOCALAPPDATA). Jika
    # reset dijalankan sebagai SYSTEM melalui Intune, HKCU menunjuk ke profil
    # SYSTEM sehingga notifier milik user login tidak boleh dihapus dari sini.
    $isSystemContext = ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-18')
    if ($isSystemContext) {
        Write-Warning 'Reset dijalankan sebagai SYSTEM; startup notifier user tidak dihapus. Jalankan reset sebagai user yang memasang notifier untuk menghapusnya.'
    }
    else {
        if (Test-Path -Path $notificationRunKeyPath) {
            $startupEntry = Get-ItemPropertyValue -Path $notificationRunKeyPath -Name $notificationRunValueName -ErrorAction SilentlyContinue
            if ($null -ne $startupEntry -and $PSCmdlet.ShouldProcess($notificationRunKeyPath, "Hapus startup entry $notificationRunValueName")) {
                Remove-ItemProperty -Path $notificationRunKeyPath -Name $notificationRunValueName -Force
                Write-Output 'Dihapus: startup entry Windows Update notification.'
            }
        }

        if (Test-Path -Path $notificationProtocolPath -and $PSCmdlet.ShouldProcess($notificationProtocolPath, 'Hapus protocol handler notifier')) {
            Remove-Item -Path $notificationProtocolPath -Recurse -Force
            Write-Output 'Dihapus: protocol handler Windows Update notification.'
        }

        # Hapus hanya folder script yang dibuat installer, bukan seluruh profil.
        if (Test-Path -Path $notificationScriptsPath -and $PSCmdlet.ShouldProcess($notificationScriptsPath, 'Hapus file Windows Update notifier')) {
            Remove-Item -Path $notificationScriptsPath -Recurse -Force
            Write-Output 'Dihapus: file Windows Update notifier pada profil user.'
        }
    }

    Write-Output 'Reset Windows Update deadline policy selesai.'
    exit 0
}
catch {
    Write-Error "Gagal mereset Windows Update deadline policy: $($_.Exception.Message)"
    exit 1
}
