#!/bin/bash
# m-tools - Tools tambahan (ringkasan, cari, nota, peringatan, kesihatan VPS)
# Developer by kancil ecem
#   m-tools           -> menu
#   m-tools remind    -> hantar peringatan ke Telegram (untuk cron)

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

# ---------- mod cron ----------
if [ "$1" = "remind" ]; then
    remind_send
    exit 0
fi

# ---------- menu ----------
while true; do
    [ -f "$CRON_FILE" ] && rs="${GR}ON${NC}" || rs="${RD}OFF${NC}"
    clear; echo ""
    kn_top; kn_title_r "TOOLS KANCIL"; kn_mid
    kn_item1 "01" "RINGKASAN AKAUN"
    kn_item1 "02" "CARI AKAUN"
    kn_item1 "03" "NOTA PELANGGAN"
    printf '%b│%b %b[%b04%b]%b PERINGATAN HARIAN %b\n' "$COLOR1" "$NC" "$WH" "$COLOR1" "$WH" "$NC" "$rs"
    kn_item1 "05" "KESIHATAN VPS"
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
        0|00|x|X) break ;;
    esac
done
clear
menu
