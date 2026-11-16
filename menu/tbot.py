#!/usr/bin/env python3
# tbot - bot Telegram untuk urus akaun VLESS, VMess, Trojan dan SSH di VPS autoscript (admin; trial awam untuk orang lain bila admin hidupkan)
# Konfigurasi: /etc/tbot/config  (TOKEN=... dan ADMINS=id1,id2). Tiada rahsia dalam fail ni.
import base64
import copy
import datetime
import html
import json
import os
import re
import secrets
import shutil
import string
import subprocess
import sys
import time
import traceback
import urllib.request
import uuid as uuidlib

ROOT = os.environ.get("TBOT_ROOT", "")
API = os.environ.get("TBOT_API", "https://api.telegram.org")


def P(p):
    return ROOT + p


CONF = P("/etc/tbot/config")
XCONF = P("/etc/xray/config.json")
TELCO = P("/etc/xray/telco.conf")
TELCO_URL = "https://raw.githubusercontent.com/harusrakus-a11y/rakus/refs/heads/main/menu/telco.conf"
TELCO_DEFAULT = """celcom|mcmc-my.metricelltestcloud.com.{domain}|mcmc-my.metricelltestcloud.com|/vless|80
digi|104.18.21.212|{domain}|/vless|80
maxis-viu|help.viu.com.{domain}|help.viu.com|/vless|80
maxis-cmgo|104.16.160.145|cfcdn.viu.com.{domain}|/vless|80
yes|104.17.147.22|{domain}|/vless|80
tonewow|172.66.169.187|{domain}|/vless|80
"""
TELCO_RE = re.compile(r"^[A-Za-z0-9_-]+\|[^|]+\|[^|]+\|/[^|]*\|[0-9]+$")
NAME_RE = re.compile(r"^[A-Za-z0-9_.-]{1,30}$")
PW_RE = re.compile(r"^[A-Za-z0-9._@#%+=!-]{4,32}$")
UUID_RE = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
UTXT_RE = re.compile(r"^[A-Za-z0-9._-]{8,30}$")

TOKEN = ""
ADMINS = set()
STATE = {}
SEEN = set()
_telco_time = 0.0


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def load_conf():
    global TOKEN, ADMINS
    d = {}
    with open(CONF) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                d[k.strip()] = v.strip()
    TOKEN = d.get("TOKEN", "")
    ADMINS = {int(x) for x in d.get("ADMINS", "").replace(" ", "").split(",") if x.isdigit()}
    if not TOKEN or not ADMINS:
        sys.exit("Config tak lengkap (TOKEN / ADMINS).")


# ---------------------------------------------------------------- Telegram
def tg(method, **params):
    t = params.get("timeout", 0)
    req = urllib.request.Request("%s/bot%s/%s" % (API, TOKEN, method),
                                 json.dumps(params).encode(), {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=t + 20) as r:
        return json.load(r)


def chunk(text, limit=3800):
    out, cur = [], ""
    for line in text.split("\n"):
        if len(cur) + len(line) + 1 > limit and cur:
            out.append(cur)
            cur = ""
        cur += line + "\n"
    if cur.strip():
        out.append(cur.rstrip("\n"))
    return out or [""]


def send(chat, text, kb=None):
    parts = chunk(text)
    for i, part in enumerate(parts):
        p = {"chat_id": chat, "text": part, "parse_mode": "HTML", "disable_web_page_preview": True}
        if kb and i == len(parts) - 1:
            p["reply_markup"] = {"inline_keyboard": kb}
        try:
            tg("sendMessage", **p)
        except Exception as e:
            log("sendMessage gagal:", e)


def btn(text, data):
    return {"text": text, "callback_data": data}


def rows(buttons, n=2):
    return [buttons[i:i + n] for i in range(0, len(buttons), n)]


MAIN_KB = [
    [btn("➕ VLESS", "m:vl"), btn("➕ VMess", "m:vm")],
    [btn("➕ Trojan", "m:tr"), btn("➕ SSH", "m:ss")],
    [btn("📋 Senarai", "m:ls"), btn("🔎 Semak", "m:ck")],
    [btn("🔁 Renew", "m:rn"), btn("🗑 Padam", "m:dl")],
    [btn("ℹ️ Status", "m:st"), btn("🎁 Trial", "m:tl")],
]


def E(x):
    return html.escape(str(x), quote=False)


def code(x):
    return "<code>%s</code>" % E(x)


# ---------------------------------------------------------------- sistem
def rd(path, default=""):
    try:
        with open(P(path)) as f:
            return f.read().strip()
    except OSError:
        return default


def lines_of(path):
    try:
        with open(P(path)) as f:
            return f.read().split("\n")
    except OSError:
        return []


def run(cmd, inp=None, timeout=90):
    return subprocess.run(cmd, input=inp, capture_output=True, text=True, timeout=timeout)


def domain():
    return rd("/etc/xray/domain", "domain-tiada")


def today():
    return datetime.date.today()


def exp_after(days):
    return (today() + datetime.timedelta(days=days)).isoformat()


def days_left(exp):
    try:
        return (datetime.date.fromisoformat(exp) - today()).days
    except ValueError:
        return 0


KIND = {
    "v": {"nama": "VLESS", "dir": "/etc/vless", "m1": "#vl", "m2": "#vlg", "lst": "#vl", "pub": "vless"},
    "m": {"nama": "VMess", "dir": "/etc/vmess", "m1": "#vm", "m2": "#vmg", "lst": "#vmg", "pub": "vmess"},
    "t": {"nama": "Trojan", "dir": "/etc/trojan", "m1": "#tr", "m2": "#trg", "lst": "#tr", "pub": "trojan"},
}
XKINDS = ("v", "m", "t")
FLOWKIND = {"vl": "v", "vm": "m", "tr": "t"}


def kname(kind):
    return KIND[kind]["nama"] if kind in KIND else "SSH"


def xusers(kind):
    out = []
    mk = KIND[kind]["lst"] + " "
    for line in lines_of("/etc/xray/config.json"):
        if line.startswith(mk):
            p = line.split()
            if len(p) >= 4:
                out.append((p[1], p[2], p[3]))
    return out


def vless_users():
    return xusers("v")


def ssh_users():
    out = []
    for line in lines_of("/etc/xray/ssh"):
        if line.startswith("### "):
            p = line.split()
            if len(p) >= 4:
                out.append((p[1], p[2], p[3]))
    return out


def users_of(kind):
    return ssh_users() if kind == "s" else xusers(kind)


def name_taken(name):
    allu = ssh_users()
    for k in XKINDS:
        allu += xusers(k)
    if any(u[0] == name for u in allu):
        return True
    if ('"email": "%s"' % name) in "\n".join(lines_of("/etc/xray/config.json")):
        return True
    return run(["id", name]).returncode == 0


def nota_get(user, kind="v"):
    return rd("%s/nota/%s" % (KIND[kind]["dir"], user), "")


def nota_set(user, text, kind="v"):
    p = P("%s/nota/%s" % (KIND[kind]["dir"], user))
    text = (text or "").strip()
    if not text:
        try:
            os.remove(p)
        except OSError:
            pass
        return
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write(text + "\n")


def find(kind, name):
    for u in users_of(kind):
        if u[0] == name:
            return u
    return None


# ---------------------------------------------------------------- config xray (dengan jaga-jaga)
def xray_bin():
    for c in (os.environ.get("TBOT_XRAY"), "/usr/local/bin/xray", shutil.which("xray")):
        if c and os.path.exists(c):
            return c
    return None


def guarded_config_edit(fn):
    """Sandar config, ubah, uji dengan xray, mula semula. Kalau gagal, pulihkan. Pulang (ok, mesej)."""
    bak = XCONF + ".bot.bak"
    shutil.copy2(XCONF, bak)
    try:
        fn()
        xb = xray_bin()
        if xb:
            r = run([xb, "run", "-test", "-config", XCONF], timeout=60)
            if r.returncode != 0 or "Configuration OK" not in (r.stdout + r.stderr):
                raise RuntimeError("config baru tak lulus ujian xray")
        run(["systemctl", "restart", "xray"], timeout=60)
        time.sleep(1)
        if run(["systemctl", "is-active", "xray"]).stdout.strip() != "active":
            raise RuntimeError("xray tak hidup selepas restart")
        return True, ""
    except Exception as e:
        shutil.copy2(bak, XCONF)
        run(["systemctl", "restart", "xray"], timeout=60)
        return False, "Gagal: %s. Config dipulihkan." % e


def sed(expr):
    r = run(["sed", "-i", expr, XCONF])
    if r.returncode != 0:
        raise RuntimeError("sed gagal: " + r.stderr.strip())


# ---------------------------------------------------------------- telco
def telco_refresh(force=False):
    global _telco_time
    if not force and time.time() - _telco_time < 300 and os.path.exists(TELCO):
        return
    _telco_time = time.time()
    try:
        with urllib.request.urlopen(TELCO_URL, timeout=8) as r:
            txt = r.read().decode("utf-8", "replace")
        if any(TELCO_RE.match(l.strip()) for l in txt.split("\n")):
            os.makedirs(os.path.dirname(TELCO), exist_ok=True)
            with open(TELCO, "w") as f:
                f.write(txt)
    except Exception:
        pass
    if not os.path.exists(TELCO):
        os.makedirs(os.path.dirname(TELCO), exist_ok=True)
        with open(TELCO, "w") as f:
            f.write(TELCO_DEFAULT)


def telcos():
    telco_refresh()
    out = []
    for l in lines_of("/etc/xray/telco.conf"):
        l = l.strip()
        if TELCO_RE.match(l):
            n, a, h, p, port = l.split("|")
            out.append((n, a, h, p, port))
    return out


def telco_path(kind, p):
    if p == "/vless":
        return {"v": "/vless", "m": "/vmess", "t": "/trojan-ws"}[kind]
    return p


def telco_link(uid, user, t, kind="v"):
    n, a, h, p, port = t
    d = domain()
    a = a.replace("{domain}", d)
    h = h.replace("{domain}", d)
    p = telco_path(kind, p)
    if kind == "m":
        js = json.dumps({"v": "2", "ps": "%s-%s" % (user, n), "add": a, "port": port, "id": uid, "aid": "0", "net": "ws",
                         "path": p, "type": "none", "host": h, "tls": "none"}, separators=(",", ":"))
        return "vmess://" + base64.b64encode(js.encode()).decode()
    if kind == "t":
        return "trojan://%s@%s:%s?path=%s&security=none&host=%s&type=ws#%s-%s" % (
            uid, a, port, p.replace("/", "%2F"), h, user, n)
    return "vless://%s@%s:%s?encryption=none&type=ws&host=%s&headerType=none&path=%s#%s-%s" % (
        uid, a, port, h, p.replace("/", "%2F"), user, n)


TACT = {"v": "t", "m": "tm", "t": "tt"}


def telco_kb(user, kind="v"):
    act = TACT[kind]
    b = [btn(t[0], "%s:%s:%d" % (act, user, i + 1)) for i, t in enumerate(telcos())]
    kb = rows(b, 3)
    kb.append([btn("Semua telco", "%s:%s:0" % (act, user)), btn("📝 Nota", "n:%s:%s" % (kind, user))])
    return kb


# ---------------------------------------------------------------- VLESS
def vless_std_links(user, uid):
    d = domain()
    return [
        ("WS TLS (443)", "vless://%s@%s:443?path=/vless&security=tls&encryption=none&host=%s&type=ws&sni=%s#%s" % (uid, d, d, d, user)),
        ("WS NTLS (80)", "vless://%s@%s:80?path=/vless&security=none&encryption=none&host=%s&type=ws#%s" % (uid, d, d, user)),
        ("gRPC (443)", "vless://%s@%s:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=vless-grpc&sni=%s#%s" % (uid, d, d, user)),
    ]


def vless_txt(user, uid):
    d = domain()
    return """_______________________________
Format Vless WS (CDN)
_______________________________
- name: vless-{u}-WS (CDN)
server: {d}
port: 443
type: vless
uuid: {id}
cipher: auto
tls: true
skip-cert-verify: true
servername: {d}
network: ws
udp: true
ws-opts:
path: /vless
headers:
Host: {d}
_______________________________
Format Vless WS (CDN) Non TLS
_______________________________
- name: vless-{u}-WS (CDN) Non TLS
server: {d}
port: 80
type: vless
uuid: {id}
cipher: auto
tls: false
skip-cert-verify: false
servername: {d}
network: ws
ws-opts:
udp: true
path: /vless
headers:
Host: {d}
_______________________________
Format Vless gRPC (SNI)
_______________________________
- name: vless-{u}-gRPC (SNI)
server: {d}
port: 443
type: vless
uuid: {id}
cipher: auto
tls: true
skip-cert-verify: true
servername: {d}
network: grpc
grpc-opts:
grpc-mode: gun
grpc-service-name: vless-grpc
udp: true
_______________________________
Link Vless Account
_______________________________
Link TLS : {l1}
_______________________________
Link none TLS : {l2}
_______________________________
Link GRPC : {l3}
_______________________________
""".format(u=user, d=d, id=uid, l1=vless_std_links(user, uid)[0][1], l2=vless_std_links(user, uid)[1][1],
           l3=vless_std_links(user, uid)[2][1])


def vmess_link(user, uid, port, net, path, tls, host=None):
    d = domain()
    js = {"v": "2", "ps": user, "add": d, "port": str(port), "id": uid, "aid": "0", "net": net,
          "path": path, "type": "none", "host": host or d, "tls": tls}
    return "vmess://" + base64.b64encode(json.dumps(js).encode()).decode()


def vmess_std_links(user, uid):
    return [
        ("WS TLS (443)", vmess_link(user, uid, 443, "ws", "/vmess", "tls")),
        ("WS NTLS (80)", vmess_link(user, uid, 80, "ws", "/vmess", "none")),
        ("gRPC (443)", vmess_link(user, uid, 443, "grpc", "vmess-grpc", "tls")),
    ]


def trojan_std_links(user, uid):
    d = domain()
    return [
        ("WS TLS (443)", "trojan://%s@%s:443?path=%%2Ftrojan-ws&security=tls&host=%s&type=ws&sni=%s#%s" % (uid, d, d, d, user)),
        ("gRPC (443)", "trojan://%s@%s:443?mode=gun&security=tls&type=grpc&serviceName=trojan-grpc&sni=%s#%s" % (uid, d, d, user)),
    ]


def std_links(kind, user, uid):
    return {"v": vless_std_links, "m": vmess_std_links, "t": trojan_std_links}[kind](user, uid)


def vmess_txt(user, uid):
    d = domain()
    sep = "_______________________________________________________"
    t = """{s}
Format Vmess WS (CDN)
{s}
- name: vmess-{u}-WS (CDN)
type: vmess
server: {d}
port: 443
uuid: {id}
alterId: 0
cipher: auto
udp: true
tls: true
skip-cert-verify: true
servername: {d}
network: ws
ws-opts:
path: /vmess
headers:
Host: {d}
{s}
Format Vmess WS (CDN) Non TLS
{s}
- name: vmess-{u}-WS (CDN) Non TLS
type: vmess
server: {d}
port: 80
uuid: {id}
alterId: 0
cipher: auto
udp: true
tls: false
skip-cert-verify: false
servername: {d}
network: ws
ws-opts:
path: /vmess
headers:
Host: {d}
{s}
Format Vmess gRPC (SNI)
{s}
- name: vmess-{u}-gRPC (SNI)
server: {d}
port: 443
type: vmess
uuid: {id}
alterId: 0
cipher: auto
network: grpc
tls: true
servername: {d}
skip-cert-verify: true
grpc-opts:
grpc-service-name: vmess-grpc
{s}
Format Vmess WS (CDN) Non TLS Opok TSEL
{s}
- name: vmess-{u}-WS (CDN) Non TLS
type: vmess
server: {d}
port: 80
uuid: {id}
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
Host: {d}
{s}
Link Vmess Account
{s}
Link TLS : {l1}
{s}
Link NTLS : {l2}
{s}
Link gRPC : {l3}
{s}
Link Opok : {l4}
{s}
""".format(s=sep, u=user, d=d, id=uid, l1=vmess_std_links(user, uid)[0][1], l2=vmess_std_links(user, uid)[1][1],
           l3=vmess_std_links(user, uid)[2][1], l4=vmess_link(user, uid, 80, "ws", "http://tsel.me/worryfree", "none", "tsel.me"))
    return t


def trojan_txt(user, uid):
    d = domain()
    sep = "_______________________________"
    L = trojan_std_links(user, uid)
    return """{s}
Format Trojan WS (CDN)
{s}
- name: Trojan-{u}-WS (CDN)
server: {d}
port: 443
type: trojan
password: {id}
network: ws
sni: {d}
skip-cert-verify: true
udp: true
ws-opts:
path: /trojan-ws
headers:
Host: {d}
{s}
Format Trojan gRPC
{s}
- name: Trojan-{u}-gRPC (SNI)
type: trojan
server: {d}
port: 443
password: {id}
udp: true
sni: {d}
skip-cert-verify: true
network: grpc
grpc-opts:
grpc-service-name: trojan-grpc
{s}
Link Trojan Account
{s}
Link WS : {l1}
{s}
Link GRPC : {l2}
{s}
""".format(s=sep, u=user, d=d, id=uid, l1=L[0][1], l2=L[1][1])


def acct_txt(kind, user, uid):
    return {"v": vless_txt, "m": vmess_txt, "t": trojan_txt}[kind](user, uid)


def xray_create(kind, user, days, iplim, quota, custom_uuid=None, nota=""):
    K = KIND[kind]
    D = K["dir"]
    uid = custom_uuid or str(uuidlib.uuid4())
    exp = exp_after(days)
    if kind == "v":
        a1, c1, a2, c2 = "#vless", "#vl %s %s %s" % (user, exp, uid), "#vlessgrpc", "#vlg %s %s" % (user, exp)
        cl = '},{"id": "%s","email": "%s"' % (uid, user)
    elif kind == "m":
        a1, c1, a2, c2 = "#vmess", "#vm %s %s" % (user, exp), "#vmessgrpc", "#vmg %s %s %s" % (user, exp, uid)
        cl = '},{"id": "%s","alterId": 0,"email": "%s"' % (uid, user)
    else:
        a1, c1, a2, c2 = "#trojanws", "#tr %s %s %s" % (user, exp, uid), "#trojangrpc", "#trg %s %s" % (user, exp)
        cl = '},{"password": "%s","email": "%s"' % (uid, user)

    def edit():
        sed(r'/%s$/a\%s' % (a1, c1) + "\\\n" + cl)
        sed(r'/%s$/a\%s' % (a2, c2) + "\\\n" + cl)

    ok, err = guarded_config_edit(edit)
    if not ok:
        return None, err
    q = quota or 9999
    il = iplim or 9999
    os.makedirs(P(D + "/akun"), exist_ok=True)
    nota_set(user, nota, kind)
    with open(P("%s/%s" % (D, user)), "w") as f:
        f.write("%d\n" % (q * 1024 ** 3))
    if kind == "t":
        with open(P("/etc/trojan/akun/%s" % user), "w") as f:
            f.write("login_ip=%d\n" % il)
    else:
        with open(P("%s/%sIP" % (D, user)), "w") as f:
            f.write("%d\n" % il)
    if kind == "v":
        with open(P("/etc/vless/akun/%s" % user), "w") as f:
            f.write("username=%s\nlimit_quota=%dGB\nusage_quota=0MB\nlogin_time=%s\nlogin_ip=0\n" % (
                user, q, time.strftime("%H:%M:%S.000000000")))
    os.makedirs(P("/home/vps/public_html"), exist_ok=True)
    with open(P("/home/vps/public_html/%s-%s.txt" % (K["pub"], user)), "w") as f:
        f.write(acct_txt(kind, user, uid))
    d = domain()
    L = [" ◇━━━━━━━━━━━━━━━━━◇", " • Premium %s Account •" % K["nama"], " ◇━━━━━━━━━━━━━━━━━◇",
         " User         : %s" % user]
    if nota:
        L.append(" Nota         : %s" % nota)
    L += [" ISP          : %s" % rd("/etc/xray/isp"), " City         : %s" % rd("/etc/xray/city"),
          " Domain       : %s" % d, " Login Limit  : %d IP" % il]
    if q != 9999:
        L.append(" Quota Limit  : %d GB" % q)
    if kind == "v":
        L += [" Port TLS     : 443", " Port NTLS    : 80,8080", " Port gRPC    : 443", " UUID         : %s" % uid,
              " Encryption   : none", " Network      : ws", " Path         : /vless", " Path grpc    : /vless-grpc"]
    elif kind == "m":
        L += [" Port TLS     : 443", " Port NTLS    : 80,8080", " Port gRPC    : 443", " AlterId      : 0",
              " Security     : auto", " Path         : /vmess", " Service      : vmess-grpc", " UUID         : %s" % uid]
    else:
        L += [" Port TLS     : 443", " Port gRPC    : 443", " Path WS      : /trojan-ws", " Path gRPC    : /trojan-grpc",
              " Key          : %s" % uid]
    L.append(" ◇━━━━━━━━━━━━━━━━━◇")
    for lab, lk in std_links(kind, user, uid):
        L += [" Link %s :" % lab, lk, " ◇━━━━━━━━━━━━━━━━━◇"]
    L += [" Format Openclash : http://%s:89/%s-%s.txt" % (d, K["pub"], user), " Expired Until   : %s" % exp,
          " ◇━━━━━━━━━━━━━━━━━◇"]
    with open(P("%s/akun/log-create-%s.log" % (D, user)), "w") as f:
        f.write("\n".join(L) + "\n")
    return {"user": user, "uuid": uid, "exp": exp, "ip": il, "quota": q}, ""


def xray_delete(kind, user):
    u = find(kind, user)
    if not u:
        return False, "Akaun tak jumpa."
    K = KIND[kind]
    D = K["dir"]
    _, exp, uid = u

    def edit():
        with open(P(D + "/akundelete"), "a") as f:
            f.write("### %s %s %s\n" % (user, exp, uid))
        sed("/^%s %s %s/,/^},{/d" % (K["m1"], user, exp))
        sed("/^%s %s %s/,/^},{/d" % (K["m2"], user, exp))

    os.makedirs(P(D), exist_ok=True)
    ok, err = guarded_config_edit(edit)
    if not ok:
        return False, err
    for f in ("%s/%sIP" % (D, user), "%s/%slogin" % (D, user), "%s/%s" % (D, user), "%s/akun/%s" % (D, user),
              "/home/vps/public_html/%s-%s.txt" % (K["pub"], user), "%s/nota/%s" % (D, user)):
        try:
            os.remove(P(f))
        except OSError:
            pass
    return True, ""


def xray_renew(kind, user, days):
    u = find(kind, user)
    if not u:
        return None, "Akaun tak jumpa."
    K = KIND[kind]
    _, exp, _ = u
    exp4 = exp_after(days_left(exp) + days)

    def edit():
        sed("s/%s %s %s/%s %s %s/g" % (K["m1"], user, exp, K["m1"], user, exp4))
        sed("s/%s %s %s/%s %s %s/g" % (K["m2"], user, exp, K["m2"], user, exp4))

    ok, err = guarded_config_edit(edit)
    return (exp4, "") if ok else (None, err)


# ---------------------------------------------------------------- SSH
SSH_PORTS = ("OpenSSH     : 22\nDropbear    : 109, 143\nSSH WS      : 80, 8080, 8880\n"
             "SSH SSL WS  : 443\nSSL/TLS     : 8443, 8881\nUDPGW       : 7100-7300")


def ssh_create(user, pw, days, iplim, quota):
    exp = exp_after(days)
    r = run(["useradd", "-e", exp, "-s", "/bin/false", "-M", user])
    if r.returncode != 0:
        return None, "useradd gagal: " + (r.stderr.strip() or "tak diketahui")
    r = run(["chpasswd"], inp="%s:%s\n" % (user, pw))
    if r.returncode != 0:
        run(["userdel", user])
        return None, "chpasswd gagal: " + r.stderr.strip()
    os.makedirs(P("/etc/xray/sshx/akun"), exist_ok=True)
    os.makedirs(P("/etc/kuota-ssh"), exist_ok=True)
    os.makedirs(P("/home/vps/public_html"), exist_ok=True)
    with open(P("/etc/xray/ssh"), "a") as f:
        f.write("### %s %s %s\n" % (user, exp, pw))
    with open(P("/etc/xray/sshx/%sIP" % user), "w") as f:
        f.write("%d\n" % iplim)
    q = quota or 9999
    with open(P("/etc/kuota-ssh/%s" % user), "w") as f:
        f.write('USERNAME="%s"\nSTATUS="AKTIF"\nLIMIT_BYTES="%d"\nUSAGE_BYTES="0"\n' % (user, q * 1024 ** 3))
    d = domain()
    txt = ("_______________________________\nFormat SSH OVPN Account\n_______________________________\n"
           "Username         : %s\nPassword         : %s\nExpired          : %s\n"
           "_______________________________\nHost             : %s\nISP              : %s\nCITY             : %s\n"
           "Login Limit      : %d IP\n%s\n_______________________________\n") % (
        user, pw, exp, d, rd("/etc/xray/isp"), rd("/etc/xray/city"), iplim, SSH_PORTS)
    with open(P("/home/vps/public_html/ssh-%s.txt" % user), "w") as f:
        f.write(txt)
    with open(P("/etc/xray/sshx/akun/log-create-%s.log" % user), "w") as f:
        f.write(txt)
    return {"user": user, "pw": pw, "exp": exp, "ip": iplim, "quota": q}, ""


def ssh_delete(user):
    u = find("s", user)
    if not u:
        return False, "Akaun tak jumpa."
    keep = [l for l in lines_of("/etc/xray/ssh") if not l.startswith("### %s " % user)]
    with open(P("/etc/xray/ssh"), "w") as f:
        f.write("\n".join(keep).rstrip("\n") + ("\n" if keep and any(keep) else ""))
    for f in ("/home/vps/public_html/ssh-%s.txt" % user, "/etc/xray/sshx/%sIP" % user,
              "/etc/xray/sshx/%slogin" % user, "/etc/kuota-ssh/%s" % user,
              "/etc/xray/sshx/akun/log-create-%s.log" % user):
        try:
            os.remove(P(f))
        except OSError:
            pass
    run(["pkill", "-KILL", "-u", user])
    run(["userdel", user])
    return True, ""


def ssh_renew(user, days):
    u = find("s", user)
    if not u:
        return None, "Akaun tak jumpa."
    _, exp, pw = u
    exp4 = exp_after(days_left(exp) + days)
    run(["passwd", "-u", user])
    r = run(["usermod", "-e", exp4, user])
    if r.returncode != 0:
        return None, "usermod gagal: " + r.stderr.strip()
    run(["chpasswd"], inp="%s:%s\n" % (user, pw))
    out = []
    for l in lines_of("/etc/xray/ssh"):
        if l.startswith("### %s %s " % (user, exp)):
            l = "### %s %s %s" % (user, exp4, pw)
        out.append(l)
    with open(P("/etc/xray/ssh"), "w") as f:
        f.write("\n".join(out).rstrip("\n") + "\n")
    return exp4, ""


# ---------------------------------------------------------------- mesej
def acct_info(kind, user, uid, exp):
    """Butiran akaun VLESS/VMess/Trojan (baris HTML) untuk mesej bot."""
    D = KIND[kind]["dir"]
    if kind == "t":
        m = re.search(r"login_ip=(\d+)", rd("/etc/trojan/akun/%s" % user, ""))
        il = m.group(1) if m else ""
    else:
        il = rd("%s/%sIP" % (D, user), "")
    qb = rd("%s/%s" % (D, user), "")
    iplim = "tiada had" if il in ("", "0", "9999") else "%s IP" % il
    quota = "tiada had"
    if qb.isdigit():
        g = int(qb) // 1024 ** 3
        if g not in (0, 9999):
            quota = "%d GB" % g
    t = ["User   : %s" % code(user)]
    n = nota_get(user, kind)
    if n:
        t.append("Nota   : %s" % E(n))
    t += ["ISP    : %s" % E(rd("/etc/xray/isp", "-")), "Domain : %s" % code(domain()),
          "Had IP : %s" % E(iplim), "Kuota  : %s" % E(quota),
          ("Key    : %s" if kind == "t" else "UUID   : %s") % code(uid),
          "Luput  : %s (%d hari)" % (E(exp), days_left(exp))]
    if kind == "v":
        t += ["Port   : TLS 443, NTLS 80/8080, gRPC 443", "Path   : /vless   gRPC: /vless-grpc",
              "Network: ws   Encryption: none"]
    elif kind == "m":
        t += ["Port   : TLS 443, NTLS 80/8080, gRPC 443", "Path   : /vmess   gRPC: vmess-grpc",
              "Network: ws   AlterId: 0"]
    else:
        t += ["Port   : TLS 443, gRPC 443", "Path   : /trojan-ws   gRPC: trojan-grpc", "Network: ws/grpc (TLS)"]
    return t


def acct_msg(kind, user, uid, exp, extra=""):
    K = KIND[kind]
    t = ["<b>%s siap</b>  ✦ kancil ecem" % K["nama"]] + acct_info(kind, user, uid, exp)
    if extra:
        t.append(E(extra))
    for lab, lk in std_links(kind, user, uid):
        t += ["", "<b>%s</b>" % E(lab), code(lk)]
    t += ["", "OpenClash: " + code("http://%s:89/%s-%s.txt" % (domain(), K["pub"], user)), "",
          "Pilih telco untuk link tambahan:"]
    return "\n".join(t)


def ssh_msg(user, pw, exp, ip):
    return "\n".join(["<b>SSH siap</b>  ✦ kancil ecem", "User     : %s" % code(user), "Password : %s" % code(pw),
                      "Host     : %s" % code(domain()), "Luput    : %s (%d hari)" % (E(exp), days_left(exp)),
                      "Had IP   : %d" % ip, "", "<pre>%s</pre>" % E(SSH_PORTS), "", "Developer by kancil ecem"])


def list_msg():
    t = []
    for k in XKINDS:
        us = xusers(k)
        t.append("<b>%s (%d)</b>" % (KIND[k]["nama"], len(us)))
        for u, e, _ in us:
            n = nota_get(u, k)
            t.append("%s  %s (%d hari)%s" % (code(u), E(e), days_left(e), (" · " + E(n)) if n else ""))
        t.append("")
    s = ssh_users()
    t.append("<b>SSH (%d)</b>" % len(s))
    for u, e, _ in s:
        t.append("%s  %s (%d hari)" % (code(u), E(e), days_left(e)))
    return "\n".join(t)


def status_msg():
    t = ["<b>Status VPS</b>  ✦ kancil ecem"]
    for svc in ("xray", "nginx", "dropbear", "stunnel4", "ws-stunnel"):
        a = run(["systemctl", "is-active", svc]).stdout.strip()
        t.append("%s %s" % ("✅" if a == "active" else "❌", svc))
    t.append("")
    t.append("Domain: %s" % code(domain()))
    t.append("Akaun: VLESS %d, VMess %d, Trojan %d, SSH %d" % (
        len(xusers("v")), len(xusers("m")), len(xusers("t")), len(ssh_users())))
    t += ["", "Developer by kancil ecem"]
    return "\n".join(t)


def user_buttons(kind, prefix):
    src = users_of(kind)
    b = [btn(u[0], "%s:%s:%s" % (prefix, kind, u[0])) for u in src[:90]]
    return rows(b, 2) + [[btn("Batal", "x")]]


# ---------------------------------------------------------------- aliran soalan
def v_int(lo, hi):
    def f(chat, s):
        if s.isdigit() and lo <= int(s) <= hi:
            return True, int(s)
        return False, "Nombor %d hingga %d sahaja." % (lo, hi)
    return f


def v_name(chat, s):
    if not NAME_RE.match(s):
        return False, "Nama tak sah (huruf, nombor, . _ - sahaja, maksimum 30)."
    if name_taken(s):
        return False, "Nama tu dah ada. Cuba nama lain."
    return True, s


def v_pw(chat, s):
    if s.lower() == "auto":
        return True, "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(10))
    if PW_RE.match(s):
        return True, s
    return False, "Kata laluan 4-32 aksara (huruf, nombor, . _ @ # % + = ! -). Atau taip auto."


def v_uuid(chat, s):
    if s.lower() == "auto":
        return True, None
    if not (UUID_RE.match(s) or UTXT_RE.match(s)):
        return False, "Tak sah. Guna UUID biasa (8-4-4-4-12) atau teks 8-30 aksara (A-Z a-z 0-9 . _ -). Atau taip auto."
    if ('"%s"' % s) in "\n".join(lines_of("/etc/xray/config.json")):
        return False, "Tu dah dipakai. Cuba yang lain."
    return True, s


def v_nota(chat, s):
    s = re.sub(r"[\x00-\x1f\x7f]", " ", s)
    s = " ".join(s.split())
    if s.lower() in ("0", "-", "tiada"):
        return True, ""
    if len(s) > 100:
        return False, "Nota terlalu panjang (maks 100 aksara). Ringkaskan, atau taip 0 kalau tiada."
    return True, s


def xflow(label, key):
    return [("nama", "Nama akaun %s?" % label, v_name),
            ("uuid", "%s custom? (taip auto untuk jana sendiri)" % key, v_uuid),
            ("hari", "Berapa hari? (contoh 30)", v_int(1, 3650)),
            ("ip", "Had IP? (0 = tiada had)", v_int(0, 9999)), ("gb", "Kuota GB? (0 = tiada had)", v_int(0, 9999)),
            ("nota", "Nota? (contoh nama pelanggan atau no. WhatsApp). Taip 0 kalau tiada", v_nota)]


FLOWS = {
    "vl": xflow("VLESS", "UUID"),
    "vm": xflow("VMess", "UUID"),
    "tr": xflow("Trojan", "Password"),
    "nt": [("nota", "Nota baru? Taip 0 untuk padam nota.", v_nota)],
    "ss": [("nama", "Nama akaun SSH?", v_name), ("pw", "Kata laluan? (taip auto untuk jana sendiri)", v_pw),
           ("hari", "Berapa hari? (contoh 30)", v_int(1, 3650)), ("ip", "Had IP? (0 = tiada had)", v_int(0, 9999)),
           ("gb", "Kuota GB? (0 = tiada had)", v_int(0, 9999))],
    "rn": [("hari", "Tambah berapa hari? (contoh 30)", v_int(1, 3650))],
}


def start_flow(chat, name, data=None):
    STATE[chat] = {"flow": name, "i": 0, "d": data or {}}
    send(chat, FLOWS[name][0][1] + "\n(/batal untuk berhenti)")


def finish(chat, st):
    d = st["d"]
    flow = st["flow"]
    STATE.pop(chat, None)
    if flow in FLOWKIND:
        kind = FLOWKIND[flow]
        send(chat, "Sekejap, cipta akaun...")
        r, err = xray_create(kind, d["nama"], d["hari"], d["ip"], d["gb"], d.get("uuid"), d.get("nota", ""))
        if not r:
            send(chat, E(err), MAIN_KB)
            return
        send(chat, acct_msg(kind, r["user"], r["uuid"], r["exp"]), telco_kb(r["user"], kind))
    elif flow == "ss":
        r, err = ssh_create(d["nama"], d["pw"], d["hari"], d["ip"], d["gb"])
        if not r:
            send(chat, E(err), MAIN_KB)
            return
        send(chat, ssh_msg(r["user"], r["pw"], r["exp"], r["ip"]), MAIN_KB)
    elif flow == "nt":
        kind = d.get("kind", "v")
        u = find(kind, d["user"])
        if not u:
            send(chat, "Akaun tak jumpa.", MAIN_KB)
            return
        nota_set(d["user"], d["nota"], kind)
        send(chat, ("Nota %s disimpan." if d["nota"] else "Nota %s dipadam.") % code(d["user"]), MAIN_KB)
        show_account(chat, kind, d["user"])
    elif flow == "rn":
        kind, user = d["kind"], d["user"]
        if kind == "s":
            exp, err = ssh_renew(user, d["hari"])
        else:
            exp, err = xray_renew(kind, user, d["hari"])
        if not exp:
            send(chat, E(err), MAIN_KB)
            return
        send(chat, "Renew siap: %s luput %s (%d hari)" % (code(user), E(exp), days_left(exp)), MAIN_KB)


def flow_input(chat, text):
    st = STATE[chat]
    steps = FLOWS[st["flow"]]
    key, _, validator = steps[st["i"]]
    ok, val = validator(chat, text)
    if not ok:
        send(chat, E(val))
        return
    st["d"][key] = val
    st["i"] += 1
    if st["i"] >= len(steps):
        finish(chat, st)
    else:
        send(chat, steps[st["i"]][1])


# ---------------------------------------------------------------- arahan dan butang
def show_account(chat, kind, user):
    u = find(kind, user)
    if not u:
        send(chat, "Akaun tak jumpa.", MAIN_KB)
        return
    if kind in KIND:
        _, exp, uid = u
        send(chat, acct_msg(kind, user, uid, exp), telco_kb(user, kind))
    else:
        _, exp, pw = u
        il = rd("/etc/xray/sshx/%sIP" % user, "0")
        send(chat, ssh_msg(user, pw, exp, int(il) if il.isdigit() else 0), MAIN_KB)


def kinds_of(name):
    return [k for k in ("v", "m", "t", "s") if find(k, name)]


def ask_kind(chat, name, prefix, label):
    ks = kinds_of(name)
    if not ks:
        send(chat, "Akaun %s tak jumpa." % code(name))
        return None
    if len(ks) == 1:
        return ks[0]
    send(chat, "%s ada dalam %s. %s yang mana?" % (code(name), ", ".join(kname(k) for k in ks), label),
         rows([btn(kname(k), "%s:%s:%s" % (prefix, k, name)) for k in ks], 2))
    return None


def quick_create(chat, kind, a):
    """/vless /vmess /trojan nama hari [ip] [gb] [uuid] [nota]"""
    flow = {"v": "vl", "m": "vm", "t": "tr"}[kind]
    if len(a) < 2:
        start_flow(chat, flow)
        return
    d = {}
    vals = a + ["0", "0"][:max(0, 4 - len(a))]
    ok1, d["nama"] = v_name(chat, vals[0])
    ok2, d["hari"] = v_int(1, 3650)(chat, vals[1])
    ok3, d["ip"] = v_int(0, 9999)(chat, vals[2])
    ok4, d["gb"] = v_int(0, 9999)(chat, vals[3])
    ok5, d["uuid"] = v_uuid(chat, a[4] if len(a) >= 5 else "auto")
    ok6, d["nota"] = v_nota(chat, " ".join(a[5:]))
    bad = [x for ok, x in ((ok1, d["nama"]), (ok2, d["hari"]), (ok3, d["ip"]), (ok4, d["gb"]), (ok5, d["uuid"]), (ok6, d["nota"])) if not ok]
    if bad:
        send(chat, E(bad[0]))
        return
    finish(chat, {"flow": flow, "d": d})


def on_command(chat, text):
    parts = text.split()
    cmd = parts[0].split("@")[0].lower()
    a = parts[1:]
    if cmd in ("/start", "/menu"):
        STATE.pop(chat, None)
        send(chat, "✦ <b>KANCIL ECEM</b> ✦\nDeveloper by kancil ecem\n\nPilih:", MAIN_KB)
    elif cmd == "/bantuan":
        send(chat, "\n".join([
            "<b>Arahan</b>", "/menu - butang utama",
            "/vless nama hari [ip] [gb] [uuid] [nota] - cipta VLESS terus (uuid custom: letak 0 0 dulu, tak nak uuid custom: letak auto)",
            "/vmess nama hari [ip] [gb] [uuid] [nota] - cipta VMess terus",
            "/trojan nama hari [ip] [gb] [password] [nota] - cipta Trojan terus",
            "/ssh nama kata_laluan hari [ip] [gb] - cipta SSH terus",
            "/nota nama [teks] - lihat atau tukar nota akaun VLESS, VMess atau Trojan (0 = padam)",
            "/senarai - semua akaun", "/semak nama", "/renew nama hari", "/padam nama",
            "/status - servis VPS", "/trial - trial awam untuk orang lain (hidup/tutup, tetapan)", "/batal - berhenti soalan"]))
    elif cmd == "/batal":
        STATE.pop(chat, None)
        send(chat, "Batal.", MAIN_KB)
    elif cmd in ("/trial", "/trialon", "/trialoff", "/trialset", "/trialban", "/trialbuka", "/trialuji"):
        trial_cmd(chat, cmd, a)
    elif cmd == "/senarai":
        send(chat, list_msg(), MAIN_KB)
    elif cmd == "/status":
        send(chat, status_msg(), MAIN_KB)
    elif cmd in ("/vless", "/vmess", "/trojan"):
        quick_create(chat, {"/vless": "v", "/vmess": "m", "/trojan": "t"}[cmd], a)
    elif cmd == "/ssh":
        if len(a) >= 3:
            d = {}
            vals = a + ["0", "0"][:max(0, 5 - len(a))]
            checks = [("nama", v_name, vals[0]), ("pw", v_pw, vals[1]), ("hari", v_int(1, 3650), vals[2]),
                      ("ip", v_int(0, 9999), vals[3]), ("gb", v_int(0, 9999), vals[4])]
            for k, f, s in checks:
                ok, v = f(chat, s)
                if not ok:
                    send(chat, E(v))
                    return
                d[k] = v
            finish(chat, {"flow": "ss", "d": d})
        else:
            start_flow(chat, "ss")
    elif cmd == "/nota":
        ks = [k for k in kinds_of(a[0]) if k in KIND] if a else []
        if not a:
            send(chat, "Guna: /nota nama teks  (tukar nota) | /nota nama  (lihat) | /nota nama 0  (padam)")
        elif not ks:
            send(chat, "Akaun VLESS, VMess atau Trojan %s tak jumpa." % code(a[0]))
        elif len(a) == 1:
            n = nota_get(a[0], ks[0])
            send(chat, ("Nota %s: %s" % (code(a[0]), E(n))) if n else "Tiada nota untuk %s." % code(a[0]))
        else:
            ok, v = v_nota(chat, " ".join(a[1:]))
            if not ok:
                send(chat, E(v))
            else:
                nota_set(a[0], v, ks[0])
                send(chat, ("Nota %s disimpan: %s" % (code(a[0]), E(v))) if v else "Nota %s dipadam." % code(a[0]), MAIN_KB)
    elif cmd == "/semak" and a:
        k = ask_kind(chat, a[0], "c", "Semak")
        if k:
            show_account(chat, k, a[0])
    elif cmd == "/padam" and a:
        k = ask_kind(chat, a[0], "d", "Padam")
        if k:
            send(chat, "Padam %s (%s)?" % (code(a[0]), kname(k)),
                 [[btn("Ya, padam", "D:%s:%s" % (k, a[0])), btn("Batal", "x")]])
    elif cmd == "/renew" and len(a) >= 2:
        ok, days = v_int(1, 3650)(chat, a[1])
        if not ok:
            send(chat, E(days))
            return
        k = ask_kind(chat, a[0], "r", "Renew")
        if k:
            STATE[chat] = {"flow": "rn", "i": 1, "d": {"kind": k, "user": a[0], "hari": days}}
            finish(chat, STATE[chat])
    elif cmd in ("/semak", "/padam", "/renew"):
        send(chat, "Guna: /semak nama | /padam nama | /renew nama hari")
    else:
        send(chat, "Arahan tak dikenali. Taip /menu atau /bantuan.")


def on_callback(chat, data):
    p = data.split(":", 2)
    k = p[0]
    KS = ("v", "m", "t", "s")
    if k == "x":
        STATE.pop(chat, None)
        send(chat, "Batal.", MAIN_KB)
    elif k == "m" and len(p) >= 2:
        what = p[1]
        if what in ("vl", "vm", "tr", "ss"):
            start_flow(chat, what)
        elif what == "ls":
            send(chat, list_msg(), MAIN_KB)
        elif what == "st":
            send(chat, status_msg(), MAIN_KB)
        elif what == "tl":
            send(chat, trial_admin_msg(), MAIN_KB)
        elif what in ("ck", "dl", "rn"):
            send(chat, "Jenis akaun?", [[btn("VLESS", "%s:v" % what), btn("VMess", "%s:m" % what)],
                                        [btn("Trojan", "%s:t" % what), btn("SSH", "%s:s" % what)], [btn("Batal", "x")]])
    elif k in ("ck", "dl", "rn") and len(p) == 2 and p[1] in KS:
        pre = {"ck": "c", "dl": "d", "rn": "r"}[k]
        kb = user_buttons(p[1], pre)
        send(chat, "Pilih akaun:" if len(kb) > 1 else "Tiada akaun.", kb if len(kb) > 1 else MAIN_KB)
    elif k == "c" and len(p) == 3 and p[1] in KS:
        show_account(chat, p[1], p[2])
    elif k == "d" and len(p) == 3 and p[1] in KS:
        send(chat, "Padam %s (%s)?" % (code(p[2]), kname(p[1])),
             [[btn("Ya, padam", "D:%s:%s" % (p[1], p[2])), btn("Batal", "x")]])
    elif k == "D" and len(p) == 3 and p[1] in KS:
        ok, err = ssh_delete(p[2]) if p[1] == "s" else xray_delete(p[1], p[2])
        send(chat, ("Dah dipadam: %s" % code(p[2])) if ok else E(err), MAIN_KB)
    elif k == "r" and len(p) == 3 and p[1] in KS:
        start_flow(chat, "rn", {"kind": p[1], "user": p[2]})
    elif k == "n" and len(p) >= 2:
        if len(p) == 3 and p[1] in XKINDS:
            kind, user = p[1], p[2]
        else:
            kind, user = "v", ":".join(p[1:])
        if not find(kind, user):
            send(chat, "Akaun tak jumpa.", MAIN_KB)
            return
        start_flow(chat, "nt", {"kind": kind, "user": user})
    elif k in ("t", "tm", "tt"):
        kind = {"t": "v", "tm": "m", "tt": "t"}[k]
        q = data.split(":")
        user, n = q[1], int(q[2]) if len(q) > 2 and q[2].isdigit() else 0
        u = find(kind, user)
        if not u:
            send(chat, "Akaun tak jumpa.", MAIN_KB)
            return
        T = telcos()
        sel = T if n == 0 else T[n - 1:n]
        if not sel:
            send(chat, "Telco tak ada.", MAIN_KB)
            return
        out = ["<b>Akaun %s</b>" % KIND[kind]["nama"]] + acct_info(kind, user, u[2], u[1]) + ["", "<b>Link telco</b>", ""]
        for t in sel:
            out += ["<b>%s</b>" % E(t[0]), code(telco_link(u[2], user, t, kind)), ""]
        send(chat, "\n".join(out).rstrip(), telco_kb(user, kind))


# ---------------------------------------------------------------- TRIAL AWAM
# Orang lain (bukan admin) boleh minta akaun trial: pilih jenis, pilih telco, dapat akaun. Hidup bila admin taip /trialon.
# Akaun dipadam sendiri bila tamat. Fail tetapan dan rekod: /etc/tbot/trial.json (tiada rahsia akaun disimpan di situ).
TRIAL_F = "/etc/tbot/trial.json"
TRIAL_KIND = {"v": "VLESS", "m": "VMess", "t": "Trojan", "s": "SSH"}
TRIAL_DEF = {"aktif": False, "minit": 60, "jam": 24, "had_aktif": 20, "had_sehari": 30, "kuota": 2, "iplimit": 1,
             "jenis": ["v", "m", "t", "s"], "hubung": "", "banned": [], "last": {}, "rec": [], "hari": "", "kira": 0}
TRIAL_RANGE = {"minit": (5, 1440), "jam": (1, 720), "had_aktif": (1, 200), "had_sehari": (1, 1000),
               "kuota": (1, 50), "iplimit": (1, 3)}
TRIAL_ALIAS = {"minit": "minit", "jam": "jam", "aktif": "had_aktif", "sehari": "had_sehari", "kuota": "kuota", "ip": "iplimit"}
HUBUNG_RE = re.compile(r"^@?[A-Za-z0-9_]{3,32}$")
TRIAL_SENYAP = {}


def trial_load():
    d = copy.deepcopy(TRIAL_DEF)
    try:
        with open(P(TRIAL_F)) as f:
            j = json.load(f)
        if isinstance(j, dict):
            d.update(j)
    except (OSError, ValueError):
        pass
    d["jenis"] = [k for k in d.get("jenis", []) if k in TRIAL_KIND]
    return d


def trial_save(d):
    p = P(TRIAL_F)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = p + ".tmp"
    with open(tmp, "w") as f:
        json.dump(d, f)
    os.chmod(tmp, 0o600)
    os.replace(tmp, p)


def trial_tempoh(sec):
    m = int((sec + 59) // 60)
    if m >= 120:
        return "%d jam %d minit" % (m // 60, m % 60) if m % 60 else "%d jam" % (m // 60)
    return "%d minit" % max(m, 1)


def trial_tunggu(d, uid):
    return max(0, d["last"].get(str(uid), 0) + d["jam"] * 3600 - time.time())


def trial_hubung(d):
    h = d.get("hubung", "")
    return ("\nNak akaun penuh, hubungi %s" % E(h if h.startswith("@") else "@" + h)) if h else ""


def trial_nama(kind):
    if kind == "s":
        return "trial" + "".join(secrets.choice(string.ascii_lowercase + string.digits) for _ in range(4))
    return "Trial-" + "".join(secrets.choice("XYZ0123456789") for _ in range(4))


def trial_start(chat, frm):
    uid = frm["id"]
    adm = uid in ADMINS
    d = trial_load()
    if not d["aktif"] or (uid in d["banned"] and not adm):
        return
    now = time.time()
    if not adm:
        if now - TRIAL_SENYAP.get(uid, 0) < 2:
            return
        if len(TRIAL_SENYAP) > 2000:
            TRIAL_SENYAP.clear()
        TRIAL_SENYAP[uid] = now
    if not d["jenis"]:
        return
    mine = [r for r in d["rec"] if r["uid"] == uid]
    if mine:
        r = mine[0]
        send(chat, "Kau masih ada trial %s (%s). Tamat dalam %s." % (
            TRIAL_KIND[r["kind"]], code(r["user"]), trial_tempoh(r["tamat"] - now)) + trial_hubung(d))
        return
    w = 0 if adm else trial_tunggu(d, uid)
    if w > 0:
        send(chat, "Kau dah guna trial. Boleh minta lagi dalam %s." % trial_tempoh(w) + trial_hubung(d))
        return
    kb = rows([btn("🎁 " + TRIAL_KIND[k], "pt:%s" % k) for k in d["jenis"]], 2)
    send(chat, "\n".join(["🎁 <b>Trial percuma</b>  ✦ kancil ecem",
                          "Tempoh %s • kuota %d GB • %d peranti" % (trial_tempoh(d["minit"] * 60), d["kuota"], d["iplimit"]),
                          "Satu trial setiap %d jam." % d["jam"], "", "Pilih jenis akaun:"]), kb)


def trial_cb(chat, frm, data):
    p = data.split(":")
    d = trial_load()
    uid = frm["id"]
    if not d["aktif"] or (uid in d["banned"] and uid not in ADMINS):
        return
    if len(p) < 2 or p[1] not in d["jenis"]:
        send(chat, "Jenis ni tak dibuka. Taip /start.")
        return
    kind = p[1]
    if p[0] == "pt":
        if kind == "s":
            trial_buat(chat, frm, kind, 0)
            return
        T = telcos()
        b = [btn(t[0], "pc:%s:%d" % (kind, i + 1)) for i, t in enumerate(T)]
        kb = rows(b, 3) + [[btn("Tanpa telco (link biasa)", "pc:%s:0" % kind)]]
        send(chat, "Pilih telco kau:", kb)
    elif p[0] == "pc" and len(p) == 3 and p[2].isdigit():
        trial_buat(chat, frm, kind, int(p[2]))


def trial_msg(kind, r, tl, minit, d):
    now = time.time()
    t = ["🎁 <b>Trial %s</b>  ✦ kancil ecem" % TRIAL_KIND[kind]]
    if kind == "s":
        t += ["User     : %s" % code(r["user"]), "Password : %s" % code(r["pw"]), "Host     : %s" % code(domain()),
              "Had     : %d peranti, %d GB" % (r["ip"], r["quota"]),
              "Tamat    : dalam %s" % trial_tempoh(minit * 60), "", "<pre>%s</pre>" % E(SSH_PORTS)]
    else:
        info = [l for l in acct_info(kind, r["user"], r["uuid"], r["exp"]) if not l.startswith(("Luput", "Nota"))]
        t += info + ["Tamat  : dalam %s" % trial_tempoh(minit * 60)]
        if tl:
            t += ["", "<b>Link %s</b>" % E(tl[0]), code(telco_link(r["uuid"], r["user"], tl, kind))]
        else:
            for lab, lk in std_links(kind, r["user"], r["uuid"]):
                t += ["", "<b>%s</b>" % E(lab), code(lk)]
    t.append(trial_hubung(d).strip("\n"))
    return "\n".join(x for x in t if x is not None)


def trial_buat(chat, frm, kind, n):
    d = trial_load()
    uid = frm["id"]
    adm = uid in ADMINS
    if not d["aktif"] or kind not in d["jenis"]:
        send(chat, "Trial tak dibuka sekarang.")
        return
    if any(r["uid"] == uid for r in d["rec"]):
        send(chat, "Kau masih ada trial aktif." + trial_hubung(d))
        return
    w = 0 if adm else trial_tunggu(d, uid)
    if w > 0:
        send(chat, "Kau dah guna trial. Boleh minta lagi dalam %s." % trial_tempoh(w) + trial_hubung(d))
        return
    hari = today().isoformat()
    if d["hari"] != hari:
        d["hari"], d["kira"] = hari, 0
    if len(d["rec"]) >= d["had_aktif"] or d["kira"] >= d["had_sehari"]:
        send(chat, "Trial penuh buat masa ni. Cuba lagi nanti." + trial_hubung(d))
        return
    tl = None
    if kind != "s" and n:
        T = telcos()
        if n < 1 or n > len(T):
            send(chat, "Telco tak sah. Taip /start.")
            return
        tl = T[n - 1]
    user = None
    for _ in range(10):
        c = trial_nama(kind)
        if not name_taken(c):
            user = c
            break
    if not user:
        send(chat, "Maaf, tak dapat cipta akaun sekarang. Cuba lagi sebentar.")
        return
    if kind == "s":
        pw = "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(8))
        r, err = ssh_create(user, pw, 1, d["iplimit"], d["kuota"])
    else:
        r, err = xray_create(kind, user, 0, d["iplimit"], d["kuota"], nota="Trial tg:%d" % uid)
    if not r:
        log("trial gagal:", err)
        send(chat, "Maaf, trial tak dapat dicipta sekarang. Cuba lagi sebentar.")
        return
    now = time.time()
    d["rec"].append({"user": user, "kind": kind, "uid": uid, "chat": chat, "tamat": now + d["minit"] * 60})
    if not adm:
        d["last"][str(uid)] = now
    d["last"] = {k: v for k, v in d["last"].items() if v + d["jam"] * 3600 > now}
    d["kira"] += 1
    trial_save(d)
    send(chat, trial_msg(kind, r, tl, d["minit"], d))
    nm = E(" ".join(x for x in (frm.get("first_name", ""), ("@" + frm["username"]) if frm.get("username") else "") if x) or "-")
    note = "🎁 Trial %s%s  •  %s (<code>%d</code>)\n%s  •  aktif sekarang %d  •  hari ni %d" % (
        TRIAL_KIND[kind], (" " + E(tl[0])) if tl else "", nm, uid, trial_tempoh(d["minit"] * 60), len(d["rec"]), d["kira"])
    for a in ADMINS:
        if a != chat:
            send(a, note)


def trial_sweep():
    """Padam trial yang dah tamat. Dipanggil tiap pusingan bot (lebih kurang setiap 30 saat)."""
    d = trial_load()
    now = time.time()
    due = [r for r in d["rec"] if r["tamat"] <= now and r.get("next", 0) <= now]
    if not due:
        return
    for r in due:
        if r["kind"] == "s":
            ok, err = ssh_delete(r["user"])
        else:
            ok, err = xray_delete(r["kind"], r["user"])
        if not ok and find(r["kind"], r["user"]) is not None:
            r["cuba"] = r.get("cuba", 0) + 1
            r["next"] = now + 120
            log("trial gagal dipadam:", r["user"], err)
            if r["cuba"] < 5:
                continue
            for a in ADMINS:
                send(a, "⚠️ Trial %s tak dapat dipadam sendiri selepas 5 cubaan. Padam manual." % code(r["user"]))
        d["rec"] = [x for x in d["rec"] if x is not r and not (x["user"] == r["user"] and x["kind"] == r["kind"])]
        send(r["chat"], "⏰ Trial %s dah tamat dan dipadam. Terima kasih dah cuba!" % code(r["user"]) + trial_hubung(d))
    # simpan dengan keadaan terkini (rekod yang masih tinggal + penanda cuba semula)
    d2 = trial_load()
    keep = {(x["user"], x["kind"]): x for x in d["rec"]}
    d2["rec"] = [keep.get((x["user"], x["kind"]), x) for x in d2["rec"] if (x["user"], x["kind"]) in keep]
    trial_save(d2)


def trial_admin_msg():
    d = trial_load()
    now = time.time()
    L = ["🎁 <b>Trial awam</b>  ✦ kancil ecem", "Status  : %s" % ("HIDUP" if d["aktif"] else "TUTUP"),
         "Tempoh  : %s  •  kuota %d GB  •  %d IP" % (trial_tempoh(d["minit"] * 60), d["kuota"], d["iplimit"]),
         "Ulang   : 1 setiap %d jam seorang" % d["jam"],
         "Had     : aktif %d, sehari %d (hari ni %d)" % (d["had_aktif"], d["had_sehari"], d["kira"] if d["hari"] == today().isoformat() else 0),
         "Jenis   : %s" % (", ".join(TRIAL_KIND[k] for k in d["jenis"]) or "tiada"),
         "Hubungi : %s" % (E(d["hubung"]) if d["hubung"] else "-"),
         "Disekat : %d orang" % len(d["banned"]), "", "Aktif sekarang: %d" % len(d["rec"])]
    for r in d["rec"]:
        L.append(" %s  %s  sisa %s  (tg:%d)" % (TRIAL_KIND[r["kind"]], code(r["user"]), trial_tempoh(max(0, r["tamat"] - now)), r["uid"]))
    L += ["", "/trialon  /trialoff", "/trialset minit=60 jam=24 aktif=20 sehari=30 kuota=2 ip=1 jenis=v,m,t,s hubung=@nama",
          "/trialban ID  /trialbuka ID  /trialuji (cuba sendiri)"]
    return "\n".join(L)


def trial_cmd(chat, cmd, a):
    d = trial_load()
    if cmd == "/trial":
        send(chat, trial_admin_msg(), MAIN_KB)
    elif cmd == "/trialon":
        if not d["jenis"]:
            send(chat, "Tiada jenis dibenarkan. Guna /trialset jenis=v,m,t,s")
            return
        d["aktif"] = True
        trial_save(d)
        send(chat, "Trial HIDUP. Sesiapa yang taip /start kat bot ni boleh minta trial.\n\n" + trial_admin_msg(), MAIN_KB)
    elif cmd == "/trialoff":
        d["aktif"] = False
        trial_save(d)
        send(chat, "Trial TUTUP. Trial yang sedang jalan tetap dipadam bila tamat.", MAIN_KB)
    elif cmd == "/trialset":
        if not a:
            send(chat, "Guna: /trialset minit=60 jam=24 aktif=20 sehari=30 kuota=2 ip=1 jenis=v,m,t,s hubung=@nama (hubung=0 untuk padam)")
            return
        for tok in a:
            if "=" not in tok:
                send(chat, "Tak sah: %s. Guna bentuk nama=nilai." % code(tok))
                return
            k, v = tok.split("=", 1)
            k = k.lower()
            if k in TRIAL_ALIAS:
                f = TRIAL_ALIAS[k]
                lo, hi = TRIAL_RANGE[f]
                if not v.isdigit() or not lo <= int(v) <= hi:
                    send(chat, "%s mesti nombor %d hingga %d." % (code(k), lo, hi))
                    return
                d[f] = int(v)
            elif k == "jenis":
                js = [x for x in v.lower().split(",") if x]
                if not js or any(x not in TRIAL_KIND for x in js):
                    send(chat, "jenis: guna huruf v m t s dipisah koma. Contoh jenis=v,m")
                    return
                d["jenis"] = [x for x in "vmts" if x in js]
            elif k == "hubung":
                if v == "0":
                    d["hubung"] = ""
                elif HUBUNG_RE.match(v):
                    d["hubung"] = v if v.startswith("@") else "@" + v
                else:
                    send(chat, "hubung: guna @nama Telegram (huruf, nombor, _).")
                    return
            else:
                send(chat, "Tak dikenali: %s" % code(k))
                return
        trial_save(d)
        send(chat, "Disimpan.\n\n" + trial_admin_msg(), MAIN_KB)
    elif cmd in ("/trialban", "/trialbuka"):
        if len(a) != 1 or not a[0].isdigit():
            send(chat, "Guna: %s ID_Telegram (nombor)" % cmd)
            return
        i = int(a[0])
        if cmd == "/trialban":
            if i in ADMINS:
                send(chat, "Itu admin.")
                return
            if i not in d["banned"]:
                d["banned"].append(i)
        else:
            d["banned"] = [x for x in d["banned"] if x != i]
        trial_save(d)
        send(chat, "%s %d. Disekat sekarang: %d orang." % ("Disekat" if cmd == "/trialban" else "Dibuka", i, len(d["banned"])), MAIN_KB)
    elif cmd == "/trialuji":
        if not d["aktif"]:
            send(chat, "Trial masih TUTUP. Taip /trialon dulu.")
        else:
            trial_start(chat, {"id": chat, "first_name": "admin"})


def handle(u):
    if "callback_query" in u:
        cq = u["callback_query"]
        msg = cq.get("message") or {}
        chat = (msg.get("chat") or {}).get("id")
        try:
            tg("answerCallbackQuery", callback_query_id=cq["id"])
        except Exception:
            pass
        if chat is None or (msg.get("chat") or {}).get("type") != "private":
            return
        data = cq.get("data", "")
        if data.startswith(("pt:", "pc:")):
            trial_cb(chat, cq["from"], data)
            return
        if cq["from"]["id"] not in ADMINS:
            return
        on_callback(chat, data)
        return
    msg = u.get("message")
    if not msg or "text" not in msg:
        return
    chat = msg["chat"]["id"]
    uid = msg["from"]["id"]
    text = msg["text"].strip()
    if msg["chat"].get("type") != "private":
        return
    if uid not in ADMINS:
        if trial_load()["aktif"]:
            trial_start(chat, msg["from"])
            return
        # senyap: orang asing tak dapat balasan langsung. Cuma catat sekali setiap ID dalam log.
        if uid not in SEEN:
            if len(SEEN) > 1000:
                SEEN.clear()
            SEEN.add(uid)
            log("akses ditolak, ID:", uid)
        return
    if text.startswith("/"):
        on_command(chat, text)
    elif chat in STATE:
        flow_input(chat, text)
    else:
        send(chat, "Taip /menu.", MAIN_KB)


def main():
    load_conf()
    log("tbot mula, admin:", sorted(ADMINS))
    offset = None
    while True:
        try:
            trial_sweep()
        except Exception:
            log("trial_sweep ralat:", traceback.format_exc())
        try:
            params = {"timeout": 30, "allowed_updates": ["message", "callback_query"]}
            if offset is not None:
                params["offset"] = offset
            r = tg("getUpdates", **params)
            for u in r.get("result", []):
                offset = u["update_id"] + 1
                try:
                    handle(u)
                except Exception:
                    log("ralat:", traceback.format_exc())
                    try:
                        c = (u.get("message") or (u.get("callback_query") or {}).get("message") or {}).get("chat", {}).get("id")
                        if c:
                            send(c, "Ada ralat dalam bot. Cuba lagi atau semak: journalctl -u tbot -n 20", MAIN_KB)
                    except Exception:
                        pass
        except KeyboardInterrupt:
            break
        except Exception as e:
            log("getUpdates gagal:", e)
            time.sleep(5)


if __name__ == "__main__":
    main()
