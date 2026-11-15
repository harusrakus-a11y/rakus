
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
###########- COLOR CODE -##############
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export NC='\033[0m' # No Color
COLOR1='\033[0;32m'
WH='\033[1;37m'
#######################################

###########- SYSTEM INFO -#############
# Server Information
date_server=$(date -u +"%Y-%m-%d")
wkt_server=$(timedatectl | grep "Time zone" | awk '{print $3}' | tr -d '()')

# RAM Information
tram=$(free -h | awk '/Mem:/ {print $2}')
uram=$(free -h | awk '/Mem:/ {print $3}')

# Network Information
ipsaya=$(curl -s4 ifconfig.me)
ipvps=$(curl -s4 ifconfig.me)
isp=$(curl -s ipinfo.io/org | cut -d ' ' -f 2-10)
city=$(curl -s ipinfo.io/city)

#######################################

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
if [ ! -e /etc/xray/sshx/akun ]; then
mkdir -p /etc/xray/sshx/akun
fi
function usernew() {
    clear
    domen=$(cat /etc/xray/domain)
    sldomain=$(cat /etc/xray/dns)
    slkey=$(cat /etc/slowdns/server.pub)
    TIMES="10"
    CHATID=$(cat /etc/per/id)
    KEY=$(cat /etc/per/token)
    URL="https://api.telegram.org/bot$KEY/sendMessage"
    ISP=$(cat /etc/xray/isp)
    CITY=$(cat /etc/xray/city)
    author=$(cat /etc/profil)
    
    clear
    echo -e "$COLOR1┌─────────────────────────────────────────────────┐${NC}"
    echo -e "$COLOR1│${NC}${COLBG1}               ${WH}• SSH PANEL MENU •                ${NC}$COLOR1│ $NC"
    echo -e "$COLOR1└─────────────────────────────────────────────────┘${NC}"
    
    while true; do
        read -p "Username : " Login
        if [[ ! "$Login" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
            echo -e "Username mengandung karakter yang tidak valid!"
            continue
        fi
        
        # Cek apakah username ada di sistem atau di file /etc/xray/ssh
        CLIENT_EXISTS_IN_SYSTEM=$(id "$Login" &>/dev/null; echo $?)
        CLIENT_EXISTS_IN_FILE=$(grep -w "^### $Login " /etc/xray/ssh | wc -l)
        
        if [ "$CLIENT_EXISTS_IN_SYSTEM" -eq 0 ] || [ "$CLIENT_EXISTS_IN_FILE" -ge 1 ]; then
            # Jika user ada di sistem, cek kedaluwarsa
            if [ "$CLIENT_EXISTS_IN_SYSTEM" -eq 0 ]; then
                exp_date=$(chage -l "$Login" | grep "Account expires" | awk -F': ' '{print $2}')
                exp_epoch=$(date -d "$exp_date" +%s 2>/dev/null)
                now_epoch=$(date +%s)
                
                if [ "$exp_epoch" -lt "$now_epoch" ]; then
                    # Hapus user kedaluwarsa
                    userdel -r "$Login" >/dev/null 2>&1
                    sed -i "/^### $Login /d" /etc/xray/ssh
                    rm -f "/etc/xray/sshx/${Login}IP" "/home/vps/public_html/ssh-$Login.txt"
                    echo -e "Akun kedaluwarsa $Login telah dihapus. Silahkan buat baru."
                    break
                else
                    echo -e "Username $Login masih aktif hingga $exp_date!"
                    continue
                fi
            else
                # Hapus entri di file jika user tidak ada di sistem
                sed -i "/^### $Login /d" /etc/xray/ssh
                rm -f "/etc/xray/sshx/${Login}IP" "/home/vps/public_html/ssh-$Login.txt"
                break
            fi
        else
            break
        fi
    done
    
    # Lanjutkan proses pembuatan akun...
    read -p "Password : " Pass
    until [[ $masaaktif =~ ^[0-9]+$ ]]; do
        read -p "Expired (hari): " masaaktif
    done
    until [[ $iplim =~ ^[0-9]+$ ]]; do
        read -p "Limit User (IP): " iplim
    done
    
    # ... (sisa kode tetap sama)

if [ ! -e /etc/xray/sshx ]; then
mkdir -p /etc/xray/sshx
fi
if [ -z ${iplim} ]; then
iplim="0"
fi
echo "${iplim}" >/etc/xray/sshx/${Login}IP
IP=$(curl -sS ifconfig.me);
if [[ -e /etc/cloudfront ]]; then
cloudfront=$(cat /etc/cloudfront)
else
cloudfront="-"
fi
sleep 1
clear
expi=`date -d "$masaaktif days" +"%Y-%m-%d"`
useradd -e `date -d "$masaaktif days" +"%Y-%m-%d"` -s /bin/false -M $Login
exp="$(chage -l $Login | grep "Account expires" | awk -F": " '{print $2}')"
echo -e "$Pass\n$Pass\n"|passwd $Login &> /dev/null
echo -e "### $Login $expi $Pass" >> /etc/xray/ssh
KUOTA_DIR="/etc/kuota-ssh"
if [ ! -d "$KUOTA_DIR" ]; then
    mkdir -p "$KUOTA_DIR"
fi
# Atur limit kuota di sini (dalam byte). Contoh: 5GB
DEFAULT_LIMIT_BYTES="5368709120" 

cat > ${KUOTA_DIR}/${Login} <<-END
USERNAME="${Login}"
STATUS="AKTIF"
LIMIT_BYTES="${DEFAULT_LIMIT_BYTES}"
USAGE_BYTES="0"
END
cat > /home/vps/public_html/ssh-$Login.txt <<-END
_______________________________
Format SSH OVPN Account
_______________________________
Username         : $Login
Password         : $Pass
Expired          : $exp
_______________________________
Host             : $domen
ISP              : $ISP
CITY             : $CITY
Login Limit      : ${iplim} IP
Port OpenSSH     : 22
Port Dropbear    : 143, 109
Port SSH WS      : 80, 8080, 8880
Port SSH SSL WS  : 443
Port SSL/TLS     : 8443, 8881
Port OVPN WS SSL : 2086
Port OVPN SSL    : 990
Port OVPN TCP    : 1194
Port OVPN UDP    : 2200,
BadVPN UDP       : 7100, 7300, 7300
_______________________________
Host Slowdns    : $sldomain
Port Slowdns     : 80, 443, 53
Pub Key          : $slkey
_______________________________
SSH UDP VIRAL : $domen:1-65535@$Login:$Pass
_______________________________
HTTP COSTUM : $domen:80@$Login:$Pass
_______________________________
Payload WS/WSS   :
GET / HTTP/1.1[crlf]Host: [host][crlf]Connection: Upgrade[crlf]User-Agent: [ua][crlf]Upgrade: ws[crlf][crlf]
_______________________________
OpenVPN SSL      : http://$domen:89/ssl.ovpn
OpenVPN TCP      : http://$domen:89/tcp.ovpn
OpenVPN UDP      : http://$domen:89/udp.ovpn
_______________________________
END
TEXT="$(kn_text "SSH" "$Login" "$exp" "$iplim IP" "")"
kn_send "$TEXT"
cd
if [ ! -e /etc/tele ]; then
echo -ne
else
echo "$TEXT" > /etc/notiftele
bash /etc/tele
fi
user2=$(echo "$Login" | cut -c 1-3)
TIME2=$(date +'%Y-%m-%d %H:%M:%S')
clear
{
kn_top
kn_title "SSH PREMIUM ACCOUNT"
kn_mid
kn_row "Username" "${Login}"
kn_row "Password" "${Pass}"
kn_row "Tamat" "${exp}"
kn_row "Host" "${domen}"
kn_row "Lokasi" "${CITY} - ${ISP}"
kn_row "Had IP" "${iplim} IP"
kn_mid
kn_row "OpenSSH" "22"
kn_row "Dropbear" "109, 143"
kn_row "SSH-WS" "80, 8080, 8880"
kn_row "SSH-SSL" "443"
kn_row "SSL/TLS" "8443, 8881"
kn_row "OVPN WS" "2086"
kn_row "OVPN TCP" "1194"
kn_row "OVPN UDP" "2200, 1-65535"
kn_row "OVPN SSL" "990"
kn_row "UDPGW" "7100-7300"
kn_mid
kn_row "SlowDNS" "80, 443, 53"
kn_row "NS" "${sldomain}"
kn_row "PubKey" "${slkey}"
kn_mid
kn_link "UDP VIRAL" "${domen}:1-65535@${Login}:${Pass}"
kn_link "HTTP COSTUM" "${domen}:80@${Login}:${Pass}"
kn_link "Payload WS/WSS" "GET / HTTP/1.1[crlf]Host: [host][crlf]Connection: Upgrade[crlf]User-Agent: [ua][crlf]Upgrade: ws[crlf][crlf]"
kn_link "OVPN TCP/UDP/SSL" "http://${domen}:89/tcp.ovpn  http://${domen}:89/udp.ovpn  http://${domen}:89/ssl.ovpn"
kn_link "Simpan config" "http://${domen}:89/ssh-${Login}.txt"
kn_foot
echo ""
} | tee -a /etc/xray/sshx/akun/log-create-${Login}.log
read -n 1 -s -r -p "Press any key to back on menu"
menu
}
function trial(){
clear
domen=`cat /etc/xray/domain`
sldomain=`cat /etc/xray/dns`
slkey=`cat /etc/slowdns/server.pub`
TIMES="10"
CHATID=$(cat /etc/per/id)
KEY=$(cat /etc/per/token)
URL="https://api.telegram.org/bot$KEY/sendMessage"
ISP=$(cat /etc/xray/isp)
CITY=$(cat /etc/xray/city)
author=$(cat /etc/profil)
clear
IP=$(curl -sS ifconfig.me)
cd
kn_top
kn_title "TRIAL SSH Account"
kn_bot
echo -e ""
until [[ $timer =~ ^[0-9]+$ ]]; do
read -p "Expired (Minutes): " timer
done
Login=Trial-`</dev/urandom tr -dc X-Z0-9 | head -c4`
hari=0
Pass=1
iplim=1
if [ ! -e /etc/xray/sshx ]; then
mkdir -p /etc/xray/sshx
fi
if [ -z ${iplim} ]; then
iplim="0"
fi
if [[ -e /etc/cloudfront ]]; then
cloudfront=$(cat /etc/cloudfront)
else
cloudfront="Kosong"
fi
echo "$iplim" > /etc/xray/sshx/${Login}IP
expi=`date -d "$hari days" +"%Y-%m-%d"`
useradd -e `date -d "$hari days" +"%Y-%m-%d"` -s /bin/false -M $Login
exp="$(chage -l $Login | grep "Account expires" | awk -F": " '{print $2}')"
echo -e "$Pass\n$Pass\n"|passwd $Login &> /dev/null
echo -e "### $Login $expi $Pass" >> /etc/xray/ssh
tmux new-session -d -s $Login "trial ssh $Login $expi $Pass ${timer}"
cat > /home/vps/public_html/ssh-$Login.txt <<-END
_______________________________
Format SSH OVPN Account
_______________________________
Username         : $Login
Password         : $Pass
Expired          : $timer Minutes
_______________________________
Host             : $domen
ISP              : $ISP
CITY             : $CITY
Login Limit      : ${iplim} IP
Port OpenSSH     : 22
Port Dropbear    : 143, 109
Port SSH WS      : 80, 8080, 8880
Port SSH SSL WS  : 443
Port SSL/TLS     : 8443, 8881
Port OVPN WS SSL : 2086
Port OVPN SSL    : 990
Port OVPN TCP    : 1194
Port OVPN UDP    : 2200,
BadVPN UDP       : 7100, 7300, 7300
_______________________________
Host Slowdns    : $sldomain
Port Slowdns     : 80, 443, 53
Pub Key          : $slkey
_______________________________
SSH UDP VIRAL : $domen:1-65535@$Login:$Pass
_______________________________
HTTP COSTUM : $domen:80@$Login:$Pass
_______________________________
Payload WS/WSS   :
GET / HTTP/1.1[crlf]Host: [host][crlf]Connection: Upgrade[crlf]User-Agent: [ua][crlf]Upgrade: ws[crlf][crlf]
_______________________________
OpenVPN SSL      : http://$domen:89/ssl.ovpn
OpenVPN TCP      : http://$domen:89/tcp.ovpn
OpenVPN UDP      : http://$domen:89/udp.ovpn
_______________________________
END
TEXT="$(kn_text "Trial SSH" "$Login" "$timer minit" "$iplim IP" "")"
kn_send "$TEXT"
cd
if [ ! -e /etc/tele ]; then
echo -ne
else
echo "$TEXT" > /etc/notiftele
bash /etc/tele
fi
cat> /etc/cron.d/trialssh${Login} << EOF
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
*/$timer * * * * root /usr/bin/trial ssh $Login $Pass $expi
EOF
clear
{
kn_top
kn_title "TRIAL SSH ACCOUNT"
kn_mid
kn_row "Username" "${Login}"
kn_row "Password" "${Pass}"
kn_row "Tamat" "${timer} minit"
kn_row "Host" "${domen}"
kn_row "Lokasi" "${CITY} - ${ISP}"
kn_row "Had IP" "${iplim} IP"
kn_mid
kn_row "OpenSSH" "22"
kn_row "Dropbear" "109, 143"
kn_row "SSH-WS" "80, 8080, 8880"
kn_row "SSH-SSL" "443"
kn_row "SSL/TLS" "8443, 8881"
kn_row "OVPN WS" "2086"
kn_row "OVPN TCP" "1194"
kn_row "OVPN UDP" "2200, 1-65535"
kn_row "OVPN SSL" "990"
kn_row "UDPGW" "7100-7300"
kn_mid
kn_row "SlowDNS" "80, 443, 53"
kn_row "NS" "${sldomain}"
kn_row "PubKey" "${slkey}"
kn_mid
kn_link "UDP VIRAL" "${domen}:1-65535@${Login}:${Pass}"
kn_link "HTTP COSTUM" "${domen}:80@${Login}:${Pass}"
kn_link "Payload WS/WSS" "GET / HTTP/1.1[crlf]Host: [host][crlf]Connection: Upgrade[crlf]User-Agent: [ua][crlf]Upgrade: ws[crlf][crlf]"
kn_link "OVPN TCP/UDP/SSL" "http://${domen}:89/tcp.ovpn  http://${domen}:89/udp.ovpn  http://${domen}:89/ssl.ovpn"
kn_link "Simpan config" "http://${domen}:89/ssh-${Login}.txt"
kn_foot
echo ""
} | tee -a /etc/xray/sshx/akun/log-create-${Login}.log
read -n 1 -s -r -p "Press any key to back on menu"
menu
}
function renew(){
clear
TIMES="10"
CHATID=$(cat /etc/per/id)
KEY=$(cat /etc/per/token)
URL="https://api.telegram.org/bot$KEY/sendMessage"
ISP=$(cat /etc/xray/isp)
CITY=$(cat /etc/xray/city)
domain=$(cat /etc/xray/domain)
NUMBER_OF_CLIENTS=$(grep -c -E "^### " "/etc/xray/ssh")
if [[ ${NUMBER_OF_CLIENTS} == '0' ]]; then
clear
kn_top
kn_title "RENEW USERS"
kn_bot
echo -e "$COLOR1┌─────────────────────────────────────────────────┐${NC}"
echo -e "$COLOR1│                                                 │"
echo -e "$COLOR1│${WH} User Tidak Ada!                              $COLOR1   │"
echo -e "$COLOR1│                                                 │"
echo -e "$COLOR1└─────────────────────────────────────────────────┘${NC}"
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
sshws
fi
kn_top
kn_title "RENEW USERS"
kn_mid
kn_item1 "0" "Kembali ke menu"
kn_mid
kn_userlist "^### " "/etc/xray/ssh"
kn_bot
until [[ ${CLIENT_NUMBER} -ge 1 && ${CLIENT_NUMBER} -le ${NUMBER_OF_CLIENTS} ]]; do
if [[ ${CLIENT_NUMBER} == '1' ]]; then
read -rp "Select one client [1]: " CLIENT_NUMBER
else
read -rp "Select one client [1-${NUMBER_OF_CLIENTS}]: " CLIENT_NUMBER
if [[ ${CLIENT_NUMBER} == '0' ]]; then
sshws
fi
fi
done
User=$(grep -E "^### " "/etc/xray/ssh" | cut -d ' ' -f 2 | sed -n "${CLIENT_NUMBER}"p)
exp=$(grep -E "^### " "/etc/xray/ssh" | cut -d ' ' -f 3 | sed -n "${CLIENT_NUMBER}"p)
Pass=$(grep -E "^### " "/etc/xray/ssh" | cut -d ' ' -f 4 | sed -n "${CLIENT_NUMBER}"p)
egrep "^$User" /etc/passwd >/dev/null
if [ $? -eq 0 ]; then
read -p "Day Extend : " Days
now=$(date +%Y-%m-%d)
d1=$(date -d "$exp" +%s)
d2=$(date -d "$now" +%s)
exp2=$(( (d1 - d2) / 86400 ))
exp3=$(($exp2 + $Days))
exp4=`date -d "$exp3 days" +"%Y-%m-%d"`
passwd -u $User
usermod -e  $exp4 $User
egrep "^$User" /etc/passwd >/dev/null
echo -e "$Pass\n$Pass\n"|passwd $User &> /dev/null
sed -i "s/### $User $exp/### $User $exp4/g" /etc/xray/ssh >/dev/null
clear
TEXT="
<code>◇━━━━━━━━━━━━━━◇</code>
<b>  SSH RENEW</b>
<code>◇━━━━━━━━━━━━━━◇</code>
<b>DOMAIN   :</b> <code>${domain} </code>
<b>ISP      :</b> <code>$ISP $CITY </code>
<b>USERNAME :</b> <code>$User </code>
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
user2=$(echo "$User" | cut -c 1-3)
TIME2=$(date +'%Y-%m-%d %H:%M:%S')
TEXT2="
<code>◇━━━━━━━━━━━━━━◇</code>
<b>   TRANSAKSI SUCCES </b>
<code>◇━━━━━━━━━━━━━━◇</code>
<b>DOMAIN   :</b> <code>${domain} </code>
<b>ISP      :</b> <code>$CITY </code>
<b>DATE   :</b> <code>${TIME2} WIB</code>
<b>DETAIL   :</b> <code>Trx SSH </code>
<b>USER :</b> <code>${user2}xxx </code>
<b>DURASI  :</b> <code>$Days Hari </code>
<code>◇━━━━━━━━━━━━━━◇</code>
<i>Renew Account From Server..</i>
"
curl -s --max-time $TIMES -d "chat_id=$CHATID2&disable_web_page_preview=1&text=$TEXT2&parse_mode=html" $URL2 >/dev/null
clear
kn_top
kn_title "RENEW USERS"
kn_bot
echo -e "$COLOR1┌─────────────────────────────────────────────────┐${NC}"
echo -e "$COLOR1│"
echo -e "$COLOR1│ ${WH}Username   : $User"
echo -e "$COLOR1│ ${WH}Days Added : $Days Days"
echo -e "$COLOR1│ ${WH}Expired on : $exp4"
echo -e "$COLOR1│"
echo -e "$COLOR1└─────────────────────────────────────────────────┘${NC}"
fi
read -n 1 -s -r -p "Press any key to back on menu"
sshws
}
function hapus(){
NUMBER_OF_CLIENTS=$(grep -c -E "^### " "/etc/xray/ssh")
if [[ ${NUMBER_OF_CLIENTS} == '0' ]]; then
clear
kn_top
kn_title "DELETE USERS"
kn_bot
echo -e "$COLOR1┌─────────────────────────────────────────────────┐${NC}"
echo -e "$COLOR1│                                                 │"
echo -e "$COLOR1│${WH} User Tidak Ada!                              $COLOR1   │"
echo -e "$COLOR1│                                                 │"
echo -e "$COLOR1└─────────────────────────────────────────────────┘${NC}"
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
sshws
fi
kn_top
kn_title "DELETE USERS"
kn_mid
kn_item1 "0" "Kembali ke menu"
kn_mid
kn_userlist "^### " "/etc/xray/ssh"
kn_bot
until [[ ${CLIENT_NUMBER} -ge 1 && ${CLIENT_NUMBER} -le ${NUMBER_OF_CLIENTS} ]]; do
if [[ ${CLIENT_NUMBER} == '1' ]]; then
read -rp "Select one client [1]: " CLIENT_NUMBER
else
read -rp "Select one client [1-${NUMBER_OF_CLIENTS}]: " CLIENT_NUMBER
if [[ ${CLIENT_NUMBER} == '0' ]]; then
sshws
fi
fi
done
Pengguna=$(grep -E "^### " "/etc/xray/ssh" | cut -d ' ' -f 2 | sed -n "${CLIENT_NUMBER}"p)
Days=$(grep -E "^### " "/etc/xray/ssh" | cut -d ' ' -f 3 | sed -n "${CLIENT_NUMBER}"p)
Pass=$(grep -E "^### " "/etc/xray/ssh" | cut -d ' ' -f 4 | sed -n "${CLIENT_NUMBER}"p)
sed -i "/^### $Pengguna $Days $Pass/d" /etc/xray/ssh
rm /home/vps/public_html/ssh-$Pengguna.txt >/dev/null 2>&1
rm /etc/xray/sshx/${Pengguna}IP >/dev/null 2>&1
rm /etc/xray/sshx/${Pengguna}login >/dev/null 2>&1
if getent passwd $Pengguna > /dev/null 2>&1; then
userdel $Pengguna > /dev/null 2>&1
echo -e "User $Pengguna was removed."
else
echo -e "Failure: User $Pengguna Not Exist."
fi
TEXT="
<code>◇━━━━━━━━━━━━━━◇</code>
<b>  DELETE SSH OVPN</b>
<code>◇━━━━━━━━━━━━━━◇</code>
<b>DOMAIN   :</b> <code>${domain} </code>
<b>ISP      :</b> <code>$ISP $CITY </code>
<b>USERNAME :</b> <code>$Pengguna </code>
<b>EXPIRED  :</b> <code>$Days </code>
<code>◇━━━━━━━━━━━━━━◇</code>
<i>Succes Delete This User...</i>
"
curl -s --max-time $TIMES -d "chat_id=$CHATID&disable_web_page_preview=1&text=$TEXT&parse_mode=html" $URL >/dev/null
cd
if [ ! -e /etc/tele ]; then
echo -ne
else
echo "$TEXT" > /etc/notiftele
bash /etc/tele
fi
read -n 1 -s -r -p "Press any key to back on menu"
sshws
}
function cekconfig(){
ISP=$(cat /etc/xray/isp)
CITY=$(cat /etc/xray/city)
author=$(cat /etc/profil)
IP=$(curl -sS ifconfig.me);
domen=`cat /etc/xray/domain`
sldomain=`cat /etc/xray/dns`
slkey=`cat /etc/slowdns/server.pub`
NUMBER_OF_CLIENTS=$(grep -c -E "^### " "/etc/xray/ssh")
if [[ ${NUMBER_OF_CLIENTS} == '0' ]]; then
clear
kn_top
kn_title "USER CONFIG"
kn_bot
echo -e "$COLOR1┌─────────────────────────────────────────────────┐${NC}"
echo -e "$COLOR1│                                                 │"
echo -e "$COLOR1│${WH} User Tidak Ada!                              $COLOR1   │"
echo -e "$COLOR1│                                                 │"
echo -e "$COLOR1└─────────────────────────────────────────────────┘${NC}"
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
sshws
fi
kn_top
kn_title "USER CONFIG"
kn_mid
kn_item1 "0" "Kembali ke menu"
kn_mid
kn_userlist "^### " "/etc/xray/ssh"
kn_bot
until [[ ${CLIENT_NUMBER} -ge 1 && ${CLIENT_NUMBER} -le ${NUMBER_OF_CLIENTS} ]]; do
if [[ ${CLIENT_NUMBER} == '1' ]]; then
read -rp "Select one client [1]: " CLIENT_NUMBER
else
read -rp "Select one client [1-${NUMBER_OF_CLIENTS}]: " CLIENT_NUMBER
if [[ ${CLIENT_NUMBER} == '0' ]]; then
sshws
fi
fi
done
Login=$(grep -E "^### " "/etc/xray/ssh" | cut -d ' ' -f 2 | sed -n "${CLIENT_NUMBER}"p)
cat /etc/xray/sshx/akun/log-create-${Login}.log
cat /etc/xray/sshx/akun/log-create-${Login}.log > /etc/notifakun
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
read -n 1 -s -r -p "   Press any key to back on menu"
menu
}
function hapuslama(){
clear
kn_top
kn_title "MEMBER SSH"
kn_bot
echo -e "$COLOR1┌─────────────────────────────────────────────────┐${NC}"
echo "USERNAME          EXP DATE          STATUS"
echo -e "$COLOR1└─────────────────────────────────────────────────┘${NC}"
while read expired
do
AKUN="$(echo $expired | cut -d: -f1)"
ID="$(echo $expired | grep -v nobody | cut -d: -f3)"
exp="$(chage -l $AKUN | grep "Account expires" | awk -F": " '{print $2}')"
status="$(passwd -S $AKUN | awk '{print $2}' )"
if [[ $ID -ge 1000 ]]; then
if [[ "$status" = "L" ]]; then
printf "%-17s %2s %-17s %2s \n" "$AKUN" "$exp     " "LOCKED"
else
printf "%-17s %2s %-17s %2s \n" "$AKUN" "$exp     " "UNLOCKED"
fi
fi
done < /etc/passwd
JUMLAH="$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | wc -l)"
echo -e "$COLOR1┌─────────────────────────────────────────────────┐${NC}"
echo "Account number: $JUMLAH user"
echo -e "$COLOR1└─────────────────────────────────────────────────┘${NC}"
kn_top
kn_title "DELETE USERS"
kn_bot
echo -e "$COLOR1┌─────────────────────────────────────────────────┐${NC}"
echo ""
read -p "Username SSH to Delete : " Pengguna
if getent passwd $Pengguna > /dev/null 2>&1; then
userdel $Pengguna > /dev/null 2>&1
echo -e "User $Pengguna was removed."
else
echo -e "Failure: User $Pengguna Not Exist."
fi
sed -i "/^### $Pengguna/d" /etc/xray/ssh
read -n 1 -s -r -p "Press any key to back on menu"
sshws
}
function cek(){

if [ -e "/var/log/auth.log" ]; then
        LOG="/var/log/auth.log";
fi
if [ -e "/var/log/secure" ]; then
        LOG="/var/log/secure";
fi
                
data=( `ps aux | grep -i dropbear | awk '{print $2}'`);
echo -e "\033[1;36m┌──────────────────────────────────────────┐\033[0m"
echo "    ID  |  Username  |  IP Address";
echo -e "\033[1;36m└──────────────────────────────────────────┘\033[0m"
cat $LOG | grep -i dropbear | grep -i "Password auth succeeded" > /tmp/login-db.txt;
for PID in "${data[@]}"
do
            cat /tmp/login-db.txt | grep "dropbear\[$PID\]" > /tmp/login-db-pid.txt;
            NUM=`cat /tmp/login-db-pid.txt | wc -l`;
            USER=`cat /tmp/login-db-pid.txt | awk '{print $10}'`;
            IP=`cat /tmp/login-db-pid.txt | awk '{print $12}'`;
            if [ $NUM -eq 1 ]; then
                    echo "$PID - $USER - $IP";
                    fi
done
echo -e "\033[1;36m└──────────────────────────────────────────┘\033[0m"
echo " "
echo -e "\033[1;36m┌──────────────────────────────────────────┐\033[0m"
echo "    ID  |  Username  |  IP Address";
echo -e "\033[1;36m└──────────────────────────────────────────┘\033[0m"
cat $LOG | grep -i sshd | grep -i "Accepted password for" > /tmp/login-db.txt
data=( `ps aux | grep "\[priv\]" | sort -k 72 | awk '{print $2}'`);

for PID in "${data[@]}"
do
            cat /tmp/login-db.txt | grep "sshd\[$PID\]" > /tmp/login-db-pid.txt;
            NUM=`cat /tmp/login-db-pid.txt | wc -l`;
            USER=`cat /tmp/login-db-pid.txt | awk '{print $9}'`;
            IP=`cat /tmp/login-db-pid.txt | awk '{print $11}'`;
            if [ $NUM -eq 1 ]; then
                    echo "$PID - $USER - $IP";
        fi
done
echo -e "\033[1;36m└──────────────────────────────────────────┘\033[0m"
if [ -f "/etc/openvpn/server/openvpn-tcp.log" ]; then
echo ""
echo -e "\033[1;36m┌──────────────────────────────────────────┐\033[0m"
echo "    Username  |  IP Address  |  Connected";
echo -e "\033[1;36m└──────────────────────────────────────────┘\033[0m"
            cat /etc/openvpn/server/openvpn-tcp.log | grep -w "^CLIENT_LIST" | cut -d ',' -f 2,3,8 | sed -e 's/,/      /g' > /tmp/vpn-login-tcp.txt
            cat /tmp/vpn-login-tcp.txt
fi
echo -e "\033[1;36m└──────────────────────────────────────────┘\033[0m"

if [ -f "/etc/openvpn/server/openvpn-udp.log" ]; then
echo " "
echo -e "\033[1;36m┌──────────────────────────────────────────┐\033[0m"
echo "    Username  |  IP Address  |  Connected";
echo -e "\033[1;36m└──────────────────────────────────────────┘\033[0m"
            cat /etc/openvpn/server/openvpn-udp.log | grep -w "^CLIENT_LIST" | cut -d ',' -f 2,3,8 | sed -e 's/,/      /g' > /tmp/vpn-login-udp.txt
            cat /tmp/vpn-login-udp.txt
fi
echo -e "\033[1;36m└──────────────────────────────────────────┘\033[0m"
echo ""
}
function limitssh(){
cd
NUMBER_OF_CLIENTS=$(grep -c -E "^### " "/etc/xray/ssh")
if [[ ${NUMBER_OF_CLIENTS} == '0' ]]; then
clear
kn_top
kn_title "Limit SSH Account"
kn_mid
echo ""
echo "You have no existing clients!"
echo ""
kn_bot
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
sshws
fi
kn_top
kn_title "Limit SSH Account"
kn_mid
kn_item1 "0" "Kembali ke menu"
kn_mid
kn_userlist "^### " "/etc/xray/ssh"
kn_bot
until [[ ${CLIENT_NUMBER} -ge 1 && ${CLIENT_NUMBER} -le ${NUMBER_OF_CLIENTS} ]]; do
if [[ ${CLIENT_NUMBER} == '1' ]]; then
read -rp "Select one client [1]: " CLIENT_NUMBER
else
read -rp "Select one client [1-${NUMBER_OF_CLIENTS}]: " CLIENT_NUMBER
if [[ ${CLIENT_NUMBER} == '0' ]]; then
sshws
fi
fi
done
until [[ $iplim =~ ^[0-9]+$ ]]; do
read -p "Limit User (IP) New: " iplim
done
if [ ! -e /etc/xray/sshx ]; then
mkdir -p /etc/xray/sshx
fi
if [ -z ${iplim} ]; then
iplim="0"
fi
user=$(grep -E "^### " "/etc/xray/ssh" | cut -d ' ' -f 2 | sed -n "${CLIENT_NUMBER}"p)
exp=$(grep -E "^### " "/etc/xray/ssh" | cut -d ' ' -f 3 | sed -n "${CLIENT_NUMBER}"p)
echo "${iplim}" >/etc/xray/sshx/${user}IP
TEXT="
<code>◇━━━━━━━━━━━━━━◇</code>
<b>  SSH IP LIMIT</b>
<code>◇━━━━━━━━━━━━━━◇</code>
<b>DOMAIN   :</b> <code>${domain} </code>
<b>ISP      :</b> <code>$ISP $CITY </code>
<b>USERNAME :</b> <code>$user </code>
<b>EXPIRED  :</b> <code>$exp </code>
<b>IP LIMIT NEW :</b> <code>$iplim IP </code>
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
echo " SSH Account Was Successfully Change Limit IP"
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo " Client Name : $user"
echo " Limit IP    : $iplim IP"
echo ""
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
sshws
}
clear
function listssh(){
clear
echo -e "$COLOR1┌──────────────────────────────────────────┐${NC}"
echo -e "$COLOR1│ \033[1;37mPlease select a your Choice              $COLOR1│${NC}"
echo -e "$COLOR1└──────────────────────────────────────────┘${NC}"
echo -e "$COLOR1┌──────────────────────────────────────────┐${NC}"
echo -e "$COLOR1│  [ 1 ]  \033[1;37mAUTO LOCKED USER SSH      ${NC}"
echo -e "$COLOR1│  "
echo -e "$COLOR1│  [ 2 ]  \033[1;37mAUTO DELETE USER SSH    ${NC}"
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
echo "lock" > /etc/typessh
kn_top
kn_title "SETTING MULTI LOGIN"
kn_mid
kn_item1 "0" "Kembali ke menu"
kn_mid
sleep 1
elif [[ $lock == "2" ]]; then
clear
echo "delete" > /etc/typessh
kn_top
kn_title "SETTING MULTI LOGIN"
kn_mid
kn_item1 "0" "Kembali ke menu"
kn_mid
sleep 1
fi
type=$(cat /etc/typessh)
if [ $type = "lock" ]; then
clear
kn_top
kn_title "SETTING MULTI LOGIN"
kn_mid
kn_item1 "0" "Kembali ke menu"
kn_mid
read -rp "   Jumlah Waktu Lock: " -e notif2
echo "${notif2}" > /etc/waktulockssh
clear
kn_top
kn_title "SETTING MULTI LOGIN"
kn_bot
echo -e "$COLOR1┌───────────────────────────────────────────────┐${NC}"
echo -e "${COLOR1}│ $NC SILAHKAN TULIS JUMLAH NOTIFIKASI UNTUK AUTO LOCK    ${NC}"
echo -e "${COLOR1}│ $NC AKUN USER YANG MULTI LOGIN     ${NC}"
echo -e "$COLOR1└───────────────────────────────────────────────┘${NC}"
read -rp "   Jika Mau 3x Notif baru kelock tulis 3, dst: " -e notif
cd /etc/xray/sshx
echo "$notif" > notif
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
kn_mid
kn_item1 "0" "Kembali ke menu"
kn_mid
read -rp "   Tulis Waktu Scan (Menit) : " -e notif2
echo "# Autokill" >/etc/cron.d/tendang
echo "SHELL=/bin/sh" >>/etc/cron.d/tendang
echo "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin" >>/etc/cron.d/tendang
echo "*/$notif2 * * * *  root /usr/bin/tendang" >>/etc/cron.d/tendang
clear
kn_top
kn_title "SETTING MULTI LOGIN"
kn_bot
echo -e "$COLOR1┌───────────────────────────────────────────────┐${NC}"
echo -e "${COLOR1}│ $NC SILAHKAN TULIS JUMLAH NOTIFIKASI UNTUK AUTO LOCK    ${NC}"
echo -e "${COLOR1}│ $NC AKUN USER YANG MULTI LOGIN     ${NC}"
echo -e "$COLOR1└───────────────────────────────────────────────┘${NC}"
read -rp "   Jika Mau 3x Notif baru kelock tulis 3, dst: " -e notif
cd /etc/xray/sshx
echo "$notif" > notif
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
sshws
}
function lockssh(){
clear
cd
if [ ! -e /etc/xray/sshx/listlock ]; then
echo "" > /etc/xray/sshx/listlock
fi
NUMBER_OF_CLIENTS=$(grep -c -E "^### " "/etc/xray/sshx/listlock")
if [[ ${NUMBER_OF_CLIENTS} == '0' ]]; then
kn_top
kn_title "Unlock SSH Account"
kn_mid
echo ""
echo "You have no existing user Lock!"
echo ""
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
read -n 1 -s -r -p "Press any key to back on menu"
sshws
fi
clear
kn_top
kn_title "Unlock SSH Account"
kn_mid
kn_item1 "0" "Kembali ke menu"
kn_item1 "clear" "Padam semua akaun"
kn_mid
kn_userlist "^### " "/etc/xray/sshx/listlock"
kn_bot
until [[ ${CLIENT_NUMBER} -ge 1 && ${CLIENT_NUMBER} -le ${NUMBER_OF_CLIENTS} ]]; do
if [[ ${CLIENT_NUMBER} == '1' ]]; then
read -rp "Select one client [1]: " CLIENT_NUMBER
else
read -rp "Select one client [1-${NUMBER_OF_CLIENTS}] to Unlock: " CLIENT_NUMBER
if [[ ${CLIENT_NUMBER} == '0' ]]; then
sshws
fi
if [[ ${CLIENT_NUMBER} == 'clear' ]]; then
rm /etc/xray/sshx/listlock
sshws
fi
fi
done
user=$(grep -E "^### " "/etc/xray/sshx/listlock" | cut -d ' ' -f 2 | sed -n "${CLIENT_NUMBER}"p)
exp=$(grep -E "^### " "/etc/xray/sshx/listlock" | cut -d ' ' -f 3 | sed -n "${CLIENT_NUMBER}"p)
pass=$(grep -E "^### " "/etc/xray/sshx/listlock" | cut -d ' ' -f 4 | sed -n "${CLIENT_NUMBER}"p)
passwd -u $user &> /dev/null
echo -e "### $Login $exp $Pass" >> /etc/xray/ssh
sed -i "/^### $user $exp $pass/d" /etc/xray/sshx/listlock &> /dev/null
TEXT="
<code>◇━━━━━━━━━━━━━━◇</code>
<b>  SSH UNLOK </b>
<code>◇━━━━━━━━━━━━━━◇
<b>DOMAIN   :</b> <code>${domain} </code>
<b>ISP      :</b> <code>$ISP $CITY </code>
<b>USERNAME :</b> <code>$user </code>
<b>IP LIMIT  :</b> <code>$iplim IP </code>
<b>EXPIRED  :</b> <code>$exp </code>
<code>◇━━━━━━━━━━━━━━◇</code>
<i>Succes Unlock Akun...</i>
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
echo " SSH Account Unlock Successfully"
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo " Client Name : $user"
echo " Status  : Unlocked"
echo -e "$COLOR1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
sshws
}
clear
author=$(cat /etc/profil)
kn_top
kn_title "SSH PANEL MENU"
kn_mid
kn_item1 "01" "ADD AKUN"
kn_item1 "02" "TRIAL AKUN"
kn_item1 "03" "RENEW AKUN"
kn_item1 "04" "DELETE AKUN"
kn_item1 "05" "CEK USER ONLINE"
kn_item1 "06" "CEK USER CONFIG"
kn_item1 "07" "CHANGE IP LIMIT"
kn_item1 "08" "SETTING LOCK LOGIN"
kn_item1 "09" "UNLOCK LOGIN"
kn_item1 "00" "GO BACK"
kn_foot
echo ""
echo -e ""
echo -ne " ${WH}Select menu ${COLOR1}: ${WH}"; read opt
case $opt in
01 | 1) clear ; usernew  ;;
02 | 2) clear ; trial  ;;
03 | 3) clear ; renew  ;;
04 | 4) clear ; hapus  ;;
05 | 5) clear ; cek  ;;
06 | 6) clear ; cekconfig  ;;
07 | 7) clear ; limitssh ;;
08 | 8) clear ; listssh  ;;
09 | 9) clear ; lockssh  ;;
10 | 10) clear ; hapuslama  ;;
00 | 0) clear ; menu  ;;
X  | 0) clear ; sshws ;;
x) exit ;;
*) echo "Anda salah tekan " ; sleep 1 ; sshws ;;
esac
