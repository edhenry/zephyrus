#!/usr/bin/env bash
# stats for tmux: CPU, Battery, Network (Wi-Fi/Ethernet)
# Works on macOS and Linux.

set -euo pipefail

say() { printf "%s" "$*"; }
OS="$(uname -s)"

# ---------- CPU ----------
if [[ "$OS" == "Darwin" ]]; then
  LOAD="$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}' | tr -d '{}')"
else
  LOAD="$(awk '{print $1}' /proc/loadavg 2>/dev/null)"
fi
LOAD="${LOAD:---}"

# ---------- Battery ----------
BATT_PCT="--"
if [[ "$OS" == "Darwin" ]]; then
  if command -v pmset >/dev/null 2>&1; then
    BATT_PCT="$(pmset -g batt 2>/dev/null | grep -Eo '[0-9]+%' | head -n1 || true)"
    [[ -z "${BATT_PCT:-}" ]] && BATT_PCT="--"
  fi
else
  # Linux: read from sysfs
  BAT_CAP="/sys/class/power_supply/BAT0/capacity"
  if [[ -r "$BAT_CAP" ]]; then
    BATT_PCT="$(cat "$BAT_CAP")%"
  fi
fi

# ========== macOS-specific network detection ==========
if [[ "$OS" == "Darwin" ]]; then

  # ---------- Interfaces ----------
  WIFI_IF="$(networksetup -listallhardwareports 2>/dev/null \
    | awk 'BEGIN{w=""} /^Hardware Port: *Wi-?Fi/{getline; sub(/^Device: */,""); w=$0} END{print w}')"

  ACTIVE_IF=""
  for IF in $(ifconfig -l | tr ' ' '\n' | grep -E '^en[0-9]+$'); do
    IP=$(ipconfig getifaddr "$IF" 2>/dev/null || true)
    if [[ -n "${IP:-}" ]]; then ACTIVE_IF="$IF"; break; fi
  done

  # ---------- Choose a writable cache dir ----------
  pick_cache_dir() {
    for C in "${XDG_CACHE_HOME:-}" "$HOME/Library/Caches" "${TMPDIR:-/tmp}" "/tmp"; do
      [[ -n "$C" ]] || continue
      D="$C/tmux_net_cache"
      mkdir -p "$D" 2>/dev/null || continue
      if tmpfile="$(mktemp "$D/.tmp.XXXXXX" 2>/dev/null)"; then
        rm -f "$tmpfile"
        echo "$D"
        return 0
      fi
    done
    echo "/tmp"
  }
  CACHE_DIR="$(pick_cache_dir)"
  CACHE_FILE="$CACHE_DIR/spairport.json"
  MAX_AGE=5

  # ---------- Refresh system_profiler JSON, if stale ----------
  need_refresh=1
  if [[ -s "$CACHE_FILE" ]]; then
    now=$(date +%s)
    mtime=$(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)
    age=$(( now - mtime ))
    (( age <= MAX_AGE )) && need_refresh=0
  fi

  if (( need_refresh )); then
    tmp="$(mktemp "$CACHE_DIR/.spairport.json.XXXXXX" 2>/dev/null || true)"
    if [[ -n "${tmp:-}" ]]; then
      /usr/sbin/system_profiler -json SPAirPortDataType 2>/dev/null > "$tmp" || true
      mv -f "$tmp" "$CACHE_FILE" 2>/dev/null || true
    fi
  fi

  # ---------- Extract SSID ----------
  SSID=""
  if [[ -s "$CACHE_FILE" ]]; then
    SSID="$(/usr/bin/plutil -extract 'SPAirPortDataType.0.spairport_airport_interfaces.0.spairport_current_network_information._name' raw -o - "$CACHE_FILE" 2>/dev/null || true)"
  fi

  # ---------- RSSI -----------
  RSSI_RAW="$(/usr/bin/plutil -extract 'SPAirPortDataType.0.spairport_airport_interfaces.0.spairport_current_network_information.spairport_signal_noise' raw -o - "$CACHE_FILE" 2>/dev/null || true)"

  BARS=""
  if [[ -n "$RSSI_RAW" ]]; then
    RSSI="$(printf "%s" "$RSSI_RAW" | awk '{print $1}')"
    if   (( RSSI >= -55 )); then BARS=" ▂▄▆█"
    elif (( RSSI >= -65 )); then BARS=" ▂▄██"
    elif (( RSSI >= -75 )); then BARS=" ▂▄▆ "
    elif (( RSSI >= -85 )); then BARS=" ▂▄  "
    else                         BARS=" ▂   "
    fi
  fi

  # ---------- Build network segment ----------
  if [[ -n "$SSID" ]]; then
    NET_SEG="WiFi:${SSID}${BARS}"
  elif [[ -n "$ACTIVE_IF" ]]; then
    if [[ -n "${WIFI_IF:-}" && "$ACTIVE_IF" == "$WIFI_IF" ]]; then
      NET_SEG="WiFi:--"
    else
      NET_SEG="Eth:${ACTIVE_IF}"
    fi
  else
    NET_SEG="Net:offline"
  fi

# ========== Linux network detection ==========
else

  NET_SEG="Net:offline"

  # Try nmcli first (NetworkManager)
  if command -v nmcli >/dev/null 2>&1; then
    SSID="$(nmcli -t -f active,ssid dev wifi 2>/dev/null | grep '^yes:' | cut -d: -f2 || true)"
    if [[ -n "$SSID" ]]; then
      NET_SEG="WiFi:${SSID}"
    elif ip route get 1.1.1.1 &>/dev/null; then
      IF="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1); exit}')"
      NET_SEG="Eth:${IF:-?}"
    fi
  elif command -v iwconfig >/dev/null 2>&1; then
    SSID="$(iwconfig 2>/dev/null | grep -oP 'ESSID:"\K[^"]+' | head -1 || true)"
    if [[ -n "$SSID" ]]; then
      NET_SEG="WiFi:${SSID}"
    elif ip route get 1.1.1.1 &>/dev/null; then
      NET_SEG="Eth:wired"
    fi
  elif ip route get 1.1.1.1 &>/dev/null; then
    NET_SEG="Eth:wired"
  fi
fi

say "CPU:${LOAD}  🔋${BATT_PCT}  ${NET_SEG}"
