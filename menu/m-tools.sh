#!/bin/bash
# m-tools - Tools tambahan (ringkasan, cari, nota, peringatan, kesihatan, pantau servis, backup, pindah akaun)
# Developer by kancil ecem
#   m-tools           -> menu
#   m-tools remind    -> hantar peringatan ke Telegram (untuk cron)
#   m-tools jaga      -> semak servis, hidupkan semula yang mati (untuk cron)
#   m-tools backup    -> hantar backup akaun ke Telegram (untuk cron)

THEME_DIR="/etc/phreakers/theme"
KDIR="/etc/kancil"
NOTA_DIR="$KDIR/nota"
REMIND_CONF="$KDIR/remind.conf"
CRON_FILE="/etc/cron.d/kancil-remind"
XRAY_CFG="/etc/xray/config.json"
SSH_LIST="/etc/xray/ssh"

colornow=$(cat "$THEME_DIR/color.conf" 2>/dev/null)
COLOR1="$(grep -w "TEXT" "$THEME_DIR/$colornow" 2>/dev/null | cut -d: -f2 | sed 's/ //g')"
COLBG1="$(grep -w "BG" "$THEME_DIR/$colornow" 2>/dev/null | cut -d: -f2 | sed 's/ //g')"
[ -z "$COLOR1" ] && COLOR1='\033[0;36m'
[ -z "$COLBG1" ] && COLBG1='\033[1;46m'
NC='\033[0m'
WH='\033[1;37m'
RD='\033[1;31m'
YL='\033[1;33m'
GR='\033[1;32m'

TIMES=10
CHATID=$(cat /etc/per/id 2>/dev/null)
KEY=$(cat /etc/per/token 2>/dev/null)
URL="https://api.telegram.org/bot$KEY/sendMessage"
domain=$(cat /etc/xray/domain 2>/dev/null)
mkdir -p "$NOTA_DIR" 2>/dev/null

# ===== Developer by kancil ecem : gaya paparan (lebar 40 lajur, sesuai phone) =====
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
kn_row()   { printf '%b│%b %b%-10s%b: %s%b\n' "$COLOR1" "$NC" "$COLOR1" "$1" "$WH" "$2" "$NC"; }
kn_item1() { printf '%b│%b %b[%b%s%b]%b %s\n' "$COLOR1" "$NC" "$WH" "$COLOR1" "$1" "$WH" "$NC" "$2"; }
# pautan / teks panjang: baris sendiri tanpa sempadan supaya senang salin
kn_link()  { printf '%b│ %s%b\n%b%s%b\n' "$COLOR1" "$1" "$NC" "$WH" "$2" "$NC"; }
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
# Senarai pengguna bernombor + tapis. Nombor asal dikekalkan supaya pilihan tetap betul.
# Guna: kn_userlist "^#vl " /etc/xray/config.json
kn_userlist() {
    local pat="$1" file="$2" total f="" t t7 out
    total=$(grep -c -E "$pat" "$file" 2>/dev/null)
    if [ "${total:-0}" -ge 8 ]; then
        echo ""
        echo " Tapis: aktif | hampir | tamat | nama"
        read -rp " Cari (Enter = semua): " f
        echo ""
    fi
    t=$(date +%Y-%m-%d); t7=$(date -d '+7 days' +%Y-%m-%d)
    case "${f,,}" in
        "")    out=$(grep -E "$pat" "$file" | cut -d ' ' -f 2-3 | nl -s ') ') ;;
        aktif) out=$(grep -E "$pat" "$file" | cut -d ' ' -f 2-3 | nl -s ') ' | awk -v t="$t" '$3 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ && $3 >= t') ;;
        hampir) out=$(grep -E "$pat" "$file" | cut -d ' ' -f 2-3 | nl -s ') ' | awk -v t="$t" -v t7="$t7" '$3 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ && $3 >= t && $3 <= t7') ;;
        tamat) out=$(grep -E "$pat" "$file" | cut -d ' ' -f 2-3 | nl -s ') ' | awk -v t="$t" '$3 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ && $3 < t') ;;
        *)     out=$(grep -E "$pat" "$file" | cut -d ' ' -f 2-3 | nl -s ') ' | grep -iF -- "$f") ;;
    esac
    echo "     No  User   Expired"
    if [ -n "$out" ]; then echo "$out"; else echo " Tiada padanan (taip 0 untuk kembali)"; fi
}
kn_esc()   { local s="$1"; s=${s//&/&amp;}; s=${s//</&lt;}; s=${s//>/&gt;}; printf '%s' "$s"; }
# Notifikasi Telegram ringkas: maklumat VPS + perkara penting sahaja.
# Tiada password, UUID atau link akaun.   Guna: kn_text JENIS USER TAMAT HAD_IP KUOTA_GB
kn_text() {
    printf '%s\n' "✦ <b>KANCIL ECEM</b> ✦" \
        "Akaun $(kn_esc "$1") baru" \
        "━━━━━━━━━━━━━━━━" \
        "User     : <code>$(kn_esc "$2")</code>" \
        "Tamat    : $(kn_esc "$3")" \
        "Had IP   : $(kn_esc "$4")"
    if [[ -n "$5" && "$5" != "9999" ]]; then printf 'Kuota    : %s GB\n' "$(kn_esc "$5")"; fi
    printf '%s\n' "━━━━━━━━━━━━━━━━" \
        "Domain   : <code>$(kn_esc "$domain")</code>" \
        "IP VPS   : <code>$(kn_esc "${IP_VPS:-?}")</code>" \
        "Lokasi   : $(kn_esc "$CITY"), $(kn_esc "$ISP")" \
        "━━━━━━━━━━━━━━━━" \
        "$KN_BRAND"
}
kn_send()  { curl -s --max-time "${TIMES:-10}" --data-urlencode "chat_id=$CHATID" --data-urlencode "text=$1" -d "disable_web_page_preview=1" -d "parse_mode=html" "$URL" >/dev/null 2>&1; }
# ===== tamat gaya paparan =====

TODAY=$(date +%Y-%m-%d)
TODAY_E=$(date -d "$TODAY" +%s)

# ---------- data ----------
# JENIS|user|tarikh  (disusun ikut tarikh)
kn_rows() {
    {
        if [ -f "$XRAY_CFG" ]; then
            grep -E '^#vm ' "$XRAY_CFG" | awk '{print "VMESS|"$2"|"$3}'
            grep -E '^#vl ' "$XRAY_CFG" | awk '{print "VLESS|"$2"|"$3}'
            grep -E '^#tr ' "$XRAY_CFG" | awk '{print "TROJAN|"$2"|"$3}'
        fi
        [ -f "$SSH_LIST" ] && grep -E '^### ' "$SSH_LIST" | awk '{print "SSH|"$2"|"$3}'
    } 2>/dev/null | sort -t'|' -k3,3 -k2,2
}
kn_days() {
    local e
    e=$(date -d "$1" +%s 2>/dev/null) || { echo 99999; return; }
    echo $(( (e - TODAY_E) / 86400 ))
}
kn_nota() {
    local f="$NOTA_DIR/$1"
    [ -f "$f" ] && head -n1 "$f" | tr -d '\000-\037' | cut -c1-60
}
kn_dcol() {   # warna ikut baki hari
    if [ "$1" -le 1 ]; then printf '%b' "$RD"; elif [ "$1" -le 3 ]; then printf '%b' "$YL"; else printf '%b' "$WH"; fi
}
kn_dtext() {
    if [ "$1" -lt 0 ]; then printf 'tamat %s hari lalu' "$(( -$1 ))"; elif [ "$1" -eq 0 ]; then printf 'hari ini'; else printf '%s hari lagi' "$1"; fi
}
kn_user_exists() { kn_rows | awk -F'|' -v u="$1" '$2==u {f=1} END{exit !f}'; }
kn_pause() { echo ""; read -n 1 -s -r -p " Tekan mana-mana kekunci"; }

# satu baris akaun (+ nota di bawah)
kn_acc_line() {   # jenis user tarikh hari
    local n
    printf '%b│%b %-6s %-12.12s %s%s%b\n' "$COLOR1" "$NC" "$1" "$2" "$(kn_dcol "$4")" "$(kn_dtext "$4")" "$NC"
    n=$(kn_nota "$2")
    [ -n "$n" ] && printf '%b│%b   %b↳ %s%b\n' "$COLOR1" "$NC" "$COLOR1" "$n" "$NC"
}

# ---------- 1) RINGKASAN ----------
t_ringkasan() {
    local t u x d ns=0 nm=0 nl=0 nt=0 naktif=0 nhampir=0 ntamat=0 hl="" tl="" HARI=7
    while IFS='|' read -r t u x; do
        [ -z "$u" ] && continue
        case "$t" in SSH) ns=$((ns+1));; VMESS) nm=$((nm+1));; VLESS) nl=$((nl+1));; TROJAN) nt=$((nt+1));; esac
        d=$(kn_days "$x")
        if [ "$d" -lt 0 ]; then
            ntamat=$((ntamat+1)); tl+="$t|$u|$x|$d"$'\n'
        elif [ "$d" -le "$HARI" ]; then
            nhampir=$((nhampir+1)); hl+="$t|$u|$x|$d"$'\n'
        else
            naktif=$((naktif+1))
        fi
    done < <(kn_rows)
    clear; echo ""
    kn_top; kn_title "RINGKASAN AKAUN"; kn_mid
    kn_row "SSH" "$ns"
    kn_row "VMESS" "$nm"
    kn_row "VLESS" "$nl"
    kn_row "TROJAN" "$nt"
    kn_mid
    kn_row "Jumlah" "$((ns+nm+nl+nt))"
    kn_row "Aktif" "$naktif"
    kn_row "Hampir" "$nhampir (dalam $HARI hari)"
    kn_row "Tamat" "$ntamat"
    if [ -n "$hl" ]; then
        kn_mid; printf '%b│%b %bHAMPIR TAMAT%b\n' "$COLOR1" "$NC" "$YL" "$NC"
        while IFS='|' read -r t u x d; do [ -n "$u" ] && kn_acc_line "$t" "$u" "$x" "$d"; done <<< "$hl"
    fi
    if [ -n "$tl" ]; then
        kn_mid; printf '%b│%b %bSUDAH TAMAT%b\n' "$COLOR1" "$NC" "$RD" "$NC"
        while IFS='|' read -r t u x d; do [ -n "$u" ] && kn_acc_line "$t" "$u" "$x" "$d"; done <<< "$tl"
    fi
    kn_foot
    kn_pause
}

# ---------- 2) CARI ----------
kn_iplim() {   # jenis user
    local v=""
    case "$1" in
        VMESS) v=$(cat "/etc/vmess/$2IP" 2>/dev/null) ;;
        VLESS) v=$(cat "/etc/vless/$2IP" 2>/dev/null) ;;
        TROJAN) v=$(cat "/etc/trojan/$2IP" 2>/dev/null)
                [ -z "$v" ] && v=$(grep -o 'login_ip=[0-9]*' "/etc/trojan/akun/$2" 2>/dev/null | head -n1 | cut -d= -f2) ;;
        SSH) v=$(cat "/etc/xray/sshx/$2IP" 2>/dev/null) ;;
    esac
    v=$(echo "$v" | tr -cd '0-9')
    if [ -z "$v" ]; then echo "-"; elif [ "$v" -ge 9999 ]; then echo "Unlimited"; else echo "$v IP"; fi
}
kn_quota() {   # jenis user
    local f b=""
    case "$1" in VMESS) f="/etc/vmess/$2";; VLESS) f="/etc/vless/$2";; TROJAN) f="/etc/trojan/$2";; *) f="";; esac
    [ -n "$f" ] && [ -f "$f" ] && b=$(head -n1 "$f" | tr -cd '0-9')
    if [ -z "$b" ] || [ "$b" -le 0 ]; then echo "-"; else
        b=$(( b / 1073741824 )); if [ "$b" -ge 9999 ]; then echo "Unlimited"; else echo "${b} GB"; fi
    fi
}
t_cari() {
    local q t u x d n m=0 res
    clear; echo ""
    kn_top; kn_title "CARI AKAUN"; kn_bot
    read -rp " Nama (sebahagian pun boleh): " q
    q=$(echo "$q" | tr -cd 'A-Za-z0-9_.-')
    [ -z "$q" ] && return
    res=$(kn_rows | awk -F'|' -v q="$q" 'index(tolower($2),tolower(q))' | head -n 10)
    clear; echo ""
    kn_top; kn_title "HASIL CARI: $q"
    if [ -z "$res" ]; then
        kn_mid; printf '%b│%b Tiada padanan\n' "$COLOR1" "$NC"
    else
        while IFS='|' read -r t u x; do
            [ -z "$u" ] && continue
            d=$(kn_days "$x"); m=$((m+1))
            kn_mid
            kn_row "Jenis" "$t"
            kn_row "User" "$u"
            kn_row "Tamat" "$x ($(kn_dtext "$d"))"
            kn_row "Had IP" "$(kn_iplim "$t" "$u")"
            [ "$t" != "SSH" ] && kn_row "Kuota" "$(kn_quota "$t" "$u")"
            n=$(kn_nota "$u"); [ -n "$n" ] && kn_row "Nota" "$n"
        done <<< "$res"
    fi
    kn_foot
    kn_pause
}

# ---------- 3) NOTA ----------
t_nota() {
    local p u n f c
    while true; do
        clear; echo ""
        kn_top; kn_title "NOTA PELANGGAN"; kn_mid
        kn_item1 "01" "TAMBAH / UBAH NOTA"
        kn_item1 "02" "SENARAI NOTA"
        kn_item1 "03" "PADAM NOTA"
        kn_item1 "00" "KEMBALI"
        kn_foot; echo ""
        read -rp " Pilih : " p
        case "$p" in
            1|01)
                read -rp " Nama akaun (tepat): " u
                u=$(echo "$u" | tr -cd 'A-Za-z0-9_.-')
                if [ -z "$u" ] || [[ "$u" == .* ]] || ! kn_user_exists "$u"; then
                    echo -e " ${RD}Akaun tidak ditemui.${NC}"; sleep 2; continue
                fi
                [ -n "$(kn_nota "$u")" ] && echo -e " Nota sekarang: $(kn_nota "$u")"
                read -rp " Nota (cth no. telefon / nama): " n
                n=$(printf '%s' "$n" | tr -d '\000-\037' | cut -c1-60)
                if [ -z "$n" ]; then echo -e " ${YL}Nota kosong, tiada perubahan.${NC}"; sleep 2; continue; fi
                printf '%s\n' "$n" > "$NOTA_DIR/$u" && echo -e " ${GR}Nota disimpan.${NC}"; sleep 2 ;;
            2|02)
                clear; echo ""
                kn_top; kn_title "SENARAI NOTA"; kn_mid
                c=0
                for f in "$NOTA_DIR"/*; do
                    [ -f "$f" ] || continue
                    u=${f##*/}
                    printf '%b│%b %-12.12s %s\n' "$COLOR1" "$NC" "$u" "$(kn_nota "$u")"
                    c=$((c+1))
                done
                [ "$c" -eq 0 ] && printf '%b│%b Tiada nota\n' "$COLOR1" "$NC"
                kn_foot; kn_pause ;;
            3|03)
                read -rp " Nama akaun: " u
                u=$(echo "$u" | tr -cd 'A-Za-z0-9_.-')
                if [ -n "$u" ] && [[ "$u" != .* ]] && [ -f "$NOTA_DIR/$u" ]; then
                    rm -f "$NOTA_DIR/$u"; echo -e " ${GR}Nota dipadam.${NC}"
                else
                    echo -e " ${RD}Tiada nota untuk akaun itu.${NC}"
                fi
                sleep 2 ;;
            0|00|x|X) return ;;
        esac
    done
}

# ---------- 4) PERINGATAN HARIAN ----------
remind_days() {
    local d
    d=$(grep -o '^DAYS=[0-9]*' "$REMIND_CONF" 2>/dev/null | head -n1 | cut -d= -f2)
    [[ "$d" =~ ^[0-9]+$ ]] && [ "$d" -ge 1 ] && [ "$d" -le 30 ] && echo "$d" || echo 3
}
# bina mesej Telegram (kosong jika tiada apa nak diingatkan)
remind_text() {
    local HARI t u x d n body="" cnt=0
    HARI=$(remind_days)
    while IFS='|' read -r t u x; do
        [ -z "$u" ] && continue
        d=$(kn_days "$x")
        [ "$d" -gt "$HARI" ] && continue
        cnt=$((cnt+1))
        n=$(kn_nota "$u")
        if [ "$d" -lt 0 ]; then body+="$(kn_esc "$t") <code>$(kn_esc "$u")</code> - tamat $(( -d )) hari lalu"
        elif [ "$d" -eq 0 ]; then body+="$(kn_esc "$t") <code>$(kn_esc "$u")</code> - tamat hari ini"
        else body+="$(kn_esc "$t") <code>$(kn_esc "$u")</code> - ${d} hari lagi ($(kn_esc "$x"))"; fi
        [ -n "$n" ] && body+=" | $(kn_esc "$n")"
        body+=$'\n'
    done < <(kn_rows)
    [ "$cnt" -eq 0 ] && return
    printf '%s\n' "✦ <b>KANCIL ECEM</b> ✦" "Peringatan akaun hampir tamat ($cnt)" "━━━━━━━━━━━━━━━━" "$body━━━━━━━━━━━━━━━━" "$(kn_esc "${domain:-?}")" "$KN_BRAND"
}
remind_send() {   # 0 = dihantar, 1 = tiada apa-apa, 2 = tiada token
    local txt
    [ -z "$CHATID" ] || [ -z "$KEY" ] && return 2
    txt=$(remind_text)
    [ -z "$txt" ] && return 1
    kn_send "$txt"
    return 0
}
remind_on()  { printf '%s\n' '0 9 * * * root /usr/bin/m-tools remind >/dev/null 2>&1' > "$CRON_FILE" 2>/dev/null && chmod 644 "$CRON_FILE"; }
remind_off() { rm -f "$CRON_FILE"; }
t_peringatan() {
    local p st r d
    while true; do
        [ -f "$CRON_FILE" ] && st="${GR}ON${NC}" || st="${RD}OFF${NC}"
        clear; echo ""
        kn_top; kn_title "PERINGATAN HARIAN"; kn_mid
        printf '%b│%b Status  : %b\n' "$COLOR1" "$NC" "$st"
        printf '%b│%b Waktu   : setiap hari 09:00\n' "$COLOR1" "$NC"
        printf '%b│%b Hantar  : akaun tamat dalam %s hari\n' "$COLOR1" "$NC" "$(remind_days)"
        printf '%b│%b Ke      : bot Telegram kamu\n' "$COLOR1" "$NC"
        kn_mid
        kn_item1 "01" "HIDUP / MATI"
        kn_item1 "02" "HANTAR SEKARANG (UJIAN)"
        kn_item1 "03" "UBAH BILANGAN HARI"
        kn_item1 "00" "KEMBALI"
        kn_foot; echo ""
        read -rp " Pilih : " p
        case "$p" in
            1|01)
                if [ -f "$CRON_FILE" ]; then remind_off; echo -e " ${YL}Peringatan dimatikan.${NC}"
                elif remind_on; then echo -e " ${GR}Peringatan dihidupkan (09:00).${NC}"
                else echo -e " ${RD}Gagal hidupkan peringatan.${NC}"; fi
                sleep 2 ;;
            2|02)
                remind_send; r=$?
                case $r in
                    0) echo -e " ${GR}Dihantar ke Telegram.${NC}" ;;
                    1) echo -e " ${YL}Tiada akaun hampir tamat, tiada apa dihantar.${NC}" ;;
                    *) echo -e " ${RD}Token/ID Telegram belum ditetapkan (menu > 10 > 06).${NC}" ;;
                esac
                sleep 3 ;;
            3|03)
                read -rp " Hari (1-30): " d
                if [[ "$d" =~ ^[0-9]+$ ]] && [ "$d" -ge 1 ] && [ "$d" -le 30 ]; then
                    printf 'DAYS=%s\n' "$d" > "$REMIND_CONF"; echo -e " ${GR}Disimpan: $d hari.${NC}"
                else echo -e " ${RD}Nombor tak sah.${NC}"; fi
                sleep 2 ;;
            0|00|x|X) return ;;
        esac
    done
}

# ---------- 5) KESIHATAN VPS ----------
kn_svc() {   # label servis
    local s; s=$(systemctl is-active "$2" 2>/dev/null | head -n1)
    if [ "$s" = "active" ]; then printf '%b│%b %-10s: %bON%b\n' "$COLOR1" "$NC" "$1" "$GR" "$NC"
    else printf '%b│%b %-10s: %bOFF%b\n' "$COLOR1" "$NC" "$1" "$RD" "$NC"; fi
}
t_kesihatan() {
    local load ram disk dpct swap cert cend cdays ccol p
    load=$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)
    ram=$(free -m 2>/dev/null | awk '/Mem:/ {printf "%d/%d MB (%d%%)", $3, $2, ($2>0)?$3*100/$2:0}')
    swap=$(free -m 2>/dev/null | awk '/Swap:/ {if ($2>0) printf "%d/%d MB", $3, $2; else printf "tiada"}')
    disk=$(df -h / 2>/dev/null | awk 'NR==2 {print $3"/"$2" ("$5")"}')
    dpct=$(df / 2>/dev/null | awk 'NR==2 {gsub("%","",$5); print $5}')
    cert=/etc/xray/xray.crt
    cdays=""
    if [ -f "$cert" ] && command -v openssl >/dev/null 2>&1; then
        cend=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2)
        [ -n "$cend" ] && cdays=$(( ( $(date -d "$cend" +%s 2>/dev/null || echo 0) - $(date +%s) ) / 86400 ))
    fi
    clear; echo ""
    kn_top; kn_title "KESIHATAN VPS"; kn_mid
    kn_row "Uptime" "$(uptime -p 2>/dev/null | sed 's/^up //')"
    kn_row "Beban" "${load:--}"
    kn_row "RAM" "${ram:--}"
    kn_row "Swap" "${swap:--}"
    if [[ "$dpct" =~ ^[0-9]+$ ]] && [ "$dpct" -ge 90 ]; then kn_row "Disk" "${disk} PENUH!"; else kn_row "Disk" "${disk:--}"; fi
    kn_mid
    if [[ "$cdays" =~ ^-?[0-9]+$ ]]; then
        if [ "$cdays" -lt 0 ]; then ccol="$RD"; kn_row "Sijil SSL" "TAMAT ${cend}"
        elif [ "$cdays" -le 14 ]; then kn_row "Sijil SSL" "${cdays} hari lagi (perbaharui!)"
        else kn_row "Sijil SSL" "${cdays} hari lagi"; fi
    else
        kn_row "Sijil SSL" "tidak dapat disemak"
    fi
    kn_mid
    kn_svc "XRAY" xray
    kn_svc "NGINX" nginx
    kn_svc "SSH" ssh
    kn_svc "DROPBEAR" dropbear
    kn_svc "STUNNEL" stunnel4
    kn_svc "SSH-WS" ws-stunnel
    kn_mid
    for p in 80 443; do
        if ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]$p$"; then kn_row "Port $p" "terbuka"; else kn_row "Port $p" "TIDAK dengar"; fi
    done
    if [[ "$cdays" =~ ^-?[0-9]+$ ]] && [ "$cdays" -le 14 ] && command -v certv2ray >/dev/null 2>&1; then
        kn_mid; printf '%b│%b Perbaharui sijil: taip  certv2ray\n' "$COLOR1" "$NC"
    fi
    kn_foot
    kn_pause
}

# ---------- 6) PANTAU SERVIS (alert Telegram + hidup semula) ----------
JAGA_DIR="$KDIR/jaga"
JAGA_LOG="$KDIR/jaga.log"
JAGA_CRON="/etc/cron.d/kancil-jaga"
JAGA_SVCS="xray nginx ssh dropbear stunnel4 ws-stunnel"
jaga_log() {
    echo "$(date '+%F %T') $*" >> "$JAGA_LOG" 2>/dev/null
    if [ "$(wc -l < "$JAGA_LOG" 2>/dev/null || echo 0)" -gt 200 ]; then
        tail -n 100 "$JAGA_LOG" > "$JAGA_LOG.t" 2>/dev/null && mv "$JAGA_LOG.t" "$JAGA_LOG"
    fi
}
jaga_tg() {   # tajuk servis baris
    [ -z "$CHATID" ] || [ -z "$KEY" ] && return 1
    kn_send "$(printf '%s\n' "✦ <b>KANCIL ECEM</b> ✦" "<b>$(kn_esc "$1")</b>" "━━━━━━━━━━━━━━━━" "Servis : <code>$(kn_esc "$2")</code>" "$(kn_esc "$3")" "Server : $(kn_esc "${domain:-$(hostname)}")" "Masa   : $(date '+%F %T')")"
}
# dipanggil cron setiap 2 minit. Servis yang "enabled" tapi mati: hidupkan semula.
# Gagal hidup: cuba lagi selepas 10 minit sahaja. Mesej Telegram dihadkan supaya tak spam.
jaga_run() {
    local s now last t first
    mkdir -p "$JAGA_DIR" 2>/dev/null
    now=$(date +%s)
    for s in $JAGA_SVCS; do
        systemctl is-enabled --quiet "$s" 2>/dev/null || continue
        if systemctl is-active --quiet "$s" 2>/dev/null; then
            if [ -f "$JAGA_DIR/$s.gagal" ]; then
                rm -f "$JAGA_DIR/$s.gagal"
                jaga_log "$s pulih"
                jaga_tg "SERVIS PULIH" "$s" "Dah hidup semula."
            fi
            continue
        fi
        if [ -f "$JAGA_DIR/$s.gagal" ]; then
            last=$(cat "$JAGA_DIR/$s.gagal" 2>/dev/null); [[ "$last" =~ ^[0-9]+$ ]] || last=0
            [ $(( now - last )) -lt 600 ] && continue
        fi
        systemctl restart "$s" >/dev/null 2>&1
        sleep 4
        if systemctl is-active --quiet "$s" 2>/dev/null; then
            jaga_log "$s mati, dihidupkan semula"
            t=0; [ -f "$JAGA_DIR/$s.msg" ] && t=$(cat "$JAGA_DIR/$s.msg" 2>/dev/null)
            [[ "$t" =~ ^[0-9]+$ ]] || t=0
            if [ $(( now - t )) -ge 1800 ]; then
                echo "$now" > "$JAGA_DIR/$s.msg"
                jaga_tg "SERVIS MATI" "$s" "Dah dihidupkan semula (berjaya)."
            fi
        else
            first=0; [ -f "$JAGA_DIR/$s.gagal" ] || first=1
            echo "$now" > "$JAGA_DIR/$s.gagal"
            jaga_log "$s mati, GAGAL dihidupkan"
            [ "$first" = 1 ] && jaga_tg "SERVIS MATI" "$s" "GAGAL dihidupkan. Semak: systemctl status $s"
        fi
    done
}
jaga_on()  { printf '%s\n' '*/2 * * * * root /usr/bin/m-tools jaga >/dev/null 2>&1' > "$JAGA_CRON" 2>/dev/null && chmod 644 "$JAGA_CRON"; }
jaga_off() { rm -f "$JAGA_CRON"; }
t_jaga() {
    local p st s
    while true; do
        [ -f "$JAGA_CRON" ] && st="${GR}ON${NC}" || st="${RD}OFF${NC}"
        clear; echo ""
        kn_top; kn_title "PANTAU SERVIS"; kn_mid
        printf '%b│%b Status  : %b\n' "$COLOR1" "$NC" "$st"
        printf '%b│%b Semak   : setiap 2 minit\n' "$COLOR1" "$NC"
        printf '%b│%b Bila mati: hidupkan semula + Telegram\n' "$COLOR1" "$NC"
        kn_mid
        for s in $JAGA_SVCS; do
            systemctl is-enabled --quiet "$s" 2>/dev/null && kn_svc "$s" "$s"
        done
        kn_mid
        kn_item1 "01" "HIDUP / MATI"
        kn_item1 "02" "UJIAN TELEGRAM"
        kn_item1 "03" "LOG TERAKHIR"
        kn_item1 "00" "KEMBALI"
        kn_foot; echo ""
        read -rp " Pilih : " p
        case "$p" in
            1|01)
                if [ -f "$JAGA_CRON" ]; then jaga_off; echo -e " ${YL}Pantau dimatikan.${NC}"
                elif jaga_on; then echo -e " ${GR}Pantau dihidupkan.${NC}"
                else echo -e " ${RD}Gagal hidupkan pantau.${NC}"; fi
                sleep 2 ;;
            2|02)
                if jaga_tg "UJIAN" "-" "Pantau servis berfungsi."; then echo -e " ${GR}Dihantar. Semak Telegram.${NC}"
                else echo -e " ${RD}Token/ID Telegram belum ditetapkan (menu > 10 > 06).${NC}"; fi
                sleep 3 ;;
            3|03)
                clear; echo ""
                if [ -s "$JAGA_LOG" ]; then tail -n 15 "$JAGA_LOG"; else echo " Tiada rekod. Semua servis sihat."; fi
                kn_pause ;;
            0|00|x|X) return ;;
        esac
    done
}

# ---------- 7) BACKUP TELEGRAM  dan  8) PINDAH AKAUN ----------
# Satu format fail (tar.gz): ssh.txt, xray.txt, lim-vless, lim-vmess, lim-trojan, meta.txt
BK_CRON="/etc/cron.d/kancil-backup"
bk_make() {   # $1 = fail .tar.gz
    local w x n_ssh n_x r
    w=$(mktemp -d) || return 1
    mkdir -p "$w/d"
    [ -f "$SSH_LIST" ] && grep -E '^### ' "$SSH_LIST" > "$w/d/ssh.txt"
    [ -f "$XRAY_CFG" ] && awk '/^#(vl|vlg|vm|vmg|tr|trg) /{print; if ((getline nx) > 0) print nx}' "$XRAY_CFG" > "$w/d/xray.txt"
    for x in vless vmess trojan; do [ -d "/etc/$x" ] && cp -r "/etc/$x" "$w/d/lim-$x" 2>/dev/null; done
    n_ssh=$(grep -c '^### ' "$w/d/ssh.txt" 2>/dev/null)
    n_x=$(grep -Ec '^#(vl|vm|tr) ' "$w/d/xray.txt" 2>/dev/null)
    printf 'KANCIL-AKAUN 1\ndomain=%s\ntarikh=%s\nssh=%s\nxray=%s\n' "${domain:--}" "$(date '+%F %T')" "${n_ssh:-0}" "${n_x:-0}" > "$w/d/meta.txt"
    tar -czf "$1" -C "$w/d" . 2>/dev/null; r=$?
    rm -rf "$w"
    chmod 600 "$1" 2>/dev/null
    return $r
}
bk_send() {   # $1 = fail  $2 = kapsyen   (0 ok, 1 gagal, 2 tiada token)
    local r
    [ -z "$CHATID" ] || [ -z "$KEY" ] && return 2
    r=$(curl -s --max-time 60 -F "chat_id=$CHATID" -F "document=@$1" -F "caption=$2" "https://api.telegram.org/bot$KEY/sendDocument" 2>/dev/null)
    echo "$r" | grep -q '"ok":true' && return 0
    return 1
}
bk_run() {   # mod cron / hantar sekarang: buat, hantar, padam
    local f r
    f="/tmp/akaun-$(date +%Y%m%d).tar.gz"
    bk_make "$f" || { rm -f "$f"; return 1; }
    bk_send "$f" "Backup akaun $(date +%F) | ${domain:--}"; r=$?
    rm -f "$f"
    return $r
}
bk_on()  { printf '%s\n' '30 3 * * * root /usr/bin/m-tools backup >/dev/null 2>&1' > "$BK_CRON" 2>/dev/null && chmod 644 "$BK_CRON"; }
bk_off() { rm -f "$BK_CRON"; }
bk_info() {   # $1 = fail  -> cetak ringkasan
    local w; w=$(mktemp -d) || return 1
    tar -xzf "$1" -C "$w" --wildcards '*meta.txt' 2>/dev/null
    if head -n1 "$w/meta.txt" 2>/dev/null | grep -q '^KANCIL-AKAUN 1$'; then
        kn_row "Dari" "$(grep '^domain=' "$w/meta.txt" | cut -d= -f2-)"
        kn_row "Tarikh" "$(grep '^tarikh=' "$w/meta.txt" | cut -d= -f2-)"
        kn_row "SSH" "$(grep '^ssh=' "$w/meta.txt" | cut -d= -f2-) akaun"
        kn_row "Xray" "$(grep '^xray=' "$w/meta.txt" | cut -d= -f2-) akaun"
        rm -rf "$w"; return 0
    fi
    rm -rf "$w"; return 1
}
t_backup() {
    local p st r
    while true; do
        [ -f "$BK_CRON" ] && st="${GR}ON${NC}" || st="${RD}OFF${NC}"
        clear; echo ""
        kn_top; kn_title "BACKUP TELEGRAM"; kn_mid
        printf '%b│%b Status  : %b\n' "$COLOR1" "$NC" "$st"
        printf '%b│%b Waktu   : setiap hari 03:30\n' "$COLOR1" "$NC"
        printf '%b│%b Isi     : akaun SSH, VMess, VLess, Trojan\n' "$COLOR1" "$NC"
        printf '%b│%b Ke      : bot Telegram kamu\n' "$COLOR1" "$NC"
        kn_mid
        printf '%b│%b Fail ada password. Bot mesti PRIVATE.\n' "$COLOR1" "$NC"
        kn_mid
        kn_item1 "01" "HIDUP / MATI"
        kn_item1 "02" "HANTAR SEKARANG"
        kn_item1 "00" "KEMBALI"
        kn_foot; echo ""
        read -rp " Pilih : " p
        case "$p" in
            1|01)
                if [ -f "$BK_CRON" ]; then bk_off; echo -e " ${YL}Backup harian dimatikan.${NC}"
                elif bk_on; then echo -e " ${GR}Backup harian dihidupkan (03:30).${NC}"
                else echo -e " ${RD}Gagal hidupkan backup.${NC}"; fi
                sleep 2 ;;
            2|02)
                echo " Menghantar..."
                bk_run; r=$?
                case $r in
                    0) echo -e " ${GR}Dihantar ke Telegram.${NC}" ;;
                    2) echo -e " ${RD}Token/ID Telegram belum ditetapkan (menu > 10 > 06).${NC}" ;;
                    *) echo -e " ${RD}Gagal hantar. Semak token dan internet.${NC}" ;;
                esac
                sleep 3 ;;
            0|00|x|X) return ;;
        esac
    done
}

# import: ssh guna useradd, xray guna python3 + ujian config. Config lama disimpan, gagal = dipulihkan.
bk_import() {   # $1 = fail tar.gz
    local f="$1" w today u e p py res nb rb XB tl pr us d
    local s_add=0 s_dup=0 s_old=0
    [ -f "$f" ] || { echo -e " ${RD}Fail tak jumpa.${NC}"; return 1; }
    w=$(mktemp -d) || return 1
    if ! tar -xzf "$f" -C "$w" 2>/dev/null || ! head -n1 "$w/meta.txt" 2>/dev/null | grep -q '^KANCIL-AKAUN 1$'; then
        echo -e " ${RD}Fail ni bukan backup akaun Kancil.${NC}"; rm -rf "$w"; return 1
    fi
    today=$(date +%Y-%m-%d)
    # --- SSH ---
    if [ -s "$w/ssh.txt" ]; then
        touch "$SSH_LIST" 2>/dev/null
        while read -r _ u e p; do
            [[ "$u" =~ ^[A-Za-z0-9_-]{1,32}$ ]] || continue
            [[ "$e" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || continue
            [ -n "$p" ] || continue
            if [[ "$e" < "$today" ]]; then s_old=$((s_old+1)); continue; fi
            if getent passwd "$u" >/dev/null 2>&1; then s_dup=$((s_dup+1)); continue; fi
            useradd -e "$e" -s /bin/false -M "$u" 2>/dev/null || { s_dup=$((s_dup+1)); continue; }
            printf '%s:%s\n' "$u" "$p" | chpasswd 2>/dev/null
            grep -q "^### $u " "$SSH_LIST" 2>/dev/null || echo "### $u $e $p" >> "$SSH_LIST"
            s_add=$((s_add+1))
        done < "$w/ssh.txt"
    fi
    # --- XRAY ---
    res="tiada xray.txt"
    if [ -s "$w/xray.txt" ] && [ -f "$XRAY_CFG" ]; then
        py="$w/merge.py"
        cat > "$py" <<'PYEOF'
import sys, re
cfg, xr, out, today = sys.argv[1:5]
ANCH = {'#vl': '#vless', '#vlg': '#vlessgrpc', '#vm': '#vmess', '#vmg': '#vmessgrpc', '#tr': '#trojanws', '#trg': '#trojangrpc'}
PROTO = {'#vl': 'vless', '#vlg': 'vless', '#vm': 'vmess', '#vmg': 'vmess', '#tr': 'trojan', '#trg': 'trojan'}
lines = open(cfg, encoding='utf-8').read().split('\n')
src = open(xr, encoding='utf-8').read().split('\n')
pairs = []
i = 0
while i + 1 < len(src):
    p = src[i].split(' ')
    if p[0] in ANCH and len(p) >= 3 and src[i + 1].startswith('},{'):
        pairs.append((p[0], p[1], p[2], src[i], src[i + 1]))
        i += 2
    else:
        i += 1
have = set()
for l in lines:
    q = l.split(' ')
    if len(q) >= 2 and q[0] in ANCH:
        have.add((q[0], q[1]))
add = 0; dup = 0; old = 0; miss = set(); users = []
for mk, user, exp, m, idl in pairs:
    if not re.match(r'^[A-Za-z0-9_.-]{1,64}$', user): continue
    if not re.match(r'^\d{4}-\d{2}-\d{2}$', exp): continue
    if exp < today:
        if mk in ('#vl', '#vm', '#tr'): old += 1
        continue
    if (mk, user) in have:
        if mk in ('#vl', '#vm', '#tr'): dup += 1
        continue
    idx = None
    for k, l in enumerate(lines):
        if l.endswith(ANCH[mk]):
            idx = k; break
    if idx is None:
        miss.add(ANCH[mk]); continue
    lines[idx + 1:idx + 1] = [m, idl]
    have.add((mk, user))
    if mk in ('#vl', '#vm', '#tr'):
        add += 1; users.append(PROTO[mk] + ' ' + user)
open(out, 'w', encoding='utf-8').write('\n'.join(lines))
open(out + '.users', 'w', encoding='utf-8').write('\n'.join(users) + ('\n' if users else ''))
print('add=%d dup=%d old=%d miss=%s' % (add, dup, old, ','.join(sorted(miss)) or '-'))
PYEOF
        res=$(python3 "$py" "$XRAY_CFG" "$w/xray.txt" "$w/new.json" "$today" 2>&1 | tail -n1)
        if [[ "$res" == add=* ]] && ! [[ "$res" == add=0\ * ]]; then
            XB=$(command -v xray 2>/dev/null || echo /usr/local/bin/xray)
            if [ -x "$XB" ] && { "$XB" run -test -config "$w/new.json" >/dev/null 2>&1 || "$XB" -test -config "$w/new.json" >/dev/null 2>&1; }; then
                nb="/root/config.json.sebelum-import-$(date +%Y%m%d-%H%M%S)"
                cp -a "$XRAY_CFG" "$nb"
                cp "$w/new.json" "$XRAY_CFG"
                systemctl restart xray >/dev/null 2>&1
                sleep 2
                if systemctl is-active --quiet xray 2>/dev/null; then
                    while read -r pr us; do
                        [ -z "$us" ] && continue
                        mkdir -p "/etc/$pr" 2>/dev/null
                        for d in "$us" "${us}IP"; do
                            [ -f "$w/lim-$pr/$d" ] && [ ! -e "/etc/$pr/$d" ] && cp "$w/lim-$pr/$d" "/etc/$pr/$d"
                        done
                        if [ "$pr" = trojan ] && [ -f "$w/lim-trojan/akun/$us" ] && [ ! -e "/etc/trojan/akun/$us" ]; then
                            mkdir -p /etc/trojan/akun; cp "$w/lim-trojan/akun/$us" "/etc/trojan/akun/$us"
                        fi
                    done < "$w/new.json.users"
                else
                    cp "$nb" "$XRAY_CFG"; systemctl restart xray >/dev/null 2>&1
                    res="GAGAL: xray tak hidup selepas import, config dipulihkan"
                fi
            else
                res="GAGAL: config baru tak lulus ujian xray, tiada apa diubah"
            fi
        fi
    fi
    rm -rf "$w"
    echo ""
    echo -e " ${WH}SSH   :${NC} ${GR}${s_add} ditambah${NC}, ${s_dup} dah ada, ${s_old} tamat"
    if [[ "$res" == add=* ]]; then
        echo -e " ${WH}Xray  :${NC} ${GR}$(echo "$res" | sed 's/add=\([0-9]*\) dup=\([0-9]*\) old=\([0-9]*\) miss=\(.*\)/\1 ditambah/')${NC}, $(echo "$res" | sed 's/.*dup=\([0-9]*\) old=\([0-9]*\).*/\1 dah ada, \2 tamat/')"
        echo "$res" | grep -q 'miss=-' || echo -e " ${YL}Tak jumpa tempat dalam config: $(echo "$res" | sed 's/.*miss=//')${NC}"
    else
        echo -e " ${WH}Xray  :${NC} ${YL}${res}${NC}"
    fi
    echo -e " ${WH}Nota  :${NC} link akaun lama lihat di menu CEK USER CONFIG"
    return 0
}
t_pindah() {
    local p f i n arr sel
    while true; do
        clear; echo ""
        kn_top; kn_title "PINDAH AKAUN"; kn_mid
        kn_item1 "01" "EKSPORT (buat fail akaun)"
        kn_item1 "02" "IMPORT (dari fail akaun)"
        kn_item1 "00" "KEMBALI"
        kn_foot; echo ""
        read -rp " Pilih : " p
        case "$p" in
            1|01)
                f="/root/akaun-$(date +%Y%m%d-%H%M).tar.gz"
                clear; echo ""
                if bk_make "$f"; then
                    kn_top; kn_title "EKSPORT SIAP"; kn_mid
                    bk_info "$f"
                    kn_mid
                    printf '%b│%b Fail: %s\n' "$COLOR1" "$NC" "$f"
                    kn_bot; echo ""
                    echo -e " ${WH}Hantar ke VPS baru, taip di VPS ni:${NC}"
                    echo " scp $f root@IP_VPS_BARU:/root/"
                    echo -e " ${WH}Lepas tu kat VPS baru: m-tools > 08 > 02${NC}"
                    echo -e " ${YL}Fail ada password. Padam lepas siap.${NC}"
                else
                    echo -e " ${RD}Gagal buat fail.${NC}"
                fi
                kn_pause ;;
            2|02)
                clear; echo ""
                arr=(/root/akaun-*.tar.gz)
                [ -e "${arr[0]}" ] || arr=()
                kn_top; kn_title "IMPORT AKAUN"; kn_mid
                if [ "${#arr[@]}" -gt 0 ]; then
                    i=0; for n in "${arr[@]}"; do i=$((i+1)); printf '%b│%b %2d) %s\n' "$COLOR1" "$NC" "$i" "$n"; done
                else
                    printf '%b│%b Tiada fail akaun-*.tar.gz dalam /root\n' "$COLOR1" "$NC"
                fi
                kn_bot; echo ""
                read -rp " Nombor atau path fail (kosong = batal): " sel
                [ -z "$sel" ] && continue
                if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#arr[@]}" ]; then f="${arr[$((sel-1))]}"; else f="$sel"; fi
                clear; echo ""
                kn_top; kn_title "SEMAK FAIL"; kn_mid
                if ! bk_info "$f"; then
                    printf '%b│%b Bukan fail akaun Kancil\n' "$COLOR1" "$NC"; kn_bot; echo ""; kn_pause; continue
                fi
                kn_bot; echo ""
                echo -e " ${YL}Akaun yang dah ada atau dah tamat dilangkau.${NC}"
                read -rp " Teruskan import? (y/n): " p
                [ "$p" = y ] || [ "$p" = Y ] && bk_import "$f"
                kn_pause ;;
            0|00|x|X) return ;;
        esac
    done
}

# ---------- mod cron ----------
if [ "$1" = "remind" ]; then
    remind_send
    exit 0
fi
if [ "$1" = "jaga" ]; then
    jaga_run
    exit 0
fi
if [ "$1" = "backup" ]; then
    bk_run
    exit $?
fi

# ---------- menu ----------
while true; do
    [ -f "$CRON_FILE" ] && rs="${GR}ON${NC}" || rs="${RD}OFF${NC}"
    [ -f "$JAGA_CRON" ] && js="${GR}ON${NC}" || js="${RD}OFF${NC}"
    [ -f "$BK_CRON" ] && bs="${GR}ON${NC}" || bs="${RD}OFF${NC}"
    clear; echo ""
    kn_top; kn_title_r "TOOLS KANCIL"; kn_mid
    kn_item1 "01" "RINGKASAN AKAUN"
    kn_item1 "02" "CARI AKAUN"
    kn_item1 "03" "NOTA PELANGGAN"
    printf '%b│%b %b[%b04%b]%b PERINGATAN HARIAN %b\n' "$COLOR1" "$NC" "$WH" "$COLOR1" "$WH" "$NC" "$rs"
    kn_item1 "05" "KESIHATAN VPS"
    printf '%b│%b %b[%b06%b]%b PANTAU SERVIS %b\n' "$COLOR1" "$NC" "$WH" "$COLOR1" "$WH" "$NC" "$js"
    printf '%b│%b %b[%b07%b]%b BACKUP TELEGRAM %b\n' "$COLOR1" "$NC" "$WH" "$COLOR1" "$WH" "$NC" "$bs"
    kn_item1 "08" "PINDAH AKAUN"
    kn_item1 "00" "KEMBALI"
    kn_foot; echo ""
    echo -ne " ${WH}Pilih menu ${COLOR1}: ${WH}"
    read -r opt || break
    echo -ne "${NC}"
    case "$opt" in
        1|01) t_ringkasan ;;
        2|02) t_cari ;;
        3|03) t_nota ;;
        4|04) t_peringatan ;;
        5|05) t_kesihatan ;;
        6|06) t_jaga ;;
        7|07) t_backup ;;
        8|08) t_pindah ;;
        0|00|x|X) break ;;
    esac
done
clear
menu
