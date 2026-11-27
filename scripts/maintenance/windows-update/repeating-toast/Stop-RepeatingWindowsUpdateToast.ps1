<#
.SYNOPSIS
    Menghentikan script Start-RepeatingWindowsUpdateToast.ps1 pada sesi user.

.DESCRIPTION
    Membuat file sinyal stop pada profil user. Script repeating memeriksa file
    tersebut setiap maksimum satu menit lalu berhenti dengan aman.
#>

$stateDirectory = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'ITSM-PRO\State'
$stopFile = Join-Path -Path $stateDirectory -ChildPath 'Stop-RepeatingWindowsUpdateToast.flag'

New-Item -Path $stateDirectory -ItemType Directory -Force | Out-Null
New-Item -Path $stopFile -ItemType File -Force | Out-Null
Write-Output 'Sinyal stop untuk repeating Windows Update toast telah dibuat.'
