#!/usr/bin/env python3
# tbot - bot Telegram untuk urus akaun VLESS dan SSH di VPS autoscript (admin sahaja)
# Konfigurasi: /etc/tbot/config  (TOKEN=... dan ADMINS=id1,id2). Tiada rahsia dalam fail ni.
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
    [btn("➕ VLESS", "m:vl"), btn("➕ SSH", "m:ss")],
    [btn("📋 Senarai", "m:ls"), btn("🔎 Semak", "m:ck")],
    [btn("🔁 Renew", "m:rn"), btn("🗑 Padam", "m:dl")],
    [btn("ℹ️ Status", "m:st")],
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


def vless_users():
    out = []
    for line in lines_of("/etc/xray/config.json"):
        if line.startswith("#vl "):
            p = line.split()
            if len(p) >= 4:
                out.append((p[1], p[2], p[3]))
    return out


def ssh_users():
    out = []
    for line in lines_of("/etc/xray/ssh"):
        if line.startswith("### "):
            p = line.split()
            if len(p) >= 4:
                out.append((p[1], p[2], p[3]))
    return out


def name_taken(name):
    if any(u[0] == name for u in vless_users() + ssh_users()):
        return True
    if ('"email": "%s"' % name) in "\n".join(lines_of("/etc/xray/config.json")):
        return True
    return run(["id", name]).returncode == 0


def find(kind, name):
    src = vless_users() if kind == "v" else ssh_users()
    for u in src:
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


def telco_link(uid, user, t):
    n, a, h, p, port = t
    d = domain()
    a = a.replace("{domain}", d)
    h = h.replace("{domain}", d)
    return "vless://%s@%s:%s?encryption=none&type=ws&host=%s&headerType=none&path=%s#%s-%s" % (
        uid, a, port, h, p.replace("/", "%2F"), user, n)


def telco_kb(user):
    b = [btn(t[0], "t:%s:%d" % (user, i + 1)) for i, t in enumerate(telcos())]
    kb = rows(b, 3)
    kb.append([btn("Semua telco", "t:%s:0" % user)])
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


def vless_create(user, days, iplim, quota, custom_uuid=None):
    uid = custom_uuid or str(uuidlib.uuid4())
    exp = exp_after(days)

    def edit():
        sed(r'/#vless$/a\#vl %s %s %s' % (user, exp, uid) + "\\\n" + '},{"id": "%s","email": "%s"' % (uid, user))
        sed(r'/#vlessgrpc$/a\#vlg %s %s' % (user, exp) + "\\\n" + '},{"id": "%s","email": "%s"' % (uid, user))

    ok, err = guarded_config_edit(edit)
    if not ok:
        return None, err
    q = quota or 9999
    il = iplim or 9999
    os.makedirs(P("/etc/vless/akun"), exist_ok=True)
    with open(P("/etc/vless/%s" % user), "w") as f:
        f.write("%d\n" % (q * 1024 ** 3))
    with open(P("/etc/vless/%sIP" % user), "w") as f:
        f.write("%d\n" % il)
    os.makedirs(P("/home/vps/public_html"), exist_ok=True)
    with open(P("/home/vps/public_html/vless-%s.txt" % user), "w") as f:
        f.write(vless_txt(user, uid))
    with open(P("/etc/vless/akun/%s" % user), "w") as f:
        f.write("username=%s\nlimit_quota=%dGB\nusage_quota=0MB\nlogin_time=%s\nlogin_ip=0\n" % (
            user, q, time.strftime("%H:%M:%S.000000000")))
    d = domain()
    L = [" ◇━━━━━━━━━━━━━━━━━◇", " • Premium Vless Account •", " ◇━━━━━━━━━━━━━━━━━◇",
         " User         : %s" % user, " ISP          : %s" % rd("/etc/xray/isp"), " City         : %s" % rd("/etc/xray/city"),
         " Domain       : %s" % d, " Login Limit  : %d IP" % il]
    if q != 9999:
        L.append(" Quota Limit  : %d GB" % q)
    L += [" Port TLS     : 443", " Port NTLS    : 80,8080", " Port gRPC    : 443", " UUID         : %s" % uid,
          " Encryption   : none", " Network      : ws", " Path         : /vless", " Path grpc    : /vless-grpc",
          " ◇━━━━━━━━━━━━━━━━━◇"]
    for lab, lk in vless_std_links(user, uid):
        L += [" Link %s :" % lab, lk, " ◇━━━━━━━━━━━━━━━━━◇"]
    L += [" Format Openclash : http://%s:89/vless-%s.txt" % (d, user), " Expired Until   : %s" % exp,
          " ◇━━━━━━━━━━━━━━━━━◇"]
    with open(P("/etc/vless/akun/log-create-%s.log" % user), "w") as f:
        f.write("\n".join(L) + "\n")
    return {"user": user, "uuid": uid, "exp": exp, "ip": il, "quota": q}, ""


def vless_delete(user):
    u = find("v", user)
    if not u:
        return False, "Akaun tak jumpa."
    _, exp, uid = u

    def edit():
        with open(P("/etc/vless/akundelete"), "a") as f:
            f.write("### %s %s %s\n" % (user, exp, uid))
        sed("/^#vl %s %s/,/^},{/d" % (user, exp))
        sed("/^#vlg %s %s/,/^},{/d" % (user, exp))

    os.makedirs(P("/etc/vless"), exist_ok=True)
    ok, err = guarded_config_edit(edit)
    if not ok:
        return False, err
    for f in ("/etc/vless/%sIP" % user, "/etc/vless/%slogin" % user, "/etc/vless/%s" % user,
              "/etc/vless/akun/%s" % user, "/home/vps/public_html/vless-%s.txt" % user):
        try:
            os.remove(P(f))
        except OSError:
            pass
    return True, ""


def vless_renew(user, days):
    u = find("v", user)
    if not u:
        return None, "Akaun tak jumpa."
    _, exp, _ = u
    exp4 = exp_after(days_left(exp) + days)

    def edit():
        sed("s/#vl %s %s/#vl %s %s/g" % (user, exp, user, exp4))
        sed("s/#vlg %s %s/#vlg %s %s/g" % (user, exp, user, exp4))

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
def vless_msg(user, uid, exp, extra=""):
    t = ["<b>VLESS siap</b>  ✦ kancil ecem", "User   : %s" % code(user), "UUID   : %s" % code(uid),
         "Luput  : %s (%d hari)" % (E(exp), days_left(exp))]
    if extra:
        t.append(E(extra))
    for lab, lk in vless_std_links(user, uid):
        t += ["", "<b>%s</b>" % E(lab), code(lk)]
    t += ["", "OpenClash: " + code("http://%s:89/vless-%s.txt" % (domain(), user)), "", "Pilih telco untuk link tambahan:"]
    return "\n".join(t)


def ssh_msg(user, pw, exp, ip):
    return "\n".join(["<b>SSH siap</b>  ✦ kancil ecem", "User     : %s" % code(user), "Password : %s" % code(pw),
                      "Host     : %s" % code(domain()), "Luput    : %s (%d hari)" % (E(exp), days_left(exp)),
                      "Had IP   : %d" % ip, "", "<pre>%s</pre>" % E(SSH_PORTS), "", "Developer by kancil ecem"])


def list_msg():
    v, s = vless_users(), ssh_users()
    t = ["<b>VLESS (%d)</b>" % len(v)]
    for u, e, _ in v:
        t.append("%s  %s (%d hari)" % (code(u), E(e), days_left(e)))
    t += ["", "<b>SSH (%d)</b>" % len(s)]
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
    t.append("Akaun: VLESS %d, SSH %d" % (len(vless_users()), len(ssh_users())))
    t += ["", "Developer by kancil ecem"]
    return "\n".join(t)


def user_buttons(kind, prefix):
    src = vless_users() if kind == "v" else ssh_users()
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
        return False, "UUID tak sah. Guna UUID biasa (8-4-4-4-12) atau teks 8-30 aksara (A-Z a-z 0-9 . _ -). Atau taip auto."
    if ('"%s"' % s) in "\n".join(lines_of("/etc/xray/config.json")):
        return False, "UUID tu dah dipakai. Cuba yang lain."
    return True, s


FLOWS = {
    "vl": [("nama", "Nama akaun VLESS?", v_name),
           ("uuid", "UUID custom? (taip auto untuk jana sendiri)", v_uuid), ("hari", "Berapa hari? (contoh 30)", v_int(1, 3650)),
           ("ip", "Had IP? (0 = tiada had)", v_int(0, 9999)), ("gb", "Kuota GB? (0 = tiada had)", v_int(0, 9999))],
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
    if flow == "vl":
        send(chat, "Sekejap, cipta akaun...")
        r, err = vless_create(d["nama"], d["hari"], d["ip"], d["gb"], d.get("uuid"))
        if not r:
            send(chat, E(err), MAIN_KB)
            return
        send(chat, vless_msg(r["user"], r["uuid"], r["exp"]), telco_kb(r["user"]))
    elif flow == "ss":
        r, err = ssh_create(d["nama"], d["pw"], d["hari"], d["ip"], d["gb"])
        if not r:
            send(chat, E(err), MAIN_KB)
            return
        send(chat, ssh_msg(r["user"], r["pw"], r["exp"], r["ip"]), MAIN_KB)
    elif flow == "rn":
        kind, user = d["kind"], d["user"]
        if kind == "v":
            exp, err = vless_renew(user, d["hari"])
        else:
            exp, err = ssh_renew(user, d["hari"])
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
    if kind == "v":
        _, exp, uid = u
        send(chat, vless_msg(user, uid, exp), telco_kb(user))
    else:
        _, exp, pw = u
        il = rd("/etc/xray/sshx/%sIP" % user, "0")
        send(chat, ssh_msg(user, pw, exp, int(il) if il.isdigit() else 0), MAIN_KB)


def kinds_of(name):
    return [k for k in ("v", "s") if find(k, name)]


def ask_kind(chat, name, prefix, label):
    ks = kinds_of(name)
    if not ks:
        send(chat, "Akaun %s tak jumpa." % code(name))
        return None
    if len(ks) == 1:
        return ks[0]
    send(chat, "%s ada dalam VLESS dan SSH. %s yang mana?" % (code(name), label),
         [[btn("VLESS", "%s:v:%s" % (prefix, name)), btn("SSH", "%s:s:%s" % (prefix, name))]])
    return None


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
            "/vless nama hari [ip] [gb] [uuid] - cipta VLESS terus (uuid custom: letak 0 0 dulu)",
            "/ssh nama kata_laluan hari [ip] [gb] - cipta SSH terus",
            "/senarai - semua akaun", "/semak nama", "/renew nama hari", "/padam nama",
            "/status - servis VPS", "/batal - berhenti soalan"]))
    elif cmd == "/batal":
        STATE.pop(chat, None)
        send(chat, "Batal.", MAIN_KB)
    elif cmd == "/senarai":
        send(chat, list_msg(), MAIN_KB)
    elif cmd == "/status":
        send(chat, status_msg(), MAIN_KB)
    elif cmd == "/vless":
        if len(a) >= 2:
            d = {}
            vals = a + ["0", "0"][:max(0, 4 - len(a))]
            ok1, d["nama"] = v_name(chat, vals[0])
            ok2, d["hari"] = v_int(1, 3650)(chat, vals[1])
            ok3, d["ip"] = v_int(0, 9999)(chat, vals[2])
            ok4, d["gb"] = v_int(0, 9999)(chat, vals[3])
            ok5, d["uuid"] = v_uuid(chat, a[4] if len(a) >= 5 else "auto")
            bad = [x for ok, x in ((ok1, d["nama"]), (ok2, d["hari"]), (ok3, d["ip"]), (ok4, d["gb"]), (ok5, d["uuid"])) if not ok]
            if bad:
                send(chat, E(bad[0]))
                return
            finish(chat, {"flow": "vl", "d": d})
        else:
            start_flow(chat, "vl")
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
    elif cmd == "/semak" and a:
        k = ask_kind(chat, a[0], "c", "Semak")
        if k:
            show_account(chat, k, a[0])
    elif cmd == "/padam" and a:
        k = ask_kind(chat, a[0], "d", "Padam")
        if k:
            send(chat, "Padam %s (%s)?" % (code(a[0]), "VLESS" if k == "v" else "SSH"),
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
    if k == "x":
        STATE.pop(chat, None)
        send(chat, "Batal.", MAIN_KB)
    elif k == "m":
        what = p[1]
        if what == "vl":
            start_flow(chat, "vl")
        elif what == "ss":
            start_flow(chat, "ss")
        elif what == "ls":
            send(chat, list_msg(), MAIN_KB)
        elif what == "st":
            send(chat, status_msg(), MAIN_KB)
        elif what in ("ck", "dl", "rn"):
            send(chat, "Jenis akaun?", [[btn("VLESS", "%s:v" % what), btn("SSH", "%s:s" % what)], [btn("Batal", "x")]])
    elif k in ("ck", "dl", "rn") and len(p) == 2:
        pre = {"ck": "c", "dl": "d", "rn": "r"}[k]
        kb = user_buttons(p[1], pre)
        send(chat, "Pilih akaun:" if len(kb) > 1 else "Tiada akaun.", kb if len(kb) > 1 else MAIN_KB)
    elif k == "c" and len(p) == 3:
        show_account(chat, p[1], p[2])
    elif k == "d" and len(p) == 3:
        send(chat, "Padam %s (%s)?" % (code(p[2]), "VLESS" if p[1] == "v" else "SSH"),
             [[btn("Ya, padam", "D:%s:%s" % (p[1], p[2])), btn("Batal", "x")]])
    elif k == "D" and len(p) == 3:
        ok, err = vless_delete(p[2]) if p[1] == "v" else ssh_delete(p[2])
        send(chat, ("Dah dipadam: %s" % code(p[2])) if ok else E(err), MAIN_KB)
    elif k == "r" and len(p) == 3:
        start_flow(chat, "rn", {"kind": p[1], "user": p[2]})
    elif k == "t":
        q = data.split(":")
        user, n = q[1], int(q[2]) if len(q) > 2 and q[2].isdigit() else 0
        u = find("v", user)
        if not u:
            send(chat, "Akaun tak jumpa.", MAIN_KB)
            return
        T = telcos()
        sel = T if n == 0 else T[n - 1:n]
        if not sel:
            send(chat, "Telco tak ada.", MAIN_KB)
            return
        out = []
        for t in sel:
            out += ["<b>%s</b>" % E(t[0]), code(telco_link(u[2], user, t)), ""]
        send(chat, "\n".join(out).rstrip(), telco_kb(user))


def handle(u):
    if "callback_query" in u:
        cq = u["callback_query"]
        msg = cq.get("message") or {}
        chat = (msg.get("chat") or {}).get("id")
        try:
            tg("answerCallbackQuery", callback_query_id=cq["id"])
        except Exception:
            pass
        if chat is None or cq["from"]["id"] not in ADMINS or (msg.get("chat") or {}).get("type") != "private":
            return
        on_callback(chat, cq.get("data", ""))
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
        if text.startswith("/start"):
            send(chat, "Tiada akses.\nID Telegram kau: %s" % code(uid))
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
