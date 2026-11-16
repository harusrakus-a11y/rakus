#!/bin/bash
# tbot-install.sh - pasang bot Telegram untuk urus VLESS dan SSH. Run sebagai root.
#   bash tbot-install.sh          pasang atau kemas kini (token dan ID dikekalkan)
#   bash tbot-install.sh ubah     tukar token atau ID admin
#   bash tbot-install.sh buang    buang bot
# Tiada rahsia dalam fail ni. Token dan ID dimasukkan masa pasang dan disimpan kat /etc/tbot/config sahaja.
PFX="${TBOT_PREFIX:-}"
RAW="https://raw.githubusercontent.com/harusrakus-a11y/rakus/refs/heads/main/menu"
BIN="$PFX/usr/local/bin/tbot.py"
CONF="$PFX/etc/tbot/config"
UNIT="$PFX/etc/systemd/system/tbot.service"

gagal() { echo "GAGAL: $*"; exit 1; }

if [ "$1" = buang ]; then
  systemctl disable --now tbot >/dev/null 2>&1
  rm -f "$UNIT" "$BIN"
  systemctl daemon-reload >/dev/null 2>&1
  echo "Bot dibuang. Token dan ID masih kat /etc/tbot (padam: rm -rf /etc/tbot)"
  exit 0
fi

[ "$(id -u)" = 0 ] || gagal "run sebagai root."
[ -s "$PFX/etc/xray/config.json" ] || gagal "autoscript VLESS belum dipasang kat VPS ni."
command -v curl >/dev/null || apt-get install -y curl >/dev/null 2>&1
command -v python3 >/dev/null || apt-get install -y python3 >/dev/null 2>&1
command -v python3 >/dev/null || gagal "python3 tak ada."
command -v ssh >/dev/null && command -v ssh-keygen >/dev/null || apt-get install -y openssh-client >/dev/null 2>&1

T=$(mktemp)
curl -fsSL --max-time 30 "$RAW/tbot.py" -o "$T" || { rm -f "$T"; gagal "tak dapat muat turun tbot.py dari GitHub."; }
grep -q '^# tbot - bot Telegram' "$T" || { rm -f "$T"; gagal "fail tbot.py tak betul."; }
python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$T" || { rm -f "$T"; gagal "tbot.py rosak."; }
mkdir -p "$(dirname "$BIN")"
install -m 755 "$T" "$BIN"
rm -f "$T"

if [ "$1" = ubah ] || [ ! -s "$CONF" ]; then
  TOKEN="${TBOT_TOKEN:-}"
  ADM="${TBOT_ADMIN:-}"
  if [ -z "$TOKEN" ]; then
    echo "Buat bot kat Telegram: cari @BotFather, taip /newbot, ikut arahan, lepas tu salin token dia."
    read -rsp "Tampal token bot (tak nampak masa tampal, itu normal), tekan Enter: " TOKEN </dev/tty
    echo ""
  fi
  [[ $TOKEN =~ ^[0-9]+:[A-Za-z0-9_-]{30,}$ ]] || gagal "token nampak tak betul."
  curl -fsS --max-time 20 "https://api.telegram.org/bot$TOKEN/getMe" 2>/dev/null | grep -q '"ok":true' || gagal "Telegram tak terima token tu."
  if [ -z "$ADM" ]; then
    echo "ID Telegram kau: cari @userinfobot, taip /start, salin nombor 'Id'."
    read -rp "ID Telegram kau (nombor): " ADM </dev/tty
  fi
  [[ $ADM =~ ^[0-9]+(,[0-9]+)*$ ]] || gagal "ID mesti nombor."
  mkdir -p "$(dirname "$CONF")"
  ( umask 077; printf 'TOKEN=%s\nADMINS=%s\n' "$TOKEN" "$ADM" > "$CONF" )
  chmod 600 "$CONF"
fi

mkdir -p "$(dirname "$UNIT")"
cat > "$UNIT" <<'EOF'
[Unit]
Description=tbot Telegram (urus VLESS dan SSH)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/tbot.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable tbot >/dev/null 2>&1
systemctl restart tbot
sleep 3
if systemctl is-active --quiet tbot; then
  echo "SIAP. Bot dah hidup. Buka bot kau kat Telegram dan taip /start"
else
  echo "Bot tak hidup. Semak: journalctl -u tbot -n 20 --no-pager"
  exit 1
fi
