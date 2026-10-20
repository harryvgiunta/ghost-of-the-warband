#Requires -RunAsAdministrator
param([ValidateRange(1024,65535)][int]$Port = 7777)
$ErrorActionPreference = 'Stop'
$enginePath = if ($env:GODOT_PATH) { $env:GODOT_PATH } else { Join-Path $PSScriptRoot '.runtime\godot\Godot_v4.7.2-stable_win64.exe' }
$engine = (Resolve-Path -LiteralPath $enginePath).Path
if (-not (Get-NetAdapter -Name 'Tailscale' -ErrorAction SilentlyContinue)) {
    throw 'Start Tailscale first. Its network adapter was not found.'
}
$ruleName = "IronwoodArena-Git-Tailscale-UDP$Port"
if (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue) {
    Set-NetFirewallRule -Name $ruleName -Enabled True -Direction Inbound -Action Allow -Profile Any `
        -Program $engine -Protocol UDP -LocalPort $Port -InterfaceAlias 'Tailscale' -RemoteAddress '100.64.0.0/10'
} else {
    New-NetFirewallRule -Name $ruleName -DisplayName "Ironwood Arena - Tailscale UDP $Port" `
        -Enabled True -Direction Inbound -Action Allow -Profile Any -Program $engine `
        -Protocol UDP -LocalPort $Port -InterfaceAlias 'Tailscale' -RemoteAddress '100.64.0.0/10' | Out-Null
}
Write-Host "Allowed this game engine on UDP $Port through Tailscale only."
Write-Host "Undo: Remove-NetFirewallRule -Name $ruleName"
