#!/bin/bash

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
permission_file=$(curl -s --connect-timeout 10 https://raw.githubusercontent.com/harusrakus-a11y/ijin/refs/heads/main/akses)

# Validasi file permission
if [ -z "$permission_file" ]; then
    echo -e "${RED}❌ Gagal mengambil data lisensi!${NC}"
    exit 1
fi

# Ambil IP VPS dengan metode alternatif
IP_VPS=$(curl -s ipv4.icanhazip.com)

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
if [ ! -e /etc/vless/akun ]; then
mkdir -p /etc/vless/akun
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
local u=$1 nm=$2 sel=$3 n=0 name addr host pth port
[ -z "$sel" ] && return
while IFS='|' read -r name addr host pth port; do
[[ -z $name || $name == \#* ]] && continue
n=$((n+1))
if [[ $sel != 0 && $sel != $n ]]; then continue; fi
addr=${addr//\{domain\}/$domain}
host=${host//\{domain\}/$domain}
pth=${pth:-/vless}
port=${port:-80}
echo "${name}|vless://${u}@${addr}:${port}?encryption=none&type=ws&host=${host}&headerType=none&path=${pth//\//%2F}#${nm}-${name}"
done < $telco_conf
}
function add-vless(){
clear
until [[ $user =~ ^[a-zA-Z0-9_.-]+$ && ${CLIENT_EXISTS} == '0' ]]; do
kn_top
kn_title "Add Vless Account"
kn_bot
echo -e ""
read -rp "User: " -e user
CLIENT_EXISTS=$(grep -w $user /etc/xray/config.json | wc -l)
if [[ ${CLIENT_EXISTS} == '1' ]]; then
clear
kn_top
kn_title "Add Vless Account"
kn_bot
echo -e "$COLOR1┌─────────────────────────────────────────────────┐${NC}"
echo -e "$COLOR1│                                                 │"
echo -e "$COLOR1│${WH} Nama Duplikat Silahkan Buat Nama Lain.          $COLOR1│"
echo -e "$COLOR1│                                                 │"
echo -e "$COLOR1└─────────────────────────────────────────────────┘${NC}"
read -n 1 -s -r -p "Press any key to back"
add-vless
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
if [ ! -e /etc/vless ]; then
mkdir -p /etc/vless
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
echo "${d}" >/etc/vless/${user}
fi
echo "${iplim}" >/etc/vless/${user}IP
exp=`date -d "$masaaktif days" +"%Y-%m-%d"`
sed -i '/#vless$/a\#vl '"$user $exp $uuid"'\
},{"id": "'""$uuid""'","email": "'""$user""'"' /etc/xray/config.json
sed -i '/#vlessgrpc$/a\#vlg '"$user $exp"'\
},{"id": "'""$uuid""'","email": "'""$user""'"' /etc/xray/config.json
vlesslink1="vless://${uuid}@${domain}:443?path=/vless&security=tls&encryption=none&host=${domain}&type=ws&sni=${domain}#${user}"
vlesslink2="vless://${uuid}@${domain}:80?path=/vless&security=none&encryption=none&host=${domain}&type=ws#${user}"
vlesslink3="vless://${uuid}@${domain}:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=vless-grpc&sni=${domain}#${user}"
vless1="vless://${uuid}@${domain}:443?path=/vless%26security=tls%26encryption=none%26host=${domain}%26type=ws%26sni=${domain}#${user}"
vless2="vless://${uuid}@${domain}:80?path=/vless%26security=none%26encryption=none%26host=${domain}%26type=ws#${user}"
vless3="vless://${uuid}@${domain}:443?mode=gun%26security=tls%26encryption=none%26type=grpc%26serviceName=vless-grpc%26sni=${domain}#${user}"
cat > /home/vps/public_html/vless-$user.txt <<-END
_______________________________
Format Vless WS (CDN)
_______________________________
- name: vless-$user-WS (CDN)
server: ${domain}
port: 443
type: vless
uuid: ${uuid}
cipher: auto
tls: true
skip-cert-verify: true
servername: ${domain}
network: ws
udp: true
ws-opts:
path: /vless
headers:
Host: ${domain}
_______________________________
Format Vless WS (CDN) Non TLS
_______________________________
- name: vless-$user-WS (CDN) Non TLS
server: ${domain}
port: 80
type: vless
uuid: ${uuid}
cipher: auto
tls: false
skip-cert-verify: false
servername: ${domain}
network: ws
ws-opts:
udp: true
path: /vless
headers:
Host: ${domain}
_______________________________
Format Vless gRPC (SNI)
_______________________________
- name: vless-$user-gRPC (SNI)
server: ${domain}
port: 443
type: vless
uuid: ${uuid}
cipher: auto
tls: true
skip-cert-verify: true
servername: ${domain}
network: grpc
grpc-opts:
grpc-mode: gun
grpc-service-name: vless-grpc
udp: true
_______________________________
Link Vless Account
_______________________________
Link TLS : vless://${uuid}@${domain}:443?path=/vless&security=tls&encryption=none&host=${domain}&type=ws&sni=${domain}#${user}
_______________________________
Link none TLS : vless://${uuid}@${domain}:80?path=/vless&security=none&encryption=none&host=${domain}&type=ws#${user}
_______________________________
Link GRPC : vless://${uuid}@${domain}:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=vless-grpc&sni=${domain}#${user}
_______________________________
END
telcolines="$(telco_links "$uuid" "$user" "$tsel")"
if [ -n "$telcolines" ]; then
while IFS='|' read -r tn tl; do
echo "Link ${tn} : ${tl}" >> /home/vps/public_html/vless-$user.txt
echo "_______________________________" >> /home/vps/public_html/vless-$user.txt
done <<< "$telcolines"
fi
TEXT="$(kn_text "VLESS" "$user" "$exp" "$iplim IP" "$Quota")"
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
kn_title "VLESS PREMIUM ACCOUNT"
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
kn_row "Path" "/vless"
kn_row "Service" "vless-grpc"
kn_link "UUID" "${uuid}"
kn_mid
kn_link "Link WS TLS" "${vlesslink1}"
kn_link "Link WS NTLS" "${vlesslink2}"
kn_link "Link gRPC" "${vlesslink3}"
if [ -n "$telcolines" ]; then
while IFS='|' read -r tn tl; do
kn_link "Link ${tn}" "${tl}"
done <<< "$telcolines"
fi
kn_link "Format OpenClash" "http://$domain:89/vless-$user.txt"
kn_foot
echo ""
} | tee -a /etc/vless/akun/log-create-${user}.log
mkdir -p /etc/vless/akun
cat > /etc/vless/akun/${user} << EOF
username=${user}
limit_quota=${Quota}GB
usage_quota=0MB
login_time=$(date +'%H:%M:%S.%N')
login_ip=0
EOF
systemctl restart xray > /dev/null 2>&1
read -n 1 -s -r -p "Press any key to back on menu"
menu
}
function trial-vless(){
clear
cd
kn_top
kn_title "Trial Vless Account"
kn_bot
until [[ $timer =~ ^[0-9]+$ ]]; do
read -p "Expired (Minutes): " timer
done
user=Trial-`</dev/urandom tr -dc X-Z0-9 | head -c4`
uuid=$(cat /proc/sys/kernel/random/uuid)
masaaktif=0
iplim=1
Quota=10
if [ ! -e /etc/vless ]; then
mkdir -p /etc/vless
fi
c=$(echo "${Quota}" | sed 's/[^0-9]*//g')
d=$((${c} * 1024 * 1024 * 1024))
if [[ ${c} != "0" ]]; then
echo "${d}" >/etc/vless/${user}
fi
echo "${iplim}" > /etc/vless/${user}IP
exp=`date -d "$masaaktif days" +"%Y-%m-%d"`
sed -i '/#vless$/a\#vl '"$user $exp $uuid"'\
},{"id": "'""$uuid""'","email": "'""$user""'"' /etc/xray/config.json
sed -i '/#vlessgrpc$/a\#vlg '"$user $exp"'\
},{"id": "'""$uuid""'","email": "'""$user""'"' /etc/xray/config.json
vlesslink1="vless://${uuid}@${domain}:443?path=/vless&security=tls&encryption=none&host=${domain}&type=ws&sni=${domain}#${user}"
vlesslink2="vless://${uuid}@${domain}:80?path=/vless&security=none&encryption=none&host=${domain}&type=ws#${user}"
vlesslink3="vless://${uuid}@${domain}:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=vless-grpc&sni=${domain}#${user}"
vless1="vless://${uuid}@${domain}:443?path=/vless%26security=tls%26encryption=none%26host=${domain}%26type=ws%26sni=${domain}#${user}"
vless2="vless://${uuid}@${domain}:80?path=/vless%26security=none%26encryption=none%26host=${domain}%26type=ws#${user}"
vless3="vless://${uuid}@${domain}:443?mode=gun%26security=tls%26encryption=none%26type=grpc%26serviceName=vless-grpc%26sni=${domain}#${user}"
clear
cat> /etc/cron.d/trialvless${user} << END
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
*/$timer * * * * root /usr/bin/trial vless $user $uuid $exp
END
cat > /home/vps/public_html/vless-$user.txt <<-END
_______________________________
Format Vless WS (CDN)
_______________________________
- name: vless-$user-WS (CDN)
server: ${domain}
port: 443
type: vless
uuid: ${uuid}
cipher: auto
tls: true
skip-cert-verify: true
servername: ${domain}
network: ws
udp: true
ws-opts:
path: /vless
headers:
Host: ${domain}
_______________________________
Format Vless WS (CDN) Non TLS
_______________________________
- name: vless-$user-WS (CDN) Non TLS
server: ${domain}
port: 80
type: vless
uuid: ${uuid}
cipher: auto
tls: false
skip-cert-verify: false
servername: ${domain}
network: ws
ws-opts:
udp: true
path: /vless
headers:
Host: ${domain}
_______________________________
Format Vless gRPC (SNI)
_______________________________
- name: vless-$user-gRPC (SNI)
server: ${domain}
port: 443
type: vless
uuid: ${uuid}
cipher: auto
tls: true
skip-cert-verify: true
servername: ${domain}
network: grpc
grpc-opts:
grpc-mode: gun
grpc-service-name: vless-grpc
udp: true
_______________________________
Link Vless Account
_______________________________
Link TLS : vless://${uuid}@${domain}:443?path=/vless&security=tls&encryption=none&host=${domain}&type=ws&sni=${domain}#${user}
_______________________________
Link NTLS : vless://${uuid}@${domain}:80?path=/vless&security=none&encryption=none&host=${domain}&type=ws#${user}
_______________________________
Link gRPC : vless://${uuid}@${domain}:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=vless-grpc&sni=${domain}#${user}
_______________________________
END
TEXT="$(kn_text "Trial VLESS" "$user" "$timer minit" "$iplim IP" "")"
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
kn_title "TRIAL VLESS ACCOUNT"
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
kn_row "Path" "/vless"
kn_row "Service" "vless-grpc"
kn_link "UUID" "${uuid}"
kn_mid
kn_link "Link WS TLS" "${vlesslink1}"
kn_link "Link WS NTLS" "${vlesslink2}"
kn_link "Link gRPC" "${vlesslink3}"
kn_link "Format OpenClash" "http://$domain:89/vless-$user.txt"
kn_foot
echo ""
} | tee -a /etc/vless/akun/log-create-${user}.log
systemctl restart xray > /dev/null 2>&1
read -n 1 -s -r -p "Press any key to back on menu"
menu
}
function limit-vless(){
clear
NUMBER_OF_CLIENTS=$(grep -c -E "^#vlg " "/etc/xray/config.json")
if [[ ${NUMBER_OF_CLIENTS} == '0' ]]; then
clear
kn_top
kn_title "Limit Vless Account"
kn_mid
echo ""
echo "You have no existing clients!"
echo ""
kn_bot
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-vless
fi
kn_top
kn_title "Limit Vless Account"
kn_mid
kn_item1 "0" "Kembali ke menu"
kn_mid
kn_userlist "^#vlg " "/etc/xray/config.json"
kn_bot
until [[ ${CLIENT_NUMBER} -ge 1 && ${CLIENT_NUMBER} -le ${NUMBER_OF_CLIENTS} ]]; do
if [[ ${CLIENT_NUMBER} == '1' ]]; then
read -rp "Select one client [1]: " CLIENT_NUMBER
else
read -rp "Select one client [1-${NUMBER_OF_CLIENTS}]: " CLIENT_NUMBER
if [[ ${CLIENT_NUMBER} == '0' ]]; then
m-vless
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
if [ ! -e /etc/vless ]; then
mkdir -p /etc/vless
fi
if [ ${iplim} = '0' ]; then
iplim="9999"
fi
if [ ${Quota} = '0' ]; then
Quota="9999"
fi
user=$(grep -E "^#vlg " "/etc/xray/config.json" | cut -d ' ' -f 2 | sed -n "${CLIENT_NUMBER}"p)
c=$(echo "${Quota}" | sed 's/[^0-9]*//g')
d=$((${c} * 1024 * 1024 * 1024))
echo "${iplim}" >/etc/vless/${user}IP
if [[ ${c} != "0" ]]; then
echo "${d}" >/etc/vless/${user}
fi
TEXT="
<code>◇━━━━━━━━━━━━━━◇</code>
<b>  XRAY VLESS IP LIMIT</b>
<code>◇━━━━━━━━━━━━━━◇</code>
<b>DOMAIN   :</b> <code>${domain} </code>
<b>ISP      :</b> <code>$ISP $CITY </code>
<b>USERNAME :</b> <code>$user </code>
<b>IP LIMIT NEW :</b> <code>$iplim IP </code>
<b>QUOTA LIMIT NEW :</b> <code>$Quota GB </code>
<code>◇━━━━━━━━━━━━━━◇</code>
<i>Succes Change IP LIMIT...</i>
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
echo " VLESS Account Was Successfully Change Limit IP"
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo " Client Name : $user"
echo " Limit IP    : $iplim IP"
echo " Limit Quota : $Quota GB"
echo ""
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-vless
}
function renew-vless(){
clear
NUMBER_OF_CLIENTS=$(grep -c -E "^#vl " "/etc/xray/config.json")
if [[ ${NUMBER_OF_CLIENTS} == '0' ]]; then
clear
kn_top
kn_title "Renew Vless Account"
kn_mid
echo ""
echo "You have no existing clients!"
echo ""
kn_bot
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-vless
fi
kn_top
kn_title "Renew Vless Account"
kn_mid
kn_item1 "0" "Kembali ke menu"
kn_mid
kn_userlist "^#vl " "/etc/xray/config.json"
kn_bot
until [[ ${CLIENT_NUMBER} -ge 1 && ${CLIENT_NUMBER} -le ${NUMBER_OF_CLIENTS} ]]; do
if [[ ${CLIENT_NUMBER} == '1' ]]; then
read -rp "Select one client [1]: " CLIENT_NUMBER
else
read -rp "Select one client [1-${NUMBER_OF_CLIENTS}]: " CLIENT_NUMBER
if [[ ${CLIENT_NUMBER} == '0' ]]; then
m-vless
fi
fi
done
read -p "Expired (days): " masaaktif
user=$(grep -E "^#vl " "/etc/xray/config.json" | cut -d ' ' -f 2 | sed -n "${CLIENT_NUMBER}"p)
exp=$(grep -E "^#vl " "/etc/xray/config.json" | cut -d ' ' -f 3 | sed -n "${CLIENT_NUMBER}"p)
now=$(date +%Y-%m-%d)
d1=$(date -d "$exp" +%s)
d2=$(date -d "$now" +%s)
exp2=$(( (d1 - d2) / 86400 ))
exp3=$(($exp2 + $masaaktif))
exp4=`date -d "$exp3 days" +"%Y-%m-%d"`
sed -i "s/#vl $user $exp/#vl $user $exp4/g" /etc/xray/config.json
sed -i "s/#vlg $user $exp/#vlg $user $exp4/g" /etc/xray/config.json
clear
TEXT="
<code>◇━━━━━━━━━━━━━━◇</code>
<b>   XRAY VLESS RENEW</b>
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
<b>   PEMBELIAN VLESS SUCCES </b>
<code>◇━━━━━━━━━━━━━━◇</code>
<b>DOMAIN   :</b> <code>${domain} </code>
<b>ISP      :</b> <code>$ISP $CITY </code>
<b>DATE   :</b> <code>${TIME2} WIB </code>
<b>DETAIL   :</b> <code>Trx VLESS </code>
<b>USER :</b> <code>${user2}xxx </code>
<b>DURASI  :</b> <code>$masaaktif Hari </code>
<code>◇━━━━━━━━━━━━━━◇</code>
<i>Renew Account From Server..</i>
"
curl -s --max-time $TIMES -d "chat_id=$CHATID2&disable_web_page_preview=1&text=$TEXT2&parse_mode=html" $URL2 >/dev/null
clear
systemctl restart xray > /dev/null 2>&1
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo " VLESS Account Was Successfully Renewed"
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo " Client Name : $user"
echo " Expired On  : $exp4"
echo ""
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-vless
}
function del-vless(){
clear
NUMBER_OF_CLIENTS=$(grep -c -E "^#vl " "/etc/xray/config.json")
if [[ ${NUMBER_OF_CLIENTS} == '0' ]]; then
kn_top
kn_title "Delete Vless Account"
kn_mid
echo ""
echo "You have no existing clients!"
echo ""
kn_bot
read -n 1 -s -r -p "Press any key to back on menu"
m-vless
fi
clear
kn_top
kn_title "Delete Vless Account"
kn_mid
kn_item1 "0" "Kembali ke menu"
kn_mid
kn_userlist "^#vl " "/etc/xray/config.json"
kn_bot
until [[ ${CLIENT_NUMBER} -ge 1 && ${CLIENT_NUMBER} -le ${NUMBER_OF_CLIENTS} ]]; do
if [[ ${CLIENT_NUMBER} == '1' ]]; then
read -rp "Select one client [1]: " CLIENT_NUMBER
else
read -rp "Select one client [1-${NUMBER_OF_CLIENTS}]: " CLIENT_NUMBER
if [[ ${CLIENT_NUMBER} == '0' ]]; then
m-vless
fi
fi
done
user=$(grep -E "^#vl " "/etc/xray/config.json" | cut -d ' ' -f 2 | sed -n "${CLIENT_NUMBER}"p)
exp=$(grep -E "^#vl " "/etc/xray/config.json" | cut -d ' ' -f 3 | sed -n "${CLIENT_NUMBER}"p)
uuid=$(grep -E "^#vl " "/etc/xray/config.json" | cut -d ' ' -f 4 | sed -n "${CLIENT_NUMBER}"p)
if [ ! -e /etc/vless/akundelete ]; then
echo "" > /etc/vless/akundelete
fi
clear
echo "### $user $exp $uuid" >> /etc/vless/akundelete
sed -i "/^#vl $user $exp/,/^},{/d" /etc/xray/config.json
sed -i "/^#vlg $user $exp/,/^},{/d" /etc/xray/config.json
clear
clear
rm /etc/vless/${user}IP >/dev/null 2>&1
rm /home/vps/public_html/vless-$user.txt >/dev/null 2>&1
rm /etc/vless/${user}login >/dev/null 2>&1
systemctl restart xray > /dev/null 2>&1
clear
TEXT="
<code>◇━━━━━━━━━━━━━━◇</code>
<b>  XRAY VLESS DELETE</b>
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
echo " Vless Account Deleted Successfully"
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo " Client Name : $user"
echo " Expired On  : $exp"
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-vless
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
function cek-vless() {
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

    # Mendapatkan daftar semua pengguna vless
    vm=($(cat /etc/xray/config.json | grep "^#vlg" | awk '{print $2}' | sort -u))

    # Proses data dan tampilkan
    if [[ ${#vm[@]} -eq 0 ]]; then
        echo -e "${COLOR_WHITE}┌──────────────────────────────────────────────────────────┐${COLOR_RESET}"
        echo -e "${COLOR_WHITE}│                  Tidak ada pengguna VLESS                │${COLOR_RESET}"
        echo -e "${COLOR_WHITE}└──────────────────────────────────────────────────────────┘${COLOR_RESET}"
    else
        for user in "${vm[@]}"; do
            # Mendapatkan data penggunaan
            used_bytes=$(cat /etc/limit/vless/"${user}" 2>/dev/null || echo 0)
            limit_bytes=$(cat /etc/vless/"${user}" 2>/dev/null || echo 0)
            
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

            # Dapatkan IP login
            login_ip_count=$(grep -w "email: ${user}" /var/log/xray/access.log | awk '{print $3}' | sed 's/tcp:\/\///g' | sort -u | wc -l)

            # Tampilkan output
            echo -e "${COLOR_WHITE}┌─${COLOR_CYAN}[ ${user} ${COLOR_WHITE}| Tipe: vless ]─┐${COLOR_RESET}"
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
    m-vless
}
function list-vless(){
clear
NUMBER_OF_CLIENTS=$(grep -c -E "^#vl " "/etc/xray/config.json")
if [[ ${NUMBER_OF_CLIENTS} == '0' ]]; then
kn_top
kn_title "Config Vless Account"
kn_mid
echo ""
echo "You have no existing clients!"
echo ""
kn_bot
read -n 1 -s -r -p "Press any key to back on menu"
m-vless
fi
kn_top
kn_title "Config Vless Account"
kn_mid
kn_item1 "0" "Kembali ke menu"
kn_mid
kn_userlist "^#vl " "/etc/xray/config.json"
kn_bot
until [[ ${CLIENT_NUMBER} -ge 1 && ${CLIENT_NUMBER} -le ${NUMBER_OF_CLIENTS} ]]; do
if [[ ${CLIENT_NUMBER} == '1' ]]; then
read -rp "Select one client [1]: " CLIENT_NUMBER
else
read -rp "Select one client [1-${NUMBER_OF_CLIENTS}]: " CLIENT_NUMBER
if [[ ${CLIENT_NUMBER} == '0' ]]; then
m-vless
fi
fi
done
clear
user=$(grep -E "^#vl " "/etc/xray/config.json" | cut -d ' ' -f 2 | sed -n "${CLIENT_NUMBER}"p)
# kn telco filter
uuid=$(grep -A1 "^#vl $user " /etc/xray/config.json | grep -o '"id": *"[^"]*"' | head -1 | cut -d '"' -f 4)
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
m-vless
return
fi
fi
clear
fi
cat /etc/vless/akun/log-create-${user}.log
cat /etc/vless/akun/log-create-${user}.log > /etc/notifakun
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
m-vless
}
function login-vless(){
clear
kn_top
kn_title "SETTING MULTI LOGIN"
kn_bot
echo -e "$COLOR1┌───────────────────────────────────────────────┐${NC}"
echo -e "${COLOR1}│ $NC SILAHKAN TULIS JUMLAH NOTIFIKASI UNTUK LOCK    ${NC}"
echo -e "${COLOR1}│ $NC AKUN USER YANG MULTI LOGIN     ${NC}"
echo -e "$COLOR1└───────────────────────────────────────────────┘${NC}"
read -rp "   Jika Mau 3x Notif baru kelock tulis 3, dst: " -e notif
cd /etc/vless
echo "$notif" > notif
clear
kn_top
kn_title "SETTING MULTI LOGIN"
kn_bot
echo -e "$COLOR1┌───────────────────────────────────────────────┐${NC}"
echo -e "${COLOR1}│ $NC SUCCES GANTI NOTIF LOCK JADI $notif $NC "
echo -e "$COLOR1└───────────────────────────────────────────────┘${NC}"
m-vless
}
function lock-vless(){
cd
clear
if [ ! -e /etc/vless/listlock ]; then
echo "" > /etc/vless/listlock
fi
NUMBER_OF_CLIENTS=$(grep -c -E "^### " "/etc/vless/listlock")
if [[ ${NUMBER_OF_CLIENTS} == '0' ]]; then
kn_top
kn_title "Unlock Vless Account"
kn_mid
echo ""
echo "You have no existing user Lock!"
echo ""
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
read -n 1 -s -r -p "Press any key to back on menu"
m-vless
fi
clear
kn_top
kn_title "Unlock Vless Account"
kn_mid
kn_item1 "0" "Kembali ke menu"
kn_item1 "999" "Padam semua akaun"
kn_mid
kn_userlist "^### " "/etc/vless/listlock"
kn_bot
until [[ ${CLIENT_NUMBER} -ge 1 && ${CLIENT_NUMBER} -le ${NUMBER_OF_CLIENTS} ]]; do
if [[ ${CLIENT_NUMBER} == '1' ]]; then
read -rp "Select one client [1]: " CLIENT_NUMBER
else
read -rp "Select one client [1-${NUMBER_OF_CLIENTS}] to Unlock: " CLIENT_NUMBER
if [[ ${CLIENT_NUMBER} == '0' ]]; then
m-vless
fi
if [[ ${CLIENT_NUMBER} == '999' ]]; then
rm /etc/vless/listlock
m-vless
fi
fi
done
user=$(grep -E "^### " "/etc/vless/listlock" | cut -d ' ' -f 2 | sed -n "${CLIENT_NUMBER}"p)
exp=$(grep -E "^### " "/etc/vless/listlock" | cut -d ' ' -f 3 | sed -n "${CLIENT_NUMBER}"p)
uuid=$(grep -E "^### " "/etc/vless/listlock" | cut -d ' ' -f 4 | sed -n "${CLIENT_NUMBER}"p)
sed -i '/#vless$/a\#vl '"$user $exp $uuid"'\
},{"id": "'""$uuid""'","email": "'""$user""'"' /etc/xray/config.json
sed -i '/#vlessgrpc$/a\#vlg '"$user $exp"'\
},{"id": "'""$uuid""'","email": "'""$user""'"' /etc/xray/config.json
sed -i "/^### $user $exp $uuid/d" /etc/vless/listlock
systemctl restart xray
TEXT="
<code>◇━━━━━━━━━━━━━━◇</code>
<b>  XRAY VLESS UNLOCKED</b>
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
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo " Vless Account Unlock Successfully"
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo " Client Name : $user"
echo " Status  : Unlocked"
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-vless
}
function res-user(){
clear
cd
if [ ! -e /etc/vless/akundelete ]; then
echo "" > /etc/vless/akundelete
fi
clear
NUMBER_OF_CLIENTS=$(grep -c -E "^### " "/etc/vless/akundelete")
if [[ ${NUMBER_OF_CLIENTS} == '0' ]]; then
kn_top
kn_title "Restore Vless Account"
kn_mid
echo ""
echo "You have no existing user Expired!"
echo ""
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
read -n 1 -s -r -p "Press any key to back on menu"
m-vless
fi
clear
kn_top
kn_title "Restore Vless Account"
kn_mid
kn_item1 "0" "Kembali ke menu"
kn_item1 "999" "Padam semua akaun"
kn_mid
kn_userlist "^### " "/etc/vless/akundelete"
kn_bot
until [[ ${CLIENT_NUMBER} -ge 1 && ${CLIENT_NUMBER} -le ${NUMBER_OF_CLIENTS} ]]; do
if [[ ${CLIENT_NUMBER} == '1' ]]; then
read -rp "Select one client [1]: " CLIENT_NUMBER
else
read -rp "Select one client [1-${NUMBER_OF_CLIENTS}] to Unlock: " CLIENT_NUMBER
if [[ ${CLIENT_NUMBER} == '0' ]]; then
m-vless
fi
if [[ ${CLIENT_NUMBER} == '999' ]]; then
rm /etc/vless/akundelete
m-vless
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
user=$(grep -E "^### " "/etc/vless/akundelete" | cut -d ' ' -f 2 | sed -n "${CLIENT_NUMBER}"p)
exp=`date -d "$masaaktif days" +"%Y-%m-%d"`
uuid=$(grep -E "^### " "/etc/vless/akundelete" | cut -d ' ' -f 4 | sed -n "${CLIENT_NUMBER}"p)
sed -i '/#vless$/a\#vl '"$user $exp $uuid"'\
},{"id": "'""$uuid""'","email": "'""$user""'"' /etc/xray/config.json
sed -i '/#vlessgrpc$/a\#vlg '"$user $exp"'\
},{"id": "'""$uuid""'","email": "'""$user""'"' /etc/xray/config.json
echo "${iplim}" >/etc/vless/${user}IP
c=$(echo "${Quota}" | sed 's/[^0-9]*//g')
d=$((${c} * 1024 * 1024 * 1024))
if [[ ${c} != "0" ]]; then
echo "${d}" >/etc/vless/${user}
fi
sed -i "/^### ${user} ${exp} ${uuid}/d" /etc/vless/akundelete
systemctl restart xray
TEXT="
<code>◇━━━━━━━━━━━━━━◇</code>
<b>  XRAY VLESS RESTORE</b>
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
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo " Vless Account Restore Successfully"
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo " Client Name : $user"
echo " Expired  : $exp"
echo " Succes to Restore"
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-vless
}
function quota-user(){
cd
clear
if [ ! -e /etc/vless/userQuota ]; then
echo "" > /etc/vless/userQuota
fi
NUMBER_OF_CLIENTS=$(grep -c -E "^### " "/etc/vless/userQuota")
if [[ ${NUMBER_OF_CLIENTS} == '0' ]]; then
kn_top
kn_title "Unlock Vless Account"
kn_mid
echo ""
echo "You have no existing user Lock!"
echo ""
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
read -n 1 -s -r -p "Press any key to back on menu"
m-vless
fi
clear
kn_top
kn_title "Unlock Vless Account"
kn_mid
kn_item1 "0" "Kembali ke menu"
kn_item1 "999" "Padam semua akaun"
kn_mid
kn_userlist "^### " "/etc/vless/userQuota"
kn_bot
until [[ ${CLIENT_NUMBER} -ge 1 && ${CLIENT_NUMBER} -le ${NUMBER_OF_CLIENTS} ]]; do
if [[ ${CLIENT_NUMBER} == '1' ]]; then
read -rp "Select one client [1]: " CLIENT_NUMBER
else
read -rp "Select one client [1-${NUMBER_OF_CLIENTS}] to Unlock: " CLIENT_NUMBER
if [[ ${CLIENT_NUMBER} == '0' ]]; then
m-vless
fi
if [[ ${CLIENT_NUMBER} == '999' ]]; then
rm /etc/vless/userQuota
m-vless
fi
fi
done
user=$(grep -E "^### " "/etc/vless/userQuota" | cut -d ' ' -f 2 | sed -n "${CLIENT_NUMBER}"p)
exp=$(grep -E "^### " "/etc/vless/userQuota" | cut -d ' ' -f 3 | sed -n "${CLIENT_NUMBER}"p)
uuid=$(grep -E "^### " "/etc/vless/userQuota" | cut -d ' ' -f 4 | sed -n "${CLIENT_NUMBER}"p)
sed -i '/#vless$/a\#vl '"$user $exp $uuid"'\
},{"id": "'""$uuid""'","email": "'""$user""'"' /etc/xray/config.json
sed -i '/#vlessgrpc$/a\#vlg '"$user $exp"'\
},{"id": "'""$uuid""'","email": "'""$user""'"' /etc/xray/config.json
sed -i "/^### $user $exp $uuid/d" /etc/vless/userQuota
systemctl restart xray
TEXT="
<code>◇━━━━━━━━━━━━━━◇</code>
<b>  XRAY VLESS UNLOCKED</b>
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
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo " Vless Account Unlock Successfully"
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo " Client Name : $user"
echo " Status  : Unlocked"
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-vless
}
clear
author=$(cat /etc/profil)
kn_top
kn_title "VLESS PANEL MENU"
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
1) clear ; add-vless  ;;
2) clear ; trial-vless  ;;
3) clear ; renew-vless  ;;
4) clear ; del-vless  ;;
5) clear ; cek-vless  ;;
6) clear ; list-vless  ;;
7) clear ; limit-vless  ;;
8) clear ; login-vless  ;;
9) clear ; lock-vless  ;;
10) clear ; quota-user  ;;
11) clear ; res-user  ;;
0) clear ; menu  ;;
x) exit ;;
*) echo "salah tekan " ; sleep 1 ; m-vless ;;
esac
