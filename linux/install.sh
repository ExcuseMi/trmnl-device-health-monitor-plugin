#!/bin/bash

echo "=== TRMNL Device Health Monitor - Linux Installer ==="

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

# Get device ID (1-10 for standard, 1-30 for TRMNL+)
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

DEFAULT_HOSTNAME=$(cat /proc/sys/kernel/hostname 2>/dev/null || uname -n)
read -p "Enter device name/label (default: $DEFAULT_HOSTNAME): " DEVICE_NAME
DEVICE_NAME=${DEVICE_NAME:-$DEFAULT_HOSTNAME}

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
else
    echo "  Standard Rate Limit: 12 requests/hour"
    echo ""
    echo "  1) Every 5 minutes (max 1 device)"
    echo "  2) Every 10 minutes (max 2 devices)"
    echo "  3) Every 15 minutes (max 3 devices)"
    echo "  4) Every 20 minutes (max 4 devices)"
    echo "  5) Every 30 minutes (max 6 devices)"
    echo "  6) Every hour (max 12 devices) [RECOMMENDED]"
fi

if [[ "$HAS_PREMIUM" =~ ^[Yy]$ ]]; then
    read -p "Select interval (1-5): " INTERVAL_CHOICE
else
    read -p "Select interval (1-4): " INTERVAL_CHOICE
fi

if [[ "$HAS_PREMIUM" =~ ^[Yy]$ ]]; then
    case $INTERVAL_CHOICE in
        1) UPDATE_INTERVAL=120; SLOTS=30; DESC="every 2 minutes" ;;   # 30 req/hr per device
        2) UPDATE_INTERVAL=300; SLOTS=12; DESC="every 5 minutes" ;;   # 12 req/hr per device
        3) UPDATE_INTERVAL=360; SLOTS=10; DESC="every 6 minutes" ;;   # 10 req/hr per device
        4) UPDATE_INTERVAL=600; SLOTS=6; DESC="every 10 minutes" ;;   # 6 req/hr per device
        5) UPDATE_INTERVAL=3600; SLOTS=30; DESC="every hour" ;;       # 1 req/hr per device
        *) UPDATE_INTERVAL=3600; SLOTS=30; DESC="every hour" ;;
    esac
else
    case $INTERVAL_CHOICE in
        1) UPDATE_INTERVAL=300; SLOTS=12; DESC="every 5 minutes" ;;   # 12 req/hr per device
        2) UPDATE_INTERVAL=360; SLOTS=10; DESC="every 6 minutes" ;;   # 10 req/hr per device
        3) UPDATE_INTERVAL=600; SLOTS=6; DESC="every 10 minutes" ;;   # 6 req/hr per device
        4) UPDATE_INTERVAL=3600; SLOTS=12; DESC="every hour" ;;       # 1 req/hr per device
        *) UPDATE_INTERVAL=3600; SLOTS=12; DESC="every hour" ;;
    esac
fi

# Always use /opt for system-wide install (SELinux-friendly)
INSTALL_DIR="/opt/trmnl-health"
LOG_DIR="/var/log/trmnl-health"

# Create directories
sudo mkdir -p "$INSTALL_DIR"
sudo mkdir -p "$LOG_DIR"
cd "$INSTALL_DIR"

# Create config file
sudo tee config.json > /dev/null <<EOF
{
  "webhook_url": "$WEBHOOK_URL",
  "device_id": "$DEVICE_ID",
  "device_name": "$DEVICE_NAME",
  "update_interval": $UPDATE_INTERVAL
}
EOF

# Create data collection script
sudo tee collect.sh > /dev/null <<'COLLECTOR'
#!/bin/bash

CONFIG_FILE="$(dirname "$0")/config.json"
WEBHOOK_URL=$(jq -r '.webhook_url' "$CONFIG_FILE")
DEVICE_ID=$(jq -r '.device_id' "$CONFIG_FILE")
DEVICE_NAME=$(jq -r '.device_name' "$CONFIG_FILE")

# OS Information
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS="${NAME} ${VERSION_ID}"
else
    OS=$(uname -s)
fi
OS=$(echo "$OS" | tr -d '"' | cut -c1-30)

# Logged in users - count and list
LOGGED_IN_COUNT=$(who | wc -l)
LOGGED_IN_USERS=$(who | awk '{print $1}' | sort -u | tr '\n' ',' | sed 's/,$//')
if [ "$LOGGED_IN_COUNT" -eq 0 ]; then
    LOGGED_IN_USERS="none"
fi

# CPU - usage, cores, frequency
CPU=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print int(100 - $1)}')
CPU_CORES=$(nproc)
CPU_FREQ=$(cat /proc/cpuinfo | grep "cpu MHz" | head -1 | awk '{print int($4)}')
CPU_FREQ=${CPU_FREQ:-0}

# Load average (1min, 5min, 15min)
LOAD_AVG=$(cat /proc/loadavg | awk '{print $1","$2","$3}')

# Memory - used/total in MiB (binary), convert to GiB
MEM_INFO=$(free -m | grep Mem)
MEM_TOTAL_MB=$(echo $MEM_INFO | awk '{print $2}')
MEM_USED_MB=$(echo $MEM_INFO | awk '{print $3}')
MEM_TOTAL=$(awk "BEGIN {printf \"%.0f\", $MEM_TOTAL_MB / 1024}")
MEM_USED=$(awk "BEGIN {printf \"%.0f\", $MEM_USED_MB / 1024}")

# Disk - used/total in GB (find largest partition, excluding special filesystems)
DISK_INFO=$(df -BG --output=size,used,target | \
    grep -v "^Size" | \
    grep -v "/dev\|/sys\|/proc\|/run\|/boot\|/snap" | \
    sort -h -r | \
    head -1)

if [ -z "$DISK_INFO" ]; then
    # Fallback to root if nothing else found
    DISK_INFO=$(df -BG / | tail -1)
fi

DISK_TOTAL=$(echo $DISK_INFO | awk '{print $1}' | tr -d 'G')
DISK_USED=$(echo $DISK_INFO | awk '{print $2}' | tr -d 'G')

# Temperature
TEMP=0
if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    TEMP=$(($(cat /sys/class/thermal/thermal_zone0/temp) / 1000))
elif command -v sensors &> /dev/null; then
    TEMP=$(sensors | grep -oP 'Core 0.*?\+\K[0-9]+' | head -1)
fi
TEMP=${TEMP:-0}

# Battery - level and charging status (0=no, 1=yes)
BATTERY=0
CHARGING=0
if [ -d /sys/class/power_supply/BAT0 ]; then
    BATTERY=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo 0)
    STATUS=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo "Unknown")
    if [ "$STATUS" = "Charging" ] || [ "$STATUS" = "Full" ]; then
        CHARGING=1
    fi
elif [ -d /sys/class/power_supply/BAT1 ]; then
    BATTERY=$(cat /sys/class/power_supply/BAT1/capacity 2>/dev/null || echo 0)
    STATUS=$(cat /sys/class/power_supply/BAT1/status 2>/dev/null || echo "Unknown")
    if [ "$STATUS" = "Charging" ] || [ "$STATUS" = "Full" ]; then
        CHARGING=1
    fi
fi

# GPU detection and stats
GPU_NAME="none"
GPU_TEMP=0
GPU_UTIL=0

# Try NVIDIA first
if command -v nvidia-smi &> /dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1 | cut -c1-20)
    GPU_TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader | head -1)
    GPU_UTIL=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | head -1)
# Try AMD
elif command -v rocm-smi &> /dev/null; then
    GPU_TEMP=$(rocm-smi --showtemp | grep -oP 'Temperature:.*?\K[0-9]+' | head -1)
    GPU_UTIL=$(rocm-smi --showuse | grep -oP 'GPU use:.*?\K[0-9]+' | head -1)
    GPU_NAME="AMD"
# Try Intel
elif [ -d /sys/class/drm/card0 ]; then
    GPU_NAME="Intel"
fi

GPU_TEMP=${GPU_TEMP:-0}
GPU_UTIL=${GPU_UTIL:-0}

# Network throughput (KB/s)
DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
if [ -n "$DEFAULT_IFACE" ]; then
    RX1=$(cat /sys/class/net/$DEFAULT_IFACE/statistics/rx_bytes 2>/dev/null || echo 0)
    TX1=$(cat /sys/class/net/$DEFAULT_IFACE/statistics/tx_bytes 2>/dev/null || echo 0)
    sleep 1
    RX2=$(cat /sys/class/net/$DEFAULT_IFACE/statistics/rx_bytes 2>/dev/null || echo 0)
    TX2=$(cat /sys/class/net/$DEFAULT_IFACE/statistics/tx_bytes 2>/dev/null || echo 0)
    NET=$(( (RX2 - RX1 + TX2 - TX1) / 1024 ))
else
    NET=0
fi

# Connection type
if command -v iwconfig &> /dev/null && iwconfig 2>/dev/null | grep -q "ESSID"; then
    SSID=$(iwconfig 2>/dev/null | grep ESSID | awk -F'"' '{print $2}' | head -1)
    CONN="wifi:${SSID}"
elif command -v nmcli &> /dev/null; then
    SSID=$(nmcli -t -f active,ssid dev wifi | grep '^yes' | cut -d: -f2)
    if [ -n "$SSID" ]; then
        CONN="wifi:${SSID}"
    else
        CONN="lan"
    fi
else
    CONN="lan"
fi

# IP Address
IP=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
IP=${IP:-127.0.0.1}

# Uptime in seconds
UPTIME=$(cat /proc/uptime | awk '{print int($1)}')

# Timestamp (Unix timestamp UTC)
TIMESTAMP=$(date +%s)

# Build payload (23 fields)
# Format: name|os|userCount|users|cpu|cores|freq|load|memU|memT|diskU|diskT|temp|bat|chr|gpu|gputemp|gpuutil|net|conn|ip|uptime|ts
PAYLOAD="${DEVICE_NAME}|${OS}|${LOGGED_IN_COUNT}|${LOGGED_IN_USERS}|${CPU}|${CPU_CORES}|${CPU_FREQ}|${LOAD_AVG}|${MEM_USED}|${MEM_TOTAL}|${DISK_USED}|${DISK_TOTAL}|${TEMP}|${BATTERY}|${CHARGING}|${GPU_NAME}|${GPU_TEMP}|${GPU_UTIL}|${NET}|${CONN}|${IP}|${UPTIME}|${TIMESTAMP}"

# Send to webhook with shortened JSON keys
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

sudo chmod +x collect.sh

# Install dependencies
echo ""
echo "Installing dependencies..."
if command -v apt-get &> /dev/null; then
    sudo apt-get update && sudo apt-get install -y jq curl bc
elif command -v yum &> /dev/null; then
    sudo yum install -y jq curl bc
elif command -v dnf &> /dev/null; then
    sudo dnf install -y jq curl bc
elif command -v pacman &> /dev/null; then
    sudo pacman -S --noconfirm jq curl bc
elif command -v apk &> /dev/null; then
    sudo apk add jq curl bc
else
    echo "Warning: Please install manually: jq curl bc"
fi

# Calculate staggered timing based on hostname hash
HASH=$(echo -n "$DEVICE_NAME" | md5sum | cut -d' ' -f1)
SLOT=$((0x${HASH:0:8} % SLOTS))

# Calculate schedule based on interval
if [ $UPDATE_INTERVAL -eq 120 ]; then
    # Every 2 minutes
    MINUTE_OFFSET=$((SLOT * 2))
    SCHEDULE_DESC="every 2 minutes starting at :$MINUTE_OFFSET"
    SYSTEMD_CALENDAR="*:00/2:00"
elif [ $UPDATE_INTERVAL -eq 300 ]; then
    # Every 5 minutes
    MINUTE_OFFSET=$((SLOT * 5))
    SCHEDULE_DESC="every 5 minutes starting at :$MINUTE_OFFSET"
    SYSTEMD_CALENDAR="*:00/5:00"
elif [ $UPDATE_INTERVAL -eq 360 ]; then
    # Every 6 minutes
    MINUTE_OFFSET=$((SLOT * 6))
    SCHEDULE_DESC="every 6 minutes starting at :$MINUTE_OFFSET"
    SYSTEMD_CALENDAR="*:00/6:00"
elif [ $UPDATE_INTERVAL -eq 600 ]; then
    # Every 10 minutes
    MINUTE_OFFSET=$((SLOT * 10))
    SCHEDULE_DESC="every 10 minutes starting at :$MINUTE_OFFSET"
    SYSTEMD_CALENDAR="*:00/10:00"
else
    # Every hour
    MINUTE_OFFSET=$((SLOT * 5))
    SCHEDULE_DESC="every hour at :$MINUTE_OFFSET"
    SYSTEMD_CALENDAR="*:$MINUTE_OFFSET:00"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Configuration Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Tier: $TIER"
echo "Device ID: $DEVICE_ID (will appear as 'd${DEVICE_ID}' in TRMNL)"
echo "Device Name: $DEVICE_NAME"
echo "Webhook: $WEBHOOK_URL"
echo "Update schedule: $SCHEDULE_DESC"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Create systemd service (SELinux-friendly paths)
if command -v systemctl &> /dev/null; then
    sudo tee /etc/systemd/system/trmnl-health.service > /dev/null <<EOF
[Unit]
Description=TRMNL Device Health Monitor
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$INSTALL_DIR/collect.sh
StandardOutput=append:$LOG_DIR/trmnl-health.log
StandardError=append:$LOG_DIR/trmnl-health.log

[Install]
WantedBy=multi-user.target
EOF

    sudo tee /etc/systemd/system/trmnl-health.timer > /dev/null <<EOF
[Unit]
Description=TRMNL Device Health Monitor Timer
Requires=trmnl-health.service

[Timer]
OnCalendar=$SYSTEMD_CALENDAR
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Set proper SELinux context for log directory
    if command -v semanage &> /dev/null; then
        sudo semanage fcontext -a -t var_log_t "$LOG_DIR(/.*)?" 2>/dev/null || true
        sudo restorecon -R "$LOG_DIR" 2>/dev/null || true
    fi

    sudo systemctl daemon-reload
    sudo systemctl enable trmnl-health.timer
    sudo systemctl start trmnl-health.timer

    echo "✓ Installed as systemd service"
    echo "  Check status: sudo systemctl status trmnl-health.timer"
    echo "  View logs: sudo tail -f $LOG_DIR/trmnl-health.log"
    echo ""
else
    # Fallback to cron
    CRON_SCHEDULE="*/$((UPDATE_INTERVAL/60)) * * * * $INSTALL_DIR/collect.sh >> $LOG_DIR/trmnl-health.log 2>&1"
    (sudo crontab -l 2>/dev/null | grep -v "trmnl-health"; echo "$CRON_SCHEDULE") | sudo crontab -
    echo "✓ Installed as cron job"
    echo "  Logs: $LOG_DIR/trmnl-health.log"
    echo ""
fi

# Test run
echo "Running test collection..."
echo ""
sudo $INSTALL_DIR/collect.sh
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ Installation complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Config: $INSTALL_DIR/config.json"
echo "Logs: $LOG_DIR/trmnl-health.log"
echo ""
echo "Payload format (23 fields):"
echo "name|os|userCount|users|cpu%|cores|freq|load|memU|memT|diskU|diskT|temp|bat%|chr|gpu|gputemp|gpuutil|net|conn|ip|uptime|ts"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"