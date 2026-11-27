
# ===========================================
# WIFI PREFERRED BAND DETECTION
# Target: 5 GHz
# ===========================================

$hostname = $env:COMPUTERNAME
$compliant = $true

# Detect physical Wi-Fi adapters
$adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
    Where-Object {
        $_.NdisPhysicalMedium -eq 9
    }

if (-not $adapters) {
    Write-Output "Hostname $hostname - Wi-Fi adapter tidak ditemukan"
    exit 0
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
            $compliant = $false
            continue
        }

        $currentBand = $property.DisplayValue

        # Check current configuration
        if ($currentBand -match "5\s*GHz|5G\s*first|Prefer.*5") {
            Write-Output "Hostname $hostname - $($adapter.Name): Already configured from $currentBand to 5 GHz"
        } else {
            Write-Output "Hostname $hostname - $($adapter.Name): Current band is $currentBand"
            $compliant = $false
        }
    } catch {
        Write-Output "Hostname $hostname - $($adapter.Name): Detection failed"
        Write-Output "Error: $($_.Exception.Message)"
        Write-Output "Error Details: $($_ | Out-String)"
        $compliant = $false
    }
}

if ($compliant) {
    Write-Output "Detection Result: Compliant"
    exit 0
}
else {
    Write-Output "Detection Result: Non-compliant"
    exit 1
}
