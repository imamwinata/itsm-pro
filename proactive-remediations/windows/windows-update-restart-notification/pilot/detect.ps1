<#
.SYNOPSIS
    Mendeteksi apakah Windows Update meminta perangkat untuk di-restart.

.DESCRIPTION
    Script ini digunakan sebagai bagian Detection dari Microsoft Intune
    Proactive Remediations. Windows membuat registry key `RebootRequired`
    setelah update terpasang dan restart diperlukan untuk menyelesaikannya.

    Exit code untuk Proactive Remediations:
    - 0 = perangkat compliant; tidak ada restart Windows Update yang tertunda.
    - 1 = perangkat non-compliant; jalankan remediate.ps1 untuk menampilkan
          notifikasi restart kepada pengguna.

.NOTES
    Jalankan script ini dalam konteks SYSTEM dan gunakan PowerShell 64-bit di
    konfigurasi Intune agar registry Windows 64-bit diperiksa secara konsisten.

    Lokasi log dipilih otomatis:
    - Eksekusi manual: %LOCALAPPDATA%\ITSM-PRO\Logs
    - Eksekusi Intune/SYSTEM: C:\ProgramData\ITSM-PRO\Logs
#>

# Script yang dijalankan lewat Intune biasanya menggunakan identitas SYSTEM.
# Bila test dilakukan manual oleh user, gunakan profil user agar tidak menuntut
# hak administrator untuk membuat folder di ProgramData.
$isSystemContext = ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-18')

if ($isSystemContext) {
    # Dipakai untuk piloting dan rollout melalui Intune.
    $logDirectory = Join-Path -Path $env:ProgramData -ChildPath 'ITSM-PRO\Logs'
}
else {
    # Dipakai saat script dijalankan manual dari sesi PowerShell user.
    $logDirectory = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'ITSM-PRO\Logs'
}

$logFile = Join-Path -Path $logDirectory -ChildPath 'WindowsUpdateRestartNotification-detect.log'

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "$timestamp [$Level] $Message"

    # Tetap tulis ke output supaya hasilnya muncul juga di laporan Intune.
    Write-Output $logEntry

    try {
        if (-not (Test-Path -Path $logDirectory)) {
            New-Item -Path $logDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }

        Add-Content -Path $logFile -Value $logEntry -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        # Jangan menghentikan proses deteksi jika hanya penulisan log yang gagal.
        Write-Output "$timestamp [ERROR] Gagal menulis log: $($_.Exception.Message)"
    }
}

function Get-AvailableWindowsUpdates {
    <#
    Mengambil daftar update software yang masih tersedia untuk diinstal dari
    Windows Update Agent. Daftar ini bersifat informatif untuk notifikasi dan
    tidak selalu merupakan update yang menyebabkan restart saat ini.
    #>
    try {
        $updateSession = New-Object -ComObject 'Microsoft.Update.Session'
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        $searchResult = $updateSearcher.Search("IsInstalled=0 and IsHidden=0 and Type='Software'")

        $updates = foreach ($update in $searchResult.Updates) {
            $kbNumber = if ($update.KBArticleIDs.Count -gt 0) {
                'KB' + ($update.KBArticleIDs -join ', KB')
            }
            else {
                'KB tidak tersedia'
            }

            [PSCustomObject]@{
                Title = $update.Title
                KB    = $kbNumber
            }
        }

        return @($updates)
    }
    catch {
        # Kegagalan query update tidak boleh membatalkan deteksi restart.
        Write-Log -Level 'WARNING' -Message "Tidak dapat mengambil daftar update tersedia: $($_.Exception.Message)"
        return @()
    }
}

function Get-WindowsUpdatePolicySetting {
    <#
    Membaca satu nilai kebijakan Windows Update dari lokasi yang biasa dipakai
    oleh Policy CSP dan Windows Update policy. Fungsi mengembalikan $null jika
    kebijakan tidak diterapkan atau tidak diekspos di perangkat.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $policyLocations = @(
        'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update',
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    )

    foreach ($policyLocation in $policyLocations) {
        try {
            $value = Get-ItemPropertyValue -Path $policyLocation -Name $Name -ErrorAction Stop

            if ($null -ne $value) {
                return [PSCustomObject]@{
                    Name  = $Name
                    Value = $value
                    Path  = $policyLocation
                }
            }
        }
        catch {
            # Coba lokasi kebijakan berikutnya. Tidak perlu dianggap error.
        }
    }

    return $null
}

function Get-TargetWindowsUpdatePolicy {
    <#
    Membaca target policy yang disimpan oleh remediate.ps1 atau
    Set-WindowsUpdateDeadlinePolicy.ps1. Nilai ini merupakan sumber acuan
    compliance, sedangkan registry Windows Update adalah kondisi aktualnya.
    #>
    $configPath = 'HKLM:\SOFTWARE\ITSM-PRO\WindowsUpdateRestartNotification'

    try {
        $config = Get-ItemProperty -Path $configPath -ErrorAction Stop

        return [PSCustomObject]@{
            IsConfigured = $true
            QualityDays  = [int]$config.QualityUpdateDeadlineDays
            FeatureDays  = [int]$config.FeatureUpdateDeadlineDays
            GraceDays    = [int]$config.GracePeriodDays
        }
    }
    catch {
        return [PSCustomObject]@{
            IsConfigured = $false
            QualityDays  = $null
            FeatureDays  = $null
            GraceDays    = $null
        }
    }
}

function Convert-RegistryDateValue {
    <#
    Mengubah format waktu registry yang umum (DateTime, string tanggal, FILETIME
    atau Unix timestamp) menjadi DateTime. Jika format tidak dikenal, $null
    dikembalikan agar nilai mentah tetap dapat dilaporkan.
    #>
    param([object]$Value)

    if ($Value -is [DateTime]) {
        return $Value
    }

    $date = [DateTime]::MinValue
    if ($Value -is [string] -and [DateTime]::TryParse($Value, [ref]$date)) {
        return $date
    }

    try {
        $numericValue = if ($Value -is [byte[]] -and $Value.Length -eq 8) {
            [BitConverter]::ToInt64($Value, 0)
        }
        else {
            [Int64]$Value
        }

        # Windows FILETIME dimulai pada 1 Januari 1601 dan umumnya memiliki
        # nilai 18 digit. Unix timestamp dipakai sebagai fallback untuk nilai
        # 10 digit yang kadang digunakan oleh aplikasi lain.
        if ($numericValue -ge 116444736000000000) {
            return [DateTime]::FromFileTimeUtc($numericValue).ToLocalTime()
        }

        if ($numericValue -ge 946684800 -and $numericValue -le 4102444800) {
            return ([DateTime]'1970-01-01T00:00:00Z').ToLocalTime().AddSeconds($numericValue)
        }
    }
    catch {
        # Format tidak dapat dikonversi; caller akan menampilkan nilai mentah.
    }

    return $null
}

function Get-ScheduledRestartTime {
    <#
    Mencari nilai ScheduleRestartTime yang disimpan Windows Update. Nilai ini
    hanya ada bila Windows memiliki jadwal restart; ketiadaannya bukan error dan
    bukan berarti tidak ada deadline policy.
    #>
    $restartScheduleLocations = @(
        'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings',
        'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\Schedule'
    )

    foreach ($restartScheduleLocation in $restartScheduleLocations) {
        try {
            $value = Get-ItemPropertyValue -Path $restartScheduleLocation -Name 'ScheduleRestartTime' -ErrorAction Stop

            return [PSCustomObject]@{
                RawValue    = $value
                ScheduledAt = Convert-RegistryDateValue -Value $value
                Path        = $restartScheduleLocation
            }
        }
        catch {
            # Coba lokasi berikutnya; nilainya mungkin memang tidak ada.
        }
    }

    return $null
}

# Lokasi ini dibuat oleh Windows Update ketika update yang diinstal membutuhkan
# restart. Tidak seperti indikator reboot lain (misalnya pending file rename),
# key ini spesifik untuk Windows Update.
$windowsUpdateRebootRequiredKey =
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'

try {
    # Test-Path bernilai True hanya ketika key RebootRequired benar-benar ada.
    # Tidak adanya key berarti Windows Update tidak sedang menunggu restart.
    $restartRequired = Test-Path -Path $windowsUpdateRebootRequiredKey

    # Baca target dan nilai policy aktual sebelum menentukan compliance.
    $targetPolicy = Get-TargetWindowsUpdatePolicy
    $qualityDeadline = Get-WindowsUpdatePolicySetting -Name 'ConfigureDeadlineForQualityUpdates'
    $featureDeadline = Get-WindowsUpdatePolicySetting -Name 'ConfigureDeadlineForFeatureUpdates'
    $gracePeriod = Get-WindowsUpdatePolicySetting -Name 'ConfigureDeadlineGracePeriod'

    $policyCompliant = $targetPolicy.IsConfigured -and
        ($null -ne $qualityDeadline) -and ($qualityDeadline.Value -eq $targetPolicy.QualityDays) -and
        ($null -ne $featureDeadline) -and ($featureDeadline.Value -eq $targetPolicy.FeatureDays) -and
        ($null -ne $gracePeriod) -and ($gracePeriod.Value -eq $targetPolicy.GraceDays)

    if (-not $targetPolicy.IsConfigured) {
        Write-Log -Level 'WARNING' -Message 'Target policy belum dikonfigurasi. Remediasi akan menerapkan nilai default.'
    }
    elseif (-not $policyCompliant) {
        Write-Log -Level 'WARNING' -Message "Policy tidak sesuai target. Target: quality $($targetPolicy.QualityDays) hari; feature $($targetPolicy.FeatureDays) hari; grace $($targetPolicy.GraceDays) hari."
    }

    if ($restartRequired) {
        Write-Log -Message 'Windows Update membutuhkan restart. Status: non-compliant.'

        # Tampilkan maksimal lima update agar output Intune tetap ringkas.
        # Ini adalah update yang Windows Update Agent saat ini tawarkan untuk
        # instalasi, bukan klaim bahwa semuanya adalah penyebab restart.
        $availableUpdates = Get-AvailableWindowsUpdates
        if ($availableUpdates.Count -gt 0) {
            Write-Log -Message "Ditemukan $($availableUpdates.Count) update software yang tersedia. Menampilkan maksimal 5."

            foreach ($update in ($availableUpdates | Select-Object -First 5)) {
                Write-Log -Message "Update tersedia: $($update.KB) - $($update.Title)"
            }
        }
        else {
            Write-Log -Level 'WARNING' -Message 'Tidak ada detail update tersedia yang dapat ditampilkan dari Windows Update Agent.'
        }

        # Nilai deadline adalah jumlah hari sejak update tersedia, bukan tanggal
        # deadline absolut. Windows menghitung tanggal aktual per perangkat.
        if ($null -ne $qualityDeadline) {
            Write-Log -Message "Deadline quality update: $($qualityDeadline.Value) hari sejak update tersedia."
        }
        else {
            Write-Log -Level 'WARNING' -Message 'Deadline quality update tidak ditemukan di kebijakan lokal.'
        }

        if ($null -ne $featureDeadline) {
            Write-Log -Message "Deadline feature update: $($featureDeadline.Value) hari sejak update tersedia."
        }
        else {
            Write-Log -Level 'WARNING' -Message 'Deadline feature update tidak ditemukan di kebijakan lokal.'
        }

        if ($null -ne $gracePeriod) {
            Write-Log -Message "Grace period restart dari kebijakan Windows Update: $($gracePeriod.Value) hari."
        }
        else {
            Write-Log -Level 'WARNING' -Message 'Grace period restart tidak ditemukan di kebijakan lokal. Periksa konfigurasi Update Ring di Intune.'
        }

        $scheduledRestart = Get-ScheduledRestartTime
        if ($null -ne $scheduledRestart) {
            if ($null -ne $scheduledRestart.ScheduledAt) {
                Write-Log -Message "ScheduleRestartTime: $($scheduledRestart.ScheduledAt.ToString('yyyy-MM-dd HH:mm:ss')) (waktu lokal perangkat)."
            }
            else {
                Write-Log -Level 'WARNING' -Message "ScheduleRestartTime ditemukan, tetapi format waktunya tidak dikenali. Nilai mentah: $($scheduledRestart.RawValue)"
            }
        }
        else {
            Write-Log -Level 'WARNING' -Message 'ScheduleRestartTime tidak ditemukan. Windows belum menyimpan jadwal restart eksplisit pada perangkat ini.'
        }

        # Exit 1 memberi tahu Intune untuk menjalankan remediate.ps1.
        exit 1
    }

    if (-not $policyCompliant) {
        Write-Log -Message 'Tidak ada restart pending, tetapi Windows Update policy perlu diremediasi. Status: non-compliant.'
        exit 1
    }

    Write-Log -Message 'Tidak ada restart Windows Update yang tertunda. Status: compliant.'

    # Exit 0 memberi tahu Intune bahwa remediasi tidak diperlukan.
    exit 0
}
catch {
    # Kegagalan membaca registry tidak boleh dianggap compliant. Dengan exit 1,
    # kondisi ini akan terlihat pada laporan Intune dan dapat ditangani oleh
    # script remediasi atau investigasi administrator.
    Write-Log -Level 'ERROR' -Message "Gagal memeriksa status restart Windows Update: $($_.Exception.Message)"
    exit 1
}
