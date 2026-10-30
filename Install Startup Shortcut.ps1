# Optional: create a per-user Startup shortcut so Network Finder opens at sign-in.
$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot 'NetworkFinder.ps1'
$startup = [Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startup 'Network Finder.lnk'
$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut($shortcutPath)
$link.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$link.Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$scriptPath`""
$link.WorkingDirectory = $PSScriptRoot
$link.Description = 'Open Network Finder at Windows sign-in'
$link.Save()
Write-Host "Startup shortcut installed: $shortcutPath"
Write-Host 'Windows will reconnect to saved Wi-Fi profiles independently of this app.'
