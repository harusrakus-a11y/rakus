#!/usr/bin/env bash
# kancil-scan - tool Termux: imbas domain app dari VPS, cari/test domain, hantar ke GitHub
# Developer by kancil ecem
#   bash kancil-scan.sh
# Fail disimpan dalam ~/.kancil (token GitHub, senarai domain, keputusan test)

D="${KANCIL_HOME:-$HOME/.kancil}"
mkdir -p "$D/hasil" 2>/dev/null
TOK="$D/token"
LOC="$D/domains.txt"
SENT="$D/domains.sent"
REPO_D="harusrakus-a11y/Data"
PATH_D="domains.txt"
RAWD="https://raw.githubusercontent.com/$REPO_D/refs/heads/main/$PATH_D"
UA="Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Mobile Safari/537.36"
LINE="──────────────────────────────────────"

R=$'\033[1;31m'; G=$'\033[1;32m'; Y=$'\033[1;33m'; W=$'\033[1;37m'; C=$'\033[1;36m'; N=$'\033[0m'

# domain kongsi (CDN/platform): kekalkan nama penuh, jangan ambil domain induk
CDN="cloudfront.net akamaized.net akamaihd.net edgekey.net edgesuite.net fastly.net azureedge.net amazonaws.com cloudflare.net cloudflare.com googleapis.com googleusercontent.com gstatic.com appspot.com herokuapp.com vercel.app netlify.app pages.dev workers.dev b-cdn.net jsdelivr.net github.io blogspot.com firebaseapp.com web.app trafficmanager.net windows.net llnwd.net edgecastcdn.net"
# domain besar: jangan hantar semua trafik ke Arca
BIG="google.com youtube.com facebook.com instagram.com whatsapp.com whatsapp.net tiktok.com microsoft.com apple.com amazon.com twitter.com x.com live.com bing.com linkedin.com"
# bising (muncul dalam HTML tapi bukan sasaran)
NOISE="w3.org schema.org ogp.me gmpg.org purl.org xmlns.com mozilla.org jquery.com bootstrapcdn.com fontawesome.com googleapis.com gstatic.com google-analytics.com googletagmanager.com doubleclick.net facebook.net facebook.com twitter.com instagram.com youtube.com ytimg.com jsdelivr.net unpkg.com gravatar.com wp.com wordpress.org"

TMPS=()
mk() { local t; t=$(mktemp -d); TMPS+=("$t"); echo "$t"; }
trap 'for t in "${TMPS[@]}"; do rm -rf "$t"; done' EXIT

pause() { echo ""; read -n 1 -s -r -p " Tekan mana-mana kekunci"; echo ""; }
title() { echo ""; echo "$C$LINE$N"; echo "$W  $1$N"; echo "$C$LINE$N"; }

# ---------- alat domain ----------
norm() { local h=${1,,}; h=${h// /}; h=${h#http://}; h=${h#https://}; h=${h%%/*}; h=${h%%:*}; h=${h#\*.}; echo "$h"; }
valid() { [[ "$1" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ && "$1" == *.* ]]; }
in_list() { local x w; x=$1; shift; for w in $*; do [[ "$x" == "$w" || "$x" == *".$w" ]] && return 0; done; return 1; }
induk() {
    local h=$1 s t n base L
    if in_list "$h" $CDN; then echo "$h"; return; fi
    IFS=. read -ra L <<< "$h"; n=${#L[@]}
    [ "$n" -le 2 ] && { echo "$h"; return; }
    t=${L[n-1]}; s=${L[n-2]}
    if [ ${#t} -eq 2 ] && [[ " com net org gov edu co ac mil or ne go " == *" $s "* ]]; then base="${L[n-3]}.$s.$t"; else base="$s.$t"; fi
    echo "$base"
}

# ---------- GitHub ----------
AUTH=()
load_auth() { AUTH=(); [ -s "$TOK" ] && AUTH=(-H "Authorization: Bearer $(tr -d ' \r\n' < "$TOK")"); }
have_tok() { [ -s "$TOK" ]; }
gh_get() {   # repo path fail_keluar
    local code
    load_auth
    code=$(curl -sS -m 20 -o "$3" -w '%{http_code}' "${AUTH[@]}" -H "Accept: application/vnd.github.raw" "https://api.github.com/repos/$1/contents/$2" 2>/dev/null)
    [ "$code" = 200 ]
}
gh_put() {   # repo path fail mesej
    local sha b64 body code
    load_auth
    sha=$(curl -s -m 20 "${AUTH[@]}" "https://api.github.com/repos/$1/contents/$2" 2>/dev/null | grep -m1 -o '"sha": *"[0-9a-f]\{40\}"' | grep -o '[0-9a-f]\{40\}')
    b64=$(base64 -w0 "$3" 2>/dev/null || base64 "$3" | tr -d '\n')
    body=$(mktemp)
    if [ -n "$sha" ]; then printf '{"message":"%s","content":"%s","sha":"%s"}' "$4" "$b64" "$sha" > "$body"
    else printf '{"message":"%s","content":"%s"}' "$4" "$b64" > "$body"; fi
    code=$(curl -sS -m 40 -o "$body.r" -w '%{http_code}' -X PUT "${AUTH[@]}" -H "Accept: application/vnd.github+json" -d @"$body" "https://api.github.com/repos/$1/contents/$2" 2>/dev/null)
    rm -f "$body" "$body.r"
    case "$code" in
        200|201) return 0 ;;
        401) echo " ${R}Token salah atau tamat. Betulkan di menu 6.$N" ;;
        403|404) echo " ${R}Token tiada kebenaran tulis untuk $1 (Contents: Read and write).$N" ;;
        409|422) echo " ${R}Fail berubah masa hantar. Cuba lagi.$N" ;;
        *) echo " ${R}Gagal hantar (kod $code). Semak internet.$N" ;;
    esac
    return 1
}
need_tok() {
    have_tok && return 0
    echo " ${Y}Token GitHub belum ada. Pergi menu 6 dulu.$N"
    return 1
}

# ---------- senarai domain tempatan ----------
ensure_loc() {
    [ -f "$LOC" ] && return 0
    local t; t=$(mktemp)
    if curl -fsSL -m 15 "$RAWD?x=$(date +%s)" -o "$t" 2>/dev/null && [ -s "$t" ]; then
        grep -E '^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$' "$t" | sort -u > "$LOC"; cp "$LOC" "$SENT"; rm -f "$D/.belum-sync"
    else
        : > "$LOC"; : > "$SENT"; : > "$D/.belum-sync"
    fi
    rm -f "$t"
}
add_domains() {   # domain...  -> tambah ke senarai tempatan, cetak bilangan baru
    local d n=0
    ensure_loc
    for d in "$@"; do
        valid "$d" || continue
        grep -qx "$d" "$LOC" 2>/dev/null && continue
        echo "$d" >> "$LOC"; n=$((n+1))
    done
    sort -u "$LOC" -o "$LOC"
    echo "$n"
}
pending() { ensure_loc; [ -f "$SENT" ] || : > "$SENT"; ! cmp -s "$LOC" "$SENT"; }

# ---------- 1) CARI DOMAIN ----------
resolve() {   # host -> IP pertama atau kosong
    curl -s -m 6 "https://dns.google/resolve?name=$1&type=A" 2>/dev/null | grep -o '"data":"[0-9.]*"' | head -n1 | cut -d'"' -f4
}
scrape() {   # url fail_keluar
    local pg base js u n=0
    pg=$(mktemp)
    curl -sL -m 15 --max-filesize 1500000 -A "$UA" "$1" -o "$pg" 2>/dev/null || true
    [ -s "$pg" ] || { rm -f "$pg"; return; }
    grep -oE '(https?:)?//[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$pg" | sed -E 's#^(https?:)?//##' >> "$2"
    base=$(echo "$1" | sed -E 's#^(https?://[^/]+).*#\1#')
    grep -oE "src=[\"'][^\"']+\.js[^\"']*[\"']" "$pg" | sed -E "s/^src=[\"']//;s/[\"']$//" | head -n 6 | while read -r js; do
        case "$js" in
            //*) u="https:$js" ;;
            http*) u="$js" ;;
            /*) u="$base$js" ;;
            *) u="$base/$js" ;;
        esac
        curl -sL -m 12 --max-filesize 2000000 -A "$UA" "$u" 2>/dev/null | grep -oE '(https?:)?//[A-Za-z0-9.-]+\.[A-Za-z]{2,}' | sed -E 's#^(https?:)?//##' >> "$2"
    done
    rm -f "$pg"
}
pick() {   # "1 3 5-7 a" jumlah -> cetak nombor terpilih
    local inp=$1 max=$2 t a b i
    inp=${inp//,/ }
    for t in $inp; do
        if [[ "$t" == a || "$t" == A ]]; then seq 1 "$max"; return; fi
        if [[ "$t" =~ ^[0-9]+$ ]]; then [ "$t" -ge 1 ] && [ "$t" -le "$max" ] && echo "$t"
        elif [[ "$t" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            a=${BASH_REMATCH[1]}; b=${BASH_REMATCH[2]}
            for (( i=a; i<=b && i<=max; i++ )); do [ "$i" -ge 1 ] && echo "$i"; done
        fi
    done | sort -un
}
t_cari() {
    local inp d tmp all h i k=0 sel hosts=() ips=() tag dom doms=() skipped=() cnt
    title "CARI DOMAIN APP / WEBSITE"
    read -rp " Domain atau website (cth astro.com.my): " inp
    d=$(norm "$inp")
    valid "$d" || { echo " ${R}Domain tak sah.$N"; pause; return; }
    tmp=$(mk); all="$tmp/all"; : > "$all"
    echo " Cari dalam sijil (crt.sh)..."
    curl -s -m 25 "https://crt.sh/?q=%25.$d&output=json" 2>/dev/null | grep -o '"name_value":"[^"]*"' | sed 's/"name_value":"//;s/"$//;s/\\n/\n/g' >> "$all"
    echo " Cari subdomain (hackertarget)..."
    curl -s -m 20 "https://api.hackertarget.com/hostsearch/?q=$d" 2>/dev/null | grep ',' | cut -d, -f1 >> "$all"
    echo " Baca laman web dan fail JS..."
    scrape "https://$d" "$all"
    scrape "https://www.$d" "$all"
    # tapis
    tr 'A-Z' 'a-z' < "$all" | sed 's/^\*\.//' | while read -r h; do
        valid "$h" || continue
        if [[ "$h" == "$d" || "$h" == *".$d" ]]; then echo "0 $h"
        else in_list "$h" $NOISE && continue; echo "1 $h"; fi
    done | sort -u -k2,2 | sort -k1,1 -s | head -n 80 > "$tmp/c"
    cnt=$(wc -l < "$tmp/c")
    [ "$cnt" -gt 0 ] || { echo " ${Y}Tiada domain jumpa. Cuba domain lain.$N"; pause; return; }
    echo " Semak $cnt domain (DNS)..."
    i=0
    while read -r tag h; do
        i=$((i+1))
        ( ip=$(resolve "$h"); echo "$tag $h $ip" > "$tmp/r.$(printf '%03d' $i)" ) &
        (( i % 10 == 0 )) && wait
    done < "$tmp/c"
    wait
    cat "$tmp"/r.* 2>/dev/null | while read -r tag h ip; do [ -n "$ip" ] && echo "$tag $h"; done > "$tmp/alive"
    cnt=$(wc -l < "$tmp/alive")
    [ "$cnt" -gt 0 ] || { echo " ${Y}Semua tak berjawab DNS.$N"; pause; return; }
    echo ""; echo "$C$LINE$N"
    while read -r tag h; do
        k=$((k+1)); hosts+=("$h")
        if [ "$tag" = 1 ]; then printf ' %s%2d%s) %s %s(luar)%s\n' "$W" "$k" "$N" "$h" "$Y" "$N"; else printf ' %s%2d%s) %s\n' "$W" "$k" "$N" "$h"; fi
    done < "$tmp/alive"
    echo "$C$LINE$N"
    echo " Pilih: nombor (1 3 5-7), a = semua, kosong = batal"
    read -rp " > " sel
    [ -z "$sel" ] && return
    for i in $(pick "$sel" "$k"); do
        dom=$(induk "${hosts[$((i-1))]}")
        if in_list "$dom" $BIG; then skipped+=("$dom"); continue; fi
        doms+=("$dom")
    done
    doms=($(printf '%s\n' "${doms[@]}" | sort -u))
    [ ${#skipped[@]} -gt 0 ] && echo " ${Y}Dilangkau (domain besar, trafik banyak): $(printf '%s\n' "${skipped[@]}" | sort -u | tr '\n' ' ')$N"
    [ ${#doms[@]} -gt 0 ] || { pause; return; }
    echo ""; echo " ${W}Akan ditambah ke senarai geo (${#doms[@]}):$N"
    printf '   %s\n' "${doms[@]}"
    read -rp " Tambah? (y/n): " k
    if [ "$k" = y ] || [ "$k" = Y ]; then
        cnt=$(add_domains "${doms[@]}")
        echo " ${G}$cnt baru ditambah.$N Guna menu 5 untuk hantar ke GitHub."
    fi
    pause
}

# ---------- 2) TEST LEPAS / SEKAT GEO ----------
GEO_RE='not available in your (country|region|location|area)|unavailable in your|not available (in|for) (your|this) (country|region|location)|restricted in your|blocked in your|tidak (tersedia|boleh diakses) (di|dalam)|only available in|available only in|outside (of )?malaysia|access from your (country|location|region)'
geo_test() {   # host -> "STATUS kod"
    local b code
    b=$(mktemp)
    code=$(curl -sL -m 8 --connect-timeout 5 --max-filesize 400000 -A "$UA" -o "$b" -w '%{http_code}' "https://$1/" 2>/dev/null)
    [ -n "$code" ] || code=000
    if [ "$code" = 000 ]; then echo "MATI 000"
    elif [ "$code" = 451 ] || head -c 400000 "$b" 2>/dev/null | grep -qiE "$GEO_RE"; then echo "SEKAT $code"
    elif [ "$code" = 403 ]; then echo "TOLAK 403"
    else echo "LEPAS $code"; fi
    rm -f "$b"
}
my_country() {
    local c
    c=$(curl -s -m 6 https://ipinfo.io/country 2>/dev/null | tr -d ' \r\n')
    [[ "$c" =~ ^[A-Z]{2}$ ]] || c=$(curl -s -m 6 https://api.country.is 2>/dev/null | grep -o '"country":"[A-Z][A-Z]"' | cut -d'"' -f4)
    [[ "$c" =~ ^[A-Z]{2}$ ]] || c=XX
    echo "$c"
}
run_geo() {   # domain...   (cetak jadual, simpan ke hasil/CC.tsv)
    local cc tmp i=0 h st f o c code
    cc=$(my_country)
    tmp=$(mk)
    echo " Negara rangkaian sekarang: ${W}$cc$N"
    [ "$cc" = XX ] && echo " ${Y}Negara tak dapat dikenal pasti. Keputusan disimpan sebagai XX.$N"
    for h in "$@"; do
        i=$((i+1))
        ( echo "$h $(geo_test "$h")" > "$tmp/o.$(printf '%03d' $i)" ) &
        (( i % 8 == 0 )) && wait
    done
    wait
    f="$D/hasil/$cc.tsv"; touch "$f"
    echo "$C$LINE$N"
    for o in "$tmp"/o.*; do
        read -r h st code < "$o"
        case "$st" in LEPAS) c=$G;; SEKAT|TOLAK) c=$R;; *) c=$Y;; esac
        printf ' %s%-6s%s %s\n' "$c" "$st" "$N" "$h"
        grep -v "^$h"$'\t' "$f" > "$f.t" 2>/dev/null; mv "$f.t" "$f"
        printf '%s\t%s\t%s\n' "$h" "$st" "$code" >> "$f"
    done
    echo "$C$LINE$N"
    echo " Disimpan: hasil/$cc.tsv"
}
t_banding() {
    local files=() f a b cc ccs=() sel base other h st n=0 cand=() x
    for f in "$D"/hasil/*.tsv; do [ -s "$f" ] && files+=("$f"); done
    if [ ${#files[@]} -lt 2 ]; then
        echo " ${Y}Perlu keputusan dari 2 negara. Test sekali guna rangkaian biasa (MY),$N"
        echo " ${Y}lepas tu hidupkan VPN ke Singapore dan test lagi.$N"
        return
    fi
    for f in "${files[@]}"; do cc=$(basename "$f" .tsv); ccs+=("$cc"); done
    echo " Keputusan ada untuk: ${ccs[*]}"
    read -rp " Negara asas (cth MY): " base; base=${base^^}
    read -rp " Banding dengan (cth SG): " other; other=${other^^}
    [ -s "$D/hasil/$base.tsv" ] && [ -s "$D/hasil/$other.tsv" ] || { echo " ${R}Fail negara tu tiada.$N"; return; }
    declare -A A B
    while IFS=$'\t' read -r h st x; do A[$h]=$st; done < "$D/hasil/$base.tsv"
    while IFS=$'\t' read -r h st x; do B[$h]=$st; done < "$D/hasil/$other.tsv"
    echo "$C$LINE$N"
    for h in "${!A[@]}"; do
        [ "${A[$h]}" = LEPAS ] || continue
        [ -n "${B[$h]}" ] || continue
        if [ "${B[$h]}" != LEPAS ]; then n=$((n+1)); cand+=("$h"); printf ' %s%2d%s) %s  (%s: %s, %s: %s)\n' "$W" "$n" "$N" "$h" "$base" "${A[$h]}" "$other" "${B[$h]}"; fi
    done
    echo "$C$LINE$N"
    [ "$n" -gt 0 ] || { echo " ${Y}Tiada domain yang beza antara $base dan $other.$N"; return; }
    echo " Ini domain yang jalan di $base tapi tak di $other: patut ikut pusat."
    echo " Pilih nombor untuk tambah ke senarai geo (a = semua, kosong = batal)"
    read -rp " > " sel
    [ -z "$sel" ] && return
    local add=()
    for x in $(pick "$sel" "$n"); do add+=("${cand[$((x-1))]}"); done
    [ ${#add[@]} -gt 0 ] && echo " ${G}$(add_domains "${add[@]}") baru ditambah.$N Guna menu 5 untuk hantar."
}
t_geo() {
    local m inp doms=()
    while true; do
        title "TEST LEPAS / SEKAT GEO"
        echo " 1) Test senarai geo sekarang"
        echo " 2) Test domain yang aku taip"
        echo " 3) Banding dua negara"
        echo " 0) Kembali"
        read -rp " Pilih: " m || return
        case "$m" in
            1) ensure_loc
               mapfile -t doms < <(grep -E '^[A-Za-z0-9]' "$LOC")
               if [ ${#doms[@]} -eq 0 ]; then echo " ${Y}Senarai kosong.$N"; else run_geo "${doms[@]}"; fi
               pause ;;
            2) read -rp " Domain (asing dengan ruang): " inp
               doms=(); for x in $inp; do x=$(norm "$x"); valid "$x" && doms+=("$x"); done
               if [ ${#doms[@]} -eq 0 ]; then echo " ${R}Tiada domain sah.$N"; else run_geo "${doms[@]}"; fi
               pause ;;
            3) t_banding; pause ;;
            0|"") return ;;
        esac
    done
}

# ---------- 3) IMBAS DOMAIN DARI VPS (app guna VLESS dll) ----------
VPSF="$D/vps"
PROTOS=(vless vmess trojan ssh semua)
get_vps() {   # cetak "host port"
    local h p
    if [ -s "$VPSF" ]; then cat "$VPSF"; return 0; fi
    read -rp " IP atau domain VPS DNS (yang ada imbas): " h >&2
    h=$(norm "$h")
    [[ "$h" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] || return 1
    read -rp " Port SSH (Enter = 22): " p >&2
    [ -z "$p" ] && p=22
    [[ "$p" =~ ^[0-9]+$ ]] || return 1
    echo "$h $p" > "$VPSF"; echo "$h $p"
}
parse_imbas() {   # fail -> baris: domain kali dari
    local l on=0 re='^[[:space:]]*([0-9]+)[[:space:]]+([a-z0-9][a-z0-9.-]*)[[:space:]]+([0-9]+)[[:space:]]+(.+)$'
    while IFS= read -r l; do
        case "$l" in
            *"Calon domain"*) on=1; continue ;;
            "("*) [ "$on" = 1 ] && break ;;
        esac
        [ "$on" = 1 ] || continue
        if [[ "$l" =~ $re ]]; then echo "${BASH_REMATCH[2]} ${BASH_REMATCH[3]} ${BASH_REMATCH[4]}"; fi
    done < <(tr -d '\r' < "$1" | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g')
}
SSHO=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -o ServerAliveInterval=10)
rsh() { ssh "${SSHO[@]}" -p "$RPORT" "root@$RHOST" "$1"; }
has_key() { [ -f "$HOME/.ssh/id_ed25519" ] || [ -f "$HOME/.ssh/id_rsa" ]; }
t_imbas() {
    local hp m pr secs akun tmp out rc k i sel cand=() doms=() skipped=() d n lab cnt x
    title "IMBAS DOMAIN DARI VPS"
    command -v ssh >/dev/null 2>&1 || { echo " ${R}ssh belum ada. Taip: pkg install openssh$N"; pause; return; }
    hp=$(get_vps) || { echo " ${R}Maklumat VPS tak sah.$N"; pause; return; }
    RHOST=${hp% *}; RPORT=${hp#* }
    echo " VPS: $W$RHOST:$RPORT$N   (tukar di menu 6)"
    has_key && echo " Kunci SSH: ${G}ada$N (tak perlu password)" || echo " Kunci SSH: ${Y}belum$N. Menu 6 > 5 supaya tak perlu password."
    echo ""
    echo " Protokol yang app guna:"
    echo "  1) VLESS   2) VMess   3) Trojan   4) SSH   5) Semua"
    read -rp " Pilih [1]: " m; [ -z "$m" ] && m=1
    [[ "$m" =~ ^[1-5]$ ]] || { echo " ${R}Pilihan tak sah.$N"; pause; return; }
    pr=${PROTOS[$((m-1))]}
    read -rp " Berapa saat [120]: " secs; [ -z "$secs" ] && secs=120
    [[ "$secs" =~ ^[0-9]+$ ]] && [ "$secs" -ge 30 ] && [ "$secs" -le 600 ] || { echo " ${R}30 hingga 600 saat.$N"; pause; return; }
    akun=""
    if [ "$pr" != ssh ] && [ "$pr" != semua ]; then
        read -rp " Nama akaun kau (Enter = semua akaun): " akun
        akun=${akun// /}
        [[ -z "$akun" || "$akun" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo " ${R}Nama akaun tak sah.$N"; pause; return; }
    fi
    command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock 2>/dev/null
    echo ""
    echo " ${W}Langkah 1: mulakan imbas kat VPS.$N"
    has_key || echo " ${Y}Password VPS diminta. TAIP terus, jangan keluar dari Termux.$N"
    out=$(rsh "[ -x /usr/local/bin/imbas ] || { echo TIADA_IMBAS; exit 1; }; nohup env YA=1 /usr/local/bin/imbas $secs $pr $akun > /root/.imbas-out.txt 2>&1 < /dev/null & echo MULA_OK")
    rc=$?
    if echo "$out" | grep -q TIADA_IMBAS; then
        echo " ${R}imbas belum dipasang kat VPS tu. Pasang dulu (BARIS F dalam ARAHAN-PASANG.txt).$N"
        command -v termux-wake-unlock >/dev/null 2>&1 && termux-wake-unlock 2>/dev/null; pause; return
    fi
    if ! echo "$out" | grep -q MULA_OK; then
        echo " ${R}Tak dapat mulakan imbas (kod $rc). Semak IP, port dan password. Matikan VPN kalau hidup.$N"
        command -v termux-wake-unlock >/dev/null 2>&1 && termux-wake-unlock 2>/dev/null; pause; return
    fi
    echo ""
    echo " ${G}Imbas dah jalan kat VPS selama $secs saat.$N"
    echo "   1. Hidupkan VPN VLESS kat phone"
    echo "   2. Buka app tu, biar video atau laman load"
    echo "   3. Lepas $secs saat, MATIKAN VPN dan balik ke Termux"
    echo ""
    tmp=$(mk)
    while true; do
        if ! read -rp " Bila dah balik dan VPN dimatikan, tekan Enter (x = batal): " x || [ "$x" = x ] || [ "$x" = X ]; then
            command -v termux-wake-unlock >/dev/null 2>&1 && termux-wake-unlock 2>/dev/null
            return
        fi
        out=$(rsh 'f=/root/.imbas-out.txt; [ -f $f ] || { echo TIADA_FAIL; exit 0; }; cat $f; grep -q "Log imbasan dah dimatikan" $f && rm -f $f')
        rc=$?
        if [ "$rc" -eq 255 ] || [ -z "$out" ]; then echo " ${R}Tak dapat sambung SSH. Matikan VPN, kemudian cuba lagi.$N"; continue; fi
        if echo "$out" | grep -q TIADA_FAIL; then echo " ${R}Fail imbas tak jumpa kat VPS. Cuba mula semula.$N"; pause; return; fi
        if echo "$out" | grep -q "Log imbasan dah dimatikan"; then break; fi
        echo " ${Y}Imbas belum siap. Tunggu sebentar.$N"
    done
    command -v termux-wake-unlock >/dev/null 2>&1 && termux-wake-unlock 2>/dev/null
    echo "$out" > "$tmp/out"
    echo "$C$LINE$N"
    tr -d '\r' < "$tmp/out" | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | sed -n '/===== HASIL =====/,/Log imbasan dah dimatikan/p' | grep -v 'Log imbasan'
    echo "$C$LINE$N"
    parse_imbas "$tmp/out" > "$tmp/cand"
    cnt=$(wc -l < "$tmp/cand")
    if [ "$cnt" -eq 0 ]; then
        echo " ${Y}Tiada calon domain baru. Baca ringkasan atas untuk sebab.$N"
        pause; return
    fi
    echo " ${W}Calon domain ($cnt):$N"
    k=0
    while read -r d n lab; do
        k=$((k+1)); cand+=("$d")
        printf ' %s%2d%s) %-26s %s%sx %s%s\n' "$W" "$k" "$N" "$d" "$Y" "$n" "$lab" "$N"
    done < "$tmp/cand"
    echo "$C$LINE$N"
    echo " Pilih yang betul milik app tu: nombor (1 3 5-7), a = semua, kosong = batal"
    read -rp " > " sel
    [ -z "$sel" ] && return
    for i in $(pick "$sel" "$k"); do
        d=${cand[$((i-1))]}
        if in_list "$d" $BIG; then skipped+=("$d"); continue; fi
        doms+=("$d")
    done
    [ ${#skipped[@]} -gt 0 ] && echo " ${Y}Dilangkau (domain besar): ${skipped[*]}$N"
    [ ${#doms[@]} -gt 0 ] || { pause; return; }
    n=$(add_domains "${doms[@]}")
    echo " ${G}$n baru ditambah ke senarai tempatan$N (${#doms[@]} dipilih, yang dah ada dilangkau)."
    read -rp " Hantar ke GitHub sekarang? (y/n): " m
    if [ "$m" = y ] || [ "$m" = Y ]; then t_hantar; return; fi
    pause
}
setup_key() {
    local hp key out
    command -v ssh-keygen >/dev/null 2>&1 || { echo " ${R}Taip: pkg install openssh$N"; return 1; }
    hp=$(get_vps) || { echo " ${R}Maklumat VPS tak sah.$N"; return 1; }
    RHOST=${hp% *}; RPORT=${hp#* }
    mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
    [ -f "$HOME/.ssh/id_ed25519" ] || ssh-keygen -q -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519"
    key=$(cat "$HOME/.ssh/id_ed25519.pub")
    echo " Taip password VPS (sekali sahaja):"
    out=$(rsh "mkdir -p ~/.ssh && chmod 700 ~/.ssh && { grep -qxF '$key' ~/.ssh/authorized_keys 2>/dev/null || echo '$key' >> ~/.ssh/authorized_keys; } && chmod 600 ~/.ssh/authorized_keys && echo KUNCI_OK")
    echo "$out" | grep -q KUNCI_OK || { echo " ${R}Gagal pasang kunci. Semak password dan port.$N"; return 1; }
    if ssh "${SSHO[@]}" -o BatchMode=yes -p "$RPORT" "root@$RHOST" 'echo OK' 2>/dev/null | grep -q OK; then
        echo " ${G}Kunci berfungsi. Lepas ni tak perlu password.$N"
    else
        echo " ${Y}Kunci dipasang tapi VPS tak terima. Imbas masih boleh guna password.$N"
    fi
}

# ---------- 4) SENARAI DOMAIN GEO ----------
t_senarai() {
    local m k i n arr x
    ensure_loc
    while true; do
        title "SENARAI DOMAIN GEO"
        pending && echo " ${Y}(ada ubahan belum dihantar ke GitHub)$N"
        mapfile -t arr < <(grep -E '^[A-Za-z0-9]' "$LOC")
        n=${#arr[@]}
        if [ "$n" -eq 0 ]; then echo " (kosong)"; else i=0; for x in "${arr[@]}"; do i=$((i+1)); printf ' %s%2d%s) %s\n' "$W" "$i" "$N" "$x"; done; fi
        echo "$C$LINE$N"
        echo " t) tambah manual   b) buang nombor"
        echo " g) ambil dari GitHub (ganti senarai ni)"
        echo " 0) kembali"
        read -rp " Pilih: " m || return
        case "$m" in
            t|T) read -rp " Domain (asing dengan ruang): " k
                 arr=(); for x in $k; do x=$(norm "$x"); valid "$x" && arr+=("$x"); done
                 [ ${#arr[@]} -gt 0 ] && echo " ${G}$(add_domains "${arr[@]}") baru ditambah.$N" ;;
            b|B) read -rp " Nombor nak dibuang (1 3 5-7): " k
                 for i in $(pick "$k" "$n"); do x=${arr[$((i-1))]}; grep -vx "$x" "$LOC" > "$LOC.t"; mv "$LOC.t" "$LOC"; echo "   - $x"; done ;;
            g|G) read -rp " Ganti senarai tempatan dengan GitHub? (y/n): " k
                 if [ "$k" = y ] || [ "$k" = Y ]; then rm -f "$LOC" "$SENT"; ensure_loc; echo " Siap."; fi ;;
            0|"") return ;;
        esac
    done
}

# ---------- 5) HANTAR KE GITHUB ----------
t_hantar() {
    local tmp add del x cnt sy
    title "HANTAR SENARAI KE GITHUB"
    ensure_loc
    need_tok || { pause; return; }
    tmp=$(mk)
    if gh_get "$REPO_D" "$PATH_D" "$tmp/remote"; then
        grep -E '^[A-Za-z0-9]' "$tmp/remote" | sort -u > "$tmp/r"
    else
        : > "$tmp/r"; echo " ${Y}domains.txt belum ada di GitHub, akan dicipta.$N"
    fi
    if [ -f "$D/.belum-sync" ] && [ -s "$tmp/r" ]; then
        sort -u "$tmp/r" "$LOC" -o "$LOC"; rm -f "$D/.belum-sync"
        echo " ${Y}Tadi luar talian, senarai digabung dengan GitHub.$N"
    fi
    grep -E '^[A-Za-z0-9]' "$LOC" | sort -u > "$tmp/l"
    if [ ! -s "$tmp/l" ]; then echo " ${R}Senarai kosong, tak dihantar.$N"; pause; return; fi
    add=$(comm -13 "$tmp/r" "$tmp/l"); del=$(comm -23 "$tmp/r" "$tmp/l")
    if [ -z "$add$del" ]; then echo " ${G}Tiada beza dengan GitHub. Semua dah sama.$N"; else
        [ -n "$add" ] && { echo " ${G}Tambah:$N"; echo "$add" | sed 's/^/   + /'; }
        [ -n "$del" ] && { echo " ${R}Buang:$N";  echo "$del" | sed 's/^/   - /'; }
        if [ -n "$del" ] && [ "$(echo "$del" | wc -l)" -ge 5 ]; then
            echo " ${R}$(echo "$del" | wc -l) domain akan DIBUANG dari GitHub.$N"
            read -rp " Taip BUANG untuk teruskan: " x
            [ "$x" = BUANG ] || { echo " Dibatalkan."; pause; return; }
        else
            read -rp " Hantar? (y/n): " x
            [ "$x" = y ] || [ "$x" = Y ] || { pause; return; }
        fi
        { echo "# Senarai domain geo (kancil-scan). Satu domain satu baris."; cat "$tmp/l"; } > "$tmp/out"
        cnt=$(wc -l < "$tmp/l")
        if gh_put "$REPO_D" "$PATH_D" "$tmp/out" "kancil-scan: $cnt domain"; then
            cp "$LOC" "$SENT"; echo " ${G}Siap. $cnt domain di GitHub.$N"
        else pause; return; fi
    fi
    sy='curl -fsSL "https://raw.githubusercontent.com/'$REPO_D'/refs/heads/main/'$PATH_D'?x=$(date +%s)" | grep -E '"'"'^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$'"'"
    {
        echo "# PUSAT (kat VPS pusat):"
        echo "bash /root/pusat-vps.sh tambah \$($sy)"
        echo "# VPS DNS (kat setiap VPS DNS):"
        echo "bash /root/dns-geo.sh tambah \$($sy)"
    } > "$D/sync-pusat.txt"
    echo ""
    echo " ${W}Lepas ${Y}~5 minit$W (cache GitHub), paste kat pusat dan VPS DNS:$N"
    echo ""
    cat "$D/sync-pusat.txt"
    if command -v termux-clipboard-set >/dev/null 2>&1; then
        timeout 5 termux-clipboard-set < "$D/sync-pusat.txt" 2>/dev/null && echo "" && echo " ${G}Dah disalin ke clipboard.$N"
    fi
    pause
}

# ---------- 6) TETAPAN ----------
t_tetap() {
    local m tk code
    while true; do
        title "TETAPAN"
        if have_tok; then echo " Token GitHub : ${G}ada$N"; else echo " Token GitHub : ${R}belum$N"; fi
        echo " VPS imbas    : $(cat "$VPSF" 2>/dev/null | tr ' ' ':' || echo -)"
        echo " 1) Letak / tukar token GitHub"
        echo " 2) Semak token"
        echo " 3) Padam token"
        echo " 4) Tukar VPS imbas"
        echo " 5) Sediakan kunci SSH (tak perlu password)"
        echo " 0) Kembali"
        read -rp " Pilih: " m || return
        case "$m" in
            1) echo ""
               echo " Cara buat token (sekali sahaja):"
               echo "  1. Buka github.com/settings/personal-access-tokens/new"
               echo "  2. Nama: kancil. Repository access: Only select"
               echo "     repositories, pilih Data."
               echo "  3. Permissions > Contents: Read and write."
               echo "  4. Generate token, salin, tampal di bawah."
               read -rsp " Token: " tk; echo ""
               tk=$(echo "$tk" | tr -d ' \r\n')
               if [ ${#tk} -lt 20 ]; then echo " ${R}Token terlalu pendek.$N"; else
                   ( umask 077; echo "$tk" > "$TOK" ); load_auth
                   code=$(curl -s -m 15 -o /dev/null -w '%{http_code}' "${AUTH[@]}" "https://api.github.com/repos/$REPO_D" 2>/dev/null)
                   if [ "$code" = 200 ]; then echo " ${G}Token berfungsi.$N"; else echo " ${R}Token disimpan tapi GitHub jawab $code. Semak kebenaran.$N"; fi
               fi
               pause ;;
            2) load_auth
               code=$(curl -s -m 15 -o /dev/null -w '%{http_code}' "${AUTH[@]}" "https://api.github.com/repos/$REPO_D" 2>/dev/null)
               [ "$code" = 200 ] && echo " ${G}Token berfungsi.$N" || echo " ${R}GitHub jawab $code.$N"
               pause ;;
            3) rm -f "$TOK"; echo " Token dipadam."; sleep 1 ;;
            4) rm -f "$VPSF"; get_vps >/dev/null && echo " Disimpan."; sleep 1 ;;
            5) setup_key; pause ;;
            0|"") return ;;
        esac
    done
}

# ---------- menu utama ----------
while true; do
    title "KANCIL SCAN"
    pending && echo " ${Y}(senarai geo ada ubahan belum dihantar)$N"
    echo " 1) Imbas domain dari VPS (app + VLESS)"
    echo " 2) Cari domain website"
    echo " 3) Test lepas / sekat geo"
    echo " 4) Senarai domain geo"
    echo " 5) Hantar ke GitHub"
    echo " 6) Tetapan"
    echo " 0) Keluar"
    read -rp " Pilih: " opt || break
    case "$opt" in
        1) t_imbas ;;
        2) t_cari ;;
        3) t_geo ;;
        4) t_senarai ;;
        5) t_hantar ;;
        6) t_tetap ;;
        0|q|Q) break ;;
    esac
done
echo ""
