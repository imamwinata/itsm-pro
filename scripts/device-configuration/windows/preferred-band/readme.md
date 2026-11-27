Berikut README dalam format Markdown (`README.md`) yang menjelaskan aktivitas dan alur kerja script tersebut. Bisa langsung disimpan sebagai file `README.md`.

markdown

````markdown

# Universal Wi-Fi Preferred Band Configuration

## Overview

PowerShell script untuk mendeteksi dan mengubah konfigurasi **Wi-Fi Preferred Band** menjadi **5 GHz** pada perangkat Windows.

Script dirancang agar dapat digunakan pada berbagai perangkat yang memiliki Wi-Fi adapter dengan dukungan konfigurasi Preferred Band.

## Objective

- Mengidentifikasi physical Wi-Fi adapter pada perangkat.
- Memeriksa konfigurasi Preferred Band saat ini.
- Mengidentifikasi opsi Preferred Band 5 GHz yang tersedia pada driver.
- Mengubah konfigurasi ke 5 GHz jika opsi tersebut tersedia.
- Menghindari perubahan konfigurasi jika perangkat sudah menggunakan preferensi 5 GHz.
- Memberikan informasi hasil eksekusi melalui output PowerShell.

## Script Activities

### 1. Retrieve Device Hostname

Mengambil hostname perangkat menggunakan environment variable Windows.

```powershell
$hostname = $env:COMPUTERNAME
```

Hostname digunakan sebagai identitas perangkat pada output eksekusi.

### 2. Detect Physical Wi-Fi Adapter

Mendeteksi physical network adapter yang menggunakan tipe media Wireless LAN.

```powershell
$adapters = Get-NetAdapter -Physical | Where-Object {
    $_.NdisPhysicalMedium -eq 9
}
```

Script menggunakan `NdisPhysicalMedium` dengan nilai `9` untuk mengidentifikasi Wireless LAN.

Jika tidak ditemukan Wi-Fi adapter, script akan menampilkan pesan:

```text
Hostname DEVICE-NAME Wi-Fi adapter tidak ditemukan
```

### 3. Retrieve Preferred Band Configuration

Mengambil konfigurasi Advanced Properties dari Wi-Fi adapter.

```powershell
$property = Get-NetAdapterAdvancedProperty `
    -Name $adapter.Name `
    -AllProperties `
    -ErrorAction Stop |
    Where-Object {
        $_.DisplayName -match "Preferred Band"
    } |
    Select-Object -First 1
```

Script mencari konfigurasi dengan nama yang mengandung `Preferred Band`.

Jika konfigurasi tidak ditemukan, script akan menampilkan:

```text
Hostname DEVICE-NAME Preferred Band tidak tersedia
```

### 4. Check Current Preferred Band

Membaca nilai Preferred Band yang sedang digunakan.

```powershell
$currentBand = $property.DisplayValue
```

Nilai ini digunakan untuk menentukan apakah konfigurasi perlu diubah.

### 5. Detect Available 5 GHz Option

Membaca seluruh pilihan Preferred Band yang disediakan oleh driver.

```powershell
$fiveGHzOption = @($property.ValidDisplayValues) |
    Where-Object {
        $_ -match "5\s*GHz|5G\s*first|Prefer.*5"
    } |
    Select-Object -First 1
```

Script melakukan pencarian berdasarkan pola teks yang mengindikasikan preferensi 5 GHz.

Contoh opsi yang dapat dikenali:

- Prefer 5 GHz
- 5 GHz first
- 3. 5G first

Pencarian dilakukan secara dinamis berdasarkan opsi yang disediakan driver.

### 6. Evaluate Current Configuration

Script melakukan evaluasi terhadap konfigurasi Preferred Band saat ini.

**Condition A: Already configured to 5 GHz**

Jika konfigurasi saat ini sudah menunjukkan preferensi 5 GHz, tidak ada perubahan yang dilakukan.

Output:

```text
Hostname DEVICE-NAME tidak ada perubahan, sudah 5GHz
```

**Condition B: 5 GHz option available**

Jika konfigurasi belum menunjukkan preferensi 5 GHz dan opsi 5 GHz tersedia, script melanjutkan proses perubahan konfigurasi.

### 7. Apply Preferred Band Configuration

Mengubah konfigurasi Preferred Band menjadi opsi 5 GHz yang ditemukan.

```powershell
Set-NetAdapterAdvancedProperty `
    -Name $adapter.Name `
    -DisplayName $property.DisplayName `
    -DisplayValue $fiveGHzOption `
    -NoRestart `
    -ErrorAction Stop
```

Parameter `-NoRestart` digunakan agar adapter tidak di-restart secara otomatis setelah perubahan konfigurasi.

Jika perintah berhasil dijalankan, output:

```text
Hostname DEVICE-NAME berhasil diubah dari CURRENT-VALUE menjadi 5GHz
```

### 8. Handle Unsupported 5 GHz Configuration

Jika driver tidak menyediakan opsi Preferred Band 5 GHz, script tidak melakukan perubahan konfigurasi.

Output:

```text
Hostname DEVICE-NAME opsi Preferred Band 5GHz tidak tersedia
```

### 9. Error Handling

Script menggunakan mekanisme `try-catch` untuk menangani kesalahan selama proses pemeriksaan dan perubahan konfigurasi.

Jika terjadi kesalahan, script menampilkan:

```text
Hostname DEVICE-NAME gagal mengubah Preferred Band
Error: ERROR MESSAGE
Error Details: ERROR DETAILS
```

Error ditampilkan untuk membantu proses troubleshooting.

## Execution Flow

```text
START
  |
  v
Get Device Hostname
  |
  v
Detect Physical Wi-Fi Adapter
  |
  +---- Not Found
  |       |
  |       v
  |    Display Adapter Not Found
  |       |
  |      END
  |
  v
Get Preferred Band Property
  |
  +---- Not Found
  |       |
  |       v
  |    Display Property Not Available
  |       |
  |    Next Adapter
  |
  v
Get Current Preferred Band
  |
  v
Detect Available 5 GHz Option
  |
  v
Check Current Configuration
  |
  +---- Already 5 GHz
  |       |
  |       v
  |    No Configuration Change
  |
  +---- 5 GHz Option Available
  |       |
  |       v
  |    Apply 5 GHz Configuration
  |       |
  |       v
  |    Display Execution Result
  |
  +---- 5 GHz Option Not Available
          |
          v
       Display Not Available
  |
  v
END
```

## Expected Output

| Scenario | Expected Output |
|---|---|
| Wi-Fi adapter not found | Wi-Fi adapter tidak ditemukan |
| Preferred Band property not found | Preferred Band tidak tersedia |
| Already configured to 5 GHz | Tidak ada perubahan, sudah 5GHz |
| Successfully changed | Berhasil diubah menjadi 5GHz |
| 5 GHz option unavailable | Opsi Preferred Band 5GHz tidak tersedia |
| Configuration failed | Gagal mengubah Preferred Band + Error Details |

## Requirements

- Windows 10 / Windows 11.
- Physical Wi-Fi adapter.
- Wi-Fi driver supporting Advanced Adapter Properties.
- Driver menyediakan konfigurasi Preferred Band.
- Administrator privileges to modify adapter configuration.

## Deployment Considerations

Script dapat digunakan untuk deployment melalui Microsoft Intune Platform Scripts dengan beberapa konfigurasi berikut:

| Configuration | Recommended Value |
|---|---|
| Run using logged-on credentials | No |
| Enforce script signature check | No* |
| Run script in 64-bit PowerShell host | Yes |

*Jika organisasi tidak mewajibkan script signing.*

Disarankan melakukan pengujian pada beberapa model perangkat dan Wi-Fi adapter sebelum deployment secara menyeluruh.

## Important Notes

1. Tidak semua Wi-Fi adapter menyediakan konfigurasi Preferred Band.
2. Nama dan nilai opsi Preferred Band dapat berbeda tergantung vendor dan versi driver.
3. Script menggunakan pencocokan teks untuk mengidentifikasi opsi 5 GHz.
4. `-NoRestart` tidak menjamin perubahan langsung diterapkan pada koneksi Wi-Fi yang sedang aktif.
5. Preferensi 5 GHz tidak memaksa perangkat selalu terkoneksi ke jaringan 5 GHz.
6. Output keberhasilan saat ini menunjukkan perintah konfigurasi berhasil dijalankan, bukan verifikasi independen bahwa driver telah menyimpan nilai baru.

## Conclusion

Script ini mengotomatisasi pemeriksaan dan perubahan konfigurasi Wi-Fi Preferred Band menjadi 5 GHz pada perangkat Windows.

Dengan deteksi adapter dan opsi konfigurasi secara dinamis, script dapat digunakan sebagai dasar standardisasi konfigurasi Wi-Fi pada lingkungan endpoint management.
````