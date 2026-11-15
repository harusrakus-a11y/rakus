#!/usr/bin/env bash
# telco - urus senarai telco dari Termux (tambah / buang / hantar ke GitHub)
RAW="https://raw.githubusercontent.com/harusrakus-a11y/rakus/refs/heads/main/menu/telco.conf"
EDIT="https://github.com/harusrakus-a11y/rakus/edit/main/menu/telco.conf"
D="${TELCO_HOME:-$HOME}"
F="$D/.telco.list"
S="$D/.telco.sent"

header() {
cat <<'EOT'
# nama|alamat|host|path|port
# {domain} = domain VPS (ditukar automatik). Nama tanpa ruang, guna sengkang.
# Jenis 1 (bug jadi subdomain): nama|BUG.{domain}|BUG|/vless|80
# Jenis 2 (IP Cloudflare):      nama|IP.CF|{domain}|/vless|80
EOT
}

default_list() {
cat <<'EOT'
celcom|mcmc-my.metricelltestcloud.com.{domain}|mcmc-my.metricelltestcloud.com|/vless|80
digi|104.18.21.212|{domain}|/vless|80
maxis-viu|help.viu.com.{domain}|help.viu.com|/vless|80
maxis-cmgo|104.16.160.145|cfcdn.viu.com.{domain}|/vless|80
yes|104.17.147.22|{domain}|/vless|80
tonewow|172.66.169.187|{domain}|/vless|80
EOT
}

RE='^[A-Za-z0-9_-]+\|[^|]+\|[^|]+\|/[^|]*\|[0-9]+$'

fetch() {
local t
t=$(mktemp)
if curl -fsSL --max-time 10 "$RAW" -o "$t" 2>/dev/null && grep -Eq "$RE" "$t"; then
grep -E '^[A-Za-z0-9_-]+\|' "$t" > "$F"
cp "$F" "$S"
rm -f "$t"
return 0
fi
rm -f "$t"
return 1
}

if [ ! -s "$F" ]; then
echo "Ambil senarai dari GitHub..."
if ! fetch; then
echo "GitHub tak dapat dicapai, guna senarai asal."
default_list > "$F"
cp "$F" "$S"
fi
fi

show() {
local i=0 n a h p q
echo ""
while IFS='|' read -r n a h p q; do
i=$((i+1))
echo " $i) $n"
echo "     alamat: $a"
echo "     host  : $h"
done < "$F"
echo ""
}

clean_host() {
local h=${1,,}
h=${h// /}
h=${h#http://}
h=${h#https://}
h=${h%%/*}
echo "$h"
}

ask_bug() {
local b
read -rp "Host bug (cth: help.viu.com): " b
b=$(clean_host "$b")
if [[ ! $b =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ || $b != *.* ]]; then
echo "Host bug tak sah."
return 1
fi
BUG=$b
}

ask_ip() {
local i
read -rp "IP Cloudflare (cth: 104.18.21.212): " i
i=${i// /}
local o
if [[ ! $i =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
echo "IP tak sah."
return 1
fi
for o in ${i//./ }; do
if (( 10#$o > 255 )); then
echo "IP tak sah."
return 1
fi
done
IP=$i
}

add() {
local nm kind rest line
read -rp "Nama telco (cth: unifi): " nm
nm=${nm,,}
nm=${nm// /-}
if [[ ! $nm =~ ^[a-z0-9_-]+$ ]]; then
echo "Nama tak sah (huruf, nombor, sengkang sahaja)."
return
fi
if grep -q "^$nm|" "$F"; then
echo "Nama tu dah ada."
return
fi
echo ""
echo "Jenis:"
echo " 1) Bug jadi subdomain      (macam celcom, maxis-viu)"
echo " 2) IP Cloudflare           (macam digi, yes, tonewow)"
echo " 3) IP Cloudflare + bug     (macam maxis-cmgo)"
echo " 4) Taip sendiri (alamat|host|path|port)"
read -rp "Pilih jenis [1-4]: " kind
case $kind in
1) ask_bug || return
line="$nm|$BUG.{domain}|$BUG|/vless|80" ;;
2) ask_ip || return
line="$nm|$IP|{domain}|/vless|80" ;;
3) ask_ip || return
ask_bug || return
line="$nm|$IP|$BUG.{domain}|/vless|80" ;;
4) read -rp "alamat|host|path|port : " rest
line="$nm|$rest" ;;
*) echo "Pilihan tak sah."
return ;;
esac
if [[ ! $line =~ $RE ]]; then
echo "Format tak sah."
return
fi
echo "$line" >> "$F"
echo "Siap, $nm ditambah."
}

del() {
local k total n y
show
total=$(wc -l < "$F")
read -rp "Nombor nak dibuang (kosong = batal): " k
[[ $k =~ ^[0-9]+$ ]] || return
if (( k < 1 || k > total )); then
echo "Nombor tak ada."
return
fi
n=$(sed -n "${k}p" "$F" | cut -d'|' -f1)
read -rp "Buang $n? (y/n): " y
if [ "$y" = y ]; then
sed -i "${k}d" "$F"
echo "Siap, $n dibuang."
fi
}

send() {
local t
t=$(mktemp)
{ header; cat "$F"; } > "$t"
if command -v termux-clipboard-set >/dev/null 2>&1 && timeout 5 termux-clipboard-set < "$t" 2>/dev/null; then
echo "Dah disalin ke clipboard."
else
echo "----- tekan lama, pilih & salin teks ni -----"
cat "$t"
echo "---------------------------------------------"
fi
rm -f "$t"
cp "$F" "$S"
echo ""
echo "Dalam GitHub: tekan dalam kotak teks, pilih semua,"
echo "Paste (ganti semua), lepas tu tekan Commit changes."
sleep 2
termux-open-url "$EDIT" 2>/dev/null || echo "$EDIT"
}

while true; do
echo ""
echo "===== SENARAI TELCO ====="
if ! cmp -s "$F" "$S"; then
echo "(ada ubahan belum dihantar ke GitHub)"
fi
echo " 1) Tambah telco"
echo " 2) Buang telco"
echo " 3) Tunjuk senarai"
echo " 4) Hantar ke GitHub (salin + buka halaman)"
echo " 5) Ambil senarai terkini dari GitHub"
echo " 0) Keluar"
read -rp "Pilih: " m || break
case $m in
1) add ;;
2) del ;;
3) show ;;
4) send ;;
5) if fetch; then echo "Siap, senarai dari GitHub."; else echo "Gagal ambil dari GitHub."; fi ;;
0) break ;;
*) echo "Pilihan tak sah." ;;
esac
done
