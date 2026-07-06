#!/usr/bin/env bash
#
# server-stats.sh – Modern Minimalist Linux Dashboard
#
# Aesthetics: Tokyo Night / Nord Minimalist
# Architecture: Asymmetrical Left-Accent Cards
#
set -uo pipefail

# =====================================================================
# Tokyo Night Color Palette
# =====================================================================
RESET=$'\e[0m'
BOLD=$'\e[1m'
DIM=$'\e[2m'
WHITE=$'\e[97m'
VIOLET=$'\e[95m'
CYAN=$'\e[96m'
TEAL=$'\e[36m'
GREEN=$'\e[32m'
AMBER=$'\e[33m'
CRIMSON=$'\e[31m'
GRAY=$'\e[90m'

# =====================================================================
# OS Validation
# =====================================================================
if [[ "$(uname -s)" != "Linux" && "$(uname -s)" != "Darwin" ]]; then
    echo -e "${CRIMSON}Error: This script is designed for Linux/Unix-like systems only.${RESET}"
    exit 1
fi

# =====================================================================
# Layout Engine
# =====================================================================

# Dual-Texture Gauge: Active (█) and Empty (░)
get_gauge_string() {
    local val="$1"
    awk -v v="$val" 'BEGIN {
        width = 24;
        filled = int((v / 100) * width);
        if (filled > width) filled = width;
        if (filled < 0) filled = 0;

        res = "";
        for (i=0; i<filled; i++) res = res "█";
        for (i=filled; i<width; i++) res = res "░";
        print res;
    }'
}

# Dynamic color based on thresholds
get_gauge_color() {
    local val="$1"
    awk -v v="$val" 'BEGIN {
        if (v >= 85) print "CRIMSON";
        else if (v >= 60) print "AMBER";
        else print "GREEN";
    }'
}

draw_banner() {
    local text="SERVER PERFORMANCE DASHBOARD"
    local line="──────────────────────────────────────────────────────────"
    echo -e "${GRAY}${line}${RESET}"
    printf "${VIOLET}${BOLD}  %s  ${RESET}\n" "$text"
    echo -e "${GRAY}${line}${RESET}"
}

draw_snapshot() {
    local host=$(hostname)
    local os=$(uname -sr)
    local date_str=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "${DIM}  ${host}  ·  ${os}  ·  ${date_str}${RESET}"
    echo ""
}

draw_main_menu() {
    echo -e "${VIOLET}${BOLD}◆ MAIN MENU${RESET} ${GRAY}──────────────────────────────────────────${RESET}"
    echo -e "${CYAN}▌${RESET}  01  CPU Metrics        ${CYAN}▌${RESET}  02  Memory Stats"
    echo -e "${CYAN}▌${RESET}  03  Disk Usage         ${CYAN}▌${RESET}  04  Top CPU Processes"
    echo -e "${CYAN}▌${RESET}  05  Top Mem Processes   ${CYAN}▌${RESET}  06  System Information"
    echo -e "${CYAN}▌${RESET}  07  Battery Status      ${CYAN}▌${RESET}  08  Hidden Processes"
    echo -e "${CYAN}▌${RESET}  09  Wi-Fi List          ${CYAN}▌${RESET}  10  Wi-Fi Current"
    echo -e "${CYAN}▌${RESET}  11  Full Report         ${CYAN}▌${RESET}  00  Exit"
    echo -e "${GRAY}──────────────────────────────────────────────────────────${RESET}"
    echo -e "${DIM}  › Select [1-11]   › Refresh [r]   › Exit [0]${RESET}"
}

render_panel() {
    local title="$1"
    local content="$2"
    local icon="${3:-🧠}"

    echo -e "\n${VIOLET}${BOLD}◆ ${icon} ${title}${RESET} ${GRAY}──────────────────────────────────────────${RESET}"

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Left accent pillar
        printf "${CYAN}▌${RESET}  %s\n" "$line"
    done <<< "$content"
    echo ""
}

# =====================================================================
# Data Gathering Logic
# =====================================================================

cpu_usage() {
    local idle used
    idle=$(vmstat 1 2 2>/dev/null | tail -1 | awk '{print $15}')
    if [[ -n "$idle" && "$idle" =~ ^[0-9]+$ ]]; then
        used=$(awk -v idle="$idle" 'BEGIN {printf "%.2f", 100-idle}')
    else
        local cpu user nice system idleT iowait irq softirq steal guest guest_nice
        cpu=$(grep '^cpu ' /proc/stat 2>/dev/null || echo "")
        if [[ -n "$cpu" ]]; then
            read -r _ user nice system idleT iowait irq softirq steal guest guest_nice <<<"$cpu"
            local total=$((user+nice+system+idleT+iowait+irq+softirq+steal))
            used=$(awk -v idleT="$idleT" -v total="$total" 'BEGIN {printf "%.2f", (($total-idleT)*100)/total}')
        else
            used="0.00"
        fi
    fi

    local gauge=$(get_gauge_string "$used")
    local color_name=$(get_gauge_color "$used")
    local color_var="${!color_name}"

    printf "${WHITE}Usage:${RESET}  ${color_var}${gauge}${RESET} ${color_var}%.2f%%${RESET}\n" "$used"
}

mem_usage() {
    local mem total used free used_pct used_mb free_mb total_mb
    if [[ "$(uname -s)" == "Darwin" ]]; then
        # macOS Fallback
        local page_size free_pages active_pages inactive_pages speculative_pages wired_pages
        page_size=$(vm_stat | grep "page size of" | awk '{print $8}')
        free_pages=$(vm_stat | grep "Pages free" | awk '{print $3}' | tr -d '.')
        active_pages=$(vm_stat | grep "Pages active" | awk '{print $3}' | tr -d '.')
        inactive_pages=$(vm_stat | grep "Pages inactive" | awk '{print $3}' | tr -d '.')
        speculative_pages=$(vm_stat | grep "Pages speculative" | awk '{print $3}' | tr -d '.')
        wired_pages=$(vm_stat | grep "Pages wired down" | awk '{print $4}' | tr -d '.')

        local total_bytes=$(( (free_pages + active_pages + inactive_pages + speculative_pages + wired_pages) * page_size ))
        local free_bytes=$(( (free_pages + speculative_pages) * page_size ))
        local used_bytes=$(( total_bytes - free_bytes ))

        used_mb=$((used_bytes/1024/1024))
        free_mb=$((free_bytes/1024/1024))
        total_mb=$((total_bytes/1024/1024))
        used_pct=$(awk -v used="$used_bytes" -v total="$total_bytes" 'BEGIN {printf "%.2f", (used*100)/total}')
    else
        # Linux / WSL
        mem=$(free -b 2>/dev/null | awk '/Mem:/ {printf "%s %s %s\n", $2, $3, $4}' || echo "")
        if [[ -n "$mem" ]]; then
            read -r total used free <<<"$mem"
            used_mb=$((used/1024/1024))
            free_mb=$((free/1024/1024))
            total_mb=$((total/1024/1024))
            used_pct=$(awk -v used="$used" -v total="$total" 'BEGIN {printf "%.2f", ($used*100)/total}')
        else
            used_mb=0; free_mb=0; total_mb=0; used_pct="0.00"
        fi
    fi

    local gauge=$(get_gauge_string "$used_pct")
    local color_name=$(get_gauge_color "$used_pct")
    local color_var="${!color_name}"

    printf "${WHITE}Usage:${RESET}  ${color_var}${gauge}${RESET} ${color_var}%.2f%%${RESET}\n" "$used_pct"
    printf "${WHITE}Stats:${RESET}  ${TEAL}%s MB used${RESET} ${GRAY} / ${RESET}${TEAL}%s MB free${RESET} ${DIM}(Total: %s MB)${RESET}\n" "$used_mb" "$free_mb" "$total_mb"
}

disk_usage() {
    printf "${WHITE}%-20s %-10s %-10s %-10s %-s${RESET}\n" "Filesystem" "Size" "Used" "Avail" "Use%"
    if df -h --output=source,size,used,avail,pcent --exclude-type=tmpfs --exclude-type=devtmpfs >/dev/null 2>&1; then
        df -h --output=source,size,used,avail,pcent --exclude-type=tmpfs --exclude-type=devtmpfs | tail -n +2
    else
        df -h | grep -vE '^tmpfs|devtmpfs|udev|map ' | tail -n +2 | awk '{print $1, $2, $3, $4, $5}'
    fi | while read -r fs size used avail pcent; do
        [[ -z "$fs" ]] && continue
        printf "${GRAY}%-20s ${WHITE}%-10s ${WHITE}%-10s ${WHITE}%-10s ${TEAL}%-s${RESET}\n" "$fs" "$size" "$used" "$avail" "$pcent"
    done
}

top_cpu() {
    printf "${WHITE}%-8s %-20s %-8s %-s${RESET}\n" "PID" "COMMAND" "%CPU" "TIME"
    local ps_out
    if ps -eo pid,comm,%cpu,etime --sort=-%cpu >/dev/null 2>&1; then
        ps_out=$(ps -eo pid,comm,%cpu,etime --sort=-%cpu | head -n 6 | tail -n 5)
    else
        ps_out=$(ps -eo pid,comm,%cpu,etime | sort -k3 -nr | head -n 5)
    fi
    echo "$ps_out" | while read -r pid comm cpu time; do
        [[ -z "$pid" ]] && continue
        printf "${GRAY}%-8s ${WHITE}%-20s ${TEAL}%-8s ${GRAY}%-s${RESET}\n" "$pid" "$comm" "$cpu" "$time"
    done
}

top_mem() {
    printf "${WHITE}%-8s %-20s %-10s %-s${RESET}\n" "PID" "COMMAND" "RSS(MB)" "TIME"
    local ps_out
    if ps -eo pid,comm,rss,etime --sort=-rss >/dev/null 2>&1; then
        ps_out=$(ps -eo pid,comm,rss,etime --sort=-rss | awk 'NR>1 && NR<=6 {printf "%s %s %.2f %s\n", $1, $2, $3/1024, $4}')
    else
        ps_out=$(ps -eo pid,comm,rss,etime | sort -k3 -nr | head -n 5 | awk '{printf "%s %s %.2f %s\n", $1, $2, $3/1024, $4}')
    fi
    echo "$ps_out" | while read -r pid comm rss time; do
        [[ -z "$pid" ]] && continue
        printf "${GRAY}%-8s ${WHITE}%-20s ${TEAL}%-10s ${GRAY}%-s${RESET}\n" "$pid" "$comm" "$rss" "$time"
    done
}

extra_stats() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo -e "${WHITE}OS:${RESET}      ${TEAL}$PRETTY_NAME${RESET}"
    else
        echo -e "${WHITE}OS:${RESET}      ${TEAL}$(uname -s) $(uname -r)${RESET}"
    fi
    echo -e "${WHITE}Uptime:${RESET}   ${TEAL}$(uptime -p 2>/dev/null | sed 's/up //' || uptime)${RESET}"
    if [[ -f /proc/loadavg ]]; then
        echo -e "${WHITE}Load:${RESET}     ${TEAL}$(awk '{print $1,$2,$3}' /proc/loadavg 2>/dev/null || echo N/A)${RESET}"
    else
        echo -e "${WHITE}Load:${RESET}     ${TEAL}$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2,$3,$4}' || echo N/A)${RESET}"
    fi
    echo -e "${WHITE}Users:${RESET}    ${TEAL}$(who | wc -l) user(s)${RESET}"
    if command -v lastb >/dev/null 2>&1; then
        echo -e "${WHITE}Failed:${RESET}   ${AMBER}$(lastb 2>/dev/null | wc -l)${RESET}"
    else
        echo -e "${WHITE}Failed:${RESET}   ${GRAY}N/A${RESET}"
    fi
}

battery_status() {
    local batdir=""
    if [ -d "/sys/class/power_supply/BAT0" ]; then batdir="/sys/class/power_supply/BAT0"
    elif [ -d "/sys/class/power_supply/BAT1" ]; then batdir="/sys/class/power_supply/BAT1"; fi

    if [ -z "$batdir" ]; then echo "No battery detected (expected on VM, desktop, or server hardware)"; return; fi

    local capacity status
    capacity=$(cat "$batdir/capacity" 2>/dev/null || echo "N/A")
    status=$(cat "$batdir/status" 2>/dev/null || echo "N/A")

    if [[ "$capacity" =~ ^[0-9]+$ ]]; then
        local gauge=$(get_gauge_string "$capacity")
        local color_name=$(get_gauge_color "$capacity")
        local color_var="${!color_name}"
        printf "${WHITE}Level:${RESET}  ${color_var}${gauge}${RESET} ${color_var}%s%%${RESET}\n" "$capacity"
    else
        echo "Battery Level: $capacity"
    fi
    echo -e "${WHITE}Status:${RESET}  ${TEAL}$status${RESET}"
}

show_hidden_background() {
    printf "${WHITE}%-8s %-5s %-20s %-s${RESET}\n" "PID" "TTY" "COMMAND" "STAT"
    ps -eo pid,tty,comm,stat | awk '$2 == "?" {printf "%-8s %-5s %-20s %-s\n", $1, $2, $3, $4}' | head -n 15 | while read -r pid tty comm stat; do
        printf "${GRAY}%-8s ${WHITE}%-5s ${WHITE}%-20s ${GRAY}%-s${RESET}\n" "$pid" "$tty" "$comm" "$stat"
    done
}

kill_process() {
    local pid="$1"
    [[ -z "$pid" ]] && return 1
    if ! kill -0 "$pid" 2>/dev/null; then echo -e "${CRIMSON}Error: PID $pid not found.${RESET}"; return 1; fi
    local info=$(ps -p "$pid" -o pid,comm,args --no-headers 2>/dev/null)
    echo -e "${WHITE}PID: $pid | Info: $info${RESET}"
    read -rp "Kill this process? [y/N] " answer
    if [[ "$answer" =~ ^[yY] ]]; then
        kill "$pid" && echo -e "${GREEN}Terminated.${RESET}" || echo -e "${CRIMSON}Failed.${RESET}"
    else
        echo "Aborted."
    fi
}

wifi_list() {
    if ! command -v nmcli >/dev/null 2>&1 && ! command -v iw >/dev/null 2>&1; then
        echo "Error: nmcli or iw not found."
        return 1
    fi

    if command -v nmcli >/dev/null 2>&1; then
        nmcli -t -f SSID,BARS,SECURITY device wifi list 2>/dev/null | awk -F: '{
            ssid = $1;
            bars = $2;
            sec = $3;
            if (ssid == "") ssid = "[Hidden]";
            printf "%-30s %-5s %-10s\n", ssid, bars, sec
        }' | head -n 15 | while read -r ssid bars sec; do
            printf "${WHITE}%-30s ${TEAL}%-5s ${GRAY}%-10s${RESET}\n" "$ssid" "$bars" "$sec"
        done
    elif command -v iw >/dev/null 2>&1; then
        local iface=$(iw dev | awk '$1=="Interface"{print $2; exit}')
        if [ -z "$iface" ]; then echo "No wireless interface detected."; return 1; fi
        iw dev "$iface" scan 2>/dev/null | awk '/SSID:/{gsub(/.*SSID:[ 	]*/,"",$0); gsub(/"/,"",$0); print $0}' | sort -u | head -n 15 | while read -r ssid; do
            printf "${WHITE}%-30s ${GRAY}[IW-SCAN]${RESET}\n" "$ssid"
        done
    else
        echo "No compatible Wi-Fi tools found."
        return 1
    fi
}

wifi_current() {
    if ! command -v nmcli >/dev/null 2>&1; then echo "Error: nmcli not found."; return 1; fi
    local res=$(nmcli -t -f ACTIVE,SSID device wifi | grep '^yes' | cut -d: -f2 || true)
    if [[ -z "$res" ]]; then echo "Not connected."; else echo -e "${WHITE}SSID:${RESET}  ${TEAL}$res${RESET}"; fi
}

wifi_connect() {
    local ssid="$1"
    local password="${2:-}"
    if ! command -v nmcli >/dev/null 2>&1; then echo "Error: nmcli not found."; return 1; fi
    if [[ -n "$password" ]]; then
        nmcli device wifi connect "$ssid" password "$password"
    else
        nmcli device wifi connect "$ssid" --ask
    fi
}

# =====================================================================
# Argument Parsing
# =====================================================================
show_hidden=false
kill_pid=""
wifi_list_req=false
wifi_current_req=false
wifi_connect_ssid=""
wifi_connect_password=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--all) show_hidden=true; shift ;;
        --kill) kill_pid="${2:-}"; shift 2 ;;
        --wifi-list) wifi_list_req=true; shift ;;
        --wifi-current) wifi_current_req=true; shift ;;
        --wifi-connect) wifi_connect_ssid="${2:-}"; shift 2; [[ -n "${1:-}" && "${1:-}" != -* ]] && wifi_connect_password="$1" && shift ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "  -a, --all                Show hidden background processes"
            echo "  --kill <PID>             Kill specified PID"
            echo "  --wifi-list              List Wi-Fi networks"
            echo "  --wifi-current           Show current Wi-Fi"
            echo "  --wifi-connect <SSID> [pw] Connect to Wi-Fi"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# =====================================================================
# Main Execution
# =====================================================================
if [[ "$wifi_list_req" == true ]]; then wifi_list; exit $?; fi
if [[ "$wifi_current_req" == true ]]; then wifi_current; exit $?; fi
if [[ -n "$wifi_connect_ssid" ]]; then wifi_connect "$wifi_connect_ssid" "$wifi_connect_password"; exit $?; fi
if [[ -n "$kill_pid" ]]; then kill_process "$kill_pid"; exit $?; fi

while true; do
    clear
    draw_banner
    draw_snapshot
    draw_main_menu

    read -rp "  Selection: " choice
    echo ""

    case "$choice" in
        1|01) render_panel "CPU Usage" "$(cpu_usage)" "⚙️" ;;
        2|02) render_panel "Memory Usage" "$(mem_usage)" "🧠" ;;
        3|03) render_panel "Disk Usage" "$(disk_usage)" "💾" ;;
        4|04) render_panel "Top 5 CPU Processes" "$(top_cpu)" "⚡" ;;
        5|05) render_panel "Top 5 Memory Processes" "$(top_mem)" "📊" ;;
        6|06) render_panel "System Information" "$(extra_stats)" "ℹ️" ;;
        7|07) render_panel "Battery Status" "$(battery_status)" "🔋" ;;
        8|08) render_panel "Hidden Processes" "$(show_hidden_background)" "👻" ;;
        9|09) render_panel "Wi-Fi List" "$(wifi_list)" "📶" ;;
        10) render_panel "Wi-Fi Current" "$(wifi_current)" "🌐" ;;
        11)
            render_panel "CPU Usage" "$(cpu_usage)" "⚙️"
            render_panel "Memory Usage" "$(mem_usage)" "🧠"
            render_panel "Disk Usage" "$(disk_usage)" "💾"
            render_panel "Top CPU" "$(top_cpu)" "⚡"
            render_panel "Top Mem" "$(top_mem)" "📊"
            render_panel "System Info" "$(extra_stats)" "ℹ️"
            render_panel "Battery" "$(battery_status)" "🔋"
            [[ "$show_hidden" == true ]] && render_panel "Hidden" "$(show_hidden_background)" "👻"
            ;;
        0|00) echo "Exiting..."; exit 0 ;;
        r) continue ;;
        *) ;;
    esac
    read -rn 1 -p "  Press any key to return to menu..."
done
