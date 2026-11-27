<# Simulasi keputusan aplikasi; tidak memasang, menghapus, atau mengunduh aplikasi. #>
[CmdletBinding()]
param(
    [string]$PolicyPath = (Join-Path $PSScriptRoot 'win32-apps\pilot-app-policy.json'),
    [string]$InventoryPath = (Join-Path $PSScriptRoot '../tests/application-update/application-inventory.json')
)

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/IntuneReplica.Common.psm1') -Force
$policy = Read-ReplicaJson -Path $PolicyPath
$inventory = Read-ReplicaJson -Path $InventoryPath
Assert-ReplicaSafeConfiguration -Configuration $policy
Assert-ReplicaSafeConfiguration -Configuration $inventory

$decisions = foreach ($appPolicy in $policy.apps) {
    $installed = @($inventory.apps | Where-Object { $_.id -eq $appPolicy.id } | Select-Object -First 1)
    $action = if ($installed.Count -eq 0) { 'install-required' } elseif ([version]$installed[0].installedVersion -lt [version]$appPolicy.desiredVersion) { 'update-required' } else { 'compliant' }
    $legacyAction = if ($appPolicy.supersedes -and $appPolicy.allowUninstallLegacy -and (@($inventory.apps | Where-Object { $_.id -eq $appPolicy.supersedes }).Count -gt 0)) { 'legacy-uninstall-after-validation' } else { 'none' }
    [PSCustomObject]@{ id = $appPolicy.id; action = $action; legacyAction = $legacyAction }
}

$report = [PSCustomObject]@{ generatedUtc = [DateTime]::UtcNow.ToString('o'); simulation = 'application-update'; deviceId = $inventory.deviceId; decisions = @($decisions) }
Write-ReplicaReport -Report $report -Path (Join-Path $PSScriptRoot 'reports/application-update-simulation.json') | Write-Output
