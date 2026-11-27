Set-StrictMode -Version Latest

function Read-ReplicaJson {
    param([Parameter(Mandatory)][string]$Path)

    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($file.Length -gt 1MB) {
        throw "File konfigurasi melebihi batas aman 1 MB: $Path"
    }

    try {
        return (Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop)
    }
    catch {
        throw "JSON tidak valid pada $Path : $($_.Exception.Message)"
    }
}

function Find-ReplicaSensitiveValue {
    param($Value, [string]$Path = '$')

    if ($null -eq $Value) { return }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string] -and $Value -isnot [pscustomobject]) {
        $index = 0
        foreach ($item in $Value) {
            Find-ReplicaSensitiveValue -Value $item -Path "$Path[$index]"
            $index++
        }
        return
    }

    if ($Value -is [pscustomobject]) {
        foreach ($property in $Value.PSObject.Properties) {
            if ($property.Name -match '(?i)(password|secret|token|private.?key|client.?secret)') {
                if ($null -ne $property.Value -and [string]$property.Value -ne '') {
                    Write-Output "$Path.$($property.Name)"
                }
            }
            Find-ReplicaSensitiveValue -Value $property.Value -Path "$Path.$($property.Name)"
        }
    }
}

function Assert-ReplicaSafeConfiguration {
    param([Parameter(Mandatory)]$Configuration)

    $sensitivePaths = @(Find-ReplicaSensitiveValue -Value $Configuration)
    if ($sensitivePaths.Count -gt 0) {
        throw "Konfigurasi berisi field rahasia yang tidak diizinkan: $($sensitivePaths -join ', ')"
    }
}

function Write-ReplicaReport {
    param(
        [Parameter(Mandatory)]$Report,
        [Parameter(Mandatory)][string]$Path
    )

    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $Report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8
    return $Path
}

Export-ModuleMember -Function Read-ReplicaJson, Assert-ReplicaSafeConfiguration, Write-ReplicaReport
