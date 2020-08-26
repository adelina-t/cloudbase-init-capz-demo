Set-Service -Name "wuauserv" -StartupType Disabled
Stop-Service -Name "wuauserv"

Set-MpPreference -DisableRealtimeMonitoring $true

Get-NetAdapter -Physical | Rename-NetAdapter -NewName "Ethernet"

Set-Service -Name "docker" -StartupType Automatic
Start-Service -Name "docker"

nssm set kubelet Start SERVICE_AUTO_START 2>$null
