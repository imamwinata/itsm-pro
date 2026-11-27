$hostname = $env:COMPUTERNAME

$adapters = Get-NetAdapter | Where-Object {
    $_.PhysicalMediaType -eq "Native 802.11"
}

foreach ($adapter in $adapters) {

    $property = Get-NetAdapterAdvancedProperty `
        -Name $adapter.Name `
        -AllProperties |
        Where-Object { $_.DisplayName -match "^Preferred Band$" } |
        Select-Object -First 1

    if (-not $property) {
        continue
    }

    $currentBand = $property.DisplayValue

    $fiveGHzOption = $property.ValidDisplayValues |
        Where-Object { $_ -match "5\s*GHz" } |
        Select-Object -First 1

    if ($currentBand -match "5\s*GHz") {
        Write-Output "Hostname $hostname tidak ada perubahan, sudah 5GHz"
    }
    elseif ($currentBand -match "2\.4\s*GHz" -and $fiveGHzOption) {

        try {
            Set-NetAdapterAdvancedProperty `
                -Name $adapter.Name `
                -DisplayName $property.DisplayName `
                -DisplayValue $fiveGHzOption `
                -NoRestart `
                -ErrorAction Stop

            Write-Output "Hostname $hostname berhasil diubah dari 2.4GHz menjadi 5GHz"
        }
        catch {
            Write-Output "Hostname $hostname gagal mengubah Preferred Band"
        }
    }
}