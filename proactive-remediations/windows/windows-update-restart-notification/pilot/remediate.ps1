<#
.SYNOPSIS
    Menerapkan target deadline Windows Update untuk solusi notifikasi restart.

.DESCRIPTION
    Script ini adalah pasangan detect.ps1 pada Intune Proactive Remediations.
    Ia menyimpan target konfigurasi aplikasi dan menerapkan tiga registry policy
    Windows Update. Script tidak menampilkan toast kepada user karena berjalan
    sebagai SYSTEM; notifikasi interaktif harus dilakukan oleh komponen yang
    berjalan di sesi user.
#>

$ErrorActionPreference = 'Stop'

# Nilai default pilot. Ubah hanya melalui perubahan terkontrol pada script atau
# gunakan Set-WindowsUpdateDeadlinePolicy.ps1 untuk test manual dengan nilai lain.
$targetPolicy = [PSCustomObject]@{
    QualityDays = 7
    FeatureDays = 14
    GraceDays   = 2
}

$applicationConfigPath = 'HKLM:\SOFTWARE\ITSM-PRO\WindowsUpdateRestartNotification'
$windowsUpdatePolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'

function Write-RemediationLog {
    param([Parameter(Mandatory)][string]$Message)

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Output "$timestamp [INFO] $Message"
}

try {
    # Buat key konfigurasi aplikasi dan key policy Windows jika belum tersedia.
    foreach ($path in @($applicationConfigPath, $windowsUpdatePolicyPath)) {
        if (-not (Test-Path -Path $path)) {
            New-Item -Path $path -Force | Out-Null
        }
    }

    # Simpan target. detect.ps1 membaca nilai ini untuk memverifikasi compliance.
    $applicationValues = @(
        @{ Name = 'QualityUpdateDeadlineDays'; Value = $targetPolicy.QualityDays },
        @{ Name = 'FeatureUpdateDeadlineDays'; Value = $targetPolicy.FeatureDays },
        @{ Name = 'GracePeriodDays'; Value = $targetPolicy.GraceDays }
    )

    foreach ($value in $applicationValues) {
        New-ItemProperty -Path $applicationConfigPath -Name $value.Name -Value $value.Value -PropertyType DWord -Force | Out-Null
    }

    # Terapkan policy Windows Update dengan nilai target yang sama.
    $windowsUpdateValues = @(
        @{ Name = 'ConfigureDeadlineForQualityUpdates'; Value = $targetPolicy.QualityDays },
        @{ Name = 'ConfigureDeadlineForFeatureUpdates'; Value = $targetPolicy.FeatureDays },
        @{ Name = 'ConfigureDeadlineGracePeriod'; Value = $targetPolicy.GraceDays }
    )

    foreach ($value in $windowsUpdateValues) {
        New-ItemProperty -Path $windowsUpdatePolicyPath -Name $value.Name -Value $value.Value -PropertyType DWord -Force | Out-Null
    }

    Write-RemediationLog -Message "Target dan Windows Update policy berhasil diterapkan: quality $($targetPolicy.QualityDays) hari, feature $($targetPolicy.FeatureDays) hari, grace $($targetPolicy.GraceDays) hari."
    exit 0
}
catch {
    Write-Error "Gagal menerapkan Windows Update policy: $($_.Exception.Message)"
    exit 1
}
