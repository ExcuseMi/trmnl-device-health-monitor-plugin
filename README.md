# TRMNL Device Health Monitor Plugin

A comprehensive system monitoring plugin for [TRMNL](https://usetrmnl.com) e-ink displays. Monitor CPU, memory, disk, temperature, battery, GPU, network, and more across all your Linux, Windows, and macOS devices.

![TRMNL Device Health Monitor](screenshot.png)

## Features

- 📊 **Real-time Metrics**: CPU, RAM, disk usage, temperature, network throughput
- 🔋 **Battery Monitoring**: Track battery level and charging status on laptops
- 🎮 **GPU Support**: Monitor NVIDIA, AMD, and Intel GPUs
- 👥 **User Tracking**: See who's logged into each device
- 🌐 **Network Info**: Connection type (WiFi/LAN), SSID, IP address
- ⏱️ **Uptime Tracking**: Monitor system uptime
- 🎨 **Beautiful Dashboard**: Clean e-ink optimized display with icons
- 🔄 **Auto-refresh**: Configurable update intervals with rate limit management
- 📱 **Compact Mode**: Display more devices in less space
- ⚠️ **Stale Detection**: Visual indicators for devices that haven't reported recently

## Installation

### Prerequisites

- A [TRMNL](https://usetrmnl.com) account and device
- Your TRMNL Plugin UUID (from the Private Plugin settings)

### Linux

**Supported Distributions:**
- Ubuntu/Debian
- Fedora/RHEL/CentOS
- Arch Linux
- Alpine Linux

**Quick Install:**
```bash
# Download installer
curl -O https://raw.githubusercontent.com/ExcuseMi/trmnl-device-health-monitor-plugin/main/linux/install.sh

# Make executable
chmod +x install.sh

# Run installer
sudo ./install.sh YOUR_PLUGIN_UUID
```

**What it installs:**
- Data collector script: `/opt/trmnl-health/collect.sh`
- Configuration: `/opt/trmnl-health/config.json`
- Logs: `/var/log/trmnl-health/trmnl-health.log`
- Systemd service: `trmnl-health.service` and `trmnl-health.timer`

**Check status:**
```bash
sudo systemctl status trmnl-health.timer
sudo tail -f /var/log/trmnl-health/trmnl-health.log
```

**Uninstall:**
```bash
sudo systemctl stop trmnl-health.timer
sudo systemctl disable trmnl-health.timer
sudo rm /etc/systemd/system/trmnl-health.service
sudo rm /etc/systemd/system/trmnl-health.timer
sudo systemctl daemon-reload
sudo rm -rf /opt/trmnl-health
sudo rm -rf /var/log/trmnl-health
```

### Windows

**Supported Versions:**
- Windows 10/11
- Windows Server 2016+

**Quick Install:**

1. **Download installer:**
```powershell
   # Download to Downloads folder
   Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ExcuseMi/trmnl-device-health-monitor-plugin/main/windows/install.ps1" -OutFile "$env:USERPROFILE\Downloads\install.ps1"
```

2. **Run as Administrator:**
   - Right-click PowerShell → "Run as Administrator"
   - Navigate to Downloads folder
   - Run:
```powershell
     cd $env:USERPROFILE\Downloads
     powershell -ExecutionPolicy Bypass -File install.ps1
```

**What it installs:**
- Data collector script: `C:\Program Files\TRMNL-Health\collect.ps1`
- Configuration: `C:\Program Files\TRMNL-Health\config.json`
- Logs: `C:\ProgramData\TRMNL-Health\Logs\`
- Scheduled Task: `TRMNL-Health-Monitor` (runs as SYSTEM)

**Check status:**
- Open Task Scheduler (`taskschd.msc`)
- Look for "TRMNL-Health-Monitor" in Task Scheduler Library
- Check "History" tab for execution logs

**Uninstall:**
```powershell
# Run as Administrator
schtasks /delete /tn TRMNL-Health-Monitor /f
Remove-Item "C:\Program Files\TRMNL-Health" -Recurse -Force
Remove-Item "C:\ProgramData\TRMNL-Health" -Recurse -Force
```

### macOS

**Supported Versions:**
- macOS 11 (Big Sur) and later

**Quick Install:**
```bash
# Download installer
curl -O https://raw.githubusercontent.com/ExcuseMi/trmnl-device-health-monitor-plugin/main/macos/install.sh

# Make executable
chmod +x install.sh

# Run installer
sudo ./install.sh YOUR_PLUGIN_UUID
```

**What it installs:**
- Data collector script: `/usr/local/bin/trmnl-health/collect.sh`
- Configuration: `/usr/local/bin/trmnl-health/config.json`
- Logs: `/var/log/trmnl-health.log`
- LaunchDaemon: `/Library/LaunchDaemons/com.trmnl.health.plist`

**Check status:**
```bash
sudo launchctl list | grep trmnl
tail -f /var/log/trmnl-health.log
```

**Uninstall:**
```bash
sudo launchctl unload /Library/LaunchDaemons/com.trmnl.health.plist
sudo rm /Library/LaunchDaemons/com.trmnl.health.plist
sudo rm -rf /usr/local/bin/trmnl-health
sudo rm /var/log/trmnl-health.log
```

## TRMNL Plugin Setup

1. **Create Private Plugin:**
   - Go to TRMNL dashboard → Plugins → Private Plugins
   - Click "Create Private Plugin"
   - Name: "Device Health Monitor"

2. **Copy Plugin Markup:**
   - Copy the contents of `plugin.html` from this repo
   - Paste into the Plugin Markup editor

3. **Get Your Plugin UUID:**
   - Found in the plugin settings URL or webhook section
   - You'll need this for the installer

4. **Add to Playlist:**
   - Go to your TRMNL device playlist
   - Add the "Device Health Monitor" plugin
   - Set display duration (recommended: 60-120 seconds)

## Update Intervals & Rate Limits

### Standard Tier (12 requests/hour)

| Interval | Max Devices | Requests/Hour per Device |
|----------|-------------|-------------------------|
| 5 min    | 1 device    | 12                      |
| 10 min   | 2 devices   | 6                       |
| 15 min   | 3 devices   | 4                       |
| 20 min   | 4 devices   | 3                       |
| 30 min   | 6 devices   | 2                       |
| **1 hour** | **12 devices** | **1 (RECOMMENDED)** |

### TRMNL+ Tier (30 requests/hour)

| Interval | Max Devices | Requests/Hour per Device |
|----------|-------------|-------------------------|
| 2 min    | 1 device    | 30                      |
| 6 min    | 3 devices   | 10                      |
| 10 min   | 5 devices   | 6                       |
| **1 hour** | **30 devices** | **1 (RECOMMENDED)** |

**Recommendation:** Use 1-hour intervals for most setups. This allows you to monitor the maximum number of devices while staying well under rate limits.

## Data Fields

The plugin tracks 23 metrics per device:

| Field | Description | Example |
|-------|-------------|---------|
| name | Device hostname | `my-server` |
| os | Operating system | `Ubuntu 24.04` |
| user_count | Number of logged-in users | `2` |
| users | Comma-separated usernames | `john,jane` |
| cpu | CPU usage percentage | `45` |
| cores | Number of CPU cores | `8` |
| freq | CPU frequency (MHz) | `3600` |
| load | Load average (1,5,15 min) | `0.5,0.8,1.0` |
| mem_used | RAM used (GB) | `16` |
| mem_total | RAM total (GB) | `64` |
| disk_used | Disk used (GB) | `500` |
| disk_total | Disk total (GB) | `2000` |
| temp | CPU temperature (°C) | `45` |
| battery | Battery percentage | `85` |
| charging | Charging status (0/1) | `1` |
| gpu | GPU name | `NVIDIA RTX 4080` |
| gpu_temp | GPU temperature (°C) | `65` |
| gpu_util | GPU utilization (%) | `80` |
| network | Network throughput (KB/s) | `1500` |
| connection | Connection type | `wifi:HomeNet` |
| ip | IP address | `192.168.1.100` |
| uptime | System uptime (seconds) | `86400` |
| timestamp | Unix timestamp | `1704067200` |

## Tools

### Data Editor (`tools/editor.html`)

Web-based editor for viewing and managing your device data:
- ✅ View all devices with live stats
- ✅ Add test devices with templates (Server, Laptop, Desktop, Minimal)
- ✅ Edit existing devices
- ✅ Delete devices
- ✅ View and copy raw JSON
- ✅ Stale device detection

**Usage:**
1. Open `tools/editor.html` in your browser
2. Enter your Plugin UUID
3. Click "Load Data"
4. Add, edit, or delete devices
5. Click "Save Changes" to update TRMNL

### Reset Tool (`tools/reset.html`)

Reset plugin data by removing specific devices or all data:
- Reset all devices (d1-d30)
- Reset specific devices only
- Complete data removal (not just nulling values)

**Usage:**
1. Open `tools/reset.html` in your browser
2. Enter your Plugin UUID
3. Choose reset option (all or specific devices)
4. Click "Reset Plugin Data"

## Compact Mode

Display more devices in less space by using compact mode:
```liquid
<!-- In plugin.html, change the last line: -->
{% render "display_devices", devices: devices, compact: true %}
```

**Compact mode shows:**
- ✅ Device name + icon
- ✅ CPU, RAM, Disk bars
- ✅ Temperature
- ✅ Uptime

**Compact mode hides:**
- ❌ OS and user info
- ❌ CPU details (cores, frequency, load)
- ❌ Battery bar
- ❌ GPU bar
- ❌ IP address
- ❌ Network speed

## Troubleshooting

### Device not showing up

1. **Check if data is being sent:**
   - Linux: `sudo tail -f /var/log/trmnl-health/trmnl-health.log`
   - Windows: Check Task Scheduler history
   - macOS: `tail -f /var/log/trmnl-health.log`

2. **Verify Plugin UUID:**
   - Make sure UUID in config matches your TRMNL plugin

3. **Test manually:**
   - Linux: `sudo /opt/trmnl-health/collect.sh`
   - Windows: `& "C:\Program Files\TRMNL-Health\collect.ps1"`
   - macOS: `sudo /usr/local/bin/trmnl-health/collect.sh`

### Device shows as "stale"

- Device hasn't reported in >2 hours
- Check if the service/task is still running
- Verify network connectivity
- Check system time is correct

### GPU not detected

**Linux:**
- NVIDIA: Install `nvidia-smi`
- AMD: Install `rocm-smi`
- Intel: Usually auto-detected

**Windows:**
- NVIDIA: Ensure drivers are installed with nvidia-smi
- Others: Basic GPU info auto-detected

**macOS:**
- GPU monitoring not supported (no reliable CLI tools)

### Temperature shows as 0

**Linux:**
- Install `lm-sensors`: `sudo apt install lm-sensors`
- Run: `sudo sensors-detect`

**Windows:**
- Requires specific hardware support
- May need admin privileges

**macOS:**
- Install `osx-cpu-temp`: `brew install osx-cpu-temp`

## Architecture
```
┌─────────────┐
│   Device    │
│  (Linux/    │
│  Windows/   │
│   macOS)    │
└──────┬──────┘
       │ Collector Script
       │ (runs every N minutes)
       ↓
┌─────────────┐
│   TRMNL     │
│  Webhook    │
│     API     │
└──────┬──────┘
       │ merge_variables
       │ (d1, d2, ... d30)
       ↓
┌─────────────┐
│   TRMNL     │
│   Plugin    │
│  (Liquid)   │
└──────┬──────┘
       │ Rendered HTML
       ↓
┌─────────────┐
│   E-ink     │
│  Display    │
└─────────────┘
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see LICENSE file for details

## Support

- **Issues:** [GitHub Issues](https://github.com/ExcuseMi/trmnl-device-health-monitor-plugin/issues)
- **TRMNL Docs:** [docs.usetrmnl.com](https://docs.usetrmnl.com)

## Credits

Created by [ExcuseMi](https://github.com/ExcuseMi)

Icons by [Font Awesome](https://fontawesome.com) and [Simple Icons](https://simpleicons.org)