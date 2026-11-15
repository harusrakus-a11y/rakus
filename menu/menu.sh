#!/bin/bash
# Menu utama - Developer by kancil ecem
clear

# =============================================
#           [ Warna asas ]
# =============================================
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export NC='\033[0m'
export ORANGE='\033[0;91m'
WH='\033[1;37m'

# =============================================
#          [ Semakan lesen ]
# =============================================
check_ip_and_get_info() {
    local ip=$1
    while IFS= read -r line; do
        line=$(echo "$line" | tr -d '\r' | sed 's/[^[:print:]]//g' | xargs)
        read -ra fields <<< "$line"
        # Kolum 4 = IP
        if [[ "${fields[3]}" == "$ip" ]]; then
            client_name="${fields[1]}"
            exp_date="${fields[2]}"
            exp_date=$(echo "$exp_date" | sed 's/[^0-9-]//g' | xargs)
            return 0
        fi
    done <<< "$permission_file"
    return 1
}

permission_file=$(curl -s --connect-timeout 10 https://raw.githubusercontent.com/harusrakus-a11y/ijin/refs/heads/main/akses)
if [ -z "$permission_file" ]; then
    echo -e "${RED}Gagal ambil data lesen. Semak internet VPS.${NC}"
    exit 1
fi

IP_VPS=$(curl -s --connect-timeout 5 ipv4.icanhazip.com)

echo -e "${GREEN}Memeriksa lesen...${NC}"
if check_ip_and_get_info "$IP_VPS"; then
    if ! [[ "$exp_date" =~ ^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$ ]]; then
        echo -e "${RED}Format tarikh lesen tak betul: '$exp_date' (mesti YYYY-MM-DD)${NC}"
        exit 1
    fi
    if ! date -d "$exp_date" "+%s" &>/dev/null; then
        echo -e "${RED}Tarikh lesen tak sah: $exp_date${NC}"
        exit 1
    fi
else
    echo -e "${RED}IP VPS ini belum didaftar.${NC}"
    echo -e "Hubungi admin: ${CYAN}kancil ecem${NC}"
    exit 1
fi

current_epoch=$(date +%s)
exp_epoch=$(date -d "$exp_date" +%s)
if (( exp_epoch < current_epoch )); then
    echo -e "${RED}Tempoh lesen dah tamat.${NC}"
    exit 1
fi
days_remaining=$(( (exp_epoch - current_epoch) / 86400 ))

if ! command -v jq &>/dev/null; then
    echo -e "${YELLOW}Memasang jq...${NC}"
    apt-get install jq -y >/dev/null 2>&1
fi

# =============================================
#          [ Warna tema ]
# =============================================
# Tema baru (12 warna): tulis fail tema sekali sahaja selepas kemas kini
if [ ! -e /etc/phreakers/theme/.kn2 ]; then
    mkdir -p /etc/phreakers/theme 2>/dev/null
    for t in red:203:160 orange:215:166 yellow:227:136 lime:154:64 green:83:28 aqua:85:36 cyan:45:31 blue:75:25 purple:141:55 magenta:207:127 pink:218:168 silver:252:240; do
        IFS=: read -r tn tf tb <<< "$t"
        printf 'BG : \033[1;48;5;%sm\nTEXT : \033[38;5;%sm\n' "$tb" "$tf" > "/etc/phreakers/theme/${tn}" 2>/dev/null
    done
    [ -s /etc/phreakers/theme/color.conf ] || echo cyan > /etc/phreakers/theme/color.conf 2>/dev/null
    : > /etc/phreakers/theme/.kn2 2>/dev/null
fi
colornow=$(cat /etc/phreakers/theme/color.conf 2>/dev/null)
COLOR1="$(grep -w "TEXT" /etc/phreakers/theme/$colornow 2>/dev/null | cut -d: -f2 | sed 's/ //g')"
COLBG1="$(grep -w "BG" /etc/phreakers/theme/$colornow 2>/dev/null | cut -d: -f2 | sed 's/ //g')"
[ -z "$COLOR1" ] && COLOR1='\033[0;36m'
[ -z "$COLBG1" ] && COLBG1='\033[1;46m'
NC='\033[0m'

# =============================================
#          [ Fungsi paparan ]
# =============================================
KN_BRAND="Developer by kancil ecem"
KN_BAR="──────────────────────────────────────"
kn_top()   { echo -e "${COLOR1}╭${KN_BAR}╮${NC}"; }
kn_mid()   { echo -e "${COLOR1}├${KN_BAR}┤${NC}"; }
kn_bot()   { echo -e "${COLOR1}╰${KN_BAR}╯${NC}"; }
kn_title() {
    local t="$1" n l r
    n=${#t}
    if [ "$n" -gt 38 ]; then t="${t:0:38}"; n=38; fi
    l=$(( (38 - n) / 2 )); r=$(( 38 - n - l ))
    printf '%b│%b%b%*s%b%s%*s%b%b│%b\n' "$COLOR1" "$NC" "$COLBG1" "$l" "" "$WH" "$t" "$r" "" "$NC" "$COLOR1" "$NC"
}
# Tajuk dengan kesan warna pelangi (boleh dimatikan: menu > SETTING > tema > 13)
kn_title_r() {
    local t="$1" n l r i k out=""
    local pal=(210 216 222 228 192 157 158 159 153 147 183 218)
    n=${#t}
    if [ -e /etc/phreakers/theme/.norainbow ] || [ "$n" -gt 38 ] || [ "$n" -lt 2 ]; then kn_title "$t"; return; fi
    l=$(( (38 - n) / 2 )); r=$(( 38 - n - l ))
    for (( i=0; i<n; i++ )); do
        k=$(( i * 11 / (n - 1) ))
        out+="\033[1;38;5;${pal[$k]}m${t:$i:1}"
    done
    printf '%b│%b%b%*s%b%*s%b%b│%b\n' "$COLOR1" "$NC" "$COLBG1" "$l" "" "$out" "$r" "" "$NC" "$COLOR1" "$NC"
}
kn_row()   { printf '%b│%b %b%-10s%b: %s%b\n' "$COLOR1" "$NC" "$COLOR1" "$1" "$WH" "$2" "$NC"; }
kn_cont()  { printf '%b│%b %-10s  %s%b\n' "$COLOR1" "$NC" "" "$1" "$NC"; }
kn_item2() { printf '%b│%b %b[%b%s%b]%b %-12s %b[%b%s%b]%b %s\n' "$COLOR1" "$NC" "$WH" "$COLOR1" "$1" "$WH" "$NC" "$2" "$WH" "$COLOR1" "$3" "$WH" "$NC" "$4"; }
kn_item1() { printf '%b│%b %b[%b%s%b]%b %s\n' "$COLOR1" "$NC" "$WH" "$COLOR1" "$1" "$WH" "$NC" "$2"; }
kn_onoff() { if [ "$1" = "running" ] || [ "$1" = "active" ]; then printf '\033[1;32mON\033[0m'; else printf '\033[1;31mOFF\033[0m'; fi; }

svc_state() { systemctl is-active "$1" 2>/dev/null | head -n1; }

# =============================================
#          [ Kumpul maklumat (laju, tempatan) ]
# =============================================
MODEL2=$(grep -w PRETTY_NAME /etc/os-release 2>/dev/null | head -n1 | cut -d= -f2 | tr -d '"')
CORE=$(nproc 2>/dev/null || echo 1)
RAM_USED=$(free -h 2>/dev/null | awk '/Mem:/ {print $3}')
RAM_TOT=$(free -h 2>/dev/null | awk '/Mem:/ {print $2}')
CPU_IDLE=$(top -bn1 2>/dev/null | awk '/Cpu/ {for(i=2;i<=NF;i++) if ($i ~ /^id,?$/) {v=$(i-1); sub(/.*,/,"",v); print v; exit}}')
if [[ "$CPU_IDLE" =~ ^[0-9.]+$ ]]; then
    CPU_USE=$(awk -v i="$CPU_IDLE" 'BEGIN{printf "%.0f%%", 100-i}')
else
    CPU_USE="-"
fi
SERONLINE=$(uptime -p 2>/dev/null | sed 's/^up //')
DOMAIN=$(cat /etc/xray/domain 2>/dev/null)
ISP=$(cat /etc/xray/isp 2>/dev/null)
CITY=$(cat /etc/xray/city 2>/dev/null)
[ -z "$DOMAIN" ] && DOMAIN="-"
[ -z "$ISP" ] && ISP="-"
[ -z "$CITY" ] && CITY="-"
[ -z "$MODEL2" ] && MODEL2="-"

# trafik hari ini / bulan ini (vnstat --oneline, jika ada)
T_DAY="-"; T_MON="-"
if command -v vnstat >/dev/null 2>&1; then
    vn=$(vnstat --oneline 2>/dev/null | head -n1)
    if [ -n "$vn" ]; then
        IFS=';' read -ra VN <<< "$vn"
        [ -n "${VN[5]}" ] && T_DAY="${VN[5]}"
        [ -n "${VN[10]}" ] && T_MON="${VN[10]}"
    fi
fi

# jumlah akaun
CFG=/etc/xray/config.json
n_vmess=$(grep -c -E "^#vmg " "$CFG" 2>/dev/null); n_vmess=${n_vmess:-0}
n_vless=$(grep -c -E "^#vlg " "$CFG" 2>/dev/null); n_vless=${n_vless:-0}
n_trojan=$(grep -c -E "^#trg " "$CFG" 2>/dev/null); n_trojan=${n_trojan:-0}
n_ssh=$(grep -c -E "^### " /etc/xray/ssh 2>/dev/null); n_ssh=${n_ssh:-0}

# status servis
st_ws=$(kn_onoff "$(svc_state ws-stunnel)")
st_nginx=$(kn_onoff "$(svc_state nginx)")
if [ "$(svc_state nginx)" != "active" ]; then systemctl start nginx >/dev/null 2>&1; fi
st_xray=$(kn_onoff "$(svc_state xray)")
st_db=$(kn_onoff "$(svc_state dropbear)")
if [ -x /usr/local/bin/tbot.py ]; then st_bot=$(kn_onoff "$(svc_state tbot)"); else st_bot="\033[0;90m-\033[0m"; fi

# =============================================
#          [ Menu bot Telegram ]
# =============================================
bot_menu() {
    local RAW="https://raw.githubusercontent.com/harusrakus-a11y/rakus/refs/heads/main/menu/tbot-install.sh"
    local c
    clear
    kn_top
    kn_title "BOT TELEGRAM"
    kn_mid
    if [ -x /usr/local/bin/tbot.py ]; then
        kn_row "Status" "$(svc_state tbot)"
    else
        kn_row "Status" "belum dipasang"
    fi
    kn_mid
    kn_item1 "1" "Pasang / kemas kini bot"
    kn_item1 "2" "Tukar token / ID admin"
    kn_item1 "3" "Mula semula bot"
    kn_item1 "4" "Lihat log bot"
    kn_item1 "5" "Buang bot"
    kn_item1 "0" "Kembali"
    kn_mid
    kn_title_r "$KN_BRAND"
    kn_bot
    echo ""
    echo -ne " ${WH}Pilih ${COLOR1}: ${WH}"; read -r c
    case $c in
    1 | 2)
        if curl -fsSL --max-time 30 "$RAW" -o /root/tbot-install.sh; then
            if [ "$c" = 2 ]; then bash /root/tbot-install.sh ubah; else bash /root/tbot-install.sh; fi
        else
            echo "Gagal muat turun pemasang bot."
        fi ;;
    3) systemctl restart tbot 2>/dev/null && echo "Bot dimulakan semula." || echo "Bot belum dipasang." ;;
    4) journalctl -u tbot -n 25 --no-pager 2>/dev/null || echo "Tiada log." ;;
    5) if [ -s /root/tbot-install.sh ]; then bash /root/tbot-install.sh buang; else echo "Pemasang tiada. Pilih 1 dulu."; fi ;;
    *) return ;;
    esac
    echo ""
    read -n 1 -s -r -p " Tekan sebarang kekunci untuk kembali"
}

kn_reboot() {
    local a
    echo -ne " ${WH}Reboot VPS sekarang? (y/n) ${COLOR1}: ${WH}"; read -r a
    echo -ne "${NC}"
    if [ "$a" = "y" ] || [ "$a" = "Y" ]; then
        reboot
    else
        menu
    fi
}

# =============================================
#          [ Paparan menu ]
# =============================================
clear
kn_top
kn_title_r "KANCIL ECEM PREMIUM"
kn_title "$KN_BRAND"
kn_mid
kn_row "OS" "$MODEL2"
kn_row "RAM" "$RAM_USED / $RAM_TOT"
kn_row "CPU" "$CPU_USE ($CORE core)"
kn_row "IP VPS" "$IP_VPS"
kn_row "Domain" "$DOMAIN"
kn_row "Lokasi" "$CITY"
kn_row "ISP" "$ISP"
kn_row "Uptime" "$SERONLINE"
kn_mid
printf '%b│%b %bXRAY%b %b   %bNGINX%b %b   %bSSH-WS%b %b\n' "$COLOR1" "$NC" "$WH" "$NC" "$st_xray" "$WH" "$NC" "$st_nginx" "$WH" "$NC" "$st_ws"
printf '%b│%b %bDROPBEAR%b %b   %bBOT TG%b %b\n' "$COLOR1" "$NC" "$WH" "$NC" "$st_db" "$WH" "$NC" "$st_bot"
kn_mid
kn_row "Akaun" "SSH $n_ssh | VMESS $n_vmess"
kn_cont "VLESS $n_vless | TROJAN $n_trojan"
kn_mid
kn_item2 "01" "SSH VPN"  "06" "RUNNING"
kn_item2 "02" "VMESS"    "07" "RESTART"
kn_item2 "03" "VLESS"    "08" "REBOOT"
kn_item2 "04" "TROJAN"   "09" "UPDATE"
kn_item2 "05" "BACKUP"   "10" "SETTING"
kn_item2 "11" "BOT TG"   "12" "ONLINE"
kn_item1 "00" "KELUAR"
kn_mid
kn_row "Trafik" "hari ini $T_DAY"
kn_cont "bulan ini $T_MON"
kn_row "Client" "$client_name"
kn_row "Lesen" "$days_remaining hari lagi ($exp_date)"
kn_row "Versi" "$(cat /opt/.ver 2>/dev/null || echo -)"
kn_mid
kn_title_r "$KN_BRAND"
kn_bot
echo ""
echo -ne " ${WH}Pilih menu ${COLOR1}: ${WH}"; read -r opt
echo -ne "${NC}"
case $opt in
01 | 1) clear ; sshws ;;
02 | 2) clear ; m-vmess ;;
03 | 3) clear ; m-vless ;;
04 | 4) clear ; m-trojan ;;
05 | 5) clear ; menu-backup ;;
06 | 6) clear ; cekservice ;;
07 | 7) clear ; running ;;
08 | 8) clear ; kn_reboot ;;
09 | 9) clear ; m-update ;;
10 | 10) clear ; system ;;
11 | 11) bot_menu ; menu ;;
12 | 12) clear ; online ;;
15 | 15) clear ; admin ;;
00 | 0 | x | X) clear ; exit 0 ;;
*) clear ; menu ;;
esac
