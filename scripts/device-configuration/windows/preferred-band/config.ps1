
# ==========================================
# UNIVERSAL WIFI PREFERRED BAND CONFIGURATION
# Target: 5 GHz
# ==========================================

$hostname = $env:COMPUTERNAME

# Detect physical Wi-Fi adapters
$adapters = Get-NetAdapter -Physical | Where-Object {
    $_.NdisPhysicalMedium -eq 9
}

if (-not $adapters) {
    Write-Output "Hostname $hostname Wi-Fi adapter tidak ditemukan"
    return
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
            Write-Output "Hostname $hostname Preferred Band tidak tersedia"
            continue
        }

        # Get current configuration
        $currentBand = $property.DisplayValue

        # Detect available 5 GHz option dynamically
        $fiveGHzOption = $property.ValidDisplayValues |
            Where-Object {
                $_ -match "5\s*GHz|5G\s*first|Prefer.*5"
            } |
            Select-Object -First 1

        # Already configured to 5 GHz
        if ($currentBand -match "5\s*GHz|5G\s*first|Prefer.*5") {

            Write-Output "Hostname $hostname tidak ada perubahan, sudah 5GHz"

        }

        # Change to 5 GHz
        elseif ($fiveGHzOption) {

            Set-NetAdapterAdvancedProperty `
                -Name $adapter.Name `
                -DisplayName $property.DisplayName `
                -DisplayValue $fiveGHzOption `
                -NoRestart `
                -ErrorAction Stop

            Write-Output "Hostname $hostname berhasil diubah dari $currentBand menjadi 5GHz"

        }

        else {

            Write-Output "Hostname $hostname opsi Preferred Band 5GHz tidak tersedia"

        }

    }
    catch {

        Write-Output "Hostname $hostname gagal mengubah Preferred Band"

    }
}
