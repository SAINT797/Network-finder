param([switch]$ServiceOnly)
# Network Finder elevated repair helper.
# Started by the unelevated UI via Start-Process -Verb RunAs (Windows UAC).
Add-Type -AssemblyName System.Windows.Forms
$ErrorActionPreference = 'Stop'
$logPath = Join-Path $env:TEMP 'NetworkFinder-repair.log'
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'This helper must be run as administrator.'
    }

    "$(Get-Date -Format o) Starting Wi-Fi repair." | Set-Content -LiteralPath $logPath -Encoding UTF8
    $service = Get-Service -Name WlanSvc -ErrorAction Stop
    if ($service.Status -eq 'Running') {
        Restart-Service -Name WlanSvc -Force -ErrorAction Stop
    } else {
        Set-Service -Name WlanSvc -StartupType Automatic
        Start-Service -Name WlanSvc -ErrorAction Stop
    }

    if (-not $ServiceOnly) {
        # Select Wi-Fi network adapters only. Avoid touching Ethernet, Bluetooth PAN, or WAN miniports.
        $wifi = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object {
            $_.InterfaceDescription -match 'Wi-Fi|Wireless|WLAN|802\.11|Intel\(R\) Dual Band Wireless'
        })
        if ($wifi.Count -eq 0) {
            throw 'No physical Wi-Fi adapter was found. Check Device Manager and the adapter driver.'
        }

        foreach ($adapter in $wifi) {
            if ($adapter.Status -eq 'Disabled') {
                Enable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop
            } else {
                Disable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop
                Start-Sleep -Seconds 2
                Enable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop
            }
        }
    }
    Start-Sleep -Seconds 3
    "$(Get-Date -Format o) Repair completed." | Add-Content -LiteralPath $logPath -Encoding UTF8
    exit 0
} catch {
    "$(Get-Date -Format o) Repair failed: $($_.Exception.Message)" | Add-Content -LiteralPath $logPath -Encoding UTF8
    [System.Windows.Forms.MessageBox]::Show("Wi-Fi repair did not complete:`n$($_.Exception.Message)`n`nDetails: $logPath",'Network Finder - Repair') | Out-Null
    exit 1
}
