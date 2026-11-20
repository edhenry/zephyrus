#!/usr/bin/env bash
# tmux status segment: load average, battery, network. macOS and Linux.
#
# tmux runs this once per attached client on every status refresh, so the
# common path only prints a cached line. Battery and interface state refresh
# on a slower timer. The macOS Wi-Fi lookup takes many seconds, so it runs in
# the background, one at a time, and never delays the status line.
#
# Tunables (seconds): TMUX_STATS_TTL, TMUX_STATS_SLOW_TTL, TMUX_STATS_WIFI_TTL
# (0 turns the Wi-Fi lookup off). TMUX_STATS_CACHE_DIR moves the cache.

set -euo pipefail

LINE_TTL="${TMUX_STATS_TTL:-5}"
SLOW_TTL="${TMUX_STATS_SLOW_TTL:-60}"
WIFI_TTL="${TMUX_STATS_WIFI_TTL:-120}"
[[ "$LINE_TTL" =~ ^[0-9]+$ ]] || LINE_TTL=5
[[ "$SLOW_TTL" =~ ^[0-9]+$ ]] || SLOW_TTL=60
[[ "$WIFI_TTL" =~ ^[0-9]+$ ]] || WIFI_TTL=120
WIFI_TIMEOUT=60
CACHE_DIR="${TMUX_STATS_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/tmux-system-stats}"
LINE_FILE="$CACHE_DIR/line"
SLOW_FILE="$CACHE_DIR/slow"
WIFI_FILE="$CACHE_DIR/wifi"
WIFI_LOCK="$CACHE_DIR/wifi.lock"

now="${EPOCHSECONDS:-}"
[[ -n "$now" ]] || now="$(date +%s)"

CACHED=()
read_lines() {
  CACHED=()
  [[ -r "$1" ]] || return 1
  local l
  while IFS= read -r l || [[ -n "$l" ]]; do CACHED+=("$l"); done < "$1"
  (( ${#CACHED[@]} > 0 ))
}

fresh() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( now >= $1 && now - $1 < $2 ))
}

write_lines() {
  local file="$1" tmp="$1.$$"
  shift
  {
    if ! { printf '%s\n' "$@" > "$tmp" && mv -f "$tmp" "$file"; }; then
      rm -f "$tmp" || true
    fi
  } 2>/dev/null
  return 0
}

if read_lines "$LINE_FILE" && fresh "${CACHED[0]}" "$LINE_TTL"; then
  printf '%s' "${CACHED[1]:-}"
  exit 0
fi

[[ -d "$CACHE_DIR" ]] || mkdir -p "$CACHE_DIR" 2>/dev/null || true

IS_MAC=0
if [[ "$OSTYPE" == darwin* ]]; then IS_MAC=1; fi

LOAD=""
if (( IS_MAC )); then
  read -r _ LOAD _ <<< "$(sysctl -n vm.loadavg 2>/dev/null || true)"
elif [[ -r /proc/loadavg ]]; then
  read -r LOAD _ < /proc/loadavg || true
fi
LOAD="${LOAD:---}"

BATT="--"
NET_BASE="Net:offline"
WANT_WIFI=0

refresh_slow_darwin() {
  local out line prev="" wifi_if="" ifname
  local wifi_port='^Hardware Port: *Wi-?Fi'
  out="$(pmset -g batt 2>/dev/null || true)"
  if [[ "$out" =~ ([0-9]+)% ]]; then BATT="${BASH_REMATCH[1]}%"; fi

  while IFS= read -r line; do
    if [[ "$prev" =~ $wifi_port && "$line" == Device:* ]]; then
      wifi_if="${line#Device: }"
    fi
    prev="$line"
  done <<< "$(networksetup -listallhardwareports 2>/dev/null || true)"

  if [[ -n "$wifi_if" && "$(ifconfig "$wifi_if" 2>/dev/null || true)" == *"status: active"* ]]; then
    NET_BASE="WiFi"
    WANT_WIFI=1
    return 0
  fi
  for ifname in $(ifconfig -l 2>/dev/null || true); do
    [[ "$ifname" =~ ^en[0-9]+$ ]] || continue
    if ipconfig getifaddr "$ifname" >/dev/null 2>&1; then
      NET_BASE="Eth:${ifname}"
      return 0
    fi
  done
  return 0
}

refresh_slow_linux() {
  local cap="" ssid ifname
  if [[ -r /sys/class/power_supply/BAT0/capacity ]]; then
    read -r cap < /sys/class/power_supply/BAT0/capacity || true
    if [[ -n "$cap" ]]; then BATT="${cap}%"; fi
  fi

  if command -v nmcli >/dev/null 2>&1; then
    ssid="$(nmcli -t -f active,ssid dev wifi 2>/dev/null | grep '^yes:' | cut -d: -f2 || true)"
    ssid="${ssid%%$'\n'*}"
    if [[ -n "$ssid" ]]; then
      NET_BASE="WiFi:${ssid}"
    elif ip route get 1.1.1.1 &>/dev/null; then
      ifname="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1); exit}')"
      NET_BASE="Eth:${ifname:-?}"
    fi
  elif command -v iwconfig >/dev/null 2>&1; then
    ssid="$(iwconfig 2>/dev/null | grep -oP 'ESSID:"\K[^"]+' | head -1 || true)"
    if [[ -n "$ssid" ]]; then
      NET_BASE="WiFi:${ssid}"
    elif ip route get 1.1.1.1 &>/dev/null; then
      NET_BASE="Eth:wired"
    fi
  elif ip route get 1.1.1.1 &>/dev/null; then
    NET_BASE="Eth:wired"
  fi
  return 0
}

if read_lines "$SLOW_FILE" && fresh "${CACHED[0]}" "$SLOW_TTL"; then
  BATT="${CACHED[1]:---}"
  NET_BASE="${CACHED[2]:-Net:offline}"
  WANT_WIFI="${CACHED[3]:-0}"
else
  if (( IS_MAC )); then refresh_slow_darwin; else refresh_slow_linux; fi
  write_lines "$SLOW_FILE" "$now" "$BATT" "$NET_BASE" "$WANT_WIFI"
fi

start_wifi_refresh() {
  if read_lines "$WIFI_LOCK" && fresh "${CACHED[0]}" "$(( WIFI_TIMEOUT + 30 ))"; then
    return 0
  fi

  # The lock is linked into place with its contents already written, so a
  # reader never sees it empty. The token lets a lookup tell its own lock
  # from one that replaced it.
  local token="$now.$$" claim="$WIFI_LOCK.$$" held=0
  {
    if [[ -e "$WIFI_LOCK" ]]; then rm -f "$WIFI_LOCK"; fi
    if printf '%s\n' "$now" "$token" > "$claim" && ln "$claim" "$WIFI_LOCK"; then held=1; fi
    rm -f "$claim"
  } 2>/dev/null || true
  (( held )) || return 0

  (
    json="$CACHE_DIR/wifi.json.$$"
    profiler=""
    watchdog=""
    # shellcheck disable=SC2329
    cleanup() {
      [[ -z "$profiler" ]] || kill "$profiler" 2>/dev/null || true
      [[ -z "$watchdog" ]] || kill "$watchdog" 2>/dev/null || true
      rm -f "$json" 2>/dev/null || true
      if read_lines "$WIFI_LOCK" && [[ "${CACHED[1]:-}" == "$token" ]]; then
        rm -f "$WIFI_LOCK" 2>/dev/null || true
      fi
    }
    trap cleanup EXIT

    rm -f "$CACHE_DIR"/wifi.json.* 2>/dev/null || true
    /usr/sbin/system_profiler -nospawn -json SPAirPortDataType > "$json" 2>/dev/null &
    profiler=$!
    (
      timer=""
      trap '[[ -z "$timer" ]] || kill "$timer" 2>/dev/null; exit 0' TERM
      sleep "$WIFI_TIMEOUT" &
      timer=$!
      if wait "$timer"; then kill "$profiler" 2>/dev/null || true; fi
    ) &
    watchdog=$!

    ok=0
    ssid=""
    rssi=""
    if wait "$profiler" && [[ -s "$json" ]]; then
      ok=1
      key='SPAirPortDataType.0.spairport_airport_interfaces.0.spairport_current_network_information'
      ssid="$(/usr/bin/plutil -extract "$key._name" raw -o - "$json" 2>/dev/null || true)"
      rssi="$(/usr/bin/plutil -extract "$key.spairport_signal_noise" raw -o - "$json" 2>/dev/null || true)"
    fi
    profiler=""

    # Lines: time of this attempt, name, signal, time the name and signal
    # were read. A failed lookup keeps the last reading.
    if (( ok )); then
      write_lines "$WIFI_FILE" "$now" "$ssid" "${rssi%% *}" "$now"
    elif read_lines "$WIFI_FILE"; then
      write_lines "$WIFI_FILE" "$now" "${CACHED[1]:-}" "${CACHED[2]:-}" "${CACHED[3]:-0}"
    else
      write_lines "$WIFI_FILE" "$now" "" "" 0
    fi
  ) < /dev/null > /dev/null 2>&1 &
  return 0
}

NET="$NET_BASE"
if (( IS_MAC )) && [[ "$WANT_WIFI" == "1" && "$WIFI_TTL" != "0" ]]; then
  SSID=""
  RSSI=""
  if read_lines "$WIFI_FILE"; then
    WIFI_TRIED="${CACHED[0]}"
    if fresh "${CACHED[3]:-0}" "$(( WIFI_TTL * 3 ))"; then
      SSID="${CACHED[1]:-}"
      RSSI="${CACHED[2]:-}"
    fi
    fresh "$WIFI_TRIED" "$WIFI_TTL" || start_wifi_refresh
  else
    start_wifi_refresh
  fi

  BARS=""
  if [[ "$RSSI" =~ ^-?[0-9]+$ ]]; then
    if   (( RSSI >= -55 )); then BARS=" ▂▄▆█"
    elif (( RSSI >= -65 )); then BARS=" ▂▄██"
    elif (( RSSI >= -75 )); then BARS=" ▂▄▆ "
    elif (( RSSI >= -85 )); then BARS=" ▂▄  "
    else                         BARS=" ▂   "
    fi
  fi
  if [[ -n "$SSID" && "$SSID" != *redacted* ]]; then
    NET="WiFi:${SSID}${BARS}"
  elif [[ -n "$BARS" ]]; then
    NET="WiFi${BARS}"
  else
    NET="WiFi:--"
  fi
fi

LINE="CPU:${LOAD}  🔋${BATT}  ${NET}"
write_lines "$LINE_FILE" "$now" "$LINE"
printf '%s' "$LINE"
