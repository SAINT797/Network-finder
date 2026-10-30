# Network Finder - lightweight Windows Wi-Fi manager
# Uses Windows WLAN profiles and netsh; no bundled runtime or adapter driver.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'SilentlyContinue'
$script:RefreshTimer = $null
$script:Notify = $null
$script:Form = $null
$script:List = $null
$script:Status = $null
$script:Networks = @()
$script:PreflightDone = $false
$script:SettingsPath = Join-Path $env:APPDATA 'NetworkFinder\settings.json'
$script:AutoRestartWlan = $false
try {
    if (Test-Path -LiteralPath $script:SettingsPath) {
        $savedSettings = Get-Content -LiteralPath $script:SettingsPath -Raw | ConvertFrom-Json
        $script:AutoRestartWlan = [bool]$savedSettings.AutoRestartWlan
    }
} catch { $script:AutoRestartWlan = $false }

function Save-AppSettings {
    $settingsFolder = Split-Path -Parent $script:SettingsPath
    if (-not (Test-Path -LiteralPath $settingsFolder)) { New-Item -ItemType Directory -Path $settingsFolder -Force | Out-Null }
    @{ AutoRestartWlan = [bool]$script:AutoRestartWlan } | ConvertTo-Json | Set-Content -LiteralPath $script:SettingsPath -Encoding UTF8
}

function Invoke-AdminRepair([bool]$ServiceOnly = $false) {
    $helper = Join-Path $PSScriptRoot 'Repair-Wifi.ps1'
    if (-not (Test-Path -LiteralPath $helper)) {
        [System.Windows.Forms.MessageBox]::Show('Repair-Wifi.ps1 is missing. Restore it from the project folder.','Network Finder') | Out-Null
        return $false
    }
    try {
        $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$helper`"")
        if ($ServiceOnly) { $arguments += '-ServiceOnly' }
        $process = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $arguments -Verb RunAs -Wait -PassThru
        if ($process.ExitCode -eq 0) { return $true }
        [System.Windows.Forms.MessageBox]::Show('Windows repair did not complete successfully. Check the adapter and driver in Device Manager.','Network Finder') | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show('Administrator approval was cancelled or the repair could not start.','Network Finder') | Out-Null
    }
    return $false
}

function Test-WifiPreflight {
    if ($script:PreflightDone) { return }
    $script:PreflightDone = $true
    $service = Get-Service -Name WlanSvc -ErrorAction SilentlyContinue
    $disabledWifi = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Disabled' -and $_.InterfaceDescription -match 'Wi-Fi|Wireless|WLAN|802\.11|Intel\(R\) Dual Band Wireless' })
    if (-not $service -or $service.Status -ne 'Running' -or $disabledWifi.Count -gt 0) {
        $answer = [System.Windows.Forms.MessageBox]::Show('Windows WLAN AutoConfig or the Wi-Fi adapter appears stopped/disabled. Allow Network Finder to request administrator approval and try restarting the Wi-Fi service and adapter before scanning?','Network Finder',[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) { [void](Invoke-AdminRepair); Start-Sleep -Seconds 2 }
    }
}

function Start-WindowsDiagnostics {
    try {
        $msdt = Join-Path $env:SystemRoot 'System32\msdt.exe'
        if (Test-Path $msdt) {
            Start-Process -FilePath $msdt -ArgumentList '-id','NetworkDiagnosticsNetworkAdapter'
        } else {
            Start-Process 'ms-settings:troubleshoot'
        }
    } catch {
        try { Start-Process 'ms-settings:troubleshoot' } catch {
            [System.Windows.Forms.MessageBox]::Show('Could not open Windows diagnostics. Open Settings > System > Troubleshoot > Other troubleshooters manually.','Network Finder') | Out-Null
        }
    }
}

function Get-WifiState {
    $text = (& netsh wlan show interfaces 2>$null | Out-String)
    if ($text -match '(?im)^\s*State\s*:\s*connected\s*$') { return 'connected' }
    return 'disconnected'
}

function Get-Networks {
    $raw = (& netsh wlan show networks mode=bssid 2>$null | Out-String)
    $items = @()
    $current = $null
    foreach ($line in ($raw -split "`r?`n")) {
        if ($line -match '^\s*SSID\s+\d+\s*:\s*(.*)$') {
            if ($null -ne $current) { $items += $current }
            $current = [ordered]@{ SSID = $Matches[1].Trim(); Signal = ''; Auth = '' }
        } elseif ($null -ne $current -and $line -match '^\s*Signal\s*:\s*(.*)$') {
            $current.Signal = $Matches[1].Trim()
        } elseif ($null -ne $current -and $line -match '^\s*Authentication\s*:\s*(.*)$') {
            $current.Auth = $Matches[1].Trim()
        }
    }
    if ($null -ne $current) { $items += $current }
    return @($items | Where-Object { $_.SSID } | Sort-Object SSID -Unique)
}

function Update-View {
    if (-not $script:Form -or $script:Form.IsDisposed) { return }
    Test-WifiPreflight
    $script:Networks = @(Get-Networks)
    $script:List.Items.Clear()
    foreach ($n in $script:Networks) {
        $security = if ($n.Auth -match 'Open|None') { 'Open' } else { 'Secured' }
        [void]$script:List.Items.Add("$($n.SSID)    $($n.Signal)    $security")
    }
    $state = Get-WifiState
    if ($state -eq 'connected') {
        $script:Status.Text = 'Connected — Windows will manage this saved connection.'
        $script:Notify.Icon = [System.Drawing.SystemIcons]::Application
        $script:Notify.Text = 'Network Finder — Connected'
    } else {
        $script:Status.Text = 'Not connected. Select a network and choose Connect.'
        $script:Notify.Icon = [System.Drawing.SystemIcons]::Information
        $script:Notify.Text = 'Network Finder — Not connected'
    }
}

function Connect-Network($network) {
    if (-not $network) { return }
    $ssid = [string]$network.SSID
    $auth = [string]$network.Auth
    $open = $auth -match 'Open|None'
    $password = ''
    if (-not $open) {
        $dialog = New-Object System.Windows.Forms.Form
        $dialog.Text = "Connect to $ssid"
        $dialog.Size = New-Object System.Drawing.Size(370,155)
        $dialog.StartPosition = 'CenterParent'
        $dialog.FormBorderStyle = 'FixedDialog'
        $dialog.MaximizeBox = $false; $dialog.MinimizeBox = $false
        $label = New-Object System.Windows.Forms.Label
        $label.Text = 'Wi-Fi password:'; $label.Location = New-Object System.Drawing.Point(14,18); $label.AutoSize = $true
        $box = New-Object System.Windows.Forms.TextBox
        $box.Location = New-Object System.Drawing.Point(15,45); $box.Width = 320; $box.UseSystemPasswordChar = $true
        $ok = New-Object System.Windows.Forms.Button
        $ok.Text = 'Connect'; $ok.Location = New-Object System.Drawing.Point(174,80); $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $cancel = New-Object System.Windows.Forms.Button
        $cancel.Text = 'Cancel'; $cancel.Location = New-Object System.Drawing.Point(260,80); $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $dialog.Controls.AddRange(@($label,$box,$ok,$cancel)); $dialog.AcceptButton = $ok; $dialog.CancelButton = $cancel
        if ($dialog.ShowDialog($script:Form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
        $password = $box.Text
        if ([string]::IsNullOrWhiteSpace($password)) {
            [System.Windows.Forms.MessageBox]::Show('Enter the network password, or cancel if this network is open.','Network Finder') | Out-Null
            return
        }
    }
    # Escape XML safely. The profile is handed to Windows, then the temporary file is removed.
    $safeSsid = [System.Security.SecurityElement]::Escape($ssid)
    $profilePath = Join-Path $env:TEMP ('NetworkFinder-' + [guid]::NewGuid().ToString('N') + '.xml')
    if ($open) {
        $xml = "<?xml version=`"1.0`"?><WLANProfile xmlns=`"http://www.microsoft.com/networking/WLAN/profile/v1`"><name>$safeSsid</name><SSIDConfig><SSID><name>$safeSsid</name></SSID></SSIDConfig><connectionType>ESS</connectionType><connectionMode>auto</connectionMode><MSM><security><authEncryption><authentication>open</authentication><encryption>none</encryption><useOneX>false</useOneX></authEncryption></security></MSM></WLANProfile>"
    } else {
        $safePassword = [System.Security.SecurityElement]::Escape($password)
        $authType = if ($auth -match 'WPA3') { 'WPA3SAE' } elseif ($auth -match 'WPA2') { 'WPA2PSK' } else { 'WPA2PSK' }
        $xml = "<?xml version=`"1.0`"?><WLANProfile xmlns=`"http://www.microsoft.com/networking/WLAN/profile/v1`"><name>$safeSsid</name><SSIDConfig><SSID><name>$safeSsid</name></SSID></SSIDConfig><connectionType>ESS</connectionType><connectionMode>auto</connectionMode><MSM><security><authEncryption><authentication>$authType</authentication><encryption>AES</encryption><useOneX>false</useOneX></authEncryption><sharedKey><keyType>passPhrase</keyType><protected>false</protected><keyMaterial>$safePassword</keyMaterial></sharedKey></security></MSM></WLANProfile>"
    }
    try {
        Set-Content -LiteralPath $profilePath -Value $xml -Encoding Unicode
        $add = (& netsh wlan add profile filename="$profilePath" user=current 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) { throw $add.Trim() }
        $result = (& netsh wlan connect name="$ssid" ssid="$ssid" 2>&1 | Out-String)
        Start-Sleep -Seconds 2
        [System.Windows.Forms.MessageBox]::Show("Windows was asked to connect to '$ssid'.`n`nIf it does not connect, verify the password and adapter/driver, then try again.",'Network Finder') | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Could not add/connect to the network:`n$($_.Exception.Message)",'Network Finder') | Out-Null
    } finally {
        Remove-Item -LiteralPath $profilePath -Force -ErrorAction SilentlyContinue
        $password = $null
    }
    Update-View
}

$script:Form = New-Object System.Windows.Forms.Form
$script:Form.Text = 'Network Finder'
$script:Form.Size = New-Object System.Drawing.Size(590,430)
$script:Form.MinimumSize = New-Object System.Drawing.Size(500,330)
$script:Form.StartPosition = 'CenterScreen'
$script:Form.Icon = [System.Drawing.SystemIcons]::Application
$title = New-Object System.Windows.Forms.Label
$title.Text = 'Available Wi-Fi networks'; $title.Font = New-Object System.Drawing.Font('Segoe UI',14,[System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(16,14); $title.AutoSize = $true
$script:List = New-Object System.Windows.Forms.ListBox
$script:List.Location = New-Object System.Drawing.Point(18,78); $script:List.Size = New-Object System.Drawing.Size(535,242)
$script:List.Anchor = 'Top,Bottom,Left,Right'; $script:List.Font = New-Object System.Drawing.Font('Segoe UI',10)
$autoRestart = New-Object System.Windows.Forms.CheckBox
$autoRestart.Text = 'Restart WLAN service on every app launch (UAC approval required)'
$autoRestart.Location = New-Object System.Drawing.Point(18,48); $autoRestart.Size = New-Object System.Drawing.Size(535,24)
$autoRestart.Checked = $script:AutoRestartWlan
$connect = New-Object System.Windows.Forms.Button
$connect.Text = 'Connect'; $connect.Location = New-Object System.Drawing.Point(18,333); $connect.Size = New-Object System.Drawing.Size(110,32); $connect.Anchor = 'Bottom,Left'
$refresh = New-Object System.Windows.Forms.Button
$refresh.Text = 'Refresh'; $refresh.Location = New-Object System.Drawing.Point(138,333); $refresh.Size = New-Object System.Drawing.Size(110,32); $refresh.Anchor = 'Bottom,Left'
$repair = New-Object System.Windows.Forms.Button
$repair.Text = 'Repair Wi-Fi (Admin)'; $repair.Location = New-Object System.Drawing.Point(258,333); $repair.Size = New-Object System.Drawing.Size(145,32); $repair.Anchor = 'Bottom,Left'
$diagnostics = New-Object System.Windows.Forms.Button
$diagnostics.Text = 'Windows diagnostics'; $diagnostics.Location = New-Object System.Drawing.Point(413,333); $diagnostics.Size = New-Object System.Drawing.Size(140,32); $diagnostics.Anchor = 'Bottom,Right'
$script:Status = New-Object System.Windows.Forms.Label
$script:Status.Location = New-Object System.Drawing.Point(18,378); $script:Status.Size = New-Object System.Drawing.Size(535,24); $script:Status.Anchor = 'Bottom,Left,Right'
$script:Form.Controls.AddRange(@($title,$autoRestart,$script:List,$connect,$refresh,$repair,$diagnostics,$script:Status))
$script:Notify = New-Object System.Windows.Forms.NotifyIcon
$script:Notify.Icon = [System.Drawing.SystemIcons]::Information
$script:Notify.Visible = $true
$script:Notify.Text = 'Network Finder'
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$openItem = $menu.Items.Add('Open Network Finder')
$exitItem = $menu.Items.Add('Exit')
$script:Notify.ContextMenuStrip = $menu
$openItem.add_Click({ $script:Form.Show(); $script:Form.WindowState = 'Normal'; $script:Form.Activate() })
$exitItem.add_Click({ $script:Notify.Visible = $false; $script:Form.Close() })
$script:Notify.add_DoubleClick({ $script:Form.Show(); $script:Form.WindowState = 'Normal'; $script:Form.Activate() })
$connect.add_Click({ if ($script:List.SelectedIndex -ge 0) { Connect-Network $script:Networks[$script:List.SelectedIndex] } })
$script:List.add_DoubleClick({ if ($script:List.SelectedIndex -ge 0) { Connect-Network $script:Networks[$script:List.SelectedIndex] } })
$refresh.add_Click({ Update-View })
$repair.add_Click({ if (Invoke-AdminRepair) { Start-Sleep -Seconds 2; Update-View } })
$diagnostics.add_Click({ Start-WindowsDiagnostics })
$autoRestart.add_CheckedChanged({
    $script:AutoRestartWlan = $autoRestart.Checked
    try { Save-AppSettings } catch { [System.Windows.Forms.MessageBox]::Show('Could not save the auto-restart setting.','Network Finder') | Out-Null }
})
$script:Form.add_Resize({ if ($script:Form.WindowState -eq 'Minimized') { $script:Form.Hide() } })
$script:Form.add_FormClosing({ param($sender,$e) if ($e.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) { $e.Cancel = $true; $script:Form.Hide() } })
$script:RefreshTimer = New-Object System.Windows.Forms.Timer
$script:RefreshTimer.Interval = 10000
$script:RefreshTimer.add_Tick({ Update-View })
$script:RefreshTimer.Start()
if ($script:AutoRestartWlan) {
    $script:Status.Text = 'Restarting WLAN AutoConfig — approve the Windows administrator prompt.'
    [void](Invoke-AdminRepair $true)
}
Update-View
[void]$script:Form.ShowDialog()
