<# Simulasi lokal Update Ring; tidak membaca atau mengubah Windows Update asli. #>
[CmdletBinding()]
param(
    [string]$RingPath = (Join-Path $PSScriptRoot 'update-rings\pilot-ring.json'),
    [string]$DeviceStatePath = (Join-Path $PSScriptRoot '../tests/windows-update/device-state.json')
)

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/IntuneReplica.Common.psm1') -Force
$ring = Read-ReplicaJson -Path $RingPath
$device = Read-ReplicaJson -Path $DeviceStatePath
Assert-ReplicaSafeConfiguration -Configuration $ring
Assert-ReplicaSafeConfiguration -Configuration $device

if ($ring.qualityDeadlineDays -notin 2..30 -or $ring.featureDeadlineDays -notin 2..30 -or $ring.gracePeriodDays -notin 0..7) {
    throw 'Nilai deadline/grace period tidak sesuai batas policy Windows Update.'
}

$now = [DateTime]::UtcNow
$results = foreach ($update in $device.updates) {
    if ($update.type -notin @('quality', 'feature')) { throw "Tipe update tidak dikenal: $($update.type)" }
    $deadlineDays = if ($update.type -eq 'quality') { [int]$ring.qualityDeadlineDays } else { [int]$ring.featureDeadlineDays }
    # ConvertFrom-Json dapat mengubah ISO timestamp menjadi DateTime. Hindari
    # cast kembali ke string karena format tanggal dapat salah pada locale berbeda.
    $offered = if ($update.offeredUtc -is [DateTime]) {
        $update.offeredUtc.ToUniversalTime()
    }
    else {
        [DateTime]::Parse([string]$update.offeredUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
    }
    $deadline = $offered.AddDays($deadlineDays)
    $graceEnds = $deadline.AddDays([int]$ring.gracePeriodDays)
    $status = if ($update.installed -and $update.requiresRestart) { 'restart-required' } elseif ($now -gt $graceEnds) { 'enforcement-window-reached' } elseif ($now -gt $deadline) { 'within-grace-period' } else { 'within-deadline' }
    [PSCustomObject]@{ id = $update.id; type = $update.type; deadlineUtc = $deadline.ToString('o'); graceEndsUtc = $graceEnds.ToString('o'); status = $status }
}

$report = [PSCustomObject]@{ generatedUtc = $now.ToString('o'); simulation = 'windows-update'; deviceId = $device.deviceId; restartRequired = [bool]$device.restartRequired; scheduledRestartUtc = $device.scheduledRestartUtc; updates = @($results) }
$reportPath = Join-Path $PSScriptRoot 'reports/windows-update-simulation.json'
Write-ReplicaReport -Report $report -Path $reportPath | Write-Output
