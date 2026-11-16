#!/bin/bash
# httpupgrade.sh - Developer by kancil ecem
# Hidupkan VLESS httpupgrade (path /vlessntls) kat VPS ni supaya telco eastle jalan.
#   bash httpupgrade.sh         hidupkan (boleh jalan banyak kali, selamat)
#   bash httpupgrade.sh off     matikan dan pulihkan macam asal
# Selamat: sandar config dulu, uji dengan xray dan nginx, pulih sendiri kalau gagal.
# Akaun VLESS yang sedia ada dan yang baru disalin sendiri ke inbound httpupgrade setiap kali xray dimulakan semula.
trap '' HUP PIPE
MODE=${1:-on}
BIN=${UPG_BIN:-/usr/local/bin}
DROP=${UPG_DROPIN:-/etc/systemd/system/xray.service.d}
CRON=${UPG_CRON:-/etc/cron.d/upg-sync}
NGX=${UPG_NGX:-/etc/nginx/conf.d/xray.conf}
BAKROOT=${UPG_BAK:-/root}
UPGPATH=${UPG_PATH:-/vlessntls}
LOG=${UPG_LOG:-/root/httpupgrade.log}
export UPG_NGX=$NGX

say() { printf '%s\n' "$*" >> "$LOG" 2>/dev/null; printf '%s\n' "$*" 2>/dev/null || true; }
die() { say "GAGAL: $*"; exit 1; }

[ "$MODE" = on ] || [ "$MODE" = off ] || die "Guna: bash httpupgrade.sh   atau   bash httpupgrade.sh off"
[ "${UPG_NOROOT:-0}" = 1 ] || [ "$(id -u)" = 0 ] || die "Jalankan sebagai root."
command -v python3 >/dev/null 2>&1 || die "python3 tiada."

CFG=${UPG_CFG:-}
if [ -z "$CFG" ]; then
  for c in /etc/xray/config.json /usr/local/etc/xray/config.json; do
    [ -f "$c" ] && CFG=$c && break
  done
fi
[ -f "$CFG" ] || die "config xray tak jumpa."
export UPG_CFG=$CFG
[ -f "$NGX" ] || die "fail nginx $NGX tak jumpa (skrip ni untuk autoscript kancil)."
XRAY=$(command -v xray 2>/dev/null || true)
[ -z "$XRAY" ] && [ -x /usr/local/bin/xray ] && XRAY=/usr/local/bin/xray
[ -n "$XRAY" ] || die "xray tak jumpa."

mkdir -p "$BIN" 2>/dev/null
cat > "$BIN/upg-sync" <<'PYEOF'
#!/usr/bin/env python3
# upg-sync - Developer by kancil ecem
# Urus inbound VLESS httpupgrade dan salin akaun VLESS (#vl) ke dalamnya.
import json
import os
import re
import subprocess
import sys
import time

MARK = "#vlessupg"
BEG, END = "#upg-begin", "#upg-end"
NBEG, NEND = "# upg-begin", "# upg-end"
CANDS = ["/etc/xray/config.json", "/usr/local/etc/xray/config.json"]
PATH_RE = re.compile(r"^/[A-Za-z0-9._/-]{1,60}$")


def cfg_path():
    p = os.environ.get("UPG_CFG")
    if p:
        return p
    for c in CANDS:
        if os.path.isfile(c):
            return c
    sys.exit("config xray tak jumpa")


def ngx_path():
    return os.environ.get("UPG_NGX", "/etc/nginx/conf.d/xray.conf")


def rd(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


def wr(p, text):
    st = os.stat(p)
    tmp = p + ".upg.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.chmod(tmp, st.st_mode & 0o7777)
    try:
        os.chown(tmp, st.st_uid, st.st_gid)
    except OSError:
        pass
    os.replace(tmp, p)


def strip(text):
    return "\n".join(l for l in text.split("\n") if not l.lstrip().startswith("#"))


def upg_inbounds(d):
    return [ib for ib in d.get("inbounds", [])
            if ib.get("protocol") == "vless" and (ib.get("streamSettings") or {}).get("network") == "httpupgrade"]


def clients(text):
    """Akaun VLESS ws (#vl nama luput [uuid]) -> [(nama, id)]. Tiada nama atau id berulang."""
    L = text.split("\n")
    out, ids, names = [], set(), set()
    for i, l in enumerate(L):
        if not l.startswith("#vl "):
            continue
        p = l.split()
        if len(p) < 3 or not re.fullmatch(r"[A-Za-z0-9_.-]{1,64}", p[1]):
            continue
        nxt = L[i + 1] if i + 1 < len(L) else ""
        m = re.match(r'^\},\{\s*"id"\s*:\s*"([^"\\\s]{1,64})"', nxt)
        if m:
            cid = m.group(1)
        elif len(p) > 3 and re.fullmatch(r'[^"\\\s]{1,64}', p[3]):
            cid = p[3]
        else:
            continue
        if cid in ids or p[1].lower() in names:
            continue
        ids.add(cid)
        names.add(p[1].lower())
        out.append((p[1], cid))
    return out


def region(L):
    idx = [i for i, l in enumerate(L) if l.strip() == MARK]
    if len(idx) != 1:
        return None
    m = idx[0]
    e = m + 1
    while e < len(L) and not re.match(r"^\s*\}\s*$", L[e]):
        e += 1
    if e >= len(L):
        raise ValueError("penutup inbound httpupgrade tak jumpa")
    for l in L[m + 1:e]:
        if not (l.startswith("#vu ") or l.startswith("},{")):
            raise ValueError("kawasan httpupgrade tak dikenali: " + l[:40])
    return m + 1, e


def sync_text(text):
    L = text.split("\n")
    r = region(L)
    if r is None:
        return None
    a, e = r
    new = []
    for user, cid in clients(text):
        new += ["#vu %s" % user, '},{"id": "%s","email": "%s"' % (cid, user)]
    if L[a:e] == new:
        return text
    L[a:e] = new
    return "\n".join(L)


def check_new(text, want):
    d = json.loads(strip(text))
    u = upg_inbounds(d)
    if len(u) != 1:
        raise ValueError("inbound httpupgrade bukan tepat satu")
    cl = (u[0].get("settings") or {}).get("clients") or []
    ids = [c.get("id") for c in cl]
    mails = [c.get("email") for c in cl if c.get("email")]
    if len(ids) != len(set(ids)) or len(mails) != len(set(m.lower() for m in mails)):
        raise ValueError("akaun berulang dalam inbound httpupgrade")
    if not set(c for _, c in want) <= set(ids) or len(ids) != len(want) + 1:
        raise ValueError("senarai akaun httpupgrade tak padan")


def xray_bin():
    for c in (os.environ.get("UPG_XRAY"), "/usr/local/bin/xray", "/usr/bin/xray"):
        if c and os.path.isfile(c) and os.access(c, os.X_OK):
            return c
    return None


def do_sync(restart):
    p = cfg_path()
    text = rd(p)
    new = sync_text(text)
    if new is None or new == text:
        return 0
    check_new(new, clients(text))
    if restart:
        if time.time() - os.path.getmtime(p) < 30:
            return 0
        xb = xray_bin()
        wr(p, new)
        try:
            ok = True
            if xb:
                r = subprocess.run([xb, "run", "-test", "-config", p], capture_output=True, text=True, timeout=60)
                ok = r.returncode == 0 and "Configuration OK" in (r.stdout + r.stderr)
            if not ok:
                raise RuntimeError("xray tak lulus ujian")
            subprocess.run(["systemctl", "restart", "xray"], timeout=60)
        except Exception:
            wr(p, text)
            raise
    else:
        wr(p, new)
    return 0


def cmd_insert(port, path):
    if not PATH_RE.match(path) or not str(port).isdigit():
        sys.exit("port atau path tak sah")
    p = cfg_path()
    text = rd(p)
    if MARK in text:
        print("inbound dah ada")
        return 0
    m = re.search(r'"inbounds"\s*:\s*\[', text)
    if not m:
        sys.exit("\"inbounds\" tak jumpa dalam config")
    import uuid
    block = '''
%s
   {
     "listen": "127.0.0.1",
     "port": %d,
     "protocol": "vless",
      "settings": {
          "decryption":"none",
            "clients": [
               {
                 "id": "%s"
%s
             }
          ]
       },
       "streamSettings":{
         "network": "httpupgrade",
            "httpupgradeSettings": {
                "path": "%s"
          }
        }
     },
%s''' % (BEG, int(port), uuid.uuid4(), MARK, path, END)
    new = text[:m.end()] + block + text[m.end():]
    json.loads(strip(new))
    wr(p, new)
    return 0


def cmd_remove():
    p = cfg_path()
    text = rd(p)
    L = text.split("\n")
    out, skip = [], False
    for l in L:
        if l.strip() == BEG:
            skip = True
            continue
        if l.strip() == END:
            skip = False
            continue
        if not skip:
            out.append(l)
    new = "\n".join(out)
    json.loads(strip(new))
    if new != text:
        wr(p, new)
    return 0


def ngx_block(port, path):
    return '''%s
location = %s
{
proxy_redirect off;
proxy_pass http://127.0.0.1:%d;
proxy_http_version 1.1;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
proxy_set_header Host $http_host;
}
%s''' % (NBEG, path, int(port), NEND)


def cmd_ngx_insert(port, path):
    if not PATH_RE.match(path) or not str(port).isdigit():
        sys.exit("port atau path tak sah")
    p = ngx_path()
    text = rd(p)
    if NBEG in text:
        print("nginx dah ada")
        return 0
    L = text.split("\n")
    last = None
    for i in range(len(L) - 1, -1, -1):
        if L[i].strip() == "}":
            last = i
            break
    if last is None:
        sys.exit("penutup server nginx tak jumpa")
    L[last:last] = ngx_block(port, path).split("\n")
    wr(p, "\n".join(L))
    return 0


def cmd_ngx_remove():
    p = ngx_path()
    text = rd(p)
    out, skip = [], False
    for l in text.split("\n"):
        if l.strip() == NBEG:
            skip = True
            continue
        if l.strip() == NEND:
            skip = False
            continue
        if not skip:
            out.append(l)
    new = "\n".join(out)
    if new != text:
        wr(p, new)
    return 0


def cmd_status():
    p = cfg_path()
    text = rd(p)
    main = clients(text)
    if MARK not in text:
        print("httpupgrade: TIDAK dipasang. Akaun VLESS: %d" % len(main))
        return 0
    d = json.loads(strip(text))
    u = upg_inbounds(d)
    if len(u) != 1:
        print("httpupgrade: config pelik (%d inbound)" % len(u))
        return 1
    cl = [c for c in (u[0].get("settings") or {}).get("clients") or [] if c.get("email")]
    path = ((u[0].get("streamSettings") or {}).get("httpupgradeSettings") or {}).get("path")
    print("httpupgrade: HIDUP  port %s  path %s" % (u[0].get("port"), path))
    print("Akaun VLESS: %d   disalin ke httpupgrade: %d   %s" % (len(main), len(cl), "SAMA" if len(main) == len(cl) else "BEZA (akan sama bila xray dimulakan semula)"))
    print("nginx: %s" % ("ada" if NBEG in rd(ngx_path()) else "TIADA"))
    return 0


def main():
    a = sys.argv[1:]
    c = a[0] if a else ""
    try:
        if c == "pre":
            return do_sync(False)
        if c == "cron":
            return do_sync(True)
        if c == "insert" and len(a) == 3:
            return cmd_insert(a[1], a[2])
        if c == "remove":
            return cmd_remove()
        if c == "ngx-insert" and len(a) == 3:
            return cmd_ngx_insert(a[1], a[2])
        if c == "ngx-remove":
            return cmd_ngx_remove()
        if c == "status":
            return cmd_status()
    except SystemExit:
        raise
    except Exception as e:
        sys.stderr.write("upg-sync: %s\n" % e)
        return 0 if c in ("pre", "cron") else 1
    sys.stderr.write("guna: upg-sync pre|cron|status|insert PORT PATH|remove|ngx-insert PORT PATH|ngx-remove\n")
    return 2


if __name__ == "__main__":
    sys.exit(main())
PYEOF
chmod +x "$BIN/upg-sync"

STAMP=$(date +%Y%m%d-%H%M%S)
B="$BAKROOT/upg-backup-$STAMP"
mkdir -p "$B" || die "tak boleh buat folder sandar $B"
cp -a "$CFG" "$B/config.json" && cp -a "$NGX" "$B/xray.conf" || die "sandar gagal"
say "Sandar disimpan: $B"
H0=$(cat "$CFG" "$NGX" | md5sum | cut -d' ' -f1)
CREATED_DROP=0

xray_ok() {
  local o
  o=$("$XRAY" run -test -config "$CFG" 2>&1)
  [ $? -eq 0 ] && printf '%s' "$o" | grep -q "Configuration OK"
}

nginx_ok() {
  nginx -t >/dev/null 2>&1
}

rollback() {
  say "Pulihkan config asal..."
  cp -a "$B/config.json" "$CFG"
  cp -a "$B/xray.conf" "$NGX"
  if [ "$MODE" = on ] && [ "$CREATED_DROP" = 1 ]; then
    rm -f "$DROP/upg.conf" "$CRON"
    rmdir "$DROP" 2>/dev/null
  fi
  systemctl daemon-reload >/dev/null 2>&1
  nginx_ok && { systemctl reload nginx >/dev/null 2>&1 || nginx -s reload >/dev/null 2>&1; }
  [ "${NEED_RESTART_ON_ROLLBACK:-0}" = 1 ] && systemctl restart xray >/dev/null 2>&1
  die "$1. Config dipulihkan, tiada perubahan kekal."
}

listening() {
  (exec 3<>/dev/tcp/127.0.0.1/"$1") 2>/dev/null
}

busy() {
  listening "$1" && return 0
  grep -Eq "\"port\"[[:space:]]*:[[:space:]]*\"?$1\"?[[:space:],]" "$CFG" && return 0
  return 1
}

if [ "$MODE" = on ]; then
  say "== Hidupkan VLESS httpupgrade ($UPGPATH) =="
  if grep -q '^#vlessupg$' "$CFG"; then
    say "Inbound dah ada, semak dan kemas kini sahaja."
    PORT=$(python3 - "$CFG" <<'PYEOF'
import json, sys
t = "\n".join(l for l in open(sys.argv[1]).read().split("\n") if not l.lstrip().startswith("#"))
for ib in json.loads(t).get("inbounds", []):
    if ib.get("protocol") == "vless" and (ib.get("streamSettings") or {}).get("network") == "httpupgrade":
        print(ib.get("port")); break
PYEOF
)
    [ -n "$PORT" ] || rollback "inbound httpupgrade tak boleh dibaca"
  else
    PORT=
    for p in $(seq 14017 14060); do
      busy "$p" || { PORT=$p; break; }
    done
    [ -n "$PORT" ] || rollback "tiada port kosong 14017-14060"
    "$BIN/upg-sync" insert "$PORT" "$UPGPATH" >> "$LOG" 2>&1 || rollback "tak dapat tambah inbound"
  fi
  "$BIN/upg-sync" ngx-remove >> "$LOG" 2>&1 || rollback "tak dapat kemas nginx"
  "$BIN/upg-sync" ngx-insert "$PORT" "$UPGPATH" >> "$LOG" 2>&1 || rollback "tak dapat tambah nginx"
  "$BIN/upg-sync" pre >> "$LOG" 2>&1
  mkdir -p "$DROP"
  [ -f "$DROP/upg.conf" ] || CREATED_DROP=1
  printf '[Service]\nExecStartPre=-+%s/upg-sync pre\n' "$BIN" > "$DROP/upg.conf"
  printf '*/3 * * * * root %s/upg-sync cron >/dev/null 2>&1\n' "$BIN" > "$CRON"
  chmod 644 "$CRON" 2>/dev/null
  systemctl daemon-reload >/dev/null 2>&1
  xray_ok || rollback "xray tak lulus ujian (versi xray mungkin lama, perlu sokongan httpupgrade)"
  nginx_ok || rollback "nginx tak lulus ujian"
  H1=$(cat "$CFG" "$NGX" | md5sum | cut -d' ' -f1)
  if [ "$H0" != "$H1" ]; then
    say "Mula semula nginx dan xray. Kalau sambungan kau putus, sambung semula, ia dah siap."
    systemctl reload nginx >/dev/null 2>&1 || nginx -s reload >/dev/null 2>&1
    NEED_RESTART_ON_ROLLBACK=1
    systemctl restart xray >/dev/null 2>&1
    sleep 2
    [ "$(systemctl is-active xray 2>/dev/null)" = active ] || rollback "xray tak hidup selepas mula semula"
    [ "${UPG_SKIP_LISTEN:-0}" = 1 ] || listening "$PORT" || rollback "port $PORT tak dengar selepas mula semula"
  else
    say "Tiada perubahan, tak perlu mula semula."
  fi
  "$BIN/upg-sync" status 2>&1 | while IFS= read -r l; do say "$l"; done
  if command -v curl >/dev/null 2>&1; then
    CODE=$(curl -s -o /dev/null -m 6 -w '%{http_code}' -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Host: uji' "http://127.0.0.1$UPGPATH" 2>/dev/null)
    say "Uji tempatan $UPGPATH: kod $CODE (101 = jalan)"
  fi
  say "SIAP. Telco eastle boleh dicuba. Log: $LOG"
else
  say "== Matikan VLESS httpupgrade =="
  "$BIN/upg-sync" ngx-remove >> "$LOG" 2>&1 || rollback "tak dapat buang nginx"
  "$BIN/upg-sync" remove >> "$LOG" 2>&1 || rollback "tak dapat buang inbound"
  rm -f "$DROP/upg.conf" "$CRON"
  rmdir "$DROP" 2>/dev/null
  systemctl daemon-reload >/dev/null 2>&1
  xray_ok || rollback "xray tak lulus ujian"
  nginx_ok || rollback "nginx tak lulus ujian"
  systemctl reload nginx >/dev/null 2>&1 || nginx -s reload >/dev/null 2>&1
  NEED_RESTART_ON_ROLLBACK=1
  systemctl restart xray >/dev/null 2>&1
  sleep 2
  [ "$(systemctl is-active xray 2>/dev/null)" = active ] || rollback "xray tak hidup selepas mula semula"
  rm -f "$BIN/upg-sync"
  say "SIAP. httpupgrade dimatikan. Sandar: $B"
fi
