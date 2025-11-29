# TRMNL Device Health Monitor - Windows Installer
# Save as: install.ps1
# Run as Administrator: powershell -ExecutionPolicy Bypass -File install.ps1

Write-Host "=== TRMNL Device Health Monitor - Windows Installer ===" -ForegroundColor Cyan
Write-Host ""

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

# Get plugin UUID
$PLUGIN_UUID = Read-Host "Enter your TRMNL plugin UUID"
if ([string]::IsNullOrWhiteSpace($PLUGIN_UUID)) {
    Write-Host "Error: Plugin UUID is required" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

$WEBHOOK_URL = "https://usetrmnl.com/api/custom_plugins/$PLUGIN_UUID"

# Check TRMNL+ subscription
Write-Host ""
$hasPremium = Read-Host "Do you have TRMNL+ subscription? (y/n) [n]"
if ([string]::IsNullOrWhiteSpace($hasPremium)) { $hasPremium = "n" }

if ($hasPremium -match "^[Yy]") {
    $MAX_DEVICES = 30
    $TIER = "TRMNL+"
} else {
    $MAX_DEVICES = 12
    $TIER = "Standard"
}

# Get device ID
Write-Host ""
Write-Host "Assign this device a number (1-$MAX_DEVICES)"
Write-Host "Each device needs a unique number for the dashboard"
[int]$DEVICE_ID = Read-Host "Device ID (1-$MAX_DEVICES)"

if ($DEVICE_ID -lt 1 -or $DEVICE_ID -gt $MAX_DEVICES) {
    Write-Host "Error: Device ID must be between 1 and $MAX_DEVICES" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Get device name
$defaultName = $env:COMPUTERNAME
$DEVICE_NAME = Read-Host "Enter device name/label (default: $defaultName)"
if ([string]::IsNullOrWhiteSpace($DEVICE_NAME)) {
    $DEVICE_NAME = $defaultName
}

# Get update interval
Write-Host ""
Write-Host "Update interval options ($TIER tier):"
if ($hasPremium -match "^[Yy]") {
    Write-Host "  TRMNL+ Rate Limit: 30 requests/hour"
    Write-Host ""
    Write-Host "  1) Every 2 minutes (max 1 device)"
    Write-Host "  2) Every 6 minutes (max 3 devices)"
    Write-Host "  3) Every 10 minutes (max 5 devices)"
    Write-Host "  4) Every hour (max 30 devices) [RECOMMENDED]"
    [int]$choice = Read-Host "Select interval (1-4)"

    switch ($choice) {
        1 { $UPDATE_INTERVAL = 120; $DESC = "every 2 minutes" }
        2 { $UPDATE_INTERVAL = 360; $DESC = "every 6 minutes" }
        3 { $UPDATE_INTERVAL = 600; $DESC = "every 10 minutes" }
        4 { $UPDATE_INTERVAL = 3600; $DESC = "every hour" }
        default { $UPDATE_INTERVAL = 3600; $DESC = "every hour" }
    }
} else {
    Write-Host "  Standard Rate Limit: 12 requests/hour"
    Write-Host ""
    Write-Host "  1) Every 5 minutes (max 1 device)"
    Write-Host "  2) Every 10 minutes (max 2 devices)"
    Write-Host "  3) Every 15 minutes (max 3 devices)"
    Write-Host "  4) Every 20 minutes (max 4 devices)"
    Write-Host "  5) Every 30 minutes (max 6 devices)"
    Write-Host "  6) Every hour (max 12 devices) [RECOMMENDED]"
    [int]$choice = Read-Host "Select interval (1-6)"

    switch ($choice) {
        1 { $UPDATE_INTERVAL = 300; $DESC = "every 5 minutes" }
        2 { $UPDATE_INTERVAL = 600; $DESC = "every 10 minutes" }
        3 { $UPDATE_INTERVAL = 900; $DESC = "every 15 minutes" }
        4 { $UPDATE_INTERVAL = 1200; $DESC = "every 20 minutes" }
        5 { $UPDATE_INTERVAL = 1800; $DESC = "every 30 minutes" }
        6 { $UPDATE_INTERVAL = 3600; $DESC = "every hour" }
        default { $UPDATE_INTERVAL = 3600; $DESC = "every hour" }
    }
}

# Install directory
$INSTALL_DIR = "C:\Program Files\TRMNL-Health"
$LOG_DIR = "C:\ProgramData\TRMNL-Health\Logs"

# Create directories
Write-Host ""
Write-Host "Creating directories..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
New-Item -ItemType Directory -Force -Path $LOG_DIR | Out-Null

# Create config file
Write-Host "Creating configuration..." -ForegroundColor Cyan
$configJson = @{
    webhook_url = $WEBHOOK_URL
    device_id = $DEVICE_ID
    device_name = $DEVICE_NAME
    update_interval = $UPDATE_INTERVAL
} | ConvertTo-Json

$configJson | Out-File -FilePath "$INSTALL_DIR\config.json" -Encoding UTF8

# Create PowerShell collector script
$collectorScript = @'
# TRMNL Health Monitor - Data Collector

$CONFIG_FILE = Join-Path $PSScriptRoot "config.json"
$config = Get-Content $CONFIG_FILE | ConvertFrom-Json

$WEBHOOK_URL = $config.webhook_url
$DEVICE_ID = $config.device_id
$DEVICE_NAME = $config.device_name

# OS Information
$osInfo = Get-CimInstance Win32_OperatingSystem
$OS = "$($osInfo.Caption) $($osInfo.Version)".Substring(0, [Math]::Min(30, "$($osInfo.Caption) $($osInfo.Version)".Length))

# Logged in users - count and list
$loggedInUsers = Get-CimInstance Win32_ComputerSystem | Select-Object -ExpandProperty UserName
if ($loggedInUsers) {
    $LOGGED_IN_COUNT = 1
    $LOGGED_IN_USERS = $loggedInUsers.Split('\')[-1]
} else {
    $LOGGED_IN_COUNT = 0
    $LOGGED_IN_USERS = "none"
}

# CPU - usage, cores, frequency
$cpuLoad = Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average | Select-Object -ExpandProperty Average
$CPU = [int]$cpuLoad

$cpuInfo = Get-CimInstance Win32_Processor | Select-Object -First 1
$CPU_CORES = $cpuInfo.NumberOfLogicalProcessors
$CPU_FREQ = [int]$cpuInfo.MaxClockSpeed

# Load average (Windows doesn't have this, use CPU load for all 3)
$loadAvg = "$cpuLoad,$cpuLoad,$cpuLoad"
$LOAD_AVG = $loadAvg -replace ' ', ''

# Memory - used/total in GB
$memInfo = Get-CimInstance Win32_OperatingSystem
$MEM_TOTAL = [math]::Round($memInfo.TotalVisibleMemorySize / 1MB, 0)
$MEM_USED = [math]::Round(($memInfo.TotalVisibleMemorySize - $memInfo.FreePhysicalMemory) / 1MB, 0)

# Disk - used/total in GB (C: drive)
$diskInfo = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DeviceID -eq "C:" }
$DISK_TOTAL = [math]::Round($diskInfo.Size / 1GB, 0)
$DISK_USED = [math]::Round(($diskInfo.Size - $diskInfo.FreeSpace) / 1GB, 0)

# Temperature (requires OpenHardwareMonitor or similar - default to 0)
$TEMP = 0
# Try to get CPU temp if available (requires admin and specific hardware)
try {
    $temp = Get-CimInstance -Namespace root/WMI -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty CurrentTemperature
    if ($temp) {
        $TEMP = [int](($temp / 10) - 273.15)  # Convert from decidegrees Kelvin to Celsius
    }
} catch {}

# Battery - level and charging status
$BATTERY = 0
$CHARGING = 0
$batteryInfo = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
if ($batteryInfo) {
    $BATTERY = $batteryInfo.EstimatedChargeRemaining
    if ($batteryInfo.BatteryStatus -eq 2) {  # 2 = Charging
        $CHARGING = 1
    }
}

# GPU detection and stats
$GPU_NAME = "none"
$GPU_TEMP = 0
$GPU_UTIL = 0

# Try NVIDIA
try {
    $nvidiaSmi = "C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe"
    if (Test-Path $nvidiaSmi) {
        $gpuName = & $nvidiaSmi --query-gpu=name --format=csv,noheader 2>$null | Select-Object -First 1
        $gpuTemp = & $nvidiaSmi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>$null | Select-Object -First 1
        $gpuUtil = & $nvidiaSmi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>$null | Select-Object -First 1

        if ($gpuName) {
            $GPU_NAME = $gpuName.Substring(0, [Math]::Min(20, $gpuName.Length))
            $GPU_TEMP = [int]$gpuTemp
            $GPU_UTIL = [int]$gpuUtil
        }
    }
} catch {}

# If no NVIDIA, try to get basic GPU info
if ($GPU_NAME -eq "none") {
    $gpuInfo = Get-CimInstance Win32_VideoController | Select-Object -First 1
    if ($gpuInfo -and $gpuInfo.Name -notlike "*Basic*" -and $gpuInfo.Name -notlike "*Microsoft*") {
        $GPU_NAME = $gpuInfo.Name.Substring(0, [Math]::Min(20, $gpuInfo.Name.Length))
    }
}

# Network throughput (bytes/sec converted to KB/s)
$netAdapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.InterfaceDescription -notlike "*Virtual*" -and $_.InterfaceDescription -notlike "*Loopback*" }
if ($netAdapters) {
    $netStats1 = Get-NetAdapterStatistics -Name $netAdapters[0].Name
    Start-Sleep -Seconds 1
    $netStats2 = Get-NetAdapterStatistics -Name $netAdapters[0].Name

    $bytesPerSec = ($netStats2.ReceivedBytes - $netStats1.ReceivedBytes) + ($netStats2.SentBytes - $netStats1.SentBytes)
    $NET = [int]($bytesPerSec / 1024)
} else {
    $NET = 0
}

# Connection type
$CONN = "lan"
$wifiAdapter = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*Wireless*" -or $_.InterfaceDescription -like "*Wi-Fi*" } | Where-Object { $_.Status -eq "Up" }
if ($wifiAdapter) {
    try {
        $ssid = (netsh wlan show interfaces) | Select-String "SSID" | Select-Object -First 1
        if ($ssid -match ":\s*(.+)$") {
            $ssidName = $matches[1].Trim()
            $CONN = "wifi:$ssidName"
        } else {
            $CONN = "wifi"
        }
    } catch {
        $CONN = "wifi"
    }
}

# IP Address
$IP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -notlike "169.254.*" } | Select-Object -First 1).IPAddress
if (-not $IP) { $IP = "127.0.0.1" }

# Uptime in seconds
$bootTime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
$UPTIME = [int]((Get-Date) - $bootTime).TotalSeconds

# Timestamp (Unix timestamp UTC)
$TIMESTAMP = [int][double]::Parse((Get-Date -UFormat %s))

# Build payload (23 fields)
# Format: name|os|userCount|users|cpu|cores|freq|load|memU|memT|diskU|diskT|temp|bat|chr|gpu|gputemp|gpuutil|net|conn|ip|uptime|ts
$PAYLOAD = "$DEVICE_NAME|$OS|$LOGGED_IN_COUNT|$LOGGED_IN_USERS|$CPU|$CPU_CORES|$CPU_FREQ|$LOAD_AVG|$MEM_USED|$MEM_TOTAL|$DISK_USED|$DISK_TOTAL|$TEMP|$BATTERY|$CHARGING|$GPU_NAME|$GPU_TEMP|$GPU_UTIL|$NET|$CONN|$IP|$UPTIME|$TIMESTAMP"

# Send to webhook
$body = @{
    merge_variables = @{
        "d$DEVICE_ID" = $PAYLOAD
    }
    merge_strategy = "deep_merge"
} | ConvertTo-Json

try {
    $response = Invoke-WebRequest -Uri $WEBHOOK_URL -Method POST -Body $body -ContentType "application/json" -UseBasicParsing
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Output "[$timestamp] Success (HTTP $($response.StatusCode))"
} catch {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $statusCode = $_.Exception.Response.StatusCode.value__
    Write-Output "[$timestamp] Error (HTTP $statusCode)"
}
'@

$collectorScript | Out-File -FilePath "$INSTALL_DIR\collect.ps1" -Encoding UTF8

# Create scheduled task
Write-Host "Creating scheduled task..." -ForegroundColor Cyan

$taskName = "TRMNL-Health-Monitor"
$taskDescription = "TRMNL Device Health Monitor - Sends system metrics to TRMNL dashboard"

# Remove existing task if it exists
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# Create action
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$INSTALL_DIR\collect.ps1`"" -WorkingDirectory $INSTALL_DIR

# Create trigger based on interval
if ($UPDATE_INTERVAL -eq 120) {
    # Every 2 minutes
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 2) -RepetitionDuration ([TimeSpan]::MaxValue)
} elseif ($UPDATE_INTERVAL -eq 300) {
    # Every 5 minutes
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration ([TimeSpan]::MaxValue)
} elseif ($UPDATE_INTERVAL -eq 360) {
    # Every 6 minutes
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 6) -RepetitionDuration ([TimeSpan]::MaxValue)
} elseif ($UPDATE_INTERVAL -eq 600) {
    # Every 10 minutes
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 10) -RepetitionDuration ([TimeSpan]::MaxValue)
} elseif ($UPDATE_INTERVAL -eq 900) {
    # Every 15 minutes
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration ([TimeSpan]::MaxValue)
} elseif ($UPDATE_INTERVAL -eq 1200) {
    # Every 20 minutes
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 20) -RepetitionDuration ([TimeSpan]::MaxValue)
} elseif ($UPDATE_INTERVAL -eq 1800) {
    # Every 30 minutes
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 30) -RepetitionDuration ([TimeSpan]::MaxValue)
} else {
    # Every hour
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration ([TimeSpan]::MaxValue)
}

# Create principal (run as SYSTEM)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

# Create settings
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

# Register task
Register-ScheduledTask -TaskName $taskName -Description $taskDescription -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null

# Run test collection
Write-Host ""
Write-Host "Running test collection..." -ForegroundColor Cyan
Write-Host ""
& PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "$INSTALL_DIR\collect.ps1"

# Summary
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host "✓ Installation complete!" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host "Tier: $TIER"
Write-Host "Device ID: $DEVICE_ID (will appear as 'd$DEVICE_ID' in TRMNL)"
Write-Host "Device Name: $DEVICE_NAME"
Write-Host "Webhook: $WEBHOOK_URL"
Write-Host "Update schedule: $DESC"
Write-Host ""
Write-Host "Config: $INSTALL_DIR\config.json"
Write-Host "Script: $INSTALL_DIR\collect.ps1"
Write-Host "Logs: Check Event Viewer or Task Scheduler History"
Write-Host ""
Write-Host "To view task: taskschd.msc (look for 'TRMNL-Health-Monitor')"
Write-Host "To uninstall: schtasks /delete /tn TRMNL-Health-Monitor /f"
Write-Host ""
Write-Host "Payload format (23 fields):"
Write-Host "name|os|userCount|users|cpu%|cores|freq|load|memU|memT|diskU|diskT|temp|bat%|chr|gpu|gputemp|gpuutil|net|conn|ip|uptime|ts"
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host ""

Read-Host "Press Enter to exit"