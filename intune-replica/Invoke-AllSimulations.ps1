<# Menjalankan seluruh simulator lokal. Tidak melakukan perubahan pada Intune atau perangkat. #>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'windows-update/Invoke-WindowsUpdateSimulation.ps1')
& (Join-Path $PSScriptRoot 'driver-update/Invoke-DriverUpdateSimulation.ps1')
& (Join-Path $PSScriptRoot 'application-update/Invoke-ApplicationUpdateSimulation.ps1')
