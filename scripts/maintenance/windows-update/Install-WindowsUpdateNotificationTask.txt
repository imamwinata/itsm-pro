<#
.SYNOPSIS
    Menginstal startup notifier user untuk Windows Update.

.DESCRIPTION
    Script ini menyalin Show-WindowsUpdateNotification.ps1 ke profil user saat
    ini, kemudian membuat startup entry pada profil user. Startup entry berjalan
    satu jam setelah user login. Script notifikasi tetap melakukan
    pengecekan update/restart sendiri, sehingga dialog hanya tampil bila Windows
    Update memerlukan tindakan.

.NOTES
    Jalankan script ini sebagai user yang sedang login, bukan SYSTEM. Kedua file
    harus dideploy bersama melalui Win32 app atau metode lain yang menjaga file
    sumber tetap berada dalam folder yang sama saat installer dijalankan.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$sourceNotificationScript = Join-Path -Path $PSScriptRoot -ChildPath 'Show-WindowsUpdateNotification.ps1'
$targetDirectory = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'ITSM-PRO\Scripts'
$targetNotificationScript = Join-Path -Path $targetDirectory -ChildPath 'Show-WindowsUpdateNotification.ps1'
$startupBootstrapScript = Join-Path -Path $targetDirectory -ChildPath 'Start-WindowsUpdateNotificationAfterDelay.ps1'
$toastAppId = 'ITSM-PRO.WindowsUpdateNotification'

# Nilai pilot: jalankan pemeriksaan 15 menit setelah user login.
# Tombol "Remind me (in 1 hour)" pada toast tetap menggunakan 60 menit.
$startupDelaySeconds = 900

function Register-ToastAppId {
    param(
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$PowerShellPath,
        [Parameter(Mandatory)][string]$NotificationScriptPath
    )

    # Aplikasi desktop perlu shortcut Start Menu dengan AppUserModelID agar
    # Windows mengenalinya sebagai pengirim native toast notification.
    $shortcutCode = @'
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

namespace ITSMPro {
    [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
    public class ShellLink { }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("000214F9-0000-0000-C000-000000000046")]
    public interface IShellLinkW {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder path, int cch, IntPtr findData, uint flags);
        void GetIDList(out IntPtr itemIdList);
        void SetIDList(IntPtr itemIdList);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder description, int cch);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string description);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder directory, int cch);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string directory);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder arguments, int cch);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string arguments);
        ushort GetHotkey();
        void SetHotkey(ushort hotkey);
        uint GetShowCmd();
        void SetShowCmd(uint showCommand);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder iconPath, int cch, out int iconIndex);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string iconPath, int iconIndex);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string relativePath, uint reserved);
        void Resolve(IntPtr windowHandle, uint flags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string filePath);
    }

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    public struct PropertyKey {
        public Guid FormatId;
        public uint PropertyId;
        public PropertyKey(Guid formatId, uint propertyId) { FormatId = formatId; PropertyId = propertyId; }
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct PropVariant {
        [FieldOffset(0)] public ushort ValueType;
        [FieldOffset(8)] public IntPtr PointerValue;
        [DllImport("ole32.dll")]
        private static extern int PropVariantClear(ref PropVariant value);
        public static PropVariant FromString(string value) {
            PropVariant result = new PropVariant();
            result.ValueType = 31; // VT_LPWSTR
            result.PointerValue = Marshal.StringToCoTaskMemUni(value);
            return result;
        }
        public void Clear() { PropVariantClear(ref this); }
    }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
    public interface IPropertyStore {
        void GetCount(out uint propertyCount);
        void GetAt(uint propertyIndex, out PropertyKey key);
        void GetValue(ref PropertyKey key, out PropVariant value);
        void SetValue(ref PropertyKey key, ref PropVariant value);
        void Commit();
    }

    public static class ToastShortcut {
        public static void Create(string shortcutPath, string targetPath, string arguments, string appId) {
            IShellLinkW shortcut = (IShellLinkW)new ShellLink();
            shortcut.SetPath(targetPath);
            shortcut.SetArguments(arguments);
            shortcut.SetDescription("ITSM-PRO Windows Update Notification");
            IPropertyStore store = (IPropertyStore)shortcut;
            PropertyKey appIdKey = new PropertyKey(new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), 5);
            PropVariant appIdValue = PropVariant.FromString(appId);
            try {
                store.SetValue(ref appIdKey, ref appIdValue);
                store.Commit();
                ((IPersistFile)shortcut).Save(shortcutPath, true);
            }
            finally {
                appIdValue.Clear();
                Marshal.ReleaseComObject(shortcut);
            }
        }
    }
}
'@

    if (-not ('ITSMPro.ToastShortcut' -as [type])) {
        Add-Type -TypeDefinition $shortcutCode -ErrorAction Stop
    }

    $startMenuDirectory = Join-Path -Path $env:APPDATA -ChildPath 'Microsoft\Windows\Start Menu\Programs\ITSM-PRO'
    $shortcutPath = Join-Path -Path $startMenuDirectory -ChildPath 'Windows Update Notification.lnk'
    New-Item -Path $startMenuDirectory -ItemType Directory -Force | Out-Null
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$NotificationScriptPath`""
    [ITSMPro.ToastShortcut]::Create($shortcutPath, $PowerShellPath, $arguments, $AppId)
}

try {
    if (-not [Environment]::UserInteractive) {
        throw 'Installer harus dijalankan pada sesi user interaktif, bukan SYSTEM.'
    }

    if (-not (Test-Path -Path $sourceNotificationScript)) {
        throw "Script notifikasi tidak ditemukan: $sourceNotificationScript"
    }

    # Simpan salinan lokal agar startup notifier tidak bergantung pada cache atau
    # lokasi temporary Intune setelah script deployment selesai.
    New-Item -Path $targetDirectory -ItemType Directory -Force | Out-Null
    Copy-Item -Path $sourceNotificationScript -Destination $targetNotificationScript -Force

    $powerShellPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'

    # Daftarkan AppUserModelID sebelum notifier digunakan. Tanpa shortcut ini,
    # Windows dapat menerima request toast tetapi tidak menampilkan bannernya.
    Register-ToastAppId -AppId $toastAppId -PowerShellPath $powerShellPath -NotificationScriptPath $targetNotificationScript

    # Daftarkan protocol handler untuk tombol "Remind me (in 10 minutes)" pada
    # native toast. Handler berada di HKCU sehingga tidak memerlukan admin.
    $protocolPath = 'HKCU:\Software\Classes\itsm-pro-windowsupdate'
    $protocolCommandPath = Join-Path -Path $protocolPath -ChildPath 'shell\open\command'
    New-Item -Path $protocolCommandPath -Force | Out-Null
    New-ItemProperty -Path $protocolPath -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null

    $protocolCommand = "`"$powerShellPath`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$targetNotificationScript`" -ActionUri `"%1`""
    Set-Item -Path $protocolCommandPath -Value $protocolCommand

    # Startup entry user menjalankan bootstrap tanpa hak Administrator. Bootstrap
    # menunggu sesuai nilai pilot lalu memanggil notifier yang disalin ke profil user.
    $escapedNotificationPath = $targetNotificationScript.Replace("'", "''")
    $bootstrapContent = "Start-Sleep -Seconds $startupDelaySeconds`r`n& '$escapedNotificationPath'"
    Set-Content -Path $startupBootstrapScript -Value $bootstrapContent -Encoding UTF8 -Force

    $runKeyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $runValueName = 'ITSM-PRO-WindowsUpdateNotification'
    $runCommand = "`"$powerShellPath`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$startupBootstrapScript`""
    New-ItemProperty -Path $runKeyPath -Name $runValueName -Value $runCommand -PropertyType String -Force | Out-Null

    Write-Output "Startup entry '$runValueName' berhasil dibuat untuk user saat ini."
    Write-Output "Script notifikasi tersimpan di: $targetNotificationScript"
    Write-Output 'Protocol handler toast berhasil didaftarkan untuk user saat ini.'
    Write-Output 'Notifikasi akan diperiksa 15 menit setelah login berikutnya.'
    exit 0
}
catch {
    Write-Error "Gagal menginstal Windows Update startup notifier: $($_.Exception.Message)"
    exit 1
}
