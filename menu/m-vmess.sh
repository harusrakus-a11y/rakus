#!/bin/bash
clear

# =============================================
#           [ Konfigurasi Warna ]
# =============================================
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export NC='\033[0m'

# =============================================
#          [ Fungsi Pengecekan IP ]
check_ip_and_get_info() {
    local ip=$1
    while IFS= read -r line; do
        # Hapus karakter khusus dan spasi berlebih
        line=$(echo "$line" | tr -d '\r' | sed 's/[^[:print:]]//g' | xargs)
        
        # Split baris menjadi array
        read -ra fields <<< "$line"
        
        
        # Kolom 4 = IP Address (index 3)
        if [[ "${fields[3]}" == "$ip" ]]; then
            client_name="${fields[1]}"  # Kolom 2
            exp_date="${fields[2]}"     # Kolom 3
            
            # Bersihkan tanggal dari karakter khusus
            exp_date=$(echo "$exp_date" | sed 's/[^0-9-]//g' | xargs)
            
            return 0
        fi
    done <<< "$permission_file"
    return 1
}

# =============================================
#          [ Main Script ]
# =============================================

# Ambil data dari GitHub dengan timeout
permission_file=$(curl -sL --connect-timeout 10 https://raw.githubusercontent.com/harusrakus-a11y/ijin/refs/heads/main/akses)

# Validasi file permission
if [ -z "$permission_file" ]; then
    echo -e "${RED}❌ Gagal mengambil data lisensi!${NC}"
    exit 1
fi

# Ambil IP VPS dengan metode alternatif
IP_VPS=$(curl -s https://ipinfo.io/ip)
# =============================================
#          [ Pengecekan IP ]
# =============================================
echo -e "${GREEN}⌛ Memeriksa lisensi...${NC}"
if check_ip_and_get_info "$IP_VPS"; then
    
    # Validasi format tanggal ISO 8601
    if ! [[ "$exp_date" =~ ^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$ ]]; then
        echo -e "${RED}❌ Format tanggal invalid: '$exp_date' (harus YYYY-MM-DD)${NC}"
        exit 1
    fi

    # Validasi tanggal menggunakan date
    if ! date -d "$exp_date" "+%s" &>/dev/null; then
        echo -e "${RED}❌ Tanggal tidak valid secara kalender: $exp_date${NC}"
        exit 1
    fi
else
    echo -e "${RED}❌ IP tidak terdaftar!${NC}"
    echo -e "➥ Hubungi admin ${CYAN}「 ✦ kancil ecem ✦ 」${NC}"
    exit 1
fi

# =============================================
#          [ Hitung Hari Tersisa ]
# =============================================
current_epoch=$(date +%s)
exp_epoch=$(date -d "$exp_date" +%s)

if (( exp_epoch < current_epoch )); then
    echo -e "${RED}❌ Masa aktif telah habis!${NC}"
    exit 1
fi

days_remaining=$(( (exp_epoch - current_epoch) / 86400 ))

biji=`date +"%Y-%m-%d" -d "$dateFromServer"`
colornow=$(cat /etc/phreakers/theme/color.conf)
NC="\e[0m"
RED="\033[0;31m"
COLOR1="$(cat /etc/phreakers/theme/$colornow | grep -w "TEXT" | cut -d: -f2|sed 's/ //g')"
COLBG1="$(cat /etc/phreakers/theme/$colornow | grep -w "BG" | cut -d: -f2|sed 's/ //g')"
WH='\033[1;37m'

clear
cd
ISP=$(cat /etc/xray/isp)
CITY=$(cat /etc/xray/city)
author=$(cat /etc/profil)
TIMES="10"
CHATID=$(cat /etc/per/id)
KEY=$(cat /etc/per/token)
URL="https://api.telegram.org/bot$KEY/sendMessage"
domain=`cat /etc/xray/domain`
CHATID2=$(cat /etc/perlogin/id)
KEY2=$(cat /etc/perlogin/token)
URL2="https://api.telegram.org/bot$KEY2/sendMessage"
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
cd
if [ ! -e /etc/vmess/akun ]; then
mkdir -p /etc/vmess/akun
fi
telco_conf=/etc/xray/telco.conf
telco_url=https://raw.githubusercontent.com/harusrakus-a11y/rakus/refs/heads/main/menu/telco.conf
telco_init() {
rm -f /tmp/telco.new
if wget -q -T 8 -t 1 -O /tmp/telco.new "$telco_url" 2>/dev/null && grep -Eq '^[A-Za-z0-9_-]+\|[^|]+\|[^|]+\|/[^|]*\|[0-9]+$' /tmp/telco.new; then
cp /tmp/telco.new $telco_conf
fi
rm -f /tmp/telco.new
[ -s $telco_conf ] && return
cat > $telco_conf <<'EOT'
# nama|alamat|host|path|port   ({domain} = domain VPS)
celcom|mcmc-my.metricelltestcloud.com.{domain}|mcmc-my.metricelltestcloud.com|/vless|80
digi|104.18.21.212|{domain}|/vless|80
maxis-viu|help.viu.com.{domain}|help.viu.com|/vless|80
maxis-cmgo|104.16.160.145|cfcdn.viu.com.{domain}|/vless|80
yes|104.17.147.22|{domain}|/vless|80
tonewow|172.66.169.187|{domain}|/vless|80
EOT
}
telco_links() {
local u=$1 nm=$2 sel=$3 n=0 name addr host pth port js
[ -z "$sel" ] && return
while IFS='|' read -r name addr host pth port; do
[[ -z $name || $name == \#* ]] && continue
n=$((n+1))
if [[ $sel != 0 && $sel != $n ]]; then continue; fi
addr=${addr//\{domain\}/$domain}
host=${host//\{domain\}/$domain}
pth=${pth:-/vless}
[[ $pth == /vless ]] && pth=/vmess
port=${port:-80}
js="{\"v\":\"2\",\"ps\":\"${nm}-${name}\",\"add\":\"${addr}\",\"port\":\"${port}\",\"id\":\"${u}\",\"aid\":\"0\",\"net\":\"ws\",\"path\":\"${pth}\",\"type\":\"none\",\"host\":\"${host}\",\"tls\":\"none\"}"
echo "${name}|vmess://$(printf '%s' "$js" | base64 -w 0)"
done < $telco_conf
}
function add-vmess(){
clear
until [[ $user =~ ^[a-zA-Z0-9_.-]+$ && ${CLIENT_EXISTS} == '0' ]]; do
kn_top
kn_title "Add Vmess Account"
kn_bot
echo -e ""
read -rp "User: " -e user
CLIENT_EXISTS=$(grep -w $user /etc/xray/config.json | wc -l)
if [[ ${CLIENT_EXISTS} == '1' ]]; then
clear
kn_top
kn_title "Add Vmess Account"
kn_bot
echo -e "$COLOR1┌─────────────────────────────────────────────────┐${NC}"
echo -e "$COLOR1│                                                 │"
echo -e "$COLOR1│${WH} Nama Duplikat Silahkan Buat Nama Lain.          $COLOR1│"
echo -e "$COLOR1│                                                 │"
echo -e "$COLOR1└─────────────────────────────────────────────────┘${NC}"
read -n 1 -s -r -p "Press any key to back"
add-vmess
fi
done
uuid=$(cat /proc/sys/kernel/random/uuid)
read -rp "UUID custom (kosong = auto): " cuuid
while [[ -n $cuuid ]]; do
if [[ $cuuid =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ || $cuuid =~ ^[A-Za-z0-9._-]{8,30}$ ]]; then
if grep -qF "\"$cuuid\"" /etc/xray/config.json; then
echo "Dah dipakai, cuba yang lain."
else
uuid=$cuuid
break
fi
else
echo "Tak sah. Guna UUID biasa (8-4-4-4-12) atau teks 8-30 aksara (A-Z a-z 0-9 . _ -)."
fi
read -rp "UUID custom (kosong = auto): " cuuid
done
until [[ $masaaktif =~ ^[0-9]+$ ]]; do
read -p "Expired (hari): " masaaktif
done
exp=`date -d "$masaaktif days" +"%Y-%m-%d"`
until [[ $iplim =~ ^[0-9]+$ ]]; do
read -p "Limit User (IP) or 0 Unlimited: " iplim
done
until [[ $Quota =~ ^[0-9]+$ ]]; do
read -p "Limit User (GB) or 0 Unlimited: " Quota
done
telco_init
echo ""
echo "Pilih telco untuk link tambahan:"
ti=0
while IFS='|' read -r tn _; do
[[ -z $tn || $tn == \#* ]] && continue
ti=$((ti+1))
echo " $ti) $tn"
done < $telco_conf
echo " 0) semua telco"
tsel="x"
until [[ -z $tsel || ( $tsel =~ ^[0-9]+$ && $tsel -le $ti ) ]]; do
read -rp "Telco (kosong = tiada): " tsel
done
if [ ! -e /etc/vmess ]; then
mkdir -p /etc/vmess
fi
if [ ${iplim} = '0' ]; then
iplim="9999"
fi
if [ ${Quota} = '0' ]; then
Quota="9999"
fi
c=$(echo "${Quota}" | sed 's/[^0-9]*//g')
d=$((${c} * 1024 * 1024 * 1024))
if [[ ${c} != "0" ]]; then
echo "${d}" >/etc/vmess/${user}
fi
echo "${iplim}" >/etc/vmess/${user}IP
exp=`date -d "$masaaktif days" +"%Y-%m-%d"`
sed -i '/#vmess$/a\#vm '"$user $exp"'\
},{"id": "'""$uuid""'","alterId": '"0"',"email": "'""$user""'"' /etc/xray/config.json
sed -i '/#vmessgrpc$/a\#vmg '"$user $exp $uuid"'\
},{"id": "'""$uuid""'","alterId": '"0"',"email": "'""$user""'"' /etc/xray/config.json
asu=`cat<<EOF
{
"v": "2",
"ps": "${user}",
"add": "${domain}",
"port": "443",
"id": "${uuid}",
"aid": "0",
"net": "ws",
"path": "/vmess",
"type": "none",
"host": "${domain}",
"tls": "tls"
}
EOF`
ask=`cat<<EOF
{
"v": "2",
"ps": "${user}",
"add": "${domain}",
"port": "80",
"id": "${uuid}",
"aid": "0",
"net": "ws",
"path": "/vmess",
"type": "none",
"host": "${domain}",
"tls": "none"
}
EOF`
grpc=`cat<<EOF
{
"v": "2",
"ps": "${user}",
"add": "${domain}",
"port": "443",
"id": "${uuid}",
"aid": "0",
"net": "grpc",
"path": "vmess-grpc",
"type": "none",
"host": "${domain}",
"tls": "tls"
}
EOF`
vmess_base641=$( base64 -w 0 <<< $vmess_json1)
vmess_base642=$( base64 -w 0 <<< $vmess_json2)
vmess_base643=$( base64 -w 0 <<< $vmess_json3)
vmesslink1="vmess://$(echo $asu | base64 -w 0)"
vmesslink2="vmess://$(echo $ask | base64 -w 0)"
vmesslink3="vmess://$(echo $grpc | base64 -w 0)"
VMESS_WS=`cat<<EOF
{
"v": "2",
"ps": "${user}",
"add": "${domain}",
"port": "443",
"id": "${uuid}",
"aid": "0",
"net": "ws",
"path": "/vmess",
"type": "none",
"host": "${domain}",
"tls": "tls"
}
EOF`
VMESS_NON_TLS=`cat<<EOF
{
"v": "2",
"ps": "${user}",
"add": "${domain}",
"port": "80",
"id": "${uuid}",
"aid": "0",
"net": "ws",
"path": "/vmess",
"type": "none",
"host": "${domain}",
"tls": "none"
}
EOF`
VMESS_GRPC=`cat<<EOF
{
"v": "2",
"ps": "${user}",
"add": "${domain}",
"port": "443",
"id": "${uuid}",
"aid": "0",
"net": "grpc",
"path": "/vmess-grpc",
"type": "none",
"host": "${domain}",
"tls": "tls"
}
EOF`
VMESS_OPOK=`cat<<EOF
{
"v": "2",
"ps": "${user}",
"add": "${domain}",
"port": "80",
"id": "${uuid}",
"aid": "0",
"net": "ws",
"path": "http://tsel.me/worryfree",
"type": "none",
"host": "tsel.me",
"tls": "none"
}
EOF`
cat > /home/vps/public_html/vmess-$user.txt <<-END
_______________________________________________________
Format Vmess WS (CDN)
_______________________________________________________
- name: vmess-$user-WS (CDN)
type: vmess
server: ${domain}
port: 443
uuid: ${uuid}
alterId: 0
cipher: auto
udp: true
tls: true
skip-cert-verify: true
servername: ${domain}
network: ws
ws-opts:
path: /vmess
headers:
Host: ${domain}
_______________________________________________________
Format Vmess WS (CDN) Non TLS
_______________________________________________________
- name: vmess-$user-WS (CDN) Non TLS
type: vmess
server: ${domain}
port: 80
uuid: ${uuid}
alterId: 0
cipher: auto
udp: true
tls: false
skip-cert-verify: false
servername: ${domain}
network: ws
ws-opts:
path: /vmess
headers:
Host: ${domain}
_______________________________________________________
Format Vmess gRPC (SNI)
_______________________________________________________
- name: vmess-$user-gRPC (SNI)
server: ${domain}
port: 443
type: vmess
uuid: ${uuid}
alterId: 0
cipher: auto
network: grpc
tls: true
servername: ${domain}
skip-cert-verify: true
grpc-opts:
grpc-service-name: vmess-grpc
_______________________________________________________
Format Vmess WS (CDN) Non TLS Opok TSEL
_______________________________________________________
- name: vmess-$user-WS (CDN) Non TLS
type: vmess
server: ${domain}
port: 80
uuid: ${uuid}
alterId: 0
cipher: auto
udp: true
tls: false
skip-cert-verify: true
servername: comunity.instagram.com
network: ws
ws-opts:
path: : http://tsel.me/worryfree
headers:
Host: ${domain}
_______________________________________________________
Link Vmess Account
_______________________________________________________
Link TLS : vmess://$(echo $VMESS_WS | base64 -w 0)
_______________________________________________________
Link NTLS : vmess://$(echo $VMESS_NON_TLS | base64 -w 0)
_______________________________________________________
Link gRPC : vmess://$(echo $VMESS_GRPC | base64 -w 0)
_______________________________________________________
Link Opok : vmess://$(echo $VMESS_OPOK | base64 -w 0)
_______________________________________________________
END
telcolines="$(telco_links "$uuid" "$user" "$tsel")"
if [ -n "$telcolines" ]; then
while IFS='|' read -r tn tl; do
echo "Link ${tn} : ${tl}" >> /home/vps/public_html/vmess-$user.txt
echo "_______________________________" >> /home/vps/public_html/vmess-$user.txt
done <<< "$telcolines"
fi
TEXT="$(kn_text "VMESS" "$user" "$exp" "$iplim IP" "$Quota")"
kn_send "$TEXT"
cd
if [ ! -e /etc/tele ]; then
echo -ne
else
echo "$TEXT" > /etc/notiftele
bash /etc/tele
fi
user2=$(echo "$user" | cut -c 1-3)
TIME2=$(date +'%Y-%m-%d %H:%M:%S')
clear
{
kn_top
kn_title "VMESS PREMIUM ACCOUNT"
kn_mid
kn_row "User" "${user}"
kn_row "Domain" "${domain}"
kn_row "Lokasi" "${CITY} - ${ISP}"
kn_row "Had IP" "${iplim} IP"
if [ "${Quota}" != "9999" ]; then
kn_row "Kuota" "${Quota} GB"
fi
kn_row "Tamat" "${exp}"
kn_mid
kn_row "Port TLS" "443"
kn_row "Port NTLS" "80, 8080"
kn_row "Port gRPC" "443"
kn_row "AlterId" "0"
kn_row "Security" "auto"
kn_row "Path" "/vmess"
kn_row "Path bug" "http://bug/vmess"
kn_row "Service" "vmess-grpc"
kn_link "UUID" "${uuid}"
kn_mid
kn_link "Link WS TLS" "${vmesslink1}"
kn_link "Link WS NTLS" "${vmesslink2}"
kn_link "Link gRPC" "${vmesslink3}"
if [ -n "$telcolines" ]; then
while IFS='|' read -r tn tl; do
kn_link "Link ${tn}" "${tl}"
done <<< "$telcolines"
fi
kn_link "Format OpenClash" "http://$domain:89/vmess-$user.txt"
kn_foot
echo ""
} | tee -a /etc/vmess/akun/log-create-${user}.log
systemctl restart xray > /dev/null 2>&1
read -n 1 -s -r -p "Press any key to back on menu"
menu
}
function trial-vmess(){
clear
cd
kn_top
kn_title "Trial Vmess Account"
kn_bot
echo -e ""
until [[ $timer =~ ^[0-9]+$ ]]; do
read -p "Expired (Minutes): " timer
done
user=Trial-`</dev/urandom tr -dc X-Z0-9 | head -c4`
iplim=1
Quota=10
uuid=$(cat /proc/sys/kernel/random/uuid)
masaaktif=0
if [ ! -e /etc/vmess ]; then
mkdir -p /etc/vmess
fi
c=$(echo "${Quota}" | sed 's/[^0-9]*//g')
d=$((${c} * 1024 * 1024 * 1024))
if [[ ${c} != "0" ]]; then
echo "${d}" >/etc/vmess/${user}
fi
echo "${iplim}" > /etc/vmess/${user}IP
exp=`date -d "$masaaktif days" +"%Y-%m-%d"`
sed -i '/#vmess$/a\#vm '"$user $exp"'\
},{"id": "'""$uuid""'","alterId": '"0"',"email": "'""$user""'"' /etc/xray/config.json
sed -i '/#vmessgrpc$/a\#vmg '"$user $exp $uuid"'\
},{"id": "'""$uuid""'","alterId": '"0"',"email": "'""$user""'"' /etc/xray/config.json
cat> /etc/cron.d/trialvmess${user} << EOF
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
*/$timer * * * * root /usr/bin/trial vmess $user $uuid $exp
EOF
asu=`cat<<EOF
{
"v": "2",
"ps": "${user}",
"add": "${domain}",
"port": "443",
"id": "${uuid}",
"aid": "0",
"net": "ws",
"path": "/vmess",
"type": "none",
"host": "${domain}",
"tls": "tls"
}
EOF`
ask=`cat<<EOF
{
"v": "2",
"ps": "${user}",
"add": "${domain}",
"port": "80",
"id": "${uuid}",
"aid": "0",
"net": "ws",
"path": "/vmess",
"type": "none",
"host": "${domain}",
"tls": "none"
}
EOF`
grpc=`cat<<EOF
{
"v": "2",
"ps": "${user}",
"add": "${domain}",
"port": "443",
"id": "${uuid}",
"aid": "0",
"net": "grpc",
"path": "vmess-grpc",
"type": "none",
"host": "${domain}",
"tls": "tls"
}
EOF`
vmess_base641=$( base64 -w 0 <<< $vmess_json1)
vmess_base642=$( base64 -w 0 <<< $vmess_json2)
vmess_base643=$( base64 -w 0 <<< $vmess_json3)
vmesslink1="vmess://$(echo $asu | base64 -w 0)"
vmesslink2="vmess://$(echo $ask | base64 -w 0)"
vmesslink3="vmess://$(echo $grpc | base64 -w 0)"
VMESS_WS=`cat<<EOF
{
"v": "2",
"ps": "${user}",
"add": "${domain}",
"port": "443",
"id": "${uuid}",
"aid": "0",
"net": "ws",
"path": "/vmess",
"type": "none",
"host": "${domain}",
"tls": "tls"
}
EOF`
VMESS_NON_TLS=`cat<<EOF
{
"v": "2",
"ps": "${user}",
"add": "${domain}",
"port": "80",
"id": "${uuid}",
"aid": "0",
"net": "ws",
"path": "/vmess",
"type": "none",
"host": "${domain}",
"tls": "none"
}
EOF`
VMESS_GRPC=`cat<<EOF
{
"v": "2",
"ps": "${user}",
"add": "${domain}",
"port": "443",
"id": "${uuid}",
"aid": "0",
"net": "grpc",
"path": "/vmess-grpc",
"type": "none",
"host": "${domain}",
"tls": "tls"
}
EOF`
VMESS_OPOK=`cat<<EOF
{
"v": "2",
"ps": "${user}",
"add": "${domain}",
"port": "80",
"id": "${uuid}",
"aid": "0",
"net": "ws",
"path": "http://tsel.me/worryfree",
"type": "none",
"host": "tsel.me",
"tls": "none"
}
EOF`
cat > /home/vps/public_html/vmess-$user.txt <<-END
_______________________________________________________
Format Vmess WS (CDN)
_______________________________________________________
- name: vmess-$user-WS (CDN)
type: vmess
server: ${domain}
port: 443
uuid: ${uuid}
alterId: 0
cipher: auto
udp: true
tls: true
skip-cert-verify: true
servername: ${domain}
network: ws
ws-opts:
path: /vmess
headers:
Host: ${domain}
_______________________________________________________
Format Vmess WS (CDN) Non TLS
_______________________________________________________
- name: vmess-$user-WS (CDN) Non TLS
type: vmess
server: ${domain}
port: 80
uuid: ${uuid}
alterId: 0
cipher: auto
udp: true
tls: false
skip-cert-verify: false
servername: ${domain}
network: ws
ws-opts:
path: /vmess
headers:
Host: ${domain}
_______________________________________________________
Format Vmess gRPC (SNI)
_______________________________________________________
- name: vmess-$user-gRPC (SNI)
server: ${domain}
port: 443
type: vmess
uuid: ${uuid}
alterId: 0
cipher: auto
network: grpc
tls: true
servername: ${domain}
skip-cert-verify: true
grpc-opts:
grpc-service-name: vmess-grpc
_______________________________________________________
Format Vmess WS (CDN) Non TLS Opok TSEL
_______________________________________________________
- name: vmess-$user-WS (CDN) Non TLS
type: vmess
server: ${domain}
port: 80
uuid: ${uuid}
alterId: 0
cipher: auto
udp: true
tls: false
skip-cert-verify: true
servername: comunity.instagram.com
network: ws
ws-opts:
path: http://tsel.me/worryfree
headers:
Host: ${domain}
_______________________________________________________
Link Vmess Account
_______________________________________________________
Link TLS : vmess://$(echo $VMESS_WS | base64 -w 0)
_______________________________________________________
Link NTLS : vmess://$(echo $VMESS_NON_TLS | base64 -w 0)
_______________________________________________________
Link gRPC : vmess://$(echo $VMESS_GRPC | base64 -w 0)
_______________________________________________________
Link Opok : vmess://$(echo $VMESS_OPOK | base64 -w 0)
_______________________________________________________
END
TEXT="$(kn_text "Trial VMESS" "$user" "$timer minit" "$iplim IP" "")"
kn_send "$TEXT"
cd
if [ ! -e /etc/tele ]; then
echo -ne
else
echo "$TEXT" > /etc/notiftele
bash /etc/tele
fi
clear
{
kn_top
kn_title "TRIAL VMESS ACCOUNT"
kn_mid
kn_row "User" "${user}"
kn_row "Domain" "${domain}"
kn_row "Lokasi" "${CITY} - ${ISP}"
kn_row "Had IP" "${iplim} IP"
kn_row "Tamat" "${timer} minit"
kn_mid
kn_row "Port TLS" "443"
kn_row "Port NTLS" "80, 8080"
kn_row "Port gRPC" "443"
kn_row "AlterId" "0"
kn_row "Security" "auto"
kn_row "Path" "/vmess"
kn_row "Path bug" "http://bug/vmess"
kn_row "Service" "vmess-grpc"
kn_link "UUID" "${uuid}"
kn_mid
kn_link "Link WS TLS" "${vmesslink1}"
kn_link "Link WS NTLS" "${vmesslink2}"
kn_link "Link gRPC" "${vmesslink3}"
kn_link "Format OpenClash" "http://$domain:89/vmess-$user.txt"
kn_foot
echo ""
} | tee -a /etc/vmess/akun/log-create-${user}.log
systemctl restart xray > /dev/null 2>&1
read -n 1 -s -r -p "Press any key to back on menu"
menu
}
function renew-vmess(){
clear
NUMBER_OF_CLIENTS=$(grep -c -E "^#vmg " "/etc/xray/config.json")
if [[ ${NUMBER_OF_CLIENTS} == '0' ]]; then
clear
kn_top
kn_title "Renew Vmess Account"
kn_mid
echo ""
echo "You have no existing clients!"
echo ""
kn_bot
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-vmess
fi
kn_top
kn_title "Renew Vmess Account"
kn_mid
kn_item1 "0" "Kembali ke menu"
kn_mid
kn_userlist "^#vmg " "/etc/xray/config.json"
kn_bot
until [[ ${CLIENT_NUMBER} -ge 1 && ${CLIENT_NUMBER} -le ${NUMBER_OF_CLIENTS} ]]; do
if [[ ${CLIENT_NUMBER} == '1' ]]; then
read -rp "Select one client [1]: " CLIENT_NUMBER
else
read -rp "Select one client [1-${NUMBER_OF_CLIENTS}]: " CLIENT_NUMBER
if [[ ${CLIENT_NUMBER} == '0' ]]; then
m-vmess
fi
fi
done
read -p "Expired (days): " masaaktif
user=$(grep -E "^#vmg " "/etc/xray/config.json" | cut -d ' ' -f 2 | sed -n "${CLIENT_NUMBER}"p)
exp=$(grep -E "^#vmg " "/etc/xray/config.json" | cut -d ' ' -f 3 | sed -n "${CLIENT_NUMBER}"p)
now=$(date +%Y-%m-%d)
d1=$(date -d "$exp" +%s)
d2=$(date -d "$now" +%s)
exp2=$(( (d1 - d2) / 86400 ))
exp3=$(($exp2 + $masaaktif))
exp4=`date -d "$exp3 days" +"%Y-%m-%d"`
sed -i "s/#vm $user $exp/#vm $user $exp4/g" /etc/xray/config.json
sed -i "s/#vmg $user $exp/#vmg $user $exp4/g" /etc/xray/config.json
clear
TEXT="
<code>◇━━━━━━━━━━━━━━◇</code>
<b>   XRAY VMESS RENEW</b>
<code>◇━━━━━━━━━━━━━━◇</code>
<b>DOMAIN   :</b> <code>${domain} </code>
<b>ISP      :</b> <code>$ISP $CITY </code>
<b>USERNAME :</b> <code>$user </code>
<b>EXPIRED  :</b> <code>$exp4 </code>
<code>◇━━━━━━━━━━━━━━◇</code>
"
curl -s --max-time $TIMES -d "chat_id=$CHATID&disable_web_page_preview=1&text=$TEXT&parse_mode=html" $URL >/dev/null
cd
if [ ! -e /etc/tele ]; then
echo -ne
else
echo "$TEXT" > /etc/notiftele
bash /etc/tele
fi
user2=$(echo "$user" | cut -c 1-3)
TIME2=$(date +'%Y-%m-%d %H:%M:%S')
TEXT2="
<code>◇━━━━━━━━━━━━━━◇</code>
<b>   PEMBELIAN VMESS SUCCES </b>
<code>◇━━━━━━━━━━━━━━◇</code>
<b>DOMAIN   :</b> <code>${domain} </code>
<b>ISP      :</b> <code>$ISP $CITY </code>
<b>DATE   :</b> <code>${TIME2} WIB </code>
<b>DETAIL   :</b> <code>Trx VMESS </code>
<b>USER :</b> <code>${user2}xxx </code>
<b>DURASI  :</b> <code>$masaaktif Hari </code>
<code>◇━━━━━━━━━━━━━━◇</code>
<i> Renew Account From Server..</i>
"
curl -s --max-time $TIMES -d "chat_id=$CHATID2&disable_web_page_preview=1&text=$TEXT2&parse_mode=html" $URL2 >/dev/null
systemctl restart xray > /dev/null 2>&1
clear
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo " VMESS Account Was Successfully Renewed"
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo " Client Name : $user"
echo " Expired On  : $exp4"
echo ""
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-vmess
}
function limit-vmess(){
clear
NUMBER_OF_CLIENTS=$(grep -c -E "^#vmg " "/etc/xray/config.json")
if [[ ${NUMBER_OF_CLIENTS} == '0' ]]; then
clear
kn_top
kn_title "Limit Vmess Account"
kn_mid
echo ""
echo "You have no existing clients!"
echo ""
kn_bot
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-vmess
fi
kn_top
kn_title "Limit Vmess Account"
kn_mid
kn_item1 "0" "Kembali ke menu"
kn_mid
kn_userlist "^#vmg " "/etc/xray/config.json"
kn_bot
until [[ ${CLIENT_NUMBER} -ge 1 && ${CLIENT_NUMBER} -le ${NUMBER_OF_CLIENTS} ]]; do
if [[ ${CLIENT_NUMBER} == '1' ]]; then
read -rp "Select one client [1]: " CLIENT_NUMBER
else
read -rp "Select one client [1-${NUMBER_OF_CLIENTS}]: " CLIENT_NUMBER
if [[ ${CLIENT_NUMBER} == '0' ]]; then
m-vmess
fi
fi
done
clear
until [[ $iplim =~ ^[0-9]+$ ]]; do
read -p "Limit User (IP) or 0 Unlimited: " iplim
done
until [[ $Quota =~ ^[0-9]+$ ]]; do
read -p "Limit User (GB) or 0 Unlimited: " Quota
done
if [ ! -e /etc/vmess ]; then
mkdir -p /etc/vmess
fi
if [ ${iplim} = '0' ]; then
iplim="9999"
fi
if [ ${Quota} = '0' ]; then
Quota="9999"
fi
user=$(grep -E "^#vmg " "/etc/xray/config.json" | cut -d ' ' -f 2 | sed -n "${CLIENT_NUMBER}"p)
echo "${iplim}" >/etc/vmess/${user}IP
c=$(echo "${Quota}" | sed 's/[^0-9]*//g')
d=$((${c} * 1024 * 1024 * 1024))
if [[ ${c} != "0" ]]; then
echo "${d}" >/etc/vmess/${user}
fi
TEXT="
<code>◇━━━━━━━━━━━━━━◇</code>
<b>  XRAY VMESS IP LIMIT</b>
<code>◇━━━━━━━━━━━━━━◇</code>
<b>DOMAIN   :</b> <code>${domain} </code>
<b>ISP      :</b> <code>$ISP $CITY </code>
<b>USERNAME :</b> <code>$user </code>
<b>IP LIMIT NEW :</b> <code>$iplim IP </code>
<b>QUOTA LIMIT NEW :</b> <code>$Quota GB </code>
<code>◇━━━━━━━━━━━━━━◇</code>
<i>Succes Change this Limit...</i>
"
curl -s --max-time $TIMES -d "chat_id=$CHATID&disable_web_page_preview=1&text=$TEXT&parse_mode=html" $URL >/dev/null
cd
if [ ! -e /etc/tele ]; then
echo -ne
else
echo "$TEXT" > /etc/notiftele
bash /etc/tele
fi
clear
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo " VMESS Account Was Successfully Change Limit IP"
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo " Client Name : $user"
echo " Limit IP    : $iplim IP"
echo " Limit Quota : $Quota GB"
echo ""
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-vmess
}
function del-vmess(){
clear
NUMBER_OF_CLIENTS=$(grep -c -E "^#vmg " "/etc/xray/config.json")
if [[ ${NUMBER_OF_CLIENTS} == '0' ]]; then
kn_top
kn_title "Delete Vmess Account"
kn_mid
echo ""
echo "You have no existing clients!"
echo ""
kn_bot
read -n 1 -s -r -p "Press any key to back on menu"
m-vmess
fi
clear
kn_top
kn_title "Delete Vmess Account"
kn_mid
kn_item1 "0" "Kembali ke menu"
kn_mid
kn_userlist "^#vmg " "/etc/xray/config.json"
kn_bot
until [[ ${CLIENT_NUMBER} -ge 1 && ${CLIENT_NUMBER} -le ${NUMBER_OF_CLIENTS} ]]; do
if [[ ${CLIENT_NUMBER} == '1' ]]; then
read -rp "Select one client [1]: " CLIENT_NUMBER
else
read -rp "Select one client [1-${NUMBER_OF_CLIENTS}]: " CLIENT_NUMBER
if [[ ${CLIENT_NUMBER} == '0' ]]; then
m-vmess
fi
fi
done
user=$(grep -E "^#vmg " "/etc/xray/config.json" | cut -d ' ' -f 2 | sed -n "${CLIENT_NUMBER}"p)
exp=$(grep -E "^#vmg " "/etc/xray/config.json" | cut -d ' ' -f 3 | sed -n "${CLIENT_NUMBER}"p)
uuid=$(grep -E "^#vmg " "/etc/xray/config.json" | cut -d ' ' -f 4 | sed -n "${CLIENT_NUMBER}"p)
if [ ! -e /etc/vmess/akundelete ]; then
echo "" > /etc/vmess/akundelete
fi
clear
echo "### $user $exp $uuid" >> /etc/vmess/akundelete
sed -i "/^#vmg $user $exp/,/^},{/d" /etc/xray/config.json
sed -i "/^#vm $user $exp/,/^},{/d" /etc/xray/config.json
rm /etc/vmess/${user}IP
clear
rm /home/vps/public_html/vmess-$user.txt >/dev/null 2>&1
rm /etc/vmess/${user}IP >/dev/null 2>&1
rm /etc/vmess/${user}login >/dev/null 2>&1
systemctl restart xray > /dev/null 2>&1
clear
TEXT="
<code>◇━━━━━━━━━━━━━━◇</code>
<b>  XRAY VMESS DELETE</b>
<code>◇━━━━━━━━━━━━━━◇</code>
<b>DOMAIN   :</b> <code>${domain} </code>
<b>ISP      :</b> <code>$ISP $CITY </code>
<b>USERNAME :</b> <code>$user </code>
<b>EXPIRED :</b> <code>$exp </code>
<code>◇━━━━━━━━━━━━━━◇</code>
<i>Succes Delete this Username...</i>
"
curl -s --max-time $TIMES -d "chat_id=$CHATID&disable_web_page_preview=1&text=$TEXT&parse_mode=html" $URL >/dev/null
cd
if [ ! -e /etc/tele ]; then
echo -ne
else
echo "$TEXT" > /etc/notiftele
bash /etc/tele
fi
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo " Vmess Account Deleted Successfully"
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo " Client Name : $user"
echo " Expired On  : $exp"
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-vmess
}
tim2sec() {
mult=1
arg="$1"
inu=0
while [ ${#arg} -gt 0 ]; do
prev="${arg%:*}"
if [ "$prev" = "$arg" ]; then
curr="${arg#0}"
prev=""
else
curr="${arg##*:}"
curr="${curr#0}"
fi
curr="${curr%.*}"
inu=$((inu + curr * mult))
mult=$((mult * 60))
arg="$prev"
done
echo "$inu"
}
function convert() {
local -i bytes=$1
if [[ $bytes -lt 1024 ]]; then
echo "${bytes} B"
elif [[ $bytes -lt 1048576 ]]; then
echo "$(((bytes + 1023) / 1024)) KB"
elif [[ $bytes -lt 1073741824 ]]; then
echo "$(((bytes + 1048575) / 1048576)) MB"
else
echo "$(((bytes + 1073741823) / 1073741824)) GB"
fi
}
function cek-vmess() {
    clear

    # ANSI Color Codes
    COLOR_RESET="\e[0m"
    COLOR_GREEN="\e[32m"
    COLOR_RED="\e[31m"
    COLOR_YELLOW="\e[33m"
    COLOR_CYAN="\e[36m"
    COLOR_WHITE="\e[37m"

    # Restart Xray jika log kurang dari 5
    xrayy=$(cat /var/log/xray/access.log | wc -l)
    [[ $xrayy -le 5 ]] && systemctl restart xray

    xraylimit

    # Mendapatkan daftar semua pengguna vmess
    vm=($(cat /etc/xray/config.json | grep "^#vmg" | awk '{print $2}' | sort -u))

    # Proses data dan tampilkan
    if [[ ${#vm[@]} -eq 0 ]]; then
        echo -e "${COLOR_WHITE}┌──────────────────────────────────────────────────────────┐${COLOR_RESET}"
        echo -e "${COLOR_WHITE}│                  Tidak ada pengguna VMESS                │${COLOR_RESET}"
        echo -e "${COLOR_WHITE}└──────────────────────────────────────────────────────────┘${COLOR_RESET}"
    else
        for user in "${vm[@]}"; do
            # Mendapatkan data penggunaan
            used_bytes=$(cat /etc/limit/vmess/"${user}" 2>/dev/null || echo 0)
            limit_bytes=$(cat /etc/vmess/"${user}" 2>/dev/null || echo 0)

            # Konversi bytes ke GB
            used_gb=$(awk "BEGIN {printf \"%.2f\", $used_bytes / 1024^3}")
            limit_gb=$(awk "BEGIN {printf \"%.2f\", $limit_bytes / 1024^3}")

            # Menghitung sisa kuota
            if [[ "$limit_bytes" -gt 0 ]]; then
                remaining_gb=$(awk "BEGIN {printf \"%.2f\", ($limit_bytes - $used_bytes) / 1024^3}")
            else
                remaining_gb="Unlimited"
            fi

            # Cek status online (logika yang lebih spesifik)
            # Periksa log 100 baris terakhir untuk aktivitas
            last_activity=$(grep -w "email: ${user}" /var/log/xray/access.log | tail -n 1)
            is_online=false
            if [[ -n "$last_activity" ]]; then
                # Dapatkan timestamp dari log
                timestamp_log=$(echo "$last_activity" | awk '{print $2}')

                # Konversi timestamp ke detik
                timestamp_sec=$(date -d "${timestamp_log}" +%s)

                # Waktu sekarang dalam detik
                now_sec=$(date +%s)

                # Jika aktivitas kurang dari 120 detik (2 menit) lalu
                if (( (now_sec - timestamp_sec) < 120 )); then
                    is_online=true
                fi
            fi

            # Tentukan status dan warna
            if $is_online; then
                status_symbol="${COLOR_GREEN}● Online${COLOR_RESET}"
            else
                status_symbol="${COLOR_RED}● Offline${COLOR_RESET}"
            fi

            # Dapatkan IP login (logika sederhana, mungkin perlu disesuaikan)
            login_ip_count=$(grep -w "email: ${user}" /var/log/xray/access.log | awk '{print $3}' | sed 's/tcp:\/\///g' | sort -u | wc -l)

            # Tampilkan output
            echo -e "${COLOR_WHITE}┌─${COLOR_CYAN}[ ${user} ${COLOR_WHITE}| Tipe: vmess ]─┐${COLOR_RESET}"
            echo -e "${COLOR_WHITE}│${COLOR_RESET} 🚦 Status      : ${status_symbol}"
            echo -e "${COLOR_WHITE}│${COLOR_RESET} 📥 Terpakai    : ${COLOR_YELLOW}${used_gb}GB${COLOR_RESET}"
            echo -e "${COLOR_WHITE}│${COLOR_RESET} 📈 Batas Kuota : ${COLOR_GREEN}${limit_gb}GB${COLOR_RESET}"
            echo -e "${COLOR_WHITE}│${COLOR_RESET} 📊 Sisa Kuota  : ${COLOR_CYAN}${remaining_gb}GB${COLOR_RESET}"
            echo -e "${COLOR_WHITE}│${COLOR_RESET} 💻 Login IP    : ${COLOR_WHITE}${login_ip_count}${COLOR_RESET}"
            echo -e "${COLOR_WHITE}└───────────────────────────────────────────────┘${COLOR_RESET}"
            echo ""
        done
    fi

    read -n 1 -s -r -p "     Press any key to back on menu"
    m-vmess
}
function list-vmess(){
clear
NUMBER_OF_CLIENTS=$(grep -c -E "^#vmg " "/etc/xray/config.json")
if [[ ${NUMBER_OF_CLIENTS} == '0' ]]; then
clear
kn_top
kn_title "Config Vmess Account"
kn_mid
echo ""
echo "You have no existing clients!"
echo ""
kn_bot
read -n 1 -s -r -p "Press any key to back on menu"
m-vmess
fi
clear
echo ""
kn_top
kn_title "Config Vmess Account"
kn_mid
kn_item1 "0" "Kembali ke menu"
kn_mid
kn_userlist "^#vmg " "/etc/xray/config.json"
kn_bot
until [[ ${CLIENT_NUMBER} -ge 1 && ${CLIENT_NUMBER} -le ${NUMBER_OF_CLIENTS} ]]; do
if [[ ${CLIENT_NUMBER} == '1' ]]; then
read -rp "Select one client [1]: " CLIENT_NUMBER
else
read -rp "Select one client [1-${NUMBER_OF_CLIENTS}]: " CLIENT_NUMBER
if [[ ${CLIENT_NUMBER} == '0' ]]; then
m-vmess
fi
fi
done
clear
user=$(grep -E "^#vmg " "/etc/xray/config.json" | cut -d ' ' -f 2 | sed -n "${CLIENT_NUMBER}"p)
# kn telco filter
uuid=$(grep -A1 "^#vm $user " /etc/xray/config.json | grep -o '"id": *"[^"]*"' | head -1 | cut -d '"' -f 4)
[ -s "$telco_conf" ] || telco_init
if [ -s "$telco_conf" ] && [ -n "$uuid" ]; then
ti=0
kn_top
kn_title "TAPIS IKUT TELCO"
kn_mid
while IFS='|' read -r tn _; do
[[ -z $tn || $tn == \#* ]] && continue
ti=$((ti+1))
kn_item1 "$ti" "$tn"
done < $telco_conf
kn_item1 "0" "Semua (config penuh)"
kn_bot
tf=""
read -rp " Pilih telco (Enter = config penuh): " tf
if [[ $tf =~ ^[1-9][0-9]*$ && $tf -le $ti ]]; then
clear
tl="$(telco_links "$uuid" "$user" "$tf")"
if [ -n "$tl" ]; then
IFS='|' read -r tname turl <<< "$tl"
kn_top
kn_title "LINK TELCO"
kn_mid
kn_row "User" "$user"
kn_row "Telco" "$tname"
kn_link "Link $tname" "$turl"
kn_foot
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-vmess
return
fi
fi
clear
fi
cat /etc/vmess/akun/log-create-${user}.log
cat /etc/vmess/akun/log-create-${user}.log > /etc/notifakun
sed -i 's/\x1B\[1;37m//g' /etc/notifakun
sed -i 's/\x1B\[0;96m//g' /etc/notifakun
sed -i 's/\x1B\[0m//g' /etc/notifakun
TEXT=$(cat /etc/notifakun)
curl -s --max-time $TIMES -d "chat_id=$CHATID&disable_web_page_preview=1&text=$TEXT&parse_mode=html" $URL >/dev/null
cd
if [ ! -e /etc/tele ]; then
echo -ne
else
echo "$TEXT" > /etc/notiftele
bash /etc/tele
fi
read -n 1 -s -r -p "Press any key to back on menu"
m-vmess
}
clear
function login-vmess(){
clear
echo -e "$COLOR1┌──────────────────────────────────────────┐${NC}"
echo -e "$COLOR1│ \033[1;37mPlease select a your Choice              $COLOR1│${NC}"
echo -e "$COLOR1└──────────────────────────────────────────┘${NC}"
echo -e "$COLOR1┌──────────────────────────────────────────┐${NC}"
echo -e "$COLOR1│  [ 1 ]  \033[1;37mAUTO LOCKED USER ALL XRAY      ${NC}"
echo -e "$COLOR1│  "
echo -e "$COLOR1│  [ 2 ]  \033[1;37mAUTO DELETE USER ALL XRAY    ${NC}"
echo -e "$COLOR1│  "
echo -e "$COLOR1│  "
echo -e "$COLOR1│  [ 0 ]  \033[1;37mBACK TO MENU    ${NC}"
echo -e "$COLOR1└──────────────────────────────────────────┘${NC}"
until [[ $lock =~ ^[0-2]+$ ]]; do
read -p "   Please select numbers 1 sampai 2 : " lock
done
if [[ $lock == "0" ]]; then
menu
elif [[ $lock == "1" ]]; then
clear
echo "lock" > /etc/typexray
kn_top
kn_title "SETTING MULTI LOGIN"
kn_mid
kn_item1 "0" "Kembali ke menu"
kn_mid
sleep 1
elif [[ $lock == "2" ]]; then
clear
echo "delete" > /etc/typexray
kn_top
kn_title "SETTING MULTI LOGIN"
kn_mid
kn_item1 "0" "Kembali ke menu"
kn_mid
sleep 1
fi
type=$(cat /etc/typexray)
if [ $type = "lock" ]; then
clear
kn_top
kn_title "SETTING MULTI LOGIN"
kn_mid
kn_item1 "0" "Kembali ke menu"
kn_mid
read -rp "   Jumlah Waktu Lock: " -e notif2
echo "${notif2}" > /etc/waktulock
clear
kn_top
kn_title "SETTING MULTI LOGIN"
kn_bot
echo -e "$COLOR1┌───────────────────────────────────────────────┐${NC}"
echo -e "${COLOR1}│ $NC SILAHKAN TULIS JUMLAH NOTIFIKASI UNTUK AUTO LOCK    ${NC}"
echo -e "${COLOR1}│ $NC AKUN USER YANG MULTI LOGIN     ${NC}"
echo -e "$COLOR1└───────────────────────────────────────────────┘${NC}"
read -rp "   Jika Mau 3x Notif baru kelock tulis 3, dst: " -e notif
echo "$notif" > /etc/vless/notif
echo "$notif" > /etc/vmess/notif
echo "$notif" > /etc/trojan/notif
clear
kn_top
kn_title "SETTING MULTI LOGIN"
kn_bot
echo -e "$COLOR1┌───────────────────────────────────────────────┐${NC}"
echo -e "${COLOR1}│ $NC SUCCES GANTI NOTIF LOCK JADI $notif $NC "
echo -e "${COLOR1}│ $NC SUCCES GANTI TIME NOTIF LOCK JADI $notif2 MENIT $NC "
echo -e "$COLOR1└───────────────────────────────────────────────┘${NC}"
else
kn_top
kn_title "SETTING MULTI LOGIN"
kn_bot
echo -e "$COLOR1┌───────────────────────────────────────────────┐${NC}"
echo -e "${COLOR1}│ $NC SILAHKAN TULIS JUMLAH WAKTU UNTUK USER YANG MULTI LOGIN   ${NC}"
echo -e "${COLOR1}│ $NC TIAP MENIT JADI NOTIF TIAP BEBERAPA MENIT. ${NC}"
echo -e "$COLOR1└───────────────────────────────────────────────┘${NC}"
read -rp "   Jika Mau 3menit baru keNotif tulis 3, dst: " -e notif2
echo "# Autokill" >/etc/cron.d/xraylimit
echo "SHELL=/bin/sh" >>/etc/cron.d/xraylimit
echo "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin" >>/etc/cron.d/xraylimit
echo "*/$notif2 * * * *  root /usr/bin/xraylimit" >>/etc/cron.d/xraylimit
clear
kn_top
kn_title "SETTING MULTI LOGIN"
kn_bot
echo -e "$COLOR1┌───────────────────────────────────────────────┐${NC}"
echo -e "${COLOR1} $NC SILAHKAN TULIS JUMLAH NOTIFIKASI UNTUK LOCK    ${NC}"
echo -e "${COLOR1} $NC AKUN USER YANG MULTI LOGIN     ${NC}"
echo -e "$COLOR1└───────────────────────────────────────────────┘${NC}"
read -rp "   Jika Mau 3x Notif baru kelock tulis 3, dst: " -e notif
echo "$notif" > /etc/vless/notif
echo "$notif" > /etc/vmess/notif
echo "$notif" > /etc/trojan/notif
clear
kn_top
kn_title "SETTING MULTI LOGIN"
kn_bot
echo -e "$COLOR1┌───────────────────────────────────────────────┐${NC}"
echo -e "${COLOR1}│ $NC SUCCES GANTI NOTIF LOCK JADI $notif $NC "
echo -e "${COLOR1}│ $NC SUCCES GANTI TIME NOTIF LOCK JADI $notif2 MENIT $NC "
echo -e "$COLOR1└───────────────────────────────────────────────┘${NC}"
fi
read -n 1 -s -r -p "Press any key to back on menu"
m-vmess
}
function lock-vmess(){
clear
cd
if [ ! -e /etc/vmess/listlock ]; then
echo "" > /etc/vmess/listlock
fi
NUMBER_OF_CLIENTS=$(grep -c -E "^### " "/etc/vmess/listlock")
if [[ ${NUMBER_OF_CLIENTS} == '0' ]]; then
kn_top
kn_title "Unlock Vmess Account"
kn_mid
echo ""
echo "You have no existing user Lock!"
echo ""
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
read -n 1 -s -r -p "Press any key to back on menu"
m-vmess
fi
clear
kn_top
kn_title "Unlock Vmess Account"
kn_mid
kn_item1 "0" "Kembali ke menu"
kn_item1 "999" "Padam semua akaun"
kn_mid
kn_userlist "^### " "/etc/vmess/listlock"
kn_bot
until [[ ${CLIENT_NUMBER} -ge 1 && ${CLIENT_NUMBER} -le ${NUMBER_OF_CLIENTS} ]]; do
if [[ ${CLIENT_NUMBER} == '1' ]]; then
read -rp "Select one client [1]: " CLIENT_NUMBER
else
read -rp "Select one client [1-${NUMBER_OF_CLIENTS}] to Unlock: " CLIENT_NUMBER
if [[ ${CLIENT_NUMBER} == '0' ]]; then
m-vmess
fi
if [[ ${CLIENT_NUMBER} == '999' ]]; then
rm /etc/vmess/listlock
m-vmess
fi
fi
done
user=$(grep -E "^### " "/etc/vmess/listlock" | cut -d ' ' -f 2 | sed -n "${CLIENT_NUMBER}"p)
exp=$(grep -E "^### " "/etc/vmess/listlock" | cut -d ' ' -f 3 | sed -n "${CLIENT_NUMBER}"p)
uuid=$(grep -E "^### " "/etc/vmess/listlock" | cut -d ' ' -f 4 | sed -n "${CLIENT_NUMBER}"p)
sed -i '/#vmess$/a\#vm '"$user $exp"'\
},{"id": "'""$uuid""'","alterId": '"0"',"email": "'""$user""'"' /etc/xray/config.json
sed -i '/#vmessgrpc$/a\#vmg '"$user $exp $uuid"'\
},{"id": "'""$uuid""'","alterId": '"0"',"email": "'""$user""'"' /etc/xray/config.json
sed -i "/^### $user $exp $uuid/d" /etc/vmess/listlock
systemctl restart xray
TEXT="
<code>◇━━━━━━━━━━━━━━◇</code>
<b>  XRAY VMESS UNLOCKED</b>
<code>◇━━━━━━━━━━━━━━◇</code>
<b>DOMAIN   :</b> <code>${domain} </code>
<b>ISP      :</b> <code>$ISP $CITY </code>
<b>USERNAME :</b> <code>$user </code>
<b>EXPIRED  :</b> <code>$exp </code>
<code>◇━━━━━━━━━━━━━━◇</code>
<i>Succes Unlocked This Akun...</i>
"
curl -s --max-time $TIMES -d "chat_id=$CHATID&disable_web_page_preview=1&text=$TEXT&parse_mode=html" $URL >/dev/null
cd
if [ ! -e /etc/tele ]; then
echo -ne
else
echo "$TEXT" > /etc/notiftele
bash /etc/tele
fi
clear
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo " Vmess Account Unlock Successfully"
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo " Client Name : $user"
echo " Status  : Unlocked"
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-vmess
}
function res-user(){
clear
cd
if [ ! -e /etc/vmess/akundelete ]; then
echo "" > /etc/vmess/akundelete
fi
clear
NUMBER_OF_CLIENTS=$(grep -c -E "^### " "/etc/vmess/akundelete")
if [[ ${NUMBER_OF_CLIENTS} == '0' ]]; then
kn_top
kn_title "Restore Vmess Account"
kn_mid
echo ""
echo "You have no existing user Expired!"
echo ""
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
read -n 1 -s -r -p "Press any key to back on menu"
m-vmess
fi
clear
kn_top
kn_title "Restore Vmess Account"
kn_mid
kn_item1 "0" "Kembali ke menu"
kn_item1 "999" "Padam semua akaun"
kn_mid
kn_userlist "^### " "/etc/vmess/akundelete"
kn_bot
until [[ ${CLIENT_NUMBER} -ge 1 && ${CLIENT_NUMBER} -le ${NUMBER_OF_CLIENTS} ]]; do
if [[ ${CLIENT_NUMBER} == '1' ]]; then
read -rp "Select one client [1]: " CLIENT_NUMBER
else
read -rp "Select one client [1-${NUMBER_OF_CLIENTS}] to Unlock: " CLIENT_NUMBER
if [[ ${CLIENT_NUMBER} == '0' ]]; then
m-vmess
fi
if [[ ${CLIENT_NUMBER} == '999' ]]; then
rm /etc/vmess/akundelete
m-vmess
fi
fi
done
until [[ $masaaktif =~ ^[0-9]+$ ]]; do
read -p "Expired (days): " masaaktif
done
until [[ $iplim =~ ^[0-9]+$ ]]; do
read -p "Limit User (IP) or 0 Unlimited: " iplim
done
until [[ $Quota =~ ^[0-9]+$ ]]; do
read -p "Limit Quota (GB) or 0 Unlimited: " Quota
done
if [ ${iplim} = '0' ]; then
iplim="9999"
fi
if [ ${Quota} = '0' ]; then
Quota="9999"
fi
user=$(grep -E "^### " "/etc/vmess/akundelete" | cut -d ' ' -f 2 | sed -n "${CLIENT_NUMBER}"p)
exp=`date -d "$masaaktif days" +"%Y-%m-%d"`
uuid=$(grep -E "^### " "/etc/vmess/akundelete" | cut -d ' ' -f 4 | sed -n "${CLIENT_NUMBER}"p)
sed -i '/#vmess$/a\#vm '"$user $exp"'\
},{"id": "'""$uuid""'","alterId": '"0"',"email": "'""$user""'"' /etc/xray/config.json
sed -i '/#vmessgrpc$/a\#vmg '"$user $exp $uuid"'\
},{"id": "'""$uuid""'","alterId": '"0"',"email": "'""$user""'"' /etc/xray/config.json
echo "${iplim}" >/etc/vmess/${user}IP
c=$(echo "${Quota}" | sed 's/[^0-9]*//g')
d=$((${c} * 1024 * 1024 * 1024))
if [[ ${c} != "0" ]]; then
echo "${d}" >/etc/vmess/${user}
fi
sed -i "/### ${user} ${exp} ${uuid}/d" /etc/vmess/akundelete
systemctl restart xray
TEXT="
<code>◇━━━━━━━━━━━━━━◇</code>
<b>  XRAY VMESS RESTORE</b>
<code>◇━━━━━━━━━━━━━━◇</code>
<b>DOMAIN   :</b> <code>${domain} </code>
<b>ISP      :</b> <code>$ISP $CITY </code>
<b>USERNAME :</b> <code>$user </code>
<b>IP LIMIT  :</b> <code>$iplim IP </code>
<b>Quota LIMIT  :</b> <code>$Quota GB </code>
<b>EXPIRED  :</b> <code>$exp </code>
<code>◇━━━━━━━━━━━━━━◇</code>
<i>Succes Restore This Akun...</i>
"
curl -s --max-time $TIMES -d "chat_id=$CHATID&disable_web_page_preview=1&text=$TEXT&parse_mode=html" $URL >/dev/null
cd
if [ ! -e /etc/tele ]; then
echo -ne
else
echo "$TEXT" > /etc/notiftele
bash /etc/tele
fi
clear
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo " Vmess Account Restore Successfully"
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo " DOMAIN : $domain"
echo " ISP  : $ISP $CITY"
echo " USERNAME : $user"
echo " IP LIMIT : $iplim IP"
echo " EXPIRED  : $exp"
echo " Succes to Restore"
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-vmess
}
function quota-user(){
clear
cd
if [ ! -e /etc/vmess/userQuota ]; then
echo "" > /etc/vmess/userQuota
fi
NUMBER_OF_CLIENTS=$(grep -c -E "^### " "/etc/vmess/userQuota")
if [[ ${NUMBER_OF_CLIENTS} == '0' ]]; then
kn_top
kn_title "Unlock Vmess Account"
kn_mid
echo ""
echo "You have no existing user Lock!"
echo ""
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
read -n 1 -s -r -p "Press any key to back on menu"
m-vmess
fi
clear
kn_top
kn_title "Unlock Vmess Account"
kn_mid
kn_item1 "0" "Kembali ke menu"
kn_item1 "999" "Padam semua akaun"
kn_mid
kn_userlist "^### " "/etc/vmess/userQuota"
kn_bot
until [[ ${CLIENT_NUMBER} -ge 1 && ${CLIENT_NUMBER} -le ${NUMBER_OF_CLIENTS} ]]; do
if [[ ${CLIENT_NUMBER} == '1' ]]; then
read -rp "Select one client [1]: " CLIENT_NUMBER
else
read -rp "Select one client [1-${NUMBER_OF_CLIENTS}] to Unlock: " CLIENT_NUMBER
if [[ ${CLIENT_NUMBER} == '0' ]]; then
m-vmess
fi
if [[ ${CLIENT_NUMBER} == '999' ]]; then
rm /etc/vmess/userQuota
m-vmess
fi
fi
done
user=$(grep -E "^### " "/etc/vmess/userQuota" | cut -d ' ' -f 2 | sed -n "${CLIENT_NUMBER}"p)
exp=$(grep -E "^### " "/etc/vmess/userQuota" | cut -d ' ' -f 3 | sed -n "${CLIENT_NUMBER}"p)
uuid=$(grep -E "^### " "/etc/vmess/userQuota" | cut -d ' ' -f 4 | sed -n "${CLIENT_NUMBER}"p)
sed -i '/#vmess$/a\#vm '"$user $exp"'\
},{"id": "'""$uuid""'","alterId": '"0"',"email": "'""$user""'"' /etc/xray/config.json
sed -i '/#vmessgrpc$/a\#vmg '"$user $exp $uuid"'\
},{"id": "'""$uuid""'","alterId": '"0"',"email": "'""$user""'"' /etc/xray/config.json
sed -i "/^### $user $exp $uuid/d" /etc/vmess/userQuota
systemctl restart xray
TEXT="
<code>◇━━━━━━━━━━━━━━◇</code>
<b>  XRAY VMESS UNLOCKED</b>
<code>◇━━━━━━━━━━━━━━◇</code>
<b>DOMAIN   :</b> <code>${domain} </code>
<b>ISP      :</b> <code>$ISP $CITY </code>
<b>USERNAME :</b> <code>$user </code>
<b>EXPIRED  :</b> <code>$exp </code>
<code>◇━━━━━━━━━━━━━━◇</code>
<i>Succes Unlocked This Akun...</i>
"
curl -s --max-time $TIMES -d "chat_id=$CHATID&disable_web_page_preview=1&text=$TEXT&parse_mode=html" $URL >/dev/null
cd
if [ ! -e /etc/tele ]; then
echo -ne
else
echo "$TEXT" > /etc/notiftele
bash /etc/tele
fi
clear
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo " Vmess Account Unlock Successfully"
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo " Client Name : $user"
echo " Status  : Unlocked"
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-vmess
}
clear
kn_top
kn_title "VMESS PANEL MENU"
kn_mid
kn_item1 "01" "ADD AKUN"
kn_item1 "02" "TRIAL AKUN"
kn_item1 "03" "RENEW AKUN"
kn_item1 "04" "DELETE AKUN"
kn_item1 "05" "CEK USER LOGIN"
kn_item1 "06" "CEK USER CONFIG"
kn_item1 "07" "CHANGE USER LIMIT"
kn_item1 "08" "SETTING LOCK LOGIN"
kn_item1 "09" "UNLOCK USER LOGIN"
kn_item1 "10" "UNLOCK USER QUOTA"
kn_item1 "11" "RESTORE AKUN"
kn_item1 "00" "GO BACK"
kn_foot
echo ""
echo -e ""
echo -ne " ${WH}Select menu ${COLOR1}: ${WH}"; read opt
case $opt in
01 | 1) clear ; add-vmess ;;
02 | 2) clear ; trial-vmess ;;
03 | 3) clear ; renew-vmess ;;
04 | 4) clear ; del-vmess ;;
05 | 5) clear ; cek-vmess ;;
06 | 6) clear ; list-vmess ;;
07 | 7) clear ; limit-vmess ;;
08 | 8) clear ; login-vmess ;;
09 | 9) clear ; lock-vmess ;;
10 | 10) clear ; quota-user ;;
11 | 11) clear ; res-user ;;
00 | 0) clear ; menu ;;
*) clear ; m-vmess ;;
esac
