#!/bin/bash
# m-theme - Pilih tema warna menu
# Developer by kancil ecem

THEME_DIR="/etc/phreakers/theme"
COLOR_CONF="${THEME_DIR}/color.conf"
NC='\033[0m'
WH='\033[1;37m'
KN_BRAND="Developer by kancil ecem"
KN_BAR="──────────────────────────────────────"

# nama:warna teks:warna latar  (kod 256 warna)
KN_THEMES="red:203:160 orange:215:166 yellow:227:136 lime:154:64 green:83:28 aqua:85:36 cyan:45:31 blue:75:25 purple:141:55 magenta:207:127 pink:218:168 silver:252:240"

# Tulis semula semua fail tema (selamat dijalankan berulang kali)
kn_theme_init() {
    local d="$THEME_DIR" t n f b
    mkdir -p "$d" 2>/dev/null
    for t in $KN_THEMES; do
        IFS=: read -r n f b <<< "$t"
        printf 'BG : \033[1;48;5;%sm\nTEXT : \033[38;5;%sm\n' "$b" "$f" > "$d/$n"
    done
    [ -s "$COLOR_CONF" ] || echo cyan > "$COLOR_CONF"
    : > "$d/.kn2"
}

load_colors() {
    colornow=$(cat "$COLOR_CONF" 2>/dev/null)
    [ -f "${THEME_DIR}/${colornow}" ] || colornow=cyan
    COLOR1=$(grep -w "TEXT" "${THEME_DIR}/${colornow}" 2>/dev/null | cut -d: -f2 | sed 's/ //g')
    COLBG1=$(grep -w "BG" "${THEME_DIR}/${colornow}" 2>/dev/null | cut -d: -f2 | sed 's/ //g')
    [ -z "$COLOR1" ] && COLOR1='\033[0;36m'
    [ -z "$COLBG1" ] && COLBG1='\033[1;46m'
}

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
kn_foot()  { kn_mid; kn_title_r "$KN_BRAND"; kn_bot; }

# warna teks sesuatu tema (untuk contoh warna)
tema_warna() { grep -w "TEXT" "${THEME_DIR}/$1" 2>/dev/null | cut -d: -f2 | sed 's/ //g'; }

# satu sel: [NN] ██ Nama
sel() {
    local no="$1" name="$2" c mark=" "
    c=$(tema_warna "$name"); [ -z "$c" ] && c="$WH"
    [ "$name" = "$colornow" ] && mark="●"
    printf '%b[%b%02d%b]%b %b██%b %b%-8s%b%s%b' "$WH" "$COLOR1" "$no" "$WH" "$NC" "$c" "$NC" "$WH" "${name^}" "$COLOR1" "$mark" "$NC"
}

tunjuk_panel() {
    local arr i a b
    arr=()
    for i in $KN_THEMES; do arr+=("${i%%:*}"); done
    clear
    load_colors
    echo ""
    kn_top
    kn_title "PILIH TEMA WARNA"
    kn_mid
    for (( i=0; i<6; i++ )); do
        a=$(sel $((i+1)) "${arr[$i]}")
        b=$(sel $((i+7)) "${arr[$((i+6))]}")
        printf '%b│%b %s  %s\n' "$COLOR1" "$NC" "$a" "$b"
    done
    kn_mid
    if [ -e "${THEME_DIR}/.norainbow" ]; then rb='\033[1;31mOFF\033[0m'; else rb='\033[1;32mON\033[0m'; fi
    printf '%b│%b %b[%b13%b]%b Kesan pelangi tajuk : %b\n' "$COLOR1" "$NC" "$WH" "$COLOR1" "$WH" "$NC" "$rb"
    printf '%b│%b %bTema semasa%b : %b%s%b\n' "$COLOR1" "$NC" "$COLOR1" "$WH" "$COLOR1" "${colornow^}" "$NC"
    printf '%b│%b %b[%b00%b]%b KEMBALI\n' "$COLOR1" "$NC" "$WH" "$COLOR1" "$WH" "$NC"
    kn_foot
    echo ""
}

tukar_tema() {
    local name="$1"
    echo "$name" > "$COLOR_CONF" 2>/dev/null
    load_colors
    clear
    echo ""
    kn_top
    kn_title "TEMA DITUKAR"
    kn_mid
    printf '%b│%b %bTema baru%b  : %b%s%b\n' "$COLOR1" "$NC" "$COLOR1" "$WH" "$COLOR1" "${colornow^}" "$NC"
    printf '%b│%b %bSemua menu guna warna ini%b\n' "$COLOR1" "$NC" "$WH" "$NC"
    kn_foot
    echo ""
}

# ================= utama =================
KN_ARR=($KN_THEMES)
[ -e "${THEME_DIR}/.kn2" ] || kn_theme_init 2>/dev/null

while true; do
    tunjuk_panel
    echo -ne " ${WH}Pilih nombor ${COLOR1}: ${WH}"
    read -r pilih || break
    echo -ne "${NC}"
    case "$pilih" in
        00|0|x|X) break ;;
        ""|*[!0-9]*) continue ;;
    esac
    n=$((10#$pilih))
    if [ "$n" -eq 13 ]; then
        if [ -e "${THEME_DIR}/.norainbow" ]; then rm -f "${THEME_DIR}/.norainbow"; else : > "${THEME_DIR}/.norainbow"; fi 2>/dev/null
        continue
    fi
    if [ "$n" -ge 1 ] && [ "$n" -le 12 ]; then
        t=${KN_ARR[$((n-1))]}
        tukar_tema "${t%%:*}"
        echo ""
        read -n 1 -s -r -p " Tekan mana-mana kekunci untuk ke menu"
        break
    fi
done
clear
menu
