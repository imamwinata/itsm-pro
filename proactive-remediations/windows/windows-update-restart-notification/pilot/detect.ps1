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

function Get-WindowsUpdateGracePeriod {
    <#
    Membaca ConfigureDeadlineGracePeriod (dalam hari) bila kebijakan tersebut
    diterapkan. Intune/Windows tidak selalu menulis nilai ini secara lokal,
    sehingga fungsi mengembalikan $null bila nilai tidak tersedia.
    #>
    $policyLocations = @(
        'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update',
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    )

    foreach ($policyLocation in $policyLocations) {
        try {
            $gracePeriod = Get-ItemPropertyValue -Path $policyLocation -Name 'ConfigureDeadlineGracePeriod' -ErrorAction Stop

            if ($null -ne $gracePeriod) {
                return [int]$gracePeriod
            }
        }
        catch {
            # Coba lokasi kebijakan berikutnya. Tidak perlu dianggap error.
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

        # Grace period ini adalah nilai ConfigureDeadlineGracePeriod bila
        # kebijakan Windows Update/Intune menuliskannya ke perangkat.
        $gracePeriodDays = Get-WindowsUpdateGracePeriod
        if ($null -ne $gracePeriodDays) {
            Write-Log -Message "Grace period restart dari kebijakan Windows Update: $gracePeriodDays hari."
        }
        else {
            Write-Log -Level 'WARNING' -Message 'Grace period restart tidak ditemukan di kebijakan lokal. Periksa konfigurasi Update Ring di Intune.'
        }

        # Exit 1 memberi tahu Intune untuk menjalankan remediate.ps1.
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
