
# ===========================================
# WIFI PREFERRED BAND REMEDIATION
# Target: 5 GHz
# ===========================================

$hostname = $env:COMPUTERNAME
$remediationFailed = $false

# Detect physical Wi-Fi adapters
$adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
    Where-Object {
        $_.NdisPhysicalMedium -eq 9
    }

if (-not $adapters) {
    Write-Output "Hostname $hostname - Wi-Fi adapter tidak ditemukan"
    exit 1
}

foreach ($adapter in $adapters) {
    try {
        # Detect Preferred Band property
        $property = Get-NetAdapterAdvancedProperty `
            -Name $adapter.Name `
            -AllProperties `
            -ErrorAction Stop |
            Where-Object {
                $_.DisplayName -match "Preferred Band"
            } |
            Select-Object -First 1

        if (-not $property) {
            Write-Output "Hostname $hostname - $($adapter.Name): Preferred Band tidak tersedia"
            $remediationFailed = $true
            continue
        }

        $currentBand = $property.DisplayValue

        # Find available 5 GHz option dynamically
        $fiveGHzOption = @($property.ValidDisplayValues) |
            Where-Object {
                $_ -match "5\s*GHz|5G\s*first|Prefer.*5"
            } |
            Select-Object -First 1

        # Already configured to 5 GHz
        if ($currentBand -match "5\s*GHz|5G\s*first|Prefer.*5") {
            Write-Output "Hostname $hostname - $($adapter.Name): Already configured to 5 GHz"
            continue
        }

        # Apply 5 GHz configuration
        if ($fiveGHzOption) {
            Set-NetAdapterAdvancedProperty `
                -Name $adapter.Name `
                -DisplayName $property.DisplayName `
                -DisplayValue $fiveGHzOption `
                -NoRestart `
                -ErrorAction Stop

            # Verify configuration
            $updatedProperty = Get-NetAdapterAdvancedProperty `
                -Name $adapter.Name `
                -AllProperties `
                -ErrorAction Stop |
                Where-Object {
                    $_.DisplayName -eq $property.DisplayName
                } |
                Select-Object -First 1

            if ($updatedProperty.DisplayValue -match "5\s*GHz|5G\s*first|Prefer.*5") {
                Write-Output "Hostname $hostname - $($adapter.Name): Successfully changed from $currentBand to 5 GHz"
            } else {
                Write-Output "Hostname $hostname - $($adapter.Name): Verification failed"
                $remediationFailed = $true
            }
        } else {
            Write-Output "Hostname $hostname - $($adapter.Name): 5 GHz option not available"
            $remediationFailed = $true
        }
    } catch {
        Write-Output "Hostname $hostname - $($adapter.Name): Remediation failed"
        Write-Output "Error: $($_.Exception.Message)"
        Write-Output "Error Details: $($_ | Out-String)"
        $remediationFailed = $true
    }
}

if ($remediationFailed) {
    Write-Output "Remediation Result: Failed"
    exit 1
}
else {
    Write-Output "Remediation Result: Completed"
    exit 0
}
