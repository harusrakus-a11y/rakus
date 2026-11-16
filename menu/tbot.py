#!/usr/bin/env python3
# tbot - bot Telegram untuk urus akaun VLESS, VMess, Trojan dan SSH di VPS autoscript (admin; trial awam untuk orang lain bila admin hidupkan)
# Konfigurasi: /etc/tbot/config  (TOKEN=... dan ADMINS=id1,id2). Tiada rahsia dalam fail ni.
import base64
import copy
import datetime
import functools
import hashlib
import html
import json
import os
import re
import secrets
import shlex
import shutil
import string
import subprocess
import sys
import time
import traceback
import unicodedata
import urllib.error
import urllib.parse
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
TELCO_RE = re.compile(r"^[A-Za-z0-9_-]+\|[^|]+\|[^|]+\|[^|]+\|[0-9]+(\|(ws|httpupgrade))?$")
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
    if kb is MAIN_KB:
        kb = main_kb(chat)
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
    [btn("ℹ️ Status", "m:st"), btn("🎁 Trial", "m:tl"), btn("🛒 Jual", "m:jl")],
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


# ---------------------------------------------------------------- banyak VPS
# Bot ni satu sahaja dan hidup kat server Utama ("local"). Server lain dihubungi guna SSH: bot hantar arahan kepada
# salinan tbot.py ("ejen") kat server tu, dan ejen jalankan fungsi yang sama kat sana. Token Telegram tak pernah keluar
# dari server Utama. Daftar server: /etc/tbot/vps.json. Kunci SSH bot: /etc/tbot/id_ed25519.
VPS_F = "/etc/tbot/vps.json"
VPS_KEY = "/etc/tbot/id_ed25519"
VPS_KH = "/etc/tbot/known_hosts"
AGENT = "/usr/local/lib/tbot-agent.py"
RPC_VER = 1
VID_RE = re.compile(r"^[a-z][a-z0-9]{0,5}$")
VNAMA_RE = re.compile(r"^[A-Za-z0-9_-]{1,20}$")
HOST_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9.-]{1,100}$")
CUR = "local"
RPC = {}
DOWN = {}
_LOOP = os.environ.get("TBOT_LOOPBACK") == "1"   # cuma untuk ujian: server Utama pun dihubungi lalu ejen (uji semua laluan JSON)


class VPSError(Exception):
    pass


def _baca_diri():
    try:
        with open(os.path.abspath(__file__), "rb") as f:
            return f.read()
    except OSError:
        return b""


_SRC = _baca_diri()   # kod yang sedang jalan (dihantar kepada ejen supaya sentiasa sama dengan bot)
MYSHA = hashlib.sha256(_SRC).hexdigest()[:16]


def vps_load():
    d = {"seq": 1, "v": [], "local": {"nama": "Utama", "buka": True}, "pilih": {}}
    try:
        with open(P(VPS_F)) as f:
            j = json.load(f)
        if isinstance(j, dict):
            d.update(j)
    except (OSError, ValueError):
        pass
    if not isinstance(d.get("v"), list):
        d["v"] = []
    d["v"] = [v for v in d["v"] if isinstance(v, dict) and VID_RE.match(str(v.get("id", ""))) and v.get("host")]
    if not isinstance(d.get("local"), dict):
        d["local"] = {"nama": "Utama", "buka": True}
    if not isinstance(d.get("pilih"), dict):
        d["pilih"] = {}
    return d


def vps_save(d):
    p = P(VPS_F)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = p + ".tmp"
    with open(tmp, "w") as f:
        json.dump(d, f)
    os.chmod(tmp, 0o600)
    os.replace(tmp, p)


def vps_semua(d=None):
    d = d or vps_load()
    lc = d["local"]
    out = [{"id": "local", "nama": lc.get("nama") or "Utama", "buka": lc.get("buka", True), "host": "", "port": 22}]
    for v in d["v"]:
        out.append({"id": v["id"], "nama": v.get("nama") or v["id"], "buka": v.get("buka", True),
                    "host": v.get("host", ""), "port": int(v.get("port", 22) or 22)})
    return out


def vps_get(vid, d=None):
    for v in vps_semua(d):
        if v["id"] == vid:
            return v
    return None


def vps_nama(vid):
    v = vps_get(vid)
    return v["nama"] if v else vid


def vps_multi():
    return bool(vps_load()["v"])


def vps_dibuka(vid):
    v = vps_get(vid)
    return bool(v and v["buka"])


def vps_buka_list():
    return [v for v in vps_semua() if v["buka"]]


def vps_pilih_get(chat, d=None):
    d = d or vps_load()
    vid = d["pilih"].get(str(chat), "local")
    return vid if vps_get(vid, d) else "local"


def vsplit(tok):
    """'ali@v2' -> ('ali', 'v2'). Tanpa @ = server Utama."""
    if "@" in tok:
        u, v = tok.rsplit("@", 1)
        if u and VID_RE.match(v):
            return u, v
    return tok, "local"


def vsuf(vid=None):
    vid = vid or CUR
    return "" if vid == "local" else "@" + vid


def vtok(vid):
    return "" if vid == "local" else ":" + vid


def akey(kind, user, vid):
    return "%s:%s%s" % (kind, user, vsuf(vid))


def vtag(vid):
    return (" • Server: %s" % E(vps_nama(vid))) if vps_multi() else ""


def vlabel(vid):
    return (" · %s" % vps_nama(vid)) if vps_multi() else ""


def vhead():
    return ("🖥 <b>%s</b>\n" % E(vps_nama(CUR))) if vps_multi() else ""


class on:
    """with on(vid): semua kerja akaun dalam blok ni dibuat kat server vid."""

    def __init__(self, vid):
        self.vid = vid or "local"

    def __enter__(self):
        global CUR
        self.old = CUR
        CUR = self.vid

    def __exit__(self, *e):
        global CUR
        CUR = self.old


def remote(fn):
    """Fungsi yang sentuh fail atau arahan server: kalau sasaran bukan Utama, dijalankan kat ejen server tu."""
    RPC[fn.__name__] = fn

    @functools.wraps(fn)
    def w(*a, **k):
        if CUR == "local" and not _LOOP:
            return fn(*a, **k)
        return rpc_call(CUR, fn.__name__, list(a), k)
    return w


def ssh_run(v, cmd, inp=b"", timeout=60):
    a = [os.environ.get("TBOT_SSH", "ssh"), "-T", "-i", P(VPS_KEY), "-p", str(v.get("port", 22)),
         "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes", "-o", "StrictHostKeyChecking=accept-new",
         "-o", "UserKnownHostsFile=" + P(VPS_KH), "-o", "ConnectTimeout=8",
         "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=3", "-o", "LogLevel=ERROR",
         "root@" + v["host"], cmd]
    try:
        r = subprocess.run(a, input=inp, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise VPSError("server lambat balas (lebih %d saat)" % timeout)
    except OSError:
        raise VPSError("arahan ssh tak ada. Jalankan: apt install -y openssh-client")
    return r.returncode, r.stdout.decode("utf-8", "replace"), r.stderr.decode("utf-8", "replace")


def _ralat_ssh(err):
    e = " ".join((err or "").split())
    if "host key verification failed" in e.lower() or "host identification has changed" in e.lower():
        return "kunci host VPS tu berubah (VPS dipasang semula?). Buang dengan /vpsbuang ID ya, kemudian tambah semula"
    return e[:140] or "tiada jawapan"


def agent_push(v):
    """Pasang atau kemas kini salinan tbot.py (ejen) kat server tu."""
    src = _SRC
    if not src:
        raise VPSError("tak dapat baca tbot.py sendiri")
    cmd = ("mkdir -p %s && cat > %s.new && python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' %s.new && mv -f %s.new %s"
           % (os.path.dirname(AGENT), AGENT, AGENT, AGENT, AGENT))
    rc, out, err = ssh_run(v, cmd, src, 60)
    if rc == 255:
        DOWN[v.get("id")] = time.time()
        raise VPSError("tak dapat sambung: " + _ralat_ssh(err))
    if rc != 0:
        raise VPSError("gagal pasang ejen kat server (kod %d): %s" % (rc, _ralat_ssh(err) if err.strip() else "python3 ada?"))


def rpc_call_v(v, fn, a, k, retry=True):
    req = json.dumps({"fn": fn, "a": a, "k": k, "sha": MYSHA, "ver": RPC_VER}).encode()
    rc, out, err = ssh_run(v, "python3 %s --rpc" % AGENT, req, 45)
    if rc == 255:
        DOWN[v.get("id")] = time.time()
        raise VPSError("tak dapat sambung: " + _ralat_ssh(err))
    m = re.search(r"@@TBOT@@(.*?)@@END@@", out, re.S)
    if not m:
        if retry and rc == 2 and "can't open file" in err:
            agent_push(v)
            return rpc_call_v(v, fn, a, k, False)
        if rc == 127:
            raise VPSError("python3 tak ada kat server tu (apt install -y python3)")
        raise VPSError("jawapan server tak betul (kod %d): %s" % (rc, _ralat_ssh(err)))
    try:
        j = json.loads(m.group(1))
    except ValueError:
        raise VPSError("jawapan server rosak")
    if j.get("stale"):
        if not retry:
            raise VPSError("versi ejen tak sama dengan bot")
        agent_push(v)
        return rpc_call_v(v, fn, a, k, False)
    DOWN.pop(v.get("id"), None)
    if not j.get("ok"):
        raise VPSError("ralat kat server: %s" % j.get("err", "?"))
    return j.get("r")


def rpc_call(vid, fn, a, k):
    v = vps_get(vid)
    if _LOOP and vid == "local" and v:
        v = dict(v, host="10.0.0.9")
    if not v or (vid == "local" and not _LOOP):
        raise VPSError("server %s tak wujud (mungkin dah dibuang)" % vid)
    if time.time() - DOWN.get(vid, 0) < 30:
        raise VPSError("server %s tak dapat dihubungi sekarang" % v["nama"])
    return rpc_call_v(v, fn, a, k)


def rpc_main():
    """Mod ejen: python3 tbot.py --rpc. Baca satu arahan JSON dari stdin, jalankan, cetak jawapan JSON."""
    real = sys.stdout
    sys.stdout = sys.stderr
    try:
        req = json.loads(sys.stdin.read())
        if req.get("sha") != MYSHA:
            out = {"stale": True}
        else:
            fn = RPC.get(req.get("fn"))
            if fn is None:
                raise ValueError("fungsi tak dikenali: %s" % req.get("fn"))
            out = {"ok": True, "r": fn(*req.get("a", []), **req.get("k", {}))}
        txt = json.dumps(out)
    except Exception as e:
        txt = json.dumps({"ok": False, "err": "%s: %s" % (type(e).__name__, e)})
    sys.stdout = real
    sys.stdout.write("\n@@TBOT@@" + txt + "@@END@@\n")
    sys.stdout.flush()


@remote
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


@remote
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


@remote
def ssh_users():
    out = []
    for line in lines_of("/etc/xray/ssh"):
        if line.startswith("### "):
            p = line.split()
            if len(p) >= 4:
                out.append((p[1], p[2], p[3]))
    return out


@remote
def users_of(kind):
    return ssh_users() if kind == "s" else xusers(kind)


@remote
def name_taken(name):
    allu = ssh_users()
    for k in XKINDS:
        allu += xusers(k)
    if any(u[0] == name for u in allu):
        return True
    if ('"email": "%s"' % name) in "\n".join(lines_of("/etc/xray/config.json")):
        return True
    return run(["id", name]).returncode == 0


@remote
def nota_get(user, kind="v"):
    return rd("%s/nota/%s" % (KIND[kind]["dir"], user), "")


@remote
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


@remote
def find(kind, name):
    for u in users_of(kind):
        if u[0] == name:
            return u
    return None


@remote
def find_many(prs):
    return [find(k, u) for k, u in prs]


@remote
def uuid_dipakai(s):
    return ('"%s"' % s) in "\n".join(lines_of("/etc/xray/config.json"))


@remote
def ssh_iplimit(user):
    il = rd("/etc/xray/sshx/%sIP" % user, "0")
    return int(il) if il.isdigit() else 0


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
    stamp = TELCO + ".chk"
    if not _telco_time:
        try:
            _telco_time = os.path.getmtime(stamp)
        except OSError:
            pass
    if not force and time.time() - _telco_time < 300 and os.path.exists(TELCO):
        return
    _telco_time = time.time()
    try:
        os.makedirs(os.path.dirname(TELCO), exist_ok=True)
        open(stamp, "w").close()
    except OSError:
        pass
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


@remote
def telcos():
    telco_refresh()
    out = []
    for l in lines_of("/etc/xray/telco.conf"):
        l = l.strip()
        if TELCO_RE.match(l):
            f = l.split("|")
            out.append((f[0], f[1], f[2], f[3], f[4], f[5] if len(f) > 5 else "ws"))
    return out


def telcos_utama():
    """Senarai telco server Utama. Status telco (berfungsi/lemah/tak) sama untuk semua server, ikut nama."""
    with on("local"):
        return telcos()


def telco_ok(t, kind):
    """Telco jenis httpupgrade ada pendengar VLESS sahaja kat VPS, jadi VMess dan Trojan tak dapat telco tu."""
    return kind == "v" or len(t) < 6 or t[5] == "ws"


def telco_nama(t):
    return t[0] + (" (VLESS sahaja)" if len(t) > 5 and t[5] != "ws" else "")


def telco_path(kind, p):
    if p == "/vless":
        return {"v": "/vless", "m": "/vmess", "t": "/trojan-ws"}[kind]
    return p


@remote
def telco_link(uid, user, t, kind="v"):
    n, a, h, p, port = t[:5]
    ty = t[5] if len(t) > 5 else "ws"
    d = domain()
    a = a.replace("{domain}", d)
    h = h.replace("{domain}", d)
    p = telco_path(kind, p)
    if kind == "m":
        js = json.dumps({"v": "2", "ps": "%s-%s" % (user, n), "add": a, "port": port, "id": uid, "aid": "0", "net": ty,
                         "path": p, "type": "none", "host": h, "tls": "none"}, separators=(",", ":"))
        return "vmess://" + base64.b64encode(js.encode()).decode()
    if kind == "t":
        return "trojan://%s@%s:%s?path=%s&security=none&host=%s&type=%s#%s-%s" % (
            uid, a, port, urllib.parse.quote(p, safe=""), h, ty, user, n)
    if ty != "ws":
        return "vless://%s@%s:%s?path=%s&security=none&encryption=none&host=%s&type=%s#%s-%s" % (
            uid, a, port, urllib.parse.quote(p, safe=""), h, ty, user, n)
    return "vless://%s@%s:%s?encryption=none&type=ws&host=%s&headerType=none&path=%s#%s-%s" % (
        uid, a, port, h, urllib.parse.quote(p, safe=""), user, n)


TACT = {"v": "t", "m": "tm", "t": "tt"}


def telco_kb(user, kind="v"):
    act = TACT[kind]
    tok = user + vsuf()
    b = [btn(t[0], "%s:%s:%d" % (act, tok, i + 1)) for i, t in enumerate(telcos()) if telco_ok(t, kind)]
    kb = rows(b, 3)
    kb.append([btn("Semua telco", "%s:%s:0" % (act, tok)), btn("📝 Nota", "n:%s:%s" % (kind, tok))])
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


@remote
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


@remote
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


@remote
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


@remote
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


@remote
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


@remote
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


@remote
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
@remote
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


@remote
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


@remote
def ssh_msg(user, pw, exp, ip):
    return "\n".join(["<b>SSH siap</b>  ✦ kancil ecem", "User     : %s" % code(user), "Password : %s" % code(pw),
                      "Host     : %s" % code(domain()), "Luput    : %s (%d hari)" % (E(exp), days_left(exp)),
                      "Had IP   : %d" % ip, "", "<pre>%s</pre>" % E(SSH_PORTS), "", "Developer by kancil ecem"])


@remote
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


@remote
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
    b = [btn(u[0], "%s:%s:%s" % (prefix, kind, u[0] + vsuf())) for u in src[:90]]
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
    if uuid_dipakai(s):
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
    STATE[chat] = {"flow": name, "i": 0, "d": data or {}, "vps": CUR}
    send(chat, vhead() + FLOWS[name][0][1] + "\n(/batal untuk berhenti)")


def finish(chat, st):
    with on(st.get("vps") or CUR):
        _finish(chat, st)


def _finish(chat, st):
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
        send(chat, vhead() + acct_msg(kind, r["user"], r["uuid"], r["exp"]), telco_kb(r["user"], kind))
    elif flow == "ss":
        r, err = ssh_create(d["nama"], d["pw"], d["hari"], d["ip"], d["gb"])
        if not r:
            send(chat, E(err), MAIN_KB)
            return
        send(chat, vhead() + ssh_msg(r["user"], r["pw"], r["exp"], r["ip"]), MAIN_KB)
        hc_lepas(chat, r["user"], CUR)
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
        send(chat, vhead() + "Renew siap: %s luput %s (%d hari)" % (code(user), E(exp), days_left(exp)), MAIN_KB)


def flow_input(chat, text):
    st = STATE[chat]
    steps = FLOWS[st["flow"]]
    key, _, validator = steps[st["i"]]
    with on(st.get("vps") or CUR):
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
        send(chat, vhead() + acct_msg(kind, user, uid, exp), telco_kb(user, kind))
    else:
        _, exp, pw = u
        send(chat, vhead() + ssh_msg(user, pw, exp, ssh_iplimit(user)), MAIN_KB)


@remote
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
         rows([btn(kname(k), "%s:%s:%s" % (prefix, k, name + vsuf())) for k in ks], 2))
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
            "/status - servis VPS", "/vps - senarai server (VPS) yang disambung ke bot, tukar, tambah, buang",
            "/trial - trial awam untuk orang lain (hidup/tutup, tetapan)",
            "/jual - jualan akaun (bayar QR, sahkan resit, harga, statistik)",
            "/telco - tanda telco mana berfungsi (pelanggan nampak dan pilih sebelum bayar)",
            "/channel @nama - pelanggan kena join channel dulu sebelum Trial atau Beli (/channel 0 untuk matikan)",
            "/hc - fail HTTP Custom berkunci untuk akaun SSH (tambah, nama telco, uji, buang)",
            "/trialreset ID [padam] - bagi orang tu cuba trial semula", "/batal - berhenti soalan"]))
    elif cmd == "/batal":
        STATE.pop(chat, None)
        send(chat, "Batal.", MAIN_KB)
    elif cmd in ("/trial", "/trialon", "/trialoff", "/trialset", "/trialban", "/trialbuka", "/trialuji", "/trialreset"):
        trial_cmd(chat, cmd, a)
    elif cmd in ("/jual", "/jualon", "/jualoff", "/jualset", "/jualnota", "/order", "/sahkan", "/tolak"):
        jual_cmd(chat, cmd, a)
    elif cmd in ("/telco", "/telcook", "/telcolemah", "/telcotak"):
        telco_cmd(chat, cmd, a)
    elif cmd == "/channel":
        chan_cmd(chat, a)
    elif cmd in ("/hc", "/hcpadam", "/hcfail"):
        hc_cmd(chat, cmd, a)
    elif cmd == "/hcnama":
        hc_nama(chat, text)
    elif cmd == "/hcset":
        hc_set_teks(chat, text)
    elif cmd == "/hcnota":
        hc_nota(chat, text)
    elif cmd == "/hcgambar":
        hc_gambar(chat, text)
    elif cmd in ("/vps", "/vpstambah", "/vpsbuang", "/vpspilih", "/vpsnama", "/vpstutup", "/vpsbuka"):
        vps_cmd(chat, cmd, a)
    elif cmd == "/senarai":
        send(chat, vhead() + list_msg(), MAIN_KB)
    elif cmd == "/status":
        send(chat, vhead() + status_msg(), MAIN_KB)
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
            send(chat, vhead() + "Padam %s (%s)?" % (code(a[0]), kname(k)),
                 [[btn("Ya, padam", "D:%s:%s" % (k, a[0] + vsuf())), btn("Batal", "x")]])
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


def telco_papar(chat, kind, user, n):
    u = find(kind, user)
    if not u:
        send(chat, "Akaun tak jumpa.", MAIN_KB)
        return
    T = telcos()
    sel = [x for x in (T if n == 0 else T[n - 1:n]) if telco_ok(x, kind)]
    if not sel:
        send(chat, "Telco tak ada untuk jenis ni.", MAIN_KB)
        return
    out = [vhead() + "<b>Akaun %s</b>" % KIND[kind]["nama"]] + acct_info(kind, user, u[2], u[1]) + ["", "<b>Link telco</b>", ""]
    for t in sel:
        out += ["<b>%s</b>" % E(t[0]), code(telco_link(u[2], user, t, kind)), ""]
    send(chat, "\n".join(out).rstrip(), telco_kb(user, kind))


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
            send(chat, vhead() + list_msg(), MAIN_KB)
        elif what == "st":
            send(chat, vhead() + status_msg(), MAIN_KB)
        elif what == "vp":
            vps_menu(chat)
        elif what == "tl":
            send(chat, trial_admin_msg(), MAIN_KB)
        elif what == "jl":
            send(chat, jual_admin_msg(), MAIN_KB)
        elif what in ("ck", "dl", "rn"):
            send(chat, vhead() + "Jenis akaun?", [[btn("VLESS", "%s:v" % what), btn("VMess", "%s:m" % what)],
                                                  [btn("Trojan", "%s:t" % what), btn("SSH", "%s:s" % what)], [btn("Batal", "x")]])
    elif k == "vp" and len(p) == 2:
        if p[1] == "+":
            vps_arahan_tambah(chat)
        else:
            vps_pilih(chat, p[1])
    elif k in ("ck", "dl", "rn") and len(p) == 2 and p[1] in KS:
        pre = {"ck": "c", "dl": "d", "rn": "r"}[k]
        kb = user_buttons(p[1], pre)
        send(chat, vhead() + "Pilih akaun:" if len(kb) > 1 else vhead() + "Tiada akaun.", kb if len(kb) > 1 else MAIN_KB)
    elif k == "c" and len(p) == 3 and p[1] in KS:
        u, vid = vsplit(p[2])
        with on(vid):
            show_account(chat, p[1], u)
    elif k == "d" and len(p) == 3 and p[1] in KS:
        u, vid = vsplit(p[2])
        with on(vid):
            send(chat, vhead() + "Padam %s (%s)?" % (code(u), kname(p[1])),
                 [[btn("Ya, padam", "D:%s:%s" % (p[1], p[2])), btn("Batal", "x")]])
    elif k == "D" and len(p) == 3 and p[1] in KS:
        u, vid = vsplit(p[2])
        with on(vid):
            ok, err = ssh_delete(u) if p[1] == "s" else xray_delete(p[1], u)
            send(chat, vhead() + (("Dah dipadam: %s" % code(u)) if ok else E(err)), MAIN_KB)
    elif k == "r" and len(p) == 3 and p[1] in KS:
        u, vid = vsplit(p[2])
        with on(vid):
            start_flow(chat, "rn", {"kind": p[1], "user": u})
    elif k == "n" and len(p) >= 2:
        if len(p) == 3 and p[1] in XKINDS:
            kind, tok = p[1], p[2]
        else:
            kind, tok = "v", ":".join(p[1:])
        user, vid = vsplit(tok)
        with on(vid):
            if not find(kind, user):
                send(chat, "Akaun tak jumpa.", MAIN_KB)
                return
            start_flow(chat, "nt", {"kind": kind, "user": user})
    elif k in ("ok", "no") and len(p) == 2 and re.match(r"^[A-Za-z0-9]{5}$", p[1]):
        (jual_sahkan if k == "ok" else jual_tolak)(p[1].upper(), chat)
    elif k in ("t", "tm", "tt"):
        kind = {"t": "v", "tm": "m", "tt": "t"}[k]
        q = data.split(":")
        user, vid = vsplit(q[1])
        n = int(q[2]) if len(q) > 2 and q[2].isdigit() else 0
        with on(vid):
            telco_papar(chat, kind, user, n)


# ---------------------------------------------------------------- TRIAL AWAM
# Orang lain (bukan admin) boleh minta akaun trial: pilih jenis, pilih telco, dapat akaun. Hidup bila admin taip /trialon.
# Akaun dipadam sendiri bila tamat. Fail tetapan dan rekod: /etc/tbot/trial.json (tiada rahsia akaun disimpan di situ).
TRIAL_F = "/etc/tbot/trial.json"
TRIAL_KIND = {"v": "VLESS", "m": "VMess", "t": "Trojan", "s": "SSH"}
TRIAL_DEF = {"aktif": False, "minit": 60, "jam": 24, "had_aktif": 20, "had_sehari": 30, "kuota": 2, "iplimit": 1,
             "jenis": ["v", "m", "t", "s"], "hubung": "", "banned": [], "last": {}, "rec": [], "hari": "", "kira": 0}
TRIAL_RANGE = {"minit": (5, 10080), "jam": (1, 720), "had_aktif": (1, 200), "had_sehari": (1, 1000),
               "kuota": (0, 9999), "iplimit": (1, 3)}
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
    if m >= 1440 and m % 1440 == 0:
        return "%d hari" % (m // 1440)
    if m >= 120:
        return "%d jam %d minit" % (m // 60, m % 60) if m % 60 else "%d jam" % (m // 60)
    return "%d minit" % max(m, 1)


def trial_gb(q):
    return "tiada had" if q in (0, 9999) else "%d GB" % q


def trial_tunggu(d, uid):
    return max(0, d["last"].get(str(uid), 0) + d["jam"] * 3600 - time.time())


def trial_hubung(d):
    h = d.get("hubung", "")
    return ("\nNak akaun penuh, hubungi %s" % E(h if h.startswith("@") else "@" + h)) if h else ""


def trial_nama(kind):
    if kind == "s":
        return "trial" + "".join(secrets.choice(string.ascii_lowercase + string.digits) for _ in range(4))
    return "Trial-" + "".join(secrets.choice("XYZ0123456789") for _ in range(4))


def trial_start(chat, frm, vid=None):
    uid = frm["id"]
    adm = uid in ADMINS
    d = trial_load()
    if not d["aktif"] or (uid in d["banned"] and not adm):
        return
    now = time.time()
    if not adm and vid is None:
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
    if not channel_ok(chat, frm, "trial"):
        return
    if vid is None:
        vid = vps_pilih_awam(chat, "trial")
        if vid is None:
            return
    elif not vps_dibuka(vid):
        send(chat, "Server tu tak dibuka sekarang. Taip /start untuk pilih semula.")
        return
    kb = rows([btn("🎁 " + TRIAL_KIND[k], "pt:%s%s" % (k, vtok(vid))) for k in d["jenis"]], 2)
    nota = hc_nota_jenis(jual_load(), vid, d["jenis"])
    send(chat, "\n".join(["🎁 <b>Trial percuma</b>  ✦ kancil ecem",
                          "Tempoh %s • kuota %s • %d peranti" % (trial_tempoh(d["minit"] * 60), trial_gb(d["kuota"]), d["iplimit"]),
                          "Satu trial setiap %d jam." % d["jam"]] +
                         (["Server: %s" % E(vps_nama(vid))] if vps_multi() else []) + ([nota] if nota else []) +
                         ["", "Pilih jenis akaun:"]), kb)


def trial_cb(chat, frm, data):
    p = data.split(":")
    d = trial_load()
    uid = frm["id"]
    if not d["aktif"] or (uid in d["banned"] and uid not in ADMINS):
        return
    if len(p) < 2 or p[1] not in d["jenis"]:
        send(chat, "Jenis ni tak dibuka. Taip /start.")
        return
    if not channel_ok(chat, frm, "trial"):
        return
    kind = p[1]
    vid = p[2] if p[0] == "pt" and len(p) > 2 else (p[3] if p[0] == "pc" and len(p) > 3 else "local")
    if not vps_dibuka(vid):
        send(chat, "Server tu tak dibuka sekarang. Taip /start untuk pilih semula.")
        return
    if p[0] == "pt":
        if kind == "s":
            trial_buat(chat, frm, kind, 0, vid)
            return
        with on(vid):
            T = telcos()
        J = jual_load()
        b = [btn(("" if telco_status(J, x[0]) == "ok" else TELCO_ST[telco_status(J, x[0])] + " ") + x[0], "pc:%s:%d%s" % (kind, i + 1, vtok(vid)))
             for i, x in enumerate(T) if telco_status(J, x[0]) != "tak" and telco_ok(x, kind)]
        kb = rows(b, 3) + [[btn("Tanpa telco (link biasa)", "pc:%s:0%s" % (kind, vtok(vid)))]]
        send(chat, "Pilih telco kau:", kb)
    elif p[0] == "pc" and len(p) in (3, 4) and p[2].isdigit():
        trial_buat(chat, frm, kind, int(p[2]), vid)


@remote
def trial_msg(kind, r, tl, minit, d):
    now = time.time()
    t = ["🎁 <b>Trial %s</b>  ✦ kancil ecem" % TRIAL_KIND[kind]]
    if kind == "s":
        t += ["User     : %s" % code(r["user"]), "Password : %s" % code(r["pw"]), "Host     : %s" % code(domain()),
              "Had     : %d peranti, kuota %s" % (r["ip"], trial_gb(r["quota"])),
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


def trial_buat(chat, frm, kind, n, vid="local"):
    with on(vid):
        _trial_buat(chat, frm, kind, n, vid)


def _trial_buat(chat, frm, kind, n, vid):
    d = trial_load()
    uid = frm["id"]
    adm = uid in ADMINS
    if not d["aktif"] or kind not in d["jenis"]:
        send(chat, "Trial tak dibuka sekarang.")
        return
    if not vps_dibuka(vid):
        send(chat, "Server tu tak dibuka sekarang. Taip /start untuk pilih semula.")
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
        if not telco_ok(tl, kind):
            send(chat, "Telco tu tak ada untuk jenis ni. Taip /start.")
            return
        if telco_status(jual_load(), tl[0]) == "tak":
            send(chat, "Telco %s tak berfungsi sekarang. Pilih yang lain." % code(tl[0]))
            return
    user = None
    for _ in range(10):
        c = trial_nama(kind)
        if not name_taken(c):
            user = c
            break
    if not user:
        send(chat, "Maaf, tak dapat cipta akaun sekarang. Cuba lagi sebentar.")
        return
    # tarikh luput dalam akaun mesti SELEPAS hari trial tamat: pembersihan harian (tengah malam) padam akaun yang luput <= hari ni
    dd = (datetime.date.fromtimestamp(time.time() + d["minit"] * 60) - today()).days + 1
    if kind == "s":
        pw = "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(8))
        r, err = ssh_create(user, pw, dd, d["iplimit"], d["kuota"])
    else:
        r, err = xray_create(kind, user, dd, d["iplimit"], d["kuota"], nota="Trial tg:%d" % uid)
    if not r:
        log("trial gagal:", err)
        send(chat, "Maaf, trial tak dapat dicipta sekarang. Cuba lagi sebentar.")
        return
    now = time.time()
    d["rec"].append({"user": user, "kind": kind, "uid": uid, "chat": chat, "tamat": now + d["minit"] * 60, "vps": vid})
    if not adm:
        d["last"][str(uid)] = now
    d["last"] = {k: v for k, v in d["last"].items() if v + d["jam"] * 3600 > now}
    d["kira"] += 1
    trial_save(d)
    send(chat, trial_msg(kind, r, tl, d["minit"], {"hubung": d.get("hubung", "")}))
    if kind == "s":
        hc_lepas(chat, user, vid)
    nm = E(" ".join(x for x in (frm.get("first_name", ""), ("@" + frm["username"]) if frm.get("username") else "") if x) or "-")
    note = "🎁 Trial %s%s  •  %s (<code>%d</code>)\n%s  •  aktif sekarang %d  •  hari ni %d" % (
        TRIAL_KIND[kind], ((" " + E(tl[0])) if tl else "") + vtag(vid), nm, uid, trial_tempoh(d["minit"] * 60), len(d["rec"]), d["kira"])
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
        vid = r.get("vps", "local")
        try:
            with on(vid):
                if r["kind"] == "s":
                    ok, err = ssh_delete(r["user"])
                else:
                    ok, err = xray_delete(r["kind"], r["user"])
                masih = (not ok) and find(r["kind"], r["user"]) is not None
        except VPSError as e:
            if vps_get(vid) is not None and now - r["tamat"] < 86400:
                r["next"] = now + 300
                log("trial: server %s tak dapat dihubungi, cuba lagi nanti: %s" % (vid, e))
                continue
            log("trial: rekod %s ditinggalkan (server %s: %s)" % (r["user"], vid, e))
            ok, err, masih = True, "", False
        if masih:
            r["cuba"] = r.get("cuba", 0) + 1
            r["next"] = now + 120
            log("trial gagal dipadam:", r["user"], err)
            if r["cuba"] < 5:
                continue
            for a in ADMINS:
                send(a, "⚠️ Trial %s tak dapat dipadam sendiri selepas 5 cubaan. Padam manual." % code(r["user"]))
        d["rec"] = [x for x in d["rec"] if x is not r and not (x["user"] == r["user"] and x["kind"] == r["kind"] and x.get("vps", "local") == vid)]
        send(r["chat"], "⏰ Trial %s dah tamat dan dipadam. Terima kasih dah cuba!" % code(r["user"]) + trial_hubung(d))
    # simpan dengan keadaan terkini (rekod yang masih tinggal + penanda cuba semula)
    d2 = trial_load()
    keep = {(x["user"], x["kind"], x.get("vps", "local")): x for x in d["rec"]}
    d2["rec"] = [keep.get((x["user"], x["kind"], x.get("vps", "local")), x) for x in d2["rec"] if (x["user"], x["kind"], x.get("vps", "local")) in keep]
    trial_save(d2)


def trial_admin_msg():
    d = trial_load()
    now = time.time()
    L = ["🎁 <b>Trial awam</b>  ✦ kancil ecem", "Status  : %s" % ("HIDUP" if d["aktif"] else "TUTUP"),
         "Tempoh  : %s  •  kuota %s  •  %d IP" % (trial_tempoh(d["minit"] * 60), trial_gb(d["kuota"]), d["iplimit"]),
         "Ulang   : 1 setiap %d jam seorang" % d["jam"],
         "Had     : aktif %d, sehari %d (hari ni %d)" % (d["had_aktif"], d["had_sehari"], d["kira"] if d["hari"] == today().isoformat() else 0),
         "Jenis   : %s" % (", ".join(TRIAL_KIND[k] for k in d["jenis"]) or "tiada"),
         "Hubungi : %s" % (E(d["hubung"]) if d["hubung"] else "-"),
         "Disekat : %d orang" % len(d["banned"]), "", "Aktif sekarang: %d" % len(d["rec"])]
    for r in d["rec"]:
        L.append(" %s  %s  sisa %s  (tg:%d)%s" % (TRIAL_KIND[r["kind"]], code(r["user"]), trial_tempoh(max(0, r["tamat"] - now)), r["uid"],
                                                    vtag(r.get("vps", "local"))))
    L += ["", "/trialon  /trialoff", "/trialset minit=60 (atau hari=1) jam=24 aktif=20 sehari=30 kuota=2 ip=1 jenis=v,m,t,s hubung=@nama",
          "/trialban ID  /trialbuka ID  /trialuji (cuba sendiri)", "/trialreset ID  (kosongkan jeda, dia boleh minta trial lagi; tambah padam untuk tamatkan trial yang masih jalan)"]
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
            send(chat, "Guna: /trialset minit=60 (atau hari=1) jam=24 aktif=20 sehari=30 kuota=2 ip=1 jenis=v,m,t,s hubung=@nama (hubung=0 untuk padam, kuota=0 tiada had)")
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
                    send(chat, "%s mesti nombor %d hingga %d%s." % (code(k), lo, hi, " (0 = tiada had)" if f == "kuota" else ""))
                    return
                d[f] = int(v)
            elif k == "hari":
                if not v.isdigit() or not 1 <= int(v) <= 7:
                    send(chat, "%s mesti nombor 1 hingga 7." % code(k))
                    return
                d["minit"] = int(v) * 1440
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
    elif cmd == "/trialreset":
        if not a or not a[0].isdigit() or len(a) > 2 or (len(a) == 2 and a[1].lower() != "padam"):
            send(chat, "Guna: /trialreset ID_Telegram  (tambah padam untuk tamatkan trial yang masih jalan sekarang)")
            return
        i = int(a[0])
        ada = d["last"].pop(str(i), None) is not None
        act = [r for r in d["rec"] if r["uid"] == i]
        if act and len(a) == 2:
            act[0]["tamat"] = time.time() - 1
            act[0].pop("next", None)
        trial_save(d)
        if act and len(a) == 2:
            trial_sweep()
            act = [r for r in trial_load()["rec"] if r["uid"] == i]
        if act:
            send(chat, "Jeda %d dikosongkan. Tapi dia masih ada trial %s (tamat dalam %s). Taip /trialreset %d padam kalau nak tamatkan sekarang." % (
                i, code(act[0]["user"]), trial_tempoh(act[0]["tamat"] - time.time()), i), MAIN_KB)
            return
        send(chat, "%d: jeda trial dikosongkan%s. Dia boleh minta trial baru." % (i, "" if ada else " (tiada rekod jeda sebelum ni)"), MAIN_KB)
        if d["aktif"]:
            send(i, "🎁 Kau boleh minta trial lagi. Taip /start.")
    elif cmd == "/trialuji":
        if not d["aktif"]:
            send(chat, "Trial masih TUTUP. Taip /trialon dulu.")
        else:
            trial_start(chat, {"id": chat, "first_name": "admin"})


# ---------------------------------------------------------------- KEDAI (jual akaun, bayar QR bank, admin sahkan)
# Pelanggan: Beli / Renew / Akaun saya. Bayar guna QR bank admin, hantar resit kat bot. Resit sampai kat admin dengan butang
# Sahkan / Tolak. Akaun dicipta (ikut nama Telegram pelanggan) hanya bila admin tekan Sahkan. QR bank biasa tak boleh
# bagitahu bot duit dah masuk, jadi admin yang semak duit dalam bank dulu.
# Tetapan dan rekod: /etc/tbot/jual.json (tiada UUID atau password disimpan di situ).
JUAL_F = "/etc/tbot/jual.json"
JUAL_DEF = {"aktif": False, "sen": 1000, "hari": 30, "kuota": 0, "iplimit": 2, "jenis": ["v", "m", "t", "s"], "luput": 24,
            "qr": "", "nota": "", "seq": 0, "orders": [], "akaun": {}, "telco": {}, "telco_t": 0, "chan": {}, "hc": {}, "hc_nota": "", "hc_gambar": ""}
JUAL_RANGE = {"hari": (1, 365), "kuota": (0, 9999), "ip": (0, 20), "luput": (1, 168)}
RM_RE = re.compile(r"^\d{1,4}(\.\d{1,2})?$")
KEDAI_SENYAP = {}
KEDAI_CB = ("ky:", "ks:", "kb:", "kc:", "kj:", "kr:", "ka:", "kt:", "kx:", "kh:")
TELCO_ST = {"ok": "✅", "lemah": "⚠️", "tak": "❌"}


def jual_load():
    d = copy.deepcopy(JUAL_DEF)
    try:
        with open(P(JUAL_F)) as f:
            j = json.load(f)
        if isinstance(j, dict):
            d.update(j)
    except (OSError, ValueError):
        pass
    d["jenis"] = [k for k in d.get("jenis", []) if k in TRIAL_KIND]
    return d


def jual_save(d):
    if len(d["orders"]) > 1500:
        done = [o for o in d["orders"] if o["status"] in ("tolak", "batal")]
        drop = {o["id"] for o in done[:len(d["orders"]) - 1500]}
        d["orders"] = [o for o in d["orders"] if o["id"] not in drop]
    p = P(JUAL_F)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = p + ".tmp"
    with open(tmp, "w") as f:
        json.dump(d, f)
    os.chmod(tmp, 0o600)
    os.replace(tmp, p)


def rm(sen):
    return "RM%d" % (sen // 100) if sen % 100 == 0 else "RM%d.%02d" % (sen // 100, sen % 100)


def jual_hidup(d):
    return bool(d["aktif"] and d["qr"] and d["jenis"])


def telco_status(J, name):
    s = J.get("telco", {}).get(name, {}).get("s", "ok")
    return s if s in TELCO_ST else "ok"


def telco_senarai_pelanggan(J, boleh_trial):
    T = telcos_utama()
    NM = [(x[0], telco_nama(x)) for x in T] + [(n, hc_tajuk(J, n) + " (SSH)") for n in sorted(J.get("hc", {}))]
    if not NM:
        return "Belum ada telco disediakan. Pilih link biasa."
    ok = [l for n, l in NM if telco_status(J, n) == "ok"]
    lm = [l for n, l in NM if telco_status(J, n) == "lemah"]
    tk = [l for n, l in NM if telco_status(J, n) == "tak"]
    L = ["📶 <b>Telco yang berfungsi</b>", "✅ Berfungsi: %s" % (E(", ".join(ok)) if ok else "tiada")]
    if lm:
        L.append("⚠️ Kadang-kadang / lemah: %s" % E(", ".join(lm)))
    if tk:
        L.append("❌ Tak berfungsi sekarang: %s" % E(", ".join(tk)))
    if J.get("telco_t"):
        L.append("Dikemas kini: %s" % datetime.datetime.fromtimestamp(J["telco_t"]).strftime("%d-%m-%Y %H:%M"))
    if any(telco_status(J, n) != "tak" for n in J.get("hc", {})):
        L += ["", "ℹ️ Telco bertanda <b>(SSH)</b>: pilih jenis <b>SSH</b>. Telco lain: pilih <b>VLESS</b>."]
    L += ["", "Pilih telco kau masa beli." + (" Nak cuba dulu? Guna Trial percuma." if boleh_trial else "")]
    return "\n".join(L)


def telco_admin_msg(J):
    T = telcos_utama()
    L = ["📶 <b>Status telco</b>  (pelanggan nampak ini)"]
    NM = [(x[0], telco_nama(x)) for x in T] + [(n, n + " (SSH, fail HTTP Custom)") for n in sorted(J.get("hc", {}))]
    for i, (n, lab) in enumerate(NM):
        L.append("%d. %s %s" % (i + 1, TELCO_ST[telco_status(J, n)], E(lab)))
    if not NM:
        L.append("(tiada telco dalam telco.conf)")
    L += ["", "✅ berfungsi   ⚠️ lemah (boleh dipilih, ada amaran)   ❌ tak berfungsi (disorok dari pilihan)",
          "/telcook nama [nama ...]", "/telcolemah nama", "/telcotak nama",
          "Guna nama atau nombor, atau  semua.  Telco tak diubah = berfungsi."]
    return "\n".join(L)


def tg_nama(frm):
    return " ".join(x for x in (frm.get("first_name", ""), ("@" + frm["username"]) if frm.get("username") else "") if x) or "-"


@remote
def jual_nama(frm, kind):
    """Nama akaun ikut nama Telegram: username kalau ada, kalau tak nama pertama. Huruf, nombor, _ . - sahaja."""
    base = frm.get("username") or frm.get("first_name") or ""
    base = unicodedata.normalize("NFKD", base).encode("ascii", "ignore").decode()
    base = re.sub(r"[^A-Za-z0-9_.-]", "", base)[:24].strip(".-")
    if kind == "s":
        base = re.sub(r"[^a-z0-9_-]", "", base.lower())
    if not base:
        base = "user%d" % (frm["id"] % 10000)
    if not re.match(r"[A-Za-z_]", base):
        base = "u" + base
    if base.lower().startswith("trial"):
        base = "u" + base
    for cand in [base] + ["%s-%d" % (base, i) for i in range(2, 10)]:
        if not name_taken(cand):
            return cand
    for _ in range(10):
        cand = "%s%03d" % (base[:20], secrets.randbelow(1000))
        if not name_taken(cand):
            return cand
    return None


def jual_order_id(d):
    while True:
        i = "".join(secrets.choice("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") for _ in range(5))
        if not any(o["id"] == i for o in d["orders"]):
            return i


def jual_cari(d, oid):
    for o in d["orders"]:
        if o["id"] == oid:
            return o
    return None


def jual_buka(d, uid):
    for o in d["orders"]:
        if o["uid"] == uid and o["status"] in ("menunggu_bayar", "menunggu_sah"):
            return o
    return None


def send_photo(chat, file_id, caption, kb=None):
    p = {"chat_id": chat, "photo": file_id, "caption": caption[:1000], "parse_mode": "HTML"}
    if kb:
        p["reply_markup"] = {"inline_keyboard": kb}
    try:
        tg("sendPhoto", **p)
    except Exception as e:
        log("sendPhoto gagal:", e)
        send(chat, caption, kb)


def kedai_aktif():
    return trial_load()["aktif"] or jual_hidup(jual_load())


def kedai_start(chat, frm):
    uid = frm["id"]
    adm = uid in ADMINS
    J = jual_load()
    T = trial_load()
    if not jual_hidup(J):
        if T["aktif"]:
            trial_start(chat, frm)
        return
    if uid in T["banned"] and not adm:
        return
    now = time.time()
    if not adm:
        if now - KEDAI_SENYAP.get(uid, 0) < 2:
            return
        if len(KEDAI_SENYAP) > 2000:
            KEDAI_SENYAP.clear()
        KEDAI_SENYAP[uid] = now
    kb = [[btn("🛒 Beli akaun", "ky:beli"), btn("🔁 Renew", "ky:renew")],
          [btn("📦 Akaun saya", "ky:akaun"), btn("📶 Telco berfungsi", "ky:telco")]]
    if T["aktif"] and T["jenis"]:
        kb.insert(0, [btn("🎁 Trial percuma", "ky:trial")])
    send(chat, "\n".join(["✦ <b>KANCIL ECEM</b> ✦", "Developer by kancil ecem", "",
                          "Akaun %s: %s / %d hari" % (", ".join(TRIAL_KIND[k] for k in J["jenis"]), rm(J["sen"]), J["hari"]),
                          "Bayar guna QR bank. Akaun dihantar kat sini lepas pembayaran disahkan.", "", "Pilih:"]), kb)


def jual_pay_screen(chat, o, J):
    t = ["🛒 <b>Order %s</b>" % code(o["id"]),
         ("%s • %d hari • %s" % (TRIAL_KIND[o["kind"]], o["hari"], rm(o["sen"]))) if o["jenis"] == "baru" else
         ("Renew %s %s • tambah %d hari • %s" % (TRIAL_KIND[o["kind"]], code(o["user"]), o["hari"], rm(o["sen"])))]
    if o.get("telco"):
        t.append("Telco: <b>%s</b>" % E(o["telco"]))
    if vps_multi():
        t.append("Server: <b>%s</b>" % E(vps_nama(o.get("vps", "local"))))
    t += ["", "1) Scan QR dan bayar <b>%s</b> tepat." % rm(o["sen"]),
          "2) Letak kod %s dalam rujukan atau catatan bayaran." % code(o["id"]),
          "3) Hantar <b>gambar resit</b> kat sini.",
          "Akaun dicipta lepas admin sahkan duit dah masuk."]
    if J["nota"]:
        t += ["", E(J["nota"])]
    send_photo(chat, J["qr"], "\n".join(t), [[btn("❌ Batal order", "kx:%s" % o["id"])]])


def jual_order_baru(chat, frm, kind, jenis, user="", telco="", vid="local"):
    J = jual_load()
    uid = frm["id"]
    if not jual_hidup(J) or kind not in J["jenis"]:
        send(chat, "Jualan tak dibuka sekarang.")
        return
    if jenis == "baru" and not vps_dibuka(vid):
        send(chat, "Server tu tak dibuka sekarang. Tekan /start untuk pilih semula.")
        return
    o = jual_buka(J, uid)
    if o:
        if o["status"] == "menunggu_sah":
            send(chat, "Kau ada order %s yang tengah disemak admin. Tunggu sekejap." % code(o["id"]))
        else:
            send(chat, "Kau ada order yang belum bayar:")
            jual_pay_screen(chat, o, J)
        return
    o = {"id": jual_order_id(J), "uid": uid, "chat": chat, "nama": tg_nama(frm), "tg": frm.get("username", ""),
         "fn": frm.get("first_name", ""), "kind": kind, "jenis": jenis, "user": user, "telco": telco, "sen": J["sen"], "hari": J["hari"],
         "t": time.time(), "status": "menunggu_bayar", "resit": 0, "vps": vid}
    J["orders"].append(o)
    jual_save(J)
    jual_pay_screen(chat, o, J)


def jual_miliknya(J, uid):
    """Akaun yang pelanggan ni beli dan masih ada: [(jenis, nama, padanan find(), id server)]."""
    per = {}
    for key, own in J["akaun"].items():
        if own != uid:
            continue
        k, tok = key.split(":", 1)
        u, vid = vsplit(tok)
        per.setdefault(vid, []).append((k, u))
    out = []
    for vid, prs in per.items():
        try:
            with on(vid):
                res = find_many(prs)
        except VPSError as e:
            log("akaun pelanggan: server %s tak dapat dihubungi: %s" % (vid, e))
            continue
        for (k, u), a in zip(prs, res):
            if a:
                out.append((k, u, a, vid))
    return out


def jual_kb_telco(kind, user):
    tok = user + vsuf()
    b = [btn(t[0], "kt:%s:%s:%d" % (kind, tok, i + 1)) for i, t in enumerate(telcos()) if telco_ok(t, kind)]
    kb = rows(b, 3)
    kb.append([btn("Semua telco", "kt:%s:%s:0" % (kind, tok))])
    return kb


@remote
def jual_butiran(kind, user, a, kepala="Akaun %s", telco=""):
    """a = padanan find(): (nama, luput, uuid/kata laluan). Teks HTML butiran akaun untuk pelanggan."""
    if kind == "s":
        pw, exp = a[2], a[1]
        t = ["<b>%s</b>  ✦ kancil ecem" % (kepala % "SSH"), "User     : %s" % code(user), "Password : %s" % code(pw),
             "Host     : %s" % code(domain()), "Luput    : %s (%d hari)" % (E(exp), days_left(exp)),
             "", "<pre>%s</pre>" % E(SSH_PORTS)]
        return "\n".join(t)
    t = ["<b>%s</b>  ✦ kancil ecem" % (kepala % TRIAL_KIND[kind])]
    t += [l for l in acct_info(kind, user, a[2], a[1]) if not l.startswith("Nota")]
    tl = [x for x in telcos() if x[0] == telco] if telco else []
    if tl:
        t += ["", "<b>Link telco pilihan: %s</b>" % E(tl[0][0]), code(telco_link(a[2], user, tl[0], kind))]
    for lab, lk in std_links(kind, user, a[2]):
        t += ["", "<b>%s</b>" % E(lab), code(lk)]
    t += ["", "OpenClash: " + code("http://%s:89/%s-%s.txt" % (domain(), KIND[kind]["pub"], user)), "", "Pilih telco untuk link tambahan:"]
    return "\n".join(t)


def jual_hantar_akaun(chat, kind, user, kepala, telco="", vid="local", fail=True):
    with on(vid):
        a = find(kind, user)
        if not a:
            return
        send(chat, jual_butiran(kind, user, a, kepala, telco), jual_kb_telco(kind, user) if kind != "s" else None)
    if kind == "s" and fail:
        hc_lepas(chat, user, vid)


def jual_pilih_jenis(chat, J, vid):
    nota = hc_nota_jenis(J, vid, J["jenis"])
    send(chat, ((nota + "\n\n") if nota else "") +
         "Pilih jenis akaun (%s / %d hari)%s:" % (rm(J["sen"]), J["hari"], (" • server %s" % vps_nama(vid)) if vps_multi() else ""),
         rows([btn(TRIAL_KIND[x], "kb:%s%s" % (x, vtok(vid))) for x in J["jenis"]], 2))


def jual_pilih_telco(chat, J, kind, vid="local"):
    with on(vid):
        T = telcos()
    b = []
    for i, x in enumerate(T):
        s = telco_status(J, x[0])
        if s != "tak" and telco_ok(x, kind):
            b.append(btn("%s %s" % (TELCO_ST[s], x[0]), "kc:%s:%d%s" % (kind, i + 1, vtok(vid))))
    tk = [x[0] for x in T if telco_status(J, x[0]) == "tak" and telco_ok(x, kind)]
    teks = ["Pilih telco kau dulu. ✅ berfungsi, ⚠️ kadang-kadang."]
    if tk:
        teks.append("❌ Tak berfungsi sekarang (tak boleh dipilih): %s" % E(", ".join(tk)))
    teks += ["", "Lepas pilih, bot hantar QR bayaran."]
    send(chat, "\n".join(teks), rows(b, 2) + [[btn("Tak pasti / mana-mana", "kc:%s:0%s" % (kind, vtok(vid)))]])


def kedai_cb(chat, frm, data):
    J = jual_load()
    T = trial_load()
    uid = frm["id"]
    adm = uid in ADMINS
    if uid in T["banned"] and not adm:
        return
    p = data.split(":")
    k = p[0]
    if (k == "ky" and len(p) == 2 and p[1] in ("trial", "beli")) or k in ("ks", "kb", "kc"):
        what = "trial" if (k == "ky" and p[1] == "trial") or (k == "ks" and len(p) > 1 and p[1] == "trial") else "beli"
        if not channel_ok(chat, frm, what):
            return
    if k == "kj" and len(p) == 2 and p[1] in ("trial", "beli"):
        if channel_ok(chat, frm, p[1], True):
            kedai_cb(chat, frm, "ky:" + p[1])
    elif k == "ky" and len(p) == 2:
        if p[1] == "trial":
            trial_start(chat, frm)
        elif p[1] == "telco":
            send(chat, telco_senarai_pelanggan(J, T["aktif"] and bool(T["jenis"])),
                 [[btn("🛒 Beli akaun", "ky:beli")]] if jual_hidup(J) else None)
        elif not jual_hidup(J):
            send(chat, "Jualan tak dibuka sekarang.")
        elif p[1] == "beli":
            vid = vps_pilih_awam(chat, "beli")
            if vid is not None:
                jual_pilih_jenis(chat, J, vid)
        elif p[1] == "renew":
            L = jual_miliknya(J, uid)
            if not L:
                send(chat, "Kau belum ada akaun beli kat sini (atau dah dipadam). Tekan Beli akaun.")
            else:
                send(chat, "Renew akaun mana? (+%d hari, %s)" % (J["hari"], rm(J["sen"])),
                     rows([btn("%s %s (%dh)%s" % (TRIAL_KIND[kk], u, days_left(a[1]), vlabel(vid)), "kr:%s:%s%s" % (kk, u, vsuf(vid))) for kk, u, a, vid in L], 1))
        elif p[1] == "akaun":
            L = jual_miliknya(J, uid)
            if not L:
                send(chat, "Kau belum ada akaun beli kat sini.")
            else:
                send(chat, "Akaun kau:", rows([btn("%s %s (%d hari)%s" % (TRIAL_KIND[kk], u, days_left(a[1]), vlabel(vid)), "ka:%s:%s%s" % (kk, u, vsuf(vid))) for kk, u, a, vid in L], 1))
    elif k == "ks" and len(p) == 3 and p[1] in ("trial", "beli"):
        vid = p[2]
        if not vps_dibuka(vid):
            send(chat, "Server tu tak dibuka sekarang. Pilih yang lain.")
            vps_pilih_awam(chat, p[1])
        elif p[1] == "trial":
            trial_start(chat, frm, vid)
        elif not jual_hidup(J):
            send(chat, "Jualan tak dibuka sekarang.")
        else:
            jual_pilih_jenis(chat, J, vid)
    elif k == "kb" and len(p) in (2, 3) and p[1] in TRIAL_KIND:
        vid = p[2] if len(p) == 3 else "local"
        if not jual_hidup(J) or p[1] not in J["jenis"]:
            send(chat, "Jualan tak dibuka sekarang.")
        elif not vps_dibuka(vid):
            send(chat, "Server tu tak dibuka sekarang. Tekan /start untuk pilih semula.")
        else:
            terus = p[1] == "s" or bool(jual_buka(J, uid))
            if not terus:
                with on(vid):
                    terus = not [x for x in telcos() if telco_ok(x, p[1])]
            if terus:
                jual_order_baru(chat, frm, p[1], "baru", vid=vid)
            else:
                jual_pilih_telco(chat, J, p[1], vid)
    elif k == "kc" and len(p) in (3, 4) and p[1] in TRIAL_KIND and p[1] != "s" and p[2].isdigit():
        vid = p[3] if len(p) == 4 else "local"
        if not vps_dibuka(vid):
            send(chat, "Server tu tak dibuka sekarang. Tekan /start untuk pilih semula.")
            return
        with on(vid):
            T2 = telcos()
        n = int(p[2])
        if n > len(T2):
            return
        nama = ""
        if n:
            nama = T2[n - 1][0]
            if not telco_ok(T2[n - 1], p[1]):
                send(chat, "Telco %s tak ada untuk jenis ni. Pilih yang lain." % code(nama))
                jual_pilih_telco(chat, J, p[1], vid)
                return
            if jual_hidup(J) and telco_status(J, nama) == "tak":
                send(chat, "Telco %s tak berfungsi sekarang. Pilih yang lain." % code(nama))
                jual_pilih_telco(chat, J, p[1], vid)
                return
        jual_order_baru(chat, frm, p[1], "baru", telco=nama, vid=vid)
    elif k == "kr" and len(p) == 3 and p[1] in TRIAL_KIND:
        u, vid = vsplit(p[2])
        if J["akaun"].get(akey(p[1], u, vid)) != uid:
            return
        with on(vid):
            ada = find(p[1], u)
        if not ada:
            send(chat, "Akaun tu dah dipadam. Tekan Beli akaun untuk beli baru.")
            return
        jual_order_baru(chat, frm, p[1], "renew", u, vid=vid)
    elif k == "kh" and len(p) == 3:
        u, vid = vsplit(p[2])
        milik = adm or J["akaun"].get(akey("s", u, vid)) == uid or any(
            r["user"] == u and r["uid"] == uid and r["kind"] == "s" and r.get("vps", "local") == vid for r in T["rec"])
        if not milik:
            return
        if vid not in hc_vids(J, p[1]):
            send(chat, "Fail tu tak ada untuk server ni. Taip /start.")
        elif telco_status(J, p[1]) == "tak":
            send(chat, "Telco %s tak berfungsi sekarang. Pilih yang lain." % code(p[1]))
        else:
            hc_hantar(chat, p[1], vid)
    elif k == "ka" and len(p) == 3 and p[1] in TRIAL_KIND:
        u, vid = vsplit(p[2])
        if J["akaun"].get(akey(p[1], u, vid)) != uid:
            return
        with on(vid):
            ada = find(p[1], u)
        if not ada:
            send(chat, "Akaun tu dah dipadam.")
            return
        jual_hantar_akaun(chat, p[1], u, "Akaun %s", vid=vid)
    elif k == "kt" and len(p) == 4 and p[1] in KIND and p[3].isdigit():
        u, vid = vsplit(p[2])
        if J["akaun"].get(akey(p[1], u, vid)) != uid:
            return
        with on(vid):
            a = find(p[1], u)
            if not a:
                send(chat, "Akaun tu dah dipadam.")
                return
            T2 = telcos()
            n = int(p[3])
            sel = [x for x in (T2 if n == 0 else T2[n - 1:n]) if telco_ok(x, p[1])]
            if not sel:
                send(chat, "Telco tak ada untuk jenis ni.")
                return
            out = ["<b>Akaun %s</b>" % KIND[p[1]]["nama"]] + [l for l in acct_info(p[1], u, a[2], a[1]) if not l.startswith("Nota")] + ["", "<b>Link telco</b>", ""]
            for t in sel:
                out += ["<b>%s</b>" % E(t[0]), code(telco_link(a[2], u, t, p[1])), ""]
            send(chat, "\n".join(out).rstrip(), jual_kb_telco(p[1], u))
    elif k == "kx" and len(p) == 2:
        o = jual_cari(J, p[1])
        if not o or o["uid"] != uid or o["status"] not in ("menunggu_bayar", "menunggu_sah"):
            return
        if o["status"] == "menunggu_sah":
            send(chat, "Resit order %s dah dihantar kat admin, tak boleh dibatalkan sekarang. Hubungi admin." % code(o["id"]))
            return
        o["status"] = "batal"
        jual_save(J)
        send(chat, "Order %s dibatalkan." % code(o["id"]), [[btn("🛒 Beli akaun", "ky:beli")]])


def kedai_media(msg):
    """Gambar atau fail daripada mesej bukan teks: (1) admin hantar QR dengan kapsyen /setqr, (2) pelanggan hantar resit."""
    chat = msg["chat"]["id"]
    uid = msg["from"]["id"]
    cap = (msg.get("caption") or "").strip()
    if uid in ADMINS:
        w = cap.split()
        if w and w[0].split("@")[0].lower() == "/hcset" and msg.get("document"):
            hc_set(chat, cap, msg["document"])
            return
        if msg.get("photo") and w and w[0].split("@")[0].lower() == "/hcgambar":
            hc_gambar_simpan(chat, msg["photo"][-1]["file_id"])
            return
        if msg.get("photo") and not cap.startswith("/"):
            HC_FOTO[chat] = {"id": msg["photo"][-1]["file_id"], "t": time.time()}
        d = msg.get("document") or {}
        if (d.get("file_name") or "").lower().endswith(".hc"):
            HC_LAST[chat] = {"doc": d, "t": time.time()}
            send(chat, "📥 Fail <b>%s</b> diterima. Sekarang taip arahan:\n<code>/hcset nama [server] [nama telco, ...]</code>\n"
                       "Contoh: <code>/hcset multi v2 Umo ultra freeze, Digi exp</code>\n(Bot ingat fail ni 30 minit.)" % E(d["file_name"]))
            return
        if cap.split("@")[0].lower() == "/setqr" and msg.get("photo"):
            J = jual_load()
            J["qr"] = msg["photo"][-1]["file_id"]
            jual_save(J)
            send(chat, "QR bayaran disimpan. Taip /jualon untuk buka jualan, /jual untuk lihat tetapan.", MAIN_KB)
        return
    J = jual_load()
    if not jual_hidup(J) or uid in trial_load()["banned"]:
        return
    ok_media = bool(msg.get("photo")) or (msg.get("document") or {}).get("mime_type", "").startswith(("image/", "application/pdf"))
    if not ok_media:
        return
    o = jual_buka(J, uid)
    if not o:
        send(chat, "Tiada order. Tekan /start dan pilih Beli akaun dulu.")
        return
    if o["resit"] >= 3:
        send(chat, "Resit dah dihantar kat admin. Tunggu pengesahan.")
        return
    o["resit"] += 1
    o["status"] = "menunggu_sah"
    jual_save(J)
    adm_cap = "\n".join(["🧾 <b>Resit order %s</b>" % code(o["id"]),
                         "Pelanggan: %s (tg:%d)" % (E(o["nama"]), uid),
                         ("Beli %s %d hari%s" % (TRIAL_KIND[o["kind"]], o["hari"], (" • telco %s" % E(o["telco"])) if o.get("telco") else "")) if o["jenis"] == "baru" else
                         ("Renew %s %s +%d hari" % (TRIAL_KIND[o["kind"]], code(o["user"]), o["hari"])),
                         "Jumlah: <b>%s</b>" % rm(o["sen"])] +
                        (["Server: <b>%s</b>" % E(vps_nama(o.get("vps", "local")))] if vps_multi() else []) +
                        ["", "⚠️ Semak duit dah masuk dalam bank dulu, baru tekan Sahkan."])
    akb = [[btn("✅ Sahkan", "ok:%s" % o["id"]), btn("❌ Tolak", "no:%s" % o["id"])]]
    for a in ADMINS:
        try:
            tg("copyMessage", chat_id=a, from_chat_id=chat, message_id=msg["message_id"], caption=adm_cap[:1000],
               parse_mode="HTML", reply_markup={"inline_keyboard": akb})
        except Exception as e:
            log("copyMessage gagal:", e)
            send(a, adm_cap + "\n(resit tak dapat disalin, minta pelanggan hantar semula atau semak bank)", akb)
    send(chat, "✅ Resit diterima untuk order %s. Admin akan semak duit masuk dan akaun dihantar kat sini." % code(o["id"]))


def jual_sahkan(oid, adm_chat):
    J = jual_load()
    o = jual_cari(J, oid)
    if not o:
        send(adm_chat, "Order %s tak jumpa." % code(oid))
        return
    if o["status"] not in ("menunggu_bayar", "menunggu_sah"):
        send(adm_chat, "Order %s dah diproses (%s)." % (code(oid), E(o["status"])))
        return
    kind = o["kind"]
    vid = o.get("vps", "local")
    def gagal_vps(e):
        return "⚠️ Server %s tak dapat dihubungi: %s. Order %s kekal, cuba tekan Sahkan lagi." % (E(vps_nama(vid)), E(e), code(oid))
    if o["jenis"] == "renew":
        u = o["user"]
        try:
            with on(vid):
                if J["akaun"].get(akey(kind, u, vid)) != o["uid"] or not find(kind, u):
                    send(adm_chat, "⚠️ Akaun %s dah tak ada atau bukan milik pelanggan. Order %s tak diproses." % (code(u), code(oid)))
                    return
                if kind == "s":
                    exp, err = ssh_renew(u, o["hari"])
                else:
                    exp, err = xray_renew(kind, u, o["hari"])
        except VPSError as e:
            send(adm_chat, gagal_vps(e))
            return
        if not exp:
            send(adm_chat, "⚠️ Renew gagal: %s. Order %s kekal, cuba tekan Sahkan lagi." % (E(err), code(oid)))
            return
        o["status"], o["siap_t"], o["akaun"] = "siap", time.time(), u
        jual_save(J)
        try:
            jual_hantar_akaun(o["chat"], kind, u, "Renew berjaya: akaun %s", vid=vid, fail=False)
        except VPSError as e:
            send(adm_chat, "⚠️ Renew siap tapi butiran tak dapat dihantar kat pelanggan (%s). Dia boleh tekan Akaun saya." % E(e))
        send(adm_chat, "✅ Order %s disahkan: renew %s %s +%d hari.%s" % (code(oid), TRIAL_KIND[kind], code(u), o["hari"], vtag(vid)), MAIN_KB)
        return
    frm = {"id": o["uid"], "first_name": o.get("fn", ""), "username": o.get("tg", "")}
    nota = "Beli tg:%d order %s %s" % (o["uid"], oid, rm(o["sen"]))
    try:
        with on(vid):
            user = jual_nama(frm, kind)
            if not user:
                send(adm_chat, "⚠️ Tak dapat cipta nama akaun. Order %s kekal." % code(oid))
                return
            if kind == "s":
                pw = "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(10))
                r, err = ssh_create(user, pw, o["hari"], J["iplimit"], J["kuota"])
            else:
                r, err = xray_create(kind, user, o["hari"], J["iplimit"], J["kuota"], nota=nota)
    except VPSError as e:
        send(adm_chat, gagal_vps(e))
        return
    if not r:
        send(adm_chat, "⚠️ Gagal cipta akaun: %s. Order %s kekal, cuba tekan Sahkan lagi." % (E(err), code(oid)))
        return
    J["akaun"][akey(kind, user, vid)] = o["uid"]
    o["status"], o["siap_t"], o["akaun"] = "siap", time.time(), user
    jual_save(J)
    try:
        jual_hantar_akaun(o["chat"], kind, user, "Akaun %s siap", o.get("telco", ""), vid=vid)
    except VPSError as e:
        send(adm_chat, "⚠️ Akaun dicipta tapi butiran tak dapat dihantar kat pelanggan (%s). Dia boleh tekan Akaun saya." % E(e))
    send(adm_chat, "✅ Order %s disahkan: %s %s dicipta untuk %s.%s" % (code(oid), TRIAL_KIND[kind], code(user), E(o["nama"]), vtag(vid)), MAIN_KB)


def jual_tolak(oid, adm_chat):
    J = jual_load()
    o = jual_cari(J, oid)
    if not o:
        send(adm_chat, "Order %s tak jumpa." % code(oid))
        return
    if o["status"] not in ("menunggu_bayar", "menunggu_sah"):
        send(adm_chat, "Order %s dah diproses (%s)." % (code(oid), E(o["status"])))
        return
    o["status"] = "tolak"
    jual_save(J)
    send(o["chat"], "Pembayaran order %s tak dapat disahkan. Kalau kau dah bayar, hubungi admin dengan resit." % code(oid))
    send(adm_chat, "❌ Order %s ditolak." % code(oid), MAIN_KB)


def jual_sweep():
    """Batalkan order belum bayar yang dah lama (tiada resit)."""
    J = jual_load()
    now = time.time()
    ubah = False
    for o in J["orders"]:
        if o["status"] == "menunggu_bayar" and now - o["t"] > J["luput"] * 3600:
            o["status"] = "batal"
            ubah = True
            send(o["chat"], "Order %s dibatalkan sebab tak dibayar dalam %d jam. Tekan /start untuk order semula." % (code(o["id"]), J["luput"]))
    if ubah:
        jual_save(J)


def jual_admin_msg():
    J = jual_load()
    now = time.time()
    hari, bulan = today().isoformat(), today().isoformat()[:7]
    siap = [o for o in J["orders"] if o["status"] == "siap"]
    tarikh = lambda o: datetime.date.fromtimestamp(o.get("siap_t", 0)).isoformat()
    h = [o for o in siap if tarikh(o) == hari]
    b = [o for o in siap if tarikh(o).startswith(bulan)]
    L = ["🛒 <b>Jualan</b>  ✦ kancil ecem", "Status  : %s" % ("HIDUP" if jual_hidup(J) else ("TUTUP" if not J["aktif"] else "TUTUP (belum ada QR)")),
         "Harga   : %s / %d hari" % (rm(J["sen"]), J["hari"]),
         "Akaun   : kuota %s, %s peranti" % (trial_gb(J["kuota"]), J["iplimit"] or "tiada had"),
         "Jenis   : %s" % (", ".join(TRIAL_KIND[k] for k in J["jenis"]) or "tiada"),
         "QR bank : %s" % ("ada" if J["qr"] else "BELUM (hantar gambar QR dengan kapsyen /setqr)"),
         "Order batal automatik: %d jam tak bayar" % J["luput"],
         "Hari ni : %d jualan, %s" % (len(h), rm(sum(o["sen"] for o in h))),
         "Bulan ni: %d jualan, %s" % (len(b), rm(sum(o["sen"] for o in b))),
         "Akaun dijual masih ada: %d" % len(J["akaun"]), ""]
    op = [o for o in J["orders"] if o["status"] in ("menunggu_bayar", "menunggu_sah")]
    L.append("Order terbuka: %d" % len(op))
    for o in op:
        L.append(" %s  %s  %s  %s  (%s, %s)" % (code(o["id"]), E(o["nama"]), TRIAL_KIND[o["kind"]], rm(o["sen"]),
                                                 "resit diterima" if o["status"] == "menunggu_sah" else "belum bayar", trial_tempoh(now - o["t"])))
    L += ["", "/jualon  /jualoff  /order",
          "/jualset harga=10 hari=30 kuota=0 ip=2 jenis=v,m,t,s luput=24",
          "/jualnota teks (arahan tambahan kat skrin bayar, 0 = padam)",
          "/sahkan KOD  /tolak KOD (kalau butang hilang)",
          "/telco (tanda telco berfungsi / lemah / tak, pelanggan nampak dan pilih sebelum bayar)",
          "QR: hantar gambar QR bank dengan kapsyen /setqr"]
    return "\n".join(L)


def telco_cmd(chat, cmd, a):
    J = jual_load()
    if cmd == "/telco":
        send(chat, telco_admin_msg(J), MAIN_KB)
        return
    st = {"/telcook": "ok", "/telcolemah": "lemah", "/telcotak": "tak"}[cmd]
    T = telcos_utama()
    T = T + [(n,) for n in sorted(J.get("hc", {})) if n not in [x[0] for x in T]]
    if not a:
        send(chat, "Guna: %s nama [nama ...]  (atau nombor, atau  semua).  Taip /telco untuk senarai." % cmd)
        return
    if len(a) == 1 and a[0].lower() == "semua":
        tgt = [x[0] for x in T]
    else:
        tgt = []
        for w in a:
            if w.isdigit() and 1 <= int(w) <= len(T):
                n = T[int(w) - 1][0]
            else:
                m = [x[0] for x in T if x[0].lower() == w.lower()]
                if not m:
                    send(chat, "Telco %s tak jumpa.\n\n%s" % (code(w[:30]), telco_admin_msg(J)))
                    return
                n = m[0]
            if n not in tgt:
                tgt.append(n)
    for n in tgt:
        if st == "ok":
            J["telco"].pop(n, None)
        else:
            J["telco"][n] = {"s": st, "t": time.time()}
    J["telco_t"] = time.time()
    jual_save(J)
    send(chat, "Disimpan.\n\n" + telco_admin_msg(J), MAIN_KB)


def jual_cmd(chat, cmd, a):
    J = jual_load()
    if cmd == "/jual":
        send(chat, jual_admin_msg(), MAIN_KB)
    elif cmd == "/jualon":
        if not J["qr"]:
            send(chat, "Hantar dulu gambar QR bank kau kat bot ni dengan kapsyen /setqr.")
            return
        if not J["jenis"]:
            send(chat, "Tiada jenis akaun. Guna /jualset jenis=v,m,t,s")
            return
        J["aktif"] = True
        jual_save(J)
        send(chat, "Jualan HIDUP.\n\n" + jual_admin_msg(), MAIN_KB)
    elif cmd == "/jualoff":
        J["aktif"] = False
        jual_save(J)
        send(chat, "Jualan TUTUP. Order yang dah ada resit masih boleh disahkan.", MAIN_KB)
    elif cmd == "/jualset":
        if not a:
            send(chat, "Guna: /jualset harga=10 hari=30 kuota=0 ip=2 jenis=v,m,t,s luput=24  (harga dalam RM, kuota 0 = tiada had)")
            return
        for tok in a:
            if "=" not in tok:
                send(chat, "Tak sah: %s. Guna bentuk nama=nilai." % code(tok))
                return
            k, v = tok.split("=", 1)
            k = k.lower()
            if k == "harga":
                if not RM_RE.match(v) or float(v) < 1:
                    send(chat, "harga mesti nombor RM 1 hingga 9999 (contoh 10 atau 12.50).")
                    return
                J["sen"] = int(round(float(v) * 100))
            elif k in JUAL_RANGE:
                lo, hi = JUAL_RANGE[k]
                if not v.isdigit() or not lo <= int(v) <= hi:
                    send(chat, "%s mesti nombor %d hingga %d." % (code(k), lo, hi))
                    return
                J["iplimit" if k == "ip" else k] = int(v)
            elif k == "jenis":
                js = [x for x in v.lower().split(",") if x]
                if not js or any(x not in TRIAL_KIND for x in js):
                    send(chat, "jenis: guna huruf v m t s dipisah koma. Contoh jenis=v,m")
                    return
                J["jenis"] = [x for x in "vmts" if x in js]
            else:
                send(chat, "Tak dikenali: %s" % code(k))
                return
        jual_save(J)
        send(chat, "Disimpan.\n\n" + jual_admin_msg(), MAIN_KB)
    elif cmd == "/jualnota":
        t = " ".join(a).strip()
        if not t:
            send(chat, "Guna: /jualnota teks  (0 = padam). Nota sekarang: %s" % (E(J["nota"]) or "tiada"))
            return
        if t == "0":
            J["nota"] = ""
        elif len(t) > 300:
            send(chat, "Nota terlalu panjang (maksimum 300 aksara).")
            return
        else:
            J["nota"] = t
        jual_save(J)
        send(chat, "Nota disimpan." if J["nota"] else "Nota dipadam.", MAIN_KB)
    elif cmd == "/order":
        op = [o for o in J["orders"] if o["status"] in ("menunggu_bayar", "menunggu_sah")]
        if not op:
            send(chat, "Tiada order terbuka.", MAIN_KB)
            return
        for o in op:
            send(chat, "%s  %s  %s %s  %s  (%s)" % (code(o["id"]), E(o["nama"]), TRIAL_KIND[o["kind"]], "renew" if o["jenis"] == "renew" else "baru",
                                                     rm(o["sen"]), "resit diterima" if o["status"] == "menunggu_sah" else "belum bayar"),
                 [[btn("✅ Sahkan", "ok:%s" % o["id"]), btn("❌ Tolak", "no:%s" % o["id"])]])
    elif cmd in ("/sahkan", "/tolak"):
        if len(a) != 1 or not re.match(r"^[A-Za-z0-9]{5}$", a[0]):
            send(chat, "Guna: %s KOD  (kod order 5 aksara, contoh K7P2Q)" % cmd)
            return
        (jual_sahkan if cmd == "/sahkan" else jual_tolak)(a[0].upper(), chat)


# ---------------------------------------------------------------- arahan server (admin)
@remote
def vps_info():
    return {"domain": domain(), "xray_conf": os.path.exists(XCONF), "xray": run(["systemctl", "is-active", "xray"]).stdout.strip(),
            "v": len(xusers("v")), "m": len(xusers("m")), "t": len(xusers("t")), "s": len(ssh_users())}


def vps_status(vid):
    """Semakan sebenar (tak guna cache DOWN). Pulang (maklumat, "") atau (None, ralat)."""
    try:
        if vid == "local":
            with on("local"):
                return RPC["vps_info"](), ""
        v = vps_get(vid)
        if not v:
            return None, "tak wujud"
        return rpc_call_v(v, "vps_info", [], {}), ""
    except VPSError as e:
        return None, str(e)


def vps_key():
    """Pastikan kunci SSH bot ada. Pulang kunci awam (teks)."""
    k = P(VPS_KEY)
    if not os.path.exists(k):
        os.makedirs(os.path.dirname(k), exist_ok=True)
        try:
            r = run(["ssh-keygen", "-t", "ed25519", "-N", "", "-C", "tbot-master", "-f", k], timeout=30)
        except OSError:
            raise VPSError("ssh-keygen tak ada. Jalankan: apt install -y openssh-client")
        if r.returncode != 0 or not os.path.exists(k + ".pub"):
            raise VPSError("gagal buat kunci SSH: " + _ralat_ssh(r.stderr))
    try:
        os.chmod(k, 0o600)
    except OSError:
        pass
    pub = rd(VPS_KEY + ".pub", "")
    if not pub:
        r = run(["ssh-keygen", "-y", "-f", k], timeout=30)
        pub = r.stdout.strip() if r.returncode == 0 else ""
        if pub:
            with open(k + ".pub", "w") as f:
                f.write(pub + " tbot-master\n")
            pub += " tbot-master"
    return pub


def vps_list_msg(chat):
    d = vps_load()
    pil = vps_pilih_get(chat, d)
    L = ["🖥 <b>Server</b>  ✦ kancil ecem", "Bot ni hidup kat server <b>Utama</b>. Server lain disambung guna SSH.", ""]
    for v in vps_semua(d):
        info, err = vps_status(v["id"])
        L.append("%s<b>%s</b>  %s%s" % ("▶ " if v["id"] == pil else "", E(v["nama"]), code(v["id"]), "" if v["buka"] else "  🔒 tutup"))
        if info:
            L.append("   %s  %s  VLESS %d, VMess %d, Trojan %d, SSH %d" % (
                code(info["domain"]), "✅" if info["xray"] == "active" else "⚠️ xray " + E(info["xray"] or "?"),
                info["v"], info["m"], info["t"], info["s"]))
        else:
            L.append("   ❌ tak dapat dihubungi: %s" % E(err))
        if v["host"]:
            L.append("   %s%s" % (E(v["host"]), (":%d" % v["port"]) if v["port"] != 22 else ""))
    L += ["", "▶ = server yang kau tengah urus (cipta, senarai, padam, renew guna server ni).",
          "🔒 tutup = pelanggan tak nampak server tu untuk beli atau trial baru (akaun sedia ada dan renew jalan macam biasa).", "",
          "/vpspilih ID  - tukar server yang diurus", "/vpstambah  - tambah server baru", "/vpsbuang ID  - buang server",
          "/vpsnama ID nama  - tukar nama", "/vpstutup ID  /vpsbuka ID  - tutup atau buka untuk pelanggan baru"]
    return "\n".join(L)


def vps_menu(chat):
    d = vps_load()
    pil = vps_pilih_get(chat, d)
    kb = rows([btn(("▶ " if v["id"] == pil else "") + v["nama"], "vp:%s" % v["id"]) for v in vps_semua(d)], 2)
    kb.append([btn("➕ Tambah server", "vp:+")])
    send(chat, vps_list_msg(chat), kb)


def vps_arahan_tambah(chat):
    try:
        key = vps_key()
    except VPSError as e:
        send(chat, "⚠️ " + E(e))
        return
    send(chat, "\n".join([
        "🖥 <b>Tambah server (VPS) baru</b>",
        "VPS tu mesti dah ada autoscript yang sama dan boleh log masuk sebagai root.", "",
        "<b>Langkah 1</b> - kat VPS baru, jalankan arahan ni (satu baris):",
        code("mkdir -p ~/.ssh && echo '%s' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" % key), "",
        "<b>Langkah 2</b> - balik sini, taip:", code("/vpstambah NAMA IP"), "contoh: /vpstambah SG1 1.2.3.4", "",
        "Token bot kekal kat server Utama sahaja. Server tambahan tak ada token."]))


def vps_pilih(chat, vid):
    d = vps_load()
    v = vps_get(vid, d)
    if not v:
        send(chat, "Server %s tak jumpa. Taip /vps." % code(vid[:20]))
        return
    d["pilih"][str(chat)] = vid
    vps_save(d)
    STATE.pop(chat, None)
    send(chat, "🖥 Sekarang kau urus server <b>%s</b>. Cipta, senarai, semak, padam dan renew akaun kat server ni." % E(v["nama"]), MAIN_KB)


def vps_tambah(chat, a):
    if not a:
        vps_arahan_tambah(chat)
        return
    if len(a) not in (2, 3):
        send(chat, "Guna: /vpstambah NAMA IP [PORT]   contoh: /vpstambah SG1 1.2.3.4")
        return
    nama, host = a[0], a[1]
    port = 22
    if not VNAMA_RE.match(nama):
        send(chat, "NAMA: huruf, nombor, - _ sahaja (maksimum 20). Contoh SG1.")
        return
    if not HOST_RE.match(host):
        send(chat, "IP atau domain tak sah.")
        return
    if len(a) == 3:
        if not a[2].isdigit() or not 1 <= int(a[2]) <= 65535:
            send(chat, "PORT mesti nombor 1 hingga 65535.")
            return
        port = int(a[2])
    d = vps_load()
    if any(v["host"].lower() == host.lower() and v["port"] == port for v in vps_semua(d)):
        send(chat, "Server tu dah ada dalam senarai. Taip /vps.")
        return
    if len(d["v"]) >= 8:
        send(chat, "Maksimum 8 server tambahan.")
        return
    vid = "v%d" % (d["seq"] + 1)
    v = {"id": vid, "nama": nama, "host": host, "port": port, "buka": True, "t": time.time()}
    send(chat, "Sekejap, cuba sambung ke %s ..." % code(host))
    try:
        vps_key()
        rc, out, err = ssh_run(v, "echo tbot-ok", b"", 40)
        if rc != 0 or "tbot-ok" not in out:
            send(chat, "❌ Tak dapat masuk ke %s.\n%s\n\nSemak: (1) IP betul, (2) arahan Langkah 1 dah dijalankan kat VPS tu (taip /vpstambah tanpa apa-apa untuk lihat semula), (3) SSH root dibenarkan." % (
                code(host), E(_ralat_ssh(err))))
            return
        rc, out, err = ssh_run(v, "command -v python3", b"", 30)
        if rc != 0:
            send(chat, "❌ VPS tu tak ada python3. Kat VPS tu jalankan: %s lepas tu cuba lagi." % code("apt install -y python3"))
            return
        agent_push(v)
        info = rpc_call_v(v, "vps_info", [], {})
    except VPSError as e:
        send(chat, "❌ %s" % E(e))
        return
    if not info.get("xray_conf"):
        send(chat, "❌ VPS tu belum ada autoscript (tiada /etc/xray/config.json). Pasang autoscript dulu.")
        return
    ada = []
    for x in vps_semua(d):
        inf, _ = vps_status(x["id"])
        if inf:
            ada.append(inf.get("domain"))
    if info.get("domain") in ada:
        send(chat, "❌ Server tu domainnya sama (%s) dengan server yang dah ada. Itu VPS yang sama?" % code(info.get("domain", "")))
        return
    d["v"].append(v)
    d["seq"] += 1
    vps_save(d)
    send(chat, "\n".join(["✅ Server <b>%s</b> ditambah (%s)." % (E(nama), code(vid)),
                          "Domain: %s  •  xray: %s" % (code(info["domain"]), E(info["xray"])),
                          "Akaun sedia ada: VLESS %d, VMess %d, Trojan %d, SSH %d" % (info["v"], info["m"], info["t"], info["s"]), "",
                          "Pelanggan sekarang boleh pilih server masa beli dan trial.",
                          "Nak urus akaun kat server ni sendiri: /vpspilih %s" % vid]), MAIN_KB)


def vps_buang(chat, a):
    if not a:
        send(chat, "Guna: /vpsbuang ID  (ID dari /vps, contoh v2)")
        return
    vid = a[0].lower()
    if vid == "local":
        send(chat, "Server Utama tak boleh dibuang sebab bot hidup kat situ. Kalau tak nak pelanggan beli kat situ, guna /vpstutup local.")
        return
    d = vps_load()
    v = vps_get(vid, d)
    if not v:
        send(chat, "Server %s tak jumpa. Taip /vps." % code(vid[:20]))
        return
    sahkan = len(a) > 1 and a[1].lower() == "ya"
    J = jual_load()
    T = trial_load()
    tunggu = [o for o in J["orders"] if o.get("vps", "local") == vid and o["status"] == "menunggu_sah"]
    if tunggu:
        send(chat, "⚠️ Ada %d order yang dah bayar (resit dihantar) untuk server %s: %s.\nSahkan atau tolak dulu, baru buang server." % (
            len(tunggu), E(v["nama"]), ", ".join(code(o["id"]) for o in tunggu)))
        return
    belum = [o for o in J["orders"] if o.get("vps", "local") == vid and o["status"] == "menunggu_bayar"]
    akaun = [k for k in J["akaun"] if vsplit(k.split(":", 1)[1])[1] == vid]
    trial = [r for r in T["rec"] if r.get("vps", "local") == vid]
    if not sahkan:
        send(chat, "\n".join([
            "⚠️ Buang server <b>%s</b> (%s)?" % (E(v["nama"]), code(vid)), "",
            "• %d akaun pelanggan: rekod dibuang dari bot (akaun tu masih ada kat VPS tu sampai luput, tapi pelanggan tak boleh renew lagi)" % len(akaun),
            "• %d trial aktif: rekod dibuang" % len(trial),
            "• %d order belum bayar: dibatalkan dan pelanggan dimaklumkan" % len(belum),
            "• Kunci bot dibuang dari VPS tu dan salinan ejen dipadam (kalau VPS tu masih hidup)", "",
            "Kalau pasti, taip: /vpsbuang %s ya" % vid]))
        return
    for o in belum:
        o["status"] = "batal"
        send(o["chat"], "Order %s dibatalkan sebab server tu tak ada lagi. Tekan /start untuk order semula." % code(o["id"]))
    for k in akaun:
        J["akaun"].pop(k, None)
    hc_buang_vps(J, vid)
    T["rec"] = [r for r in T["rec"] if r.get("vps", "local") != vid]
    jual_save(J)
    trial_save(T)
    nota = ""
    try:
        rc, out, err = ssh_run(v, "sed -i '/ tbot-master$/d' ~/.ssh/authorized_keys; rm -f %s; echo selesai" % AGENT, b"", 20)
        if "selesai" in out:
            nota = "Kunci bot dah dibuang dari VPS tu."
        elif rc == 255:
            raise VPSError(_ralat_ssh(err))
        else:
            nota = "Kunci bot tak dapat dibuang dari VPS tu (%s). Buang sendiri baris 'tbot-master' dalam ~/.ssh/authorized_keys." % E(_ralat_ssh(err))
    except VPSError as e:
        nota = "VPS tu tak dapat dihubungi (%s), jadi kunci bot tak sempat dibuang. Kalau VPS tu masih hidup, buang baris 'tbot-master' dalam ~/.ssh/authorized_keys." % E(e)
    try:
        run(["ssh-keygen", "-R", v["host"] if v["port"] == 22 else "[%s]:%d" % (v["host"], v["port"]), "-f", P(VPS_KH)])
    except OSError:
        pass
    d = vps_load()
    d["v"] = [x for x in d["v"] if x["id"] != vid]
    d["pilih"] = {k: x for k, x in d["pilih"].items() if x != vid}
    vps_save(d)
    DOWN.pop(vid, None)
    send(chat, "✅ Server <b>%s</b> dibuang dari bot.\n%s" % (E(v["nama"]), nota), MAIN_KB)


def vps_cmd(chat, cmd, a):
    if cmd == "/vps":
        vps_menu(chat)
    elif cmd == "/vpstambah":
        vps_tambah(chat, a)
    elif cmd == "/vpsbuang":
        vps_buang(chat, a)
    elif cmd == "/vpspilih":
        if len(a) != 1:
            send(chat, "Guna: /vpspilih ID  (ID dari /vps, contoh local atau v2)")
        else:
            vps_pilih(chat, a[0].lower())
    elif cmd == "/vpsnama":
        if len(a) < 2:
            send(chat, "Guna: /vpsnama ID nama baru  (contoh /vpsnama v2 Singapura 1)")
            return
        vid = a[0].lower()
        nama = " ".join(re.sub(r"[\x00-\x1f\x7f<>&]", " ", " ".join(a[1:])).split())
        d = vps_load()
        if not vps_get(vid, d):
            send(chat, "Server %s tak jumpa. Taip /vps." % code(vid[:20]))
        elif not 1 <= len(nama) <= 30:
            send(chat, "Nama 1 hingga 30 aksara.")
        else:
            if vid == "local":
                d["local"]["nama"] = nama
            else:
                for v in d["v"]:
                    if v["id"] == vid:
                        v["nama"] = nama
            vps_save(d)
            send(chat, "Nama server %s: <b>%s</b>" % (code(vid), E(nama)), MAIN_KB)
    elif cmd in ("/vpstutup", "/vpsbuka"):
        if len(a) != 1:
            send(chat, "Guna: %s ID" % cmd)
            return
        vid = a[0].lower()
        d = vps_load()
        if not vps_get(vid, d):
            send(chat, "Server %s tak jumpa. Taip /vps." % code(vid[:20]))
            return
        buka = cmd == "/vpsbuka"
        if vid == "local":
            d["local"]["buka"] = buka
        else:
            for v in d["v"]:
                if v["id"] == vid:
                    v["buka"] = buka
        vps_save(d)
        send(chat, "Server <b>%s</b> %s untuk pelanggan baru." % (E(vps_nama(vid)), "DIBUKA" if buka else "DITUTUP"), MAIN_KB)
        if not vps_buka_list():
            send(chat, "⚠️ Semua server ditutup. Pelanggan tak boleh beli atau trial sampai ada yang dibuka (/vpsbuka ID).")


def admin_ctx(chat):
    global CUR
    CUR = vps_pilih_get(chat)


def main_kb(chat):
    try:
        multi = vps_multi()
        nama = vps_nama(vps_pilih_get(chat))
    except Exception:
        multi, nama = False, ""
    return MAIN_KB + [[btn(("🖥 Server: %s" % nama) if multi else "🖥 Server", "m:vp")]]


def vps_pilih_awam(chat, nxt):
    """Untuk pelanggan. Satu server dibuka: pulang id terus. Lebih: hantar pilihan server dan pulang None. Tiada: maklumkan dan None."""
    L = vps_buka_list()
    if not L:
        send(chat, "Tiada server dibuka sekarang. Cuba lagi nanti.")
        return None
    if len(L) == 1:
        return L[0]["id"]
    send(chat, "Pilih server:", rows([btn("🖥 " + v["nama"], "ks:%s:%s" % (nxt, v["id"])) for v in L], 2))
    return None


# ---------------------------------------------------------------- wajib join channel
# Pelanggan kena jadi ahli channel kau sebelum boleh Trial atau Beli. Bot mesti jadi admin channel tu (supaya boleh semak ahli).
# Admin tak disekat. Renew, Akaun saya dan Telco berfungsi tak disekat. Kalau semakan gagal (bot bukan admin lagi dll), semua orang dibenarkan dan admin dimaklumkan.
# ---------------------------------------------------------------- HTTP Custom (.hc) berkunci
# Admin buat fail .hc berkunci dalam app HTTP Custom (payload tersembunyi, bahagian Account dibiar boleh diedit),
# lepas tu hantar kat bot dengan kapsyen  /hcset nama [server]. Bot simpan fail sebijik (TAK dibuka, TAK diubah) dan hantar kat
# pelanggan SSH bersama butiran akaun. Pelanggan isi username dan password sendiri dalam app.
# Satu fail untuk setiap telco setiap server, sebab payload ada domain server.
HC_DIR = "/etc/tbot/hc"
HC_NAMA = re.compile(r"^[a-z0-9][a-z0-9-]{1,19}$")
HC_MAX = 200000


def hc_path(nama, vid):
    return P("%s/%s.%s.hc" % (HC_DIR, nama, vid))


def hc_vids(J, nama):
    return J.get("hc", {}).get(nama, {}).get("v", {})


def hc_tajuk(J, n):
    """Nama yang pelanggan nampak: senarai nama telco yang admin tetapkan, atau nama pendek kalau tiada."""
    l = J.get("hc", {}).get(n, {}).get("lbl") or []
    return ", ".join(l) if l else n


def hc_items(t):
    """Teks (baris atau koma) -> (senarai nama, ralat)."""
    items = [re.sub(r"\s+", " ", y).strip() for x in t.split("\n") for y in x.split(",")]
    items = [y for y in items if y]
    if len(items) > 8 or any(len(y) > 40 for y in items):
        return [], "Maksimum 8 nama, setiap satu 40 aksara."
    return items, ""


def hc_boleh(J, vid):
    """Nama telco SSH yang ada fail untuk server vid dan tak ditanda tak berfungsi."""
    return [n for n in sorted(J.get("hc", {})) if vid in hc_vids(J, n) and telco_status(J, n) != "tak"]


def hc_nota_jenis(J, vid, jenis):
    """Nota di skrin pilih jenis akaun: telco yang perlu SSH (fail HTTP Custom) lawan telco lain."""
    if "s" not in jenis:
        return ""
    nm = []
    for n in hc_boleh(J, vid):
        for x in (J.get("hc", {}).get(n, {}).get("lbl") or [n]):
            if x not in nm:
                nm.append(x)
    if not nm:
        return ""
    lain = "VLESS" if "v" in jenis else next((TRIAL_KIND[x] for x in jenis if x != "s"), "")
    t = "ℹ️ Telco <b>%s</b>: pilih <b>SSH</b>." % E(", ".join(nm))
    if lain:
        t += "\nTelco lain: pilih <b>%s</b>." % lain
    return t


def tg_ambil(file_id):
    r = tg("getFile", file_id=file_id)["result"]
    with urllib.request.urlopen("%s/file/bot%s/%s" % (API, TOKEN, r["file_path"]), timeout=30) as f:
        return f.read(HC_MAX + 1)


def tg_dokumen(chat, nama, data, caption=""):
    b = "kancil" + secrets.token_hex(10)
    body = b""
    for k, v in (("chat_id", str(chat)), ("caption", caption), ("parse_mode", "HTML")):
        body += ('--%s\r\nContent-Disposition: form-data; name="%s"\r\n\r\n%s\r\n' % (b, k, v)).encode()
    body += ('--%s\r\nContent-Disposition: form-data; name="document"; filename="%s"\r\n'
             'Content-Type: application/octet-stream\r\n\r\n' % (b, nama)).encode() + data + ("\r\n--%s--\r\n" % b).encode()
    req = urllib.request.Request("%s/bot%s/sendDocument" % (API, TOKEN), body,
                                 {"Content-Type": "multipart/form-data; boundary=" + b})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def hc_hantar(chat, nama, vid):
    J = jual_load()
    if vid not in hc_vids(J, nama):
        return False
    try:
        with open(hc_path(nama, vid), "rb") as f:
            data = f.read()
        lbl = J["hc"][nama].get("lbl") or []
        cap = ("📱 <b>Fail HTTP Custom</b>\nBoleh guna untuk:\n" + "\n".join("• " + E(x) for x in lbl)) if lbl else "📱 <b>Fail HTTP Custom: %s</b>" % E(nama)
        tg_dokumen(chat, "%s.hc" % nama, data, cap)
    except (OSError, ValueError) as e:
        log("hc gagal:", e)
        send(chat, "Fail HTTP Custom tak dapat dihantar sekarang. Hubungi admin.")
        return False
    hc_panduan(chat)
    return True


def hc_lepas(chat, user, vid):
    """Lepas akaun SSH dihantar: satu telco = terus hantar fail; lebih satu = butang pilih."""
    J = jual_load()
    H = hc_boleh(J, vid)
    if len(H) == 1:
        hc_hantar(chat, H[0], vid)
    elif H:
        tok = user + vsuf(vid)
        send(chat, "📱 Pilih telco untuk fail HTTP Custom (akaun SSH kau):",
             rows([btn(("" if telco_status(J, n) == "ok" else TELCO_ST[telco_status(J, n)] + " ") + hc_tajuk(J, n), "kh:%s:%s" % (n, tok)) for n in H], 2))


def hc_padam_fail(J, nama, vid=None):
    """Buang fail telco nama (satu server, atau semua kalau vid kosong). Telco tanpa fail langsung dibuang terus."""
    v = hc_vids(J, nama)
    for x in ([vid] if vid else list(v)):
        if x in v:
            v.pop(x)
            try:
                os.remove(hc_path(nama, x))
            except OSError:
                pass
    if not v:
        J.get("hc", {}).pop(nama, None)
        J["telco"].pop(nama, None)


def hc_buang_vps(J, vid):
    for n in list(J.get("hc", {})):
        if vid in hc_vids(J, n):
            hc_padam_fail(J, n, vid)


HC_LAST = {}
HC_FOTO = {}
HC_NOTA_LALAI = ("Cara guna fail HTTP Custom:\n1. Buka fail .hc tadi dengan HTTP Custom.\n"
                 "2. Isi SSH username dan password (ada dalam mesej akaun kau).\n3. Tekan Start.\nJangan kongsi fail ni.")


def hc_panduan(chat):
    """Lepas fail dihantar: gambar panduan (kalau ada) dengan nota sebagai kapsyen, atau nota sahaja."""
    J = jual_load()
    nota = J.get("hc_nota") or HC_NOTA_LALAI
    if J.get("hc_gambar"):
        try:
            tg("sendPhoto", chat_id=chat, photo=J["hc_gambar"], caption=nota)
            return
        except Exception as e:
            log("hc gambar gagal:", e)
    send(chat, E(nota))


def hc_nota(chat, text):
    J = jual_load()
    t = text.strip().split(None, 1)
    rest = t[1].strip() if len(t) > 1 else ""
    if not rest:
        send(chat, "📝 <b>Nota cara guna</b> (dihantar lepas fail HTTP Custom)%s:\n\n%s\n\nTukar: /hcnota teks   (0 = guna nota lalai)" % (
            "" if J.get("hc_nota") else " [lalai]", E(J.get("hc_nota") or HC_NOTA_LALAI)))
    elif rest == "0":
        J["hc_nota"] = ""
        jual_save(J)
        send(chat, "Nota guna yang lalai semula.", MAIN_KB)
    elif len(rest) > 800:
        send(chat, "❌ Nota terlalu panjang (maksimum 800 aksara, ini %d)." % len(rest))
    else:
        J["hc_nota"] = rest
        jual_save(J)
        send(chat, "✅ Nota disimpan:\n\n%s" % E(rest), MAIN_KB)


def hc_gambar_simpan(chat, file_id):
    J = jual_load()
    J["hc_gambar"] = file_id
    jual_save(J)
    HC_FOTO.pop(chat, None)
    send(chat, "✅ Gambar panduan disimpan. Bot hantar gambar ni (dengan nota sebagai kapsyen) lepas fail HTTP Custom. /hcfail nama untuk tengok macam mana pelanggan nampak.", MAIN_KB)


def hc_gambar(chat, text):
    J = jual_load()
    a = text.split()[1:]
    if a and a[0] == "0":
        J["hc_gambar"] = ""
        jual_save(J)
        send(chat, "Gambar panduan dibuang. Pelanggan dapat nota sahaja.", MAIN_KB)
        return
    x = HC_FOTO.get(chat)
    if x and time.time() - x["t"] <= 1800:
        hc_gambar_simpan(chat, x["id"])
    elif J.get("hc_gambar"):
        try:
            tg("sendPhoto", chat_id=chat, photo=J["hc_gambar"], caption="Gambar panduan sekarang.\nTukar: hantar gambar baru kat bot, lepas tu taip /hcgambar.   (0 = buang)")
        except Exception:
            send(chat, "Gambar panduan ada tapi tak dapat dipaparkan. Hantar gambar baru, lepas tu taip /hcgambar.")
    else:
        send(chat, "Hantar gambar panduan kat bot ni (tangkap skrin cara guna), lepas tu taip /hcgambar.")


def hc_set_teks(chat, text):
    """/hcset ditaip sebagai mesej biasa: guna fail .hc terakhir yang admin hantar (30 minit)."""
    x = HC_LAST.get(chat)
    if not x or time.time() - x["t"] > 1800:
        HC_LAST.pop(chat, None)
        send(chat, "Hantar dulu fail .hc kat bot ni (klip kertas > File), lepas tu taip arahan ni.")
        return
    hc_set(chat, text, x["doc"])


def hc_set(chat, cap, doc):
    """cap: '/hcset nama [server] [nama telco, ...]' dan baris tambahan = nama telco yang pelanggan nampak."""
    baris = [x.strip() for x in cap.strip().split("\n")]
    w = baris[0].split()[1:]
    if not w or not HC_NAMA.match(w[0].lower()):
        send(chat, "Guna: hantar fail .hc dengan kapsyen  /hcset nama [server]\nNama: huruf kecil, nombor, sengkang (2-20 aksara), contoh celcom-sg.\n"
                   "Server: ID dari /vps (contoh v2). Kalau kosong, guna server yang tengah kau pilih.\n"
                   "Nama telco untuk pelanggan (pilihan): tulis selepas server, asing dengan koma atau baris baru.")
        return
    nama = w[0].lower()
    rest = w[1:]
    vid = None
    if rest and re.match(r"^(local|v\d{1,4})$", rest[0].lower()):
        vid, rest = rest[0].lower(), rest[1:]
    vid = vid or vps_pilih_get(chat)
    items, err = hc_items("\n".join([" ".join(rest)] + baris[1:]))
    if err:
        send(chat, "❌ " + err)
        return
    if not vps_get(vid):
        send(chat, "Server %s tak jumpa. Taip /vps." % code(vid[:20]))
        return
    if not (doc.get("file_name") or "").lower().endswith(".hc"):
        send(chat, "❌ Itu bukan fail .hc. Export fail dari HTTP Custom.")
        return
    if (doc.get("file_size") or 0) > HC_MAX:
        send(chat, "❌ Fail terlalu besar untuk fail .hc.")
        return
    try:
        raw = tg_ambil(doc["file_id"])
    except Exception as e:
        send(chat, "❌ Tak dapat ambil fail dari Telegram: %s" % E(str(e)[:150]))
        return
    if not raw or len(raw) > HC_MAX:
        send(chat, "❌ Fail kosong atau terlalu besar.")
        return
    os.makedirs(P(HC_DIR), mode=0o700, exist_ok=True)
    p = hc_path(nama, vid)
    with open(p + ".tmp", "wb") as f:
        f.write(raw)
    os.chmod(p + ".tmp", 0o600)
    os.replace(p + ".tmp", p)
    J = jual_load()
    ada = vid in hc_vids(J, nama)
    ent = J["hc"].setdefault(nama, {"v": {}})
    ent.setdefault("v", {})[vid] = {"t": time.time(), "n": len(raw)}
    if items:
        ent["lbl"] = items
    jual_save(J)
    dom = ""
    try:
        with on(vid):
            dom = domain()
    except VPSError:
        pass
    L = ["✅ Fail %s untuk server <b>%s</b> %s." % (code(nama), E(vps_nama(vid)), "dikemas kini" if ada else "disimpan"),
         "Bot simpan fail sebijik, tak buka. Pelanggan SSH di server ni dapat fail ni lepas beli atau trial."]
    L.append(("Nama telco untuk pelanggan: %s" % E(", ".join(ent["lbl"]))) if ent.get("lbl") else
             "Nama telco untuk pelanggan: belum ada. Tetapkan dengan  /hcnama %s Nama satu, Nama dua" % nama)
    if dom:
        L.append("Pastikan payload dalam fail ni guna domain server ni: %s" % code(dom))
    L += ["", "Uji: /hcfail %s %s  (bot hantar fail tu balik, import dalam HTTP Custom)" % (nama, vid),
          "/telcotak %s untuk sorok sementara dari pelanggan." % nama]
    send(chat, "\n".join(L), MAIN_KB)


def hc_nama(chat, text):
    J = jual_load()
    t = text.strip().split(None, 2)
    nama = t[1].lower() if len(t) > 1 else ""
    if nama not in J["hc"]:
        send(chat, "Guna: /hcnama nama Nama satu, Nama dua, ...   (0 = buang)\nSenarai: %s" % E(", ".join(sorted(J["hc"])) or "(belum ada, taip /hc)"))
        return
    rest = t[2].strip() if len(t) > 2 else ""
    if rest == "0":
        J["hc"][nama].pop("lbl", None)
        jual_save(J)
        send(chat, "Nama telco untuk %s dibuang. Pelanggan nampak: %s" % (code(nama), code(nama)), MAIN_KB)
        return
    items, err = hc_items(rest)
    if err or not items:
        send(chat, "❌ %s\nGuna: /hcnama %s Nama satu, Nama dua, ...   (0 = buang)" % (E(err or "Tiada nama."), nama))
        return
    J["hc"][nama]["lbl"] = items
    jual_save(J)
    send(chat, "✅ Pelanggan akan nampak fail %s sebagai:\n%s" % (code(nama), "\n".join("• " + E(x) for x in items)), MAIN_KB)


def hc_cmd(chat, cmd, a):
    J = jual_load()
    H = J["hc"]
    if cmd == "/hc":
        L = ["📱 <b>Fail HTTP Custom berkunci</b> (akaun SSH)"]
        buka = [v["id"] for v in vps_semua() if v["buka"]]
        for n in sorted(H):
            ada = [x for x in hc_vids(J, n) if vps_get(x)]
            kurang = [vps_nama(x) for x in buka if x not in ada]
            L.append("%s %s  • server: %s%s%s" % (TELCO_ST[telco_status(J, n)], code(n), E(", ".join(vps_nama(x) for x in ada) or "-"),
                                                  ("  • belum ada untuk: %s" % E(", ".join(kurang))) if kurang and vps_multi() else "",
                                                  ("\n    nama: %s" % E(", ".join(H[n]["lbl"]))) if H[n].get("lbl") else ""))
        if not H:
            L.append("Belum ada.")
        L.append("Panduan lepas fail: %s, nota %s" % ("gambar" if J.get("hc_gambar") else "tiada gambar", "tersendiri" if J.get("hc_nota") else "lalai"))
        L += ["", "<b>Tambah</b>: dalam HTTP Custom buat config (payload dsb), hidupkan lock tapi biar bahagian Account (username/password) boleh diedit, Export. "
              "Hantar fail .hc tu kat bot ni (klip kertas > File), lepas tu taip  /hcset nama [server]  (boleh juga letak arahan ni sebagai kapsyen fail)",
              "/hcnama nama Nama satu, Nama dua - nama telco yang pelanggan nampak (0 = buang)",
              "/hcnota teks - nota cara guna (0 = lalai).  /hcgambar - gambar panduan (hantar gambar dulu, lepas tu taip arahan; 0 = buang)",
              "Satu fail untuk setiap server (payload ada domain server tu). Server kosong = server yang tengah kau pilih.",
              "/hcfail nama [server] - bot hantar fail tu balik untuk uji", "/hcpadam nama [server] - buang", "/telcotak nama - sorok sementara dari pelanggan"]
        send(chat, "\n".join(L), MAIN_KB)
        return
    n = a[0].lower() if a else ""
    if n not in H:
        send(chat, "Guna: %s nama [server]\nSenarai: %s" % (cmd, E(", ".join(sorted(H)) or "(belum ada, taip /hc)")))
        return
    vid = a[1].lower() if len(a) > 1 else (None if cmd == "/hcpadam" else vps_pilih_get(chat))
    if vid and vid not in hc_vids(J, n):
        send(chat, "Fail %s tak ada untuk server %s. Ada untuk: %s" % (code(n), code(vid[:20]), E(", ".join(hc_vids(J, n)) or "-")))
        return
    if cmd == "/hcpadam":
        hc_padam_fail(J, n, vid)
        jual_save(J)
        send(chat, "Fail %s dibuang%s." % (code(n), (" untuk server " + E(vps_nama(vid))) if vid else " (semua server)"), MAIN_KB)
        return
    if not hc_hantar(chat, n, vid):
        send(chat, "❌ Gagal hantar fail.")


CH_USER = re.compile(r"^@[A-Za-z][A-Za-z0-9_]{3,31}$")
CH_ID = re.compile(r"^-100[0-9]{5,15}$")
CH_LINK = re.compile(r"^https://t\.me/[A-Za-z0-9_+/-]{3,64}$")
CHAN_OK = {}
CHAN_AMARAN = [0.0]


def tg_coba(method, **p):
    """Panggil API Telegram tanpa melontar ralat. Pulang (berjaya, hasil atau sebab)."""
    try:
        r = tg(method, **p)
        return bool(r.get("ok")), r.get("result")
    except urllib.error.HTTPError as e:
        try:
            d = json.load(e).get("description", "")
        except Exception:
            d = ""
        return False, d or "HTTP %d" % e.code
    except Exception as e:
        return False, str(e)


def chan_semak(uid, c):
    """True = ahli, False = bukan ahli, None = tak dapat semak."""
    ok, r = tg_coba("getChatMember", chat_id=c["id"], user_id=uid)
    if not ok or not isinstance(r, dict):
        return None, str(r)
    st = r.get("status")
    if st in ("creator", "administrator", "member"):
        return True, ""
    if st == "restricted":
        return bool(r.get("is_member")), ""
    return False, ""


def chan_amaran(sebab):
    if time.time() - CHAN_AMARAN[0] < 3600:
        return
    CHAN_AMARAN[0] = time.time()
    log("semak channel gagal:", sebab)
    for a in ADMINS:
        send(a, "⚠️ Bot tak dapat semak ahli channel (%s). Pastikan bot masih admin channel tu. Sementara ni semua orang dibenarkan guna bot." % E(sebab[:100]))


def channel_ok(chat, frm, what, ulang=False):
    """Benarkan pelanggan teruskan Trial atau Beli? Kalau belum join, hantar arahan join dan pulang False."""
    uid = frm["id"]
    if uid in ADMINS:
        return True
    c = jual_load().get("chan") or {}
    if not c.get("id"):
        return True
    if CHAN_OK.get(uid, 0) > time.time():
        return True
    r, sebab = chan_semak(uid, c)
    if r is None:
        chan_amaran(sebab)
        return True
    if r:
        if len(CHAN_OK) > 5000:
            CHAN_OK.clear()
        CHAN_OK[uid] = time.time() + 600
        return True
    send(chat, ("Belum nampak kau dalam channel lagi. " if ulang else "") +
         "📢 Untuk guna %s, join channel <b>%s</b> dulu. Lepas join, tekan ✅ Dah join." % ("Trial" if what == "trial" else "Beli akaun", E(c.get("nama") or c["id"])),
         [[{"text": "📢 Join channel", "url": c["link"]}], [btn("✅ Dah join", "kj:%s" % what)]])
    return False


def chan_cmd(chat, a):
    J = jual_load()
    c = J.get("chan") or {}
    guna = "Guna: /channel @namachannel   (channel awam)\n/channel -100123456789 https://t.me/+pautan   (channel peribadi)\n/channel 0   (matikan)"
    if not a:
        if c.get("id"):
            send(chat, "📢 Wajib join channel: <b>HIDUP</b>\nChannel: %s (%s)\nPautan: %s\n\nSekat: Trial dan Beli akaun. Tak disekat: Renew, Akaun saya, Telco berfungsi, admin.\n\n%s" % (
                E(c.get("nama", "")), E(c["id"]), E(c["link"]), guna), MAIN_KB)
        else:
            send(chat, "📢 Wajib join channel: <b>MATI</b>\n\nCara hidupkan: (1) jadikan bot ni admin channel kau (Channel > Administrators > Add Admin > pilih bot), (2) taip /channel @namachannel\n\n" + guna, MAIN_KB)
        return
    if a[0] == "0" and len(a) == 1:
        J["chan"] = {}
        jual_save(J)
        CHAN_OK.clear()
        send(chat, "Wajib join channel dimatikan.", MAIN_KB)
        return
    ident = a[0]
    link = a[1] if len(a) > 1 else ""
    if len(a) > 2:
        send(chat, guna)
        return
    if CH_USER.match(ident):
        link = "https://t.me/" + ident[1:]
    elif CH_ID.match(ident):
        if not CH_LINK.match(link):
            send(chat, "Channel peribadi perlu pautan jemputan sekali.\n" + guna)
            return
    else:
        send(chat, guna)
        return
    ok, info = tg_coba("getChat", chat_id=ident)
    if not ok or not isinstance(info, dict):
        send(chat, "❌ Channel %s tak dijumpai (%s). Semak nama channel." % (code(ident), E(str(info)[:100])))
        return
    botid = int(TOKEN.split(":")[0]) if TOKEN[:1].isdigit() else 0
    ok, m = tg_coba("getChatMember", chat_id=ident, user_id=botid)
    if not ok or not isinstance(m, dict) or m.get("status") not in ("administrator", "creator"):
        send(chat, "❌ Bot belum jadi admin channel tu. Buka channel > Administrators > Add Admin > pilih bot ni > simpan. Lepas tu taip semula arahan tadi.")
        return
    J["chan"] = {"id": ident, "link": link, "nama": info.get("title") or ident}
    jual_save(J)
    CHAN_OK.clear()
    send(chat, "✅ Wajib join channel HIDUP: <b>%s</b>\nPelanggan kena join dulu sebelum Trial atau Beli akaun. Admin dan pelanggan lama (renew) tak disekat.\n/channel 0 untuk matikan." % E(J["chan"]["nama"]), MAIN_KB)


def handle(u):
    global CUR
    CUR = "local"
    try:
        _handle(u)
    finally:
        CUR = "local"


def _handle(u):
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
        if data.startswith(KEDAI_CB):
            kedai_cb(chat, cq["from"], data)
            return
        if cq["from"]["id"] not in ADMINS:
            return
        admin_ctx(chat)
        on_callback(chat, data)
        return
    msg = u.get("message")
    if msg and "text" not in msg and ("photo" in msg or "document" in msg) and (msg.get("chat") or {}).get("type") == "private" and "from" in msg:
        kedai_media(msg)
        return
    if not msg or "text" not in msg:
        return
    chat = msg["chat"]["id"]
    uid = msg["from"]["id"]
    text = msg["text"].strip()
    if msg["chat"].get("type") != "private":
        return
    if uid not in ADMINS:
        if kedai_aktif():
            kedai_start(chat, msg["from"])
            return
        # senyap: orang asing tak dapat balasan langsung. Cuma catat sekali setiap ID dalam log.
        if uid not in SEEN:
            if len(SEEN) > 1000:
                SEEN.clear()
            SEEN.add(uid)
            log("akses ditolak, ID:", uid)
        return
    admin_ctx(chat)
    if text.startswith("/"):
        on_command(chat, text)
    elif chat in STATE:
        flow_input(chat, text)
    else:
        send(chat, "Taip /menu.", MAIN_KB)


def proses(u):
    """Kendalikan satu kemas kini Telegram; ralat tak ranapkan bot."""
    try:
        handle(u)
    except VPSError as e:
        log("ralat server:", e)
        try:
            c = (u.get("message") or (u.get("callback_query") or {}).get("message") or {}).get("chat", {}).get("id")
            if c:
                send(c, "⚠️ Server tak dapat dihubungi sekarang. Cuba lagi sebentar" + (" atau pilih server lain (/start)." if c not in ADMINS else ".") +
                     (("\n" + E(e)) if c in ADMINS else ""))
        except Exception:
            pass
    except Exception:
        log("ralat:", traceback.format_exc())
        try:
            c = (u.get("message") or (u.get("callback_query") or {}).get("message") or {}).get("chat", {}).get("id")
            if c:
                send(c, "Ada ralat dalam bot. Cuba lagi atau semak: journalctl -u tbot -n 20", MAIN_KB)
        except Exception:
            pass


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
            jual_sweep()
        except Exception:
            log("jual_sweep ralat:", traceback.format_exc())
        try:
            params = {"timeout": 30, "allowed_updates": ["message", "callback_query"]}
            if offset is not None:
                params["offset"] = offset
            r = tg("getUpdates", **params)
            for u in r.get("result", []):
                offset = u["update_id"] + 1
                proses(u)
        except KeyboardInterrupt:
            break
        except Exception as e:
            log("getUpdates gagal:", e)
            time.sleep(5)


if __name__ == "__main__":
    if "--rpc" in sys.argv:
        rpc_main()
    else:
        main()
