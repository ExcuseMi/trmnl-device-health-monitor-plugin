#!/bin/bash
# TRMNL Device Health Monitor - macOS Installer
# Save as: install.sh
# Run: sudo ./install.sh YOUR_PLUGIN_UUID

echo "=== TRMNL Device Health Monitor - macOS Installer ==="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

# Get plugin UUID from argument or prompt
if [ -n "$1" ]; then
    PLUGIN_UUID="$1"
else
    read -p "Enter your TRMNL plugin UUID: " PLUGIN_UUID
fi

# Validate UUID format
if [[ ! "$PLUGIN_UUID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Error: Invalid plugin UUID format"
    exit 1
fi

WEBHOOK_URL="https://usetrmnl.com/api/custom_plugins/$PLUGIN_UUID"

# Get device ID (1-12 for standard, 1-30 for TRMNL+)
echo ""
echo "Do you have TRMNL+ subscription?"
read -p "TRMNL+ (y/n) [n]: " HAS_PREMIUM
HAS_PREMIUM=${HAS_PREMIUM:-n}

if [[ "$HAS_PREMIUM" =~ ^[Yy]$ ]]; then
    MAX_DEVICES=30
    TIER="TRMNL+"
else
    MAX_DEVICES=12
    TIER="Standard"
fi

echo ""
echo "Assign this device a number (1-$MAX_DEVICES)"
echo "Each device needs a unique number for the dashboard"
read -p "Device ID (1-$MAX_DEVICES): " DEVICE_ID

if ! [[ "$DEVICE_ID" =~ ^[0-9]+$ ]] || [ "$DEVICE_ID" -lt 1 ] || [ "$DEVICE_ID" -gt "$MAX_DEVICES" ]; then
    echo "Error: Device ID must be between 1 and $MAX_DEVICES"
    exit 1
fi

read -p "Enter device name/label (default: $(hostname)): " DEVICE_NAME
DEVICE_NAME=${DEVICE_NAME:-$(hostname)}

# Get update interval with CORRECT rate limit calculations
echo ""
echo "Update interval options ($TIER tier):"
if [[ "$HAS_PREMIUM" =~ ^[Yy]$ ]]; then
    echo "  TRMNL+ Rate Limit: 30 requests/hour"
    echo ""
    echo "  1) Every 2 minutes (max 1 device)"
    echo "  2) Every 6 minutes (max 3 devices)"
    echo "  3) Every 10 minutes (max 5 devices)"
    echo "  4) Every hour (max 30 devices) [RECOMMENDED]"
    read -p "Select interval (1-4): " INTERVAL_CHOICE
else
    echo "  Standard Rate Limit: 12 requests/hour"
    echo ""
    echo "  1) Every 5 minutes (max 1 device)"
    echo "  2) Every 10 minutes (max 2 devices)"
    echo "  3) Every 15 minutes (max 3 devices)"
    echo "  4) Every 20 minutes (max 4 devices)"
    echo "  5) Every 30 minutes (max 6 devices)"
    echo "  6) Every hour (max 12 devices) [RECOMMENDED]"
    read -p "Select interval (1-6): " INTERVAL_CHOICE
fi

if [[ "$HAS_PREMIUM" =~ ^[Yy]$ ]]; then
    case $INTERVAL_CHOICE in
        1) UPDATE_INTERVAL=120; DESC="every 2 minutes" ;;
        2) UPDATE_INTERVAL=360; DESC="every 6 minutes" ;;
        3) UPDATE_INTERVAL=600; DESC="every 10 minutes" ;;
        4) UPDATE_INTERVAL=3600; DESC="every hour" ;;
        *) UPDATE_INTERVAL=3600; DESC="every hour" ;;
    esac
else
    case $INTERVAL_CHOICE in
        1) UPDATE_INTERVAL=300; DESC="every 5 minutes" ;;
        2) UPDATE_INTERVAL=600; DESC="every 10 minutes" ;;
        3) UPDATE_INTERVAL=900; DESC="every 15 minutes" ;;
        4) UPDATE_INTERVAL=1200; DESC="every 20 minutes" ;;
        5) UPDATE_INTERVAL=1800; DESC="every 30 minutes" ;;
        6) UPDATE_INTERVAL=3600; DESC="every hour" ;;
        *) UPDATE_INTERVAL=3600; DESC="every hour" ;;
    esac
fi

# Install directory
INSTALL_DIR="/usr/local/bin/trmnl-health"
LOG_FILE="/var/log/trmnl-health.log"

# Create directories
mkdir -p "$INSTALL_DIR"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

# Create config file
cat > "$INSTALL_DIR/config.json" <<EOF
{
  "webhook_url": "$WEBHOOK_URL",
  "device_id": "$DEVICE_ID",
  "device_name": "$DEVICE_NAME",
  "update_interval": $UPDATE_INTERVAL
}
EOF

# Create data collection script
cat > "$INSTALL_DIR/collect.sh" <<'COLLECTOR'
#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required. Install with: brew install jq"
    exit 1
fi

WEBHOOK_URL=$(jq -r '.webhook_url' "$CONFIG_FILE")
DEVICE_ID=$(jq -r '.device_id' "$CONFIG_FILE")
DEVICE_NAME=$(jq -r '.device_name' "$CONFIG_FILE")

# OS Information
OS=$(sw_vers -productName)" "$(sw_vers -productVersion)
OS=$(echo "$OS" | cut -c1-30)

# Logged in users - count and list
LOGGED_IN_COUNT=$(who | wc -l | tr -d ' ')
LOGGED_IN_USERS=$(who | awk '{print $1}' | sort -u | tr '\n' ',' | sed 's/,$//')
if [ "$LOGGED_IN_COUNT" -eq 0 ]; then
    LOGGED_IN_USERS="none"
fi

# CPU - usage, cores, frequency
CPU=$(ps -A -o %cpu | awk '{s+=$1} END {print int(s)}')
CPU_CORES=$(sysctl -n hw.ncpu)
CPU_FREQ=$(sysctl -n hw.cpufrequency 2>/dev/null || echo 0)
CPU_FREQ=$((CPU_FREQ / 1000000))  # Convert to MHz
if [ "$CPU_FREQ" -eq 0 ]; then
    # Fallback for Apple Silicon
    CPU_FREQ=$(sysctl -n hw.cpufrequency_max 2>/dev/null || echo 0)
    CPU_FREQ=$((CPU_FREQ / 1000000))
fi

# Load average (1min, 5min, 15min)
LOAD_AVG=$(sysctl -n vm.loadavg | awk '{print $2","$3","$4}')

# Memory - used/total in GB
MEM_TOTAL_BYTES=$(sysctl -n hw.memsize)
MEM_TOTAL=$((MEM_TOTAL_BYTES / 1024 / 1024 / 1024))

# macOS memory calculation
MEM_WIRED=$(vm_stat | grep "Pages wired down" | awk '{print $4}' | tr -d '.')
MEM_ACTIVE=$(vm_stat | grep "Pages active" | awk '{print $3}' | tr -d '.')
MEM_COMPRESSED=$(vm_stat | grep "Pages occupied by compressor" | awk '{print $5}' | tr -d '.')
PAGE_SIZE=$(pagesize)

MEM_USED_BYTES=$(((MEM_WIRED + MEM_ACTIVE + MEM_COMPRESSED) * PAGE_SIZE))
MEM_USED=$((MEM_USED_BYTES / 1024 / 1024 / 1024))

# Disk - used/total in GB (root filesystem)
DISK_INFO=$(df -g / | tail -1)
DISK_TOTAL=$(echo $DISK_INFO | awk '{print $2}')
DISK_USED=$(echo $DISK_INFO | awk '{print $3}')

# Temperature - requires osx-cpu-temp
TEMP=0
if command -v osx-cpu-temp &> /dev/null; then
    TEMP=$(osx-cpu-temp | grep -oE '[0-9]+' | head -1)
fi
TEMP=${TEMP:-0}

# Battery - level and charging status
BATTERY=0
CHARGING=0
if command -v pmset &> /dev/null; then
    BATTERY_INFO=$(pmset -g batt)
    if echo "$BATTERY_INFO" | grep -q "InternalBattery"; then
        BATTERY=$(echo "$BATTERY_INFO" | grep -oE '[0-9]+%' | head -1 | tr -d '%')
        if echo "$BATTERY_INFO" | grep -q "charging\|charged"; then
            CHARGING=1
        fi
    fi
fi

# GPU - macOS doesn't have easy CLI access to GPU stats
GPU_NAME="none"
GPU_TEMP=0
GPU_UTIL=0

# Try to get GPU name from system_profiler (slow, so we'll use a simpler approach)
if command -v system_profiler &> /dev/null; then
    GPU_NAME=$(system_profiler SPDisplaysDataType 2>/dev/null | grep "Chipset Model" | head -1 | awk -F': ' '{print $2}' | cut -c1-20)
    GPU_NAME=${GPU_NAME:-none}
fi

# Network throughput (KB/s)
DEFAULT_IFACE=$(route -n get default 2>/dev/null | grep interface | awk '{print $2}')
if [ -n "$DEFAULT_IFACE" ]; then
    RX1=$(netstat -ib -I "$DEFAULT_IFACE" 2>/dev/null | tail -1 | awk '{print $7}')
    TX1=$(netstat -ib -I "$DEFAULT_IFACE" 2>/dev/null | tail -1 | awk '{print $10}')
    sleep 1
    RX2=$(netstat -ib -I "$DEFAULT_IFACE" 2>/dev/null | tail -1 | awk '{print $7}')
    TX2=$(netstat -ib -I "$DEFAULT_IFACE" 2>/dev/null | tail -1 | awk '{print $10}')
    NET=$(( (RX2 - RX1 + TX2 - TX1) / 1024 ))
else
    NET=0
fi

# Connection type
CONN="lan"
if command -v networksetup &> /dev/null; then
    WIFI_INTERFACE=$(networksetup -listallhardwareports | awk '/Wi-Fi|AirPort/{getline; print $2}')
    if [ -n "$WIFI_INTERFACE" ]; then
        SSID=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | awk '/ SSID/ {print $2}')
        if [ -n "$SSID" ]; then
            CONN="wifi:${SSID}"
        fi
    fi
fi

# IP Address
IP=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | head -1 | awk '{print $2}')
IP=${IP:-127.0.0.1}

# Uptime in seconds
UPTIME=$(sysctl -n kern.boottime | awk '{print $4}' | tr -d ',')
CURRENT_TIME=$(date +%s)
UPTIME=$((CURRENT_TIME - UPTIME))

# Timestamp (Unix timestamp UTC)
TIMESTAMP=$(date +%s)

# Build payload (23 fields)
PAYLOAD="${DEVICE_NAME}|${OS}|${LOGGED_IN_COUNT}|${LOGGED_IN_USERS}|${CPU}|${CPU_CORES}|${CPU_FREQ}|${LOAD_AVG}|${MEM_USED}|${MEM_TOTAL}|${DISK_USED}|${DISK_TOTAL}|${TEMP}|${BATTERY}|${CHARGING}|${GPU_NAME}|${GPU_TEMP}|${GPU_UTIL}|${NET}|${CONN}|${IP}|${UPTIME}|${TIMESTAMP}"

# Send to webhook
HTTP_CODE=$(curl -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "{\"merge_variables\":{\"d${DEVICE_ID}\":\"$PAYLOAD\"},\"merge_strategy\":\"deep_merge\"}" \
  -s -o /dev/null -w "%{http_code}")

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Success (HTTP $HTTP_CODE)"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Error (HTTP $HTTP_CODE)"
fi
COLLECTOR

chmod +x "$INSTALL_DIR/collect.sh"

# Check for dependencies
echo ""
echo "Checking dependencies..."

if ! command -v jq &> /dev/null; then
    echo "Installing jq..."
    if command -v brew &> /dev/null; then
        brew install jq
    else
        echo "Warning: Homebrew not found. Please install jq manually: brew install jq"
    fi
fi

if ! command -v osx-cpu-temp &> /dev/null; then
    echo "Note: osx-cpu-temp not installed. Temperature monitoring will be disabled."
    echo "To enable: brew install osx-cpu-temp"
fi

# Create LaunchDaemon plist
cat > /Library/LaunchDaemons/com.trmnl.health.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.trmnl.health</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$INSTALL_DIR/collect.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>$UPDATE_INTERVAL</integer>
    <key>StandardOutPath</key>
    <string>$LOG_FILE</string>
    <key>StandardErrorPath</key>
    <string>$LOG_FILE</string>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF

# Set permissions
chmod 644 /Library/LaunchDaemons/com.trmnl.health.plist
chown root:wheel /Library/LaunchDaemons/com.trmnl.health.plist

# Load LaunchDaemon
launchctl load /Library/LaunchDaemons/com.trmnl.health.plist

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Configuration Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Tier: $TIER"
echo "Device ID: $DEVICE_ID (will appear as 'd${DEVICE_ID}' in TRMNL)"
echo "Device Name: $DEVICE_NAME"
echo "Webhook: $WEBHOOK_URL"
echo "Update schedule: $DESC"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test run
echo "Running test collection..."
echo ""
"$INSTALL_DIR/collect.sh"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ Installation complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Config: $INSTALL_DIR/config.json"
echo "Script: $INSTALL_DIR/collect.sh"
echo "Logs: $LOG_FILE"
echo ""
echo "Check status: sudo launchctl list | grep trmnl"
echo "View logs: tail -f $LOG_FILE"
echo ""
echo "To uninstall:"
echo "  sudo launchctl unload /Library/LaunchDaemons/com.trmnl.health.plist"
echo "  sudo rm /Library/LaunchDaemons/com.trmnl.health.plist"
echo "  sudo rm -rf $INSTALL_DIR"
echo "  sudo rm $LOG_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"