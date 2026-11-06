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
param()

$ErrorActionPreference = 'Stop'

$windowsUpdatePolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$applicationConfigPath = 'HKLM:\SOFTWARE\ITSM-PRO\WindowsUpdateRestartNotification'

# Hanya nilai yang sebelumnya dikelola oleh script ITSM-PRO yang dihapus.
$managedPolicyValues = @(
    'ConfigureDeadlineForQualityUpdates',
    'ConfigureDeadlineForFeatureUpdates',
    'ConfigureDeadlineGracePeriod'
)

try {
    if (Test-Path -Path $windowsUpdatePolicyPath) {
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
    else {
        Write-Output 'Key policy Windows Update tidak ditemukan; tidak ada nilai policy yang perlu dihapus.'
    }

    # Key ini khusus untuk solusi ITSM-PRO sehingga aman dihapus seluruhnya.
    # Tidak ada key policy Windows atau konfigurasi solusi lain yang dihapus.
    if (Test-Path -Path $applicationConfigPath) {
        if ($PSCmdlet.ShouldProcess($applicationConfigPath, 'Hapus konfigurasi solusi ITSM-PRO')) {
            Remove-Item -Path $applicationConfigPath -Recurse -Force
            Write-Output 'Dihapus: konfigurasi ITSM-PRO Windows Update Restart Notification.'
        }
    }
    else {
        Write-Output 'Tidak ada perubahan: konfigurasi solusi ITSM-PRO tidak ditemukan.'
    }

    Write-Output 'Reset Windows Update deadline policy selesai.'
    exit 0
}
catch {
    Write-Error "Gagal mereset Windows Update deadline policy: $($_.Exception.Message)"
    exit 1
}
