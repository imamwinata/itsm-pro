<#
.SYNOPSIS
    Mengatur deadline Windows Update dan grace period melalui registry policy.

.DESCRIPTION
    Script ini membuat atau memperbarui policy Windows Update berikut pada
    perangkat lokal:

    - ConfigureDeadlineForQualityUpdates : deadline quality update dalam hari.
    - ConfigureDeadlineForFeatureUpdates : deadline feature update dalam hari.
    - ConfigureDeadlineGracePeriod       : tambahan waktu restart dalam hari.

    Nilai ini dapat dibaca oleh detect.ps1 pada solusi
    windows-update-restart-notification.

    PERINGATAN
    Jika setting yang sama dikelola oleh Intune Update Ring, Settings Catalog,
    atau Group Policy, policy pusat dapat menimpa nilai dari script ini saat
    perangkat melakukan sync. Gunakan script ini hanya untuk pilot atau bila
    organisasi memang memilih registry policy sebagai sumber konfigurasi.

.NOTES
    Jalankan dalam konteks Administrator atau SYSTEM. Nilai default:
    quality update = 7 hari, feature update = 14 hari, grace period = 2 hari.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    # Microsoft mendukung deadline update pada rentang 2 sampai 30 hari.
    [ValidateRange(2, 30)]
    [int]$QualityUpdateDeadlineDays = 7,

    [ValidateRange(2, 30)]
    [int]$FeatureUpdateDeadlineDays = 14,

    # Grace period restart dapat bernilai 0 sampai 7 hari.
    [ValidateRange(0, 7)]
    [int]$GracePeriodDays = 2
)

$ErrorActionPreference = 'Stop'

# Lokasi registry policy Windows Update yang digunakan untuk konfigurasi lokal.
$policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'

# Lokasi konfigurasi aplikasi. detect.ps1 membaca nilai ini sebagai target saat
# memeriksa compliance, sehingga tidak ada angka target yang tersembunyi di
# dalam script detection.
$applicationConfigPath = 'HKLM:\SOFTWARE\ITSM-PRO\WindowsUpdateRestartNotification'

# Definisikan nilai policy dalam satu koleksi supaya mudah ditambah atau diubah.
$policySettings = @(
    @{ Name = 'ConfigureDeadlineForQualityUpdates'; Value = $QualityUpdateDeadlineDays; Description = 'deadline quality update' },
    @{ Name = 'ConfigureDeadlineForFeatureUpdates'; Value = $FeatureUpdateDeadlineDays; Description = 'deadline feature update' },
    @{ Name = 'ConfigureDeadlineGracePeriod'; Value = $GracePeriodDays; Description = 'grace period restart' }
)

try {
    # Buat key policy jika perangkat belum memilikinya.
    if (-not (Test-Path -Path $policyPath)) {
        New-Item -Path $policyPath -Force | Out-Null
    }

    if (-not (Test-Path -Path $applicationConfigPath)) {
        New-Item -Path $applicationConfigPath -Force | Out-Null
    }

    # Simpan target policy untuk dipakai detect.ps1 dan komponen notifikasi.
    $applicationSettings = @(
        @{ Name = 'QualityUpdateDeadlineDays'; Value = $QualityUpdateDeadlineDays },
        @{ Name = 'FeatureUpdateDeadlineDays'; Value = $FeatureUpdateDeadlineDays },
        @{ Name = 'GracePeriodDays'; Value = $GracePeriodDays }
    )

    foreach ($setting in $applicationSettings) {
        New-ItemProperty -Path $applicationConfigPath -Name $setting.Name -Value $setting.Value -PropertyType DWord -Force | Out-Null
    }

    foreach ($setting in $policySettings) {
        if ($PSCmdlet.ShouldProcess($policyPath, "Set $($setting.Name) menjadi $($setting.Value) hari")) {
            # -Force membuat nilai baru atau mengganti nilai yang sudah ada.
            # DWord memastikan format registry sesuai yang diharapkan Windows.
            New-ItemProperty -Path $policyPath -Name $setting.Name -Value $setting.Value -PropertyType DWord -Force | Out-Null
            Write-Output "Berhasil mengatur $($setting.Description): $($setting.Value) hari."
        }
    }

    Write-Output 'Windows Update deadline policy berhasil dikonfigurasi.'
    Write-Output 'Lakukan sync policy Intune atau restart perangkat bila policy belum segera terbaca oleh Windows Update.'
    exit 0
}
catch {
    Write-Error "Gagal mengatur Windows Update deadline policy: $($_.Exception.Message)"
    exit 1
}
