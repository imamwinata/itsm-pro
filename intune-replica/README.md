# Intune Replica

Kerangka lokal untuk mendokumentasikan, membuat script, menguji, dan mengelola
fitur update yang setara dengan area Microsoft Intune. Folder ini bukan salinan
tenant Intune; konfigurasi tetap perlu dideploy melalui Intune atau Microsoft
Graph sesuai proses organisasi.

## Area fitur

| Area | Cakupan |
| --- | --- |
| `windows-update/` | Update rings, quality/feature/expedited updates, delivery optimization, notifikasi, dan laporan. |
| `driver-update/` | Profile driver, approval/review, aksi manual, dan laporan. |
| `application-update/` | Win32, Microsoft Store, Microsoft 365 Apps, aplikasi pihak ketiga, supersedence, uninstall, dan laporan. |
| `shared/` | Konfigurasi, schema, script reusable, template, dan log lokal. |
| `tests/` | Test pilot dan validasi per area. |

## Pola kerja

1. Simpan konfigurasi deklaratif di folder area fitur terkait.
2. Simpan script deployment/remediasi di `shared/scripts/` atau subfolder solusi.
3. Uji dahulu dengan target pilot di `tests/`.
4. Simpan hasil dan prosedur rollback di folder `reports/` atau `docs/`.

Jangan menyimpan credential, token Graph, atau rahasia tenant di repository.

## Menjalankan simulasi

Jalankan dari PowerShell di root `intune-replica`:

```powershell
.\Invoke-AllSimulations.ps1
```

Simulator hanya membaca JSON contoh dan menghasilkan laporan JSON pada folder
`reports/`. Ia tidak memanggil Intune/Graph, mengunduh payload, menjalankan
installer, mengubah registry, atau mengubah konfigurasi Windows.

Lihat [security model](docs/SECURITY.md) untuk batasan keamanan simulator.
