<# Simulasi keputusan deployment driver; tidak memasang driver. #>
[CmdletBinding()]
param(
    [string]$ProfilePath = (Join-Path $PSScriptRoot 'update-profiles\pilot-drivers.json'),
    [string]$InventoryPath = (Join-Path $PSScriptRoot '../tests/driver-update/driver-inventory.json')
)

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/IntuneReplica.Common.psm1') -Force
$profile = Read-ReplicaJson -Path $ProfilePath
$inventory = Read-ReplicaJson -Path $InventoryPath
Assert-ReplicaSafeConfiguration -Configuration $profile
Assert-ReplicaSafeConfiguration -Configuration $inventory

$decisions = foreach ($driver in $inventory.drivers) {
    $reason = if ($driver.manufacturer -notin $profile.allowedManufacturers) { 'manufacturer-not-allowed' } elseif ($driver.category -in $profile.blockedCategories) { 'category-blocked' } elseif (-not $driver.compatible) { 'not-compatible' } elseif ($profile.requireApproval -and -not $driver.approved) { 'not-approved' } else { 'eligible-for-pilot' }
    [PSCustomObject]@{ id = $driver.id; decision = $reason }
}

$report = [PSCustomObject]@{ generatedUtc = [DateTime]::UtcNow.ToString('o'); simulation = 'driver-update'; deviceId = $inventory.deviceId; decisions = @($decisions) }
Write-ReplicaReport -Report $report -Path (Join-Path $PSScriptRoot 'reports/driver-update-simulation.json') | Write-Output
