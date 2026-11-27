#!/usr/bin/env python3
import json, os, select, signal, subprocess, sys, time, re, shutil, sqlite3, hashlib, tempfile
USAGE = """usage: reinstall-extension.py <pre|edit|install|check> <profile>

Reinstalls the 1Password extension through Chrome itself. Chrome 158 discards a
restored registration at startup, so the registration must be written by Chrome.
Run in order, one profile at a time, with the profile not in use:
  pre      record a baseline, copy the profile to $BACKUP_DIR/<profile>-<ts>, open
           the most recent authenticated page
  edit     drop the extension entry and `protection` from Secure Preferences and
           remove Default/Extensions/<id>
  install  start chrome-devtools-mcp with the install test flag, open the Web
           Store page, click Add to Chrome and wait for the registration
  check    compare with the baseline and open the authenticated page and the popup
           (run twice, each a full restart)
env: PROFILES_DIR, BACKUP_DIR
"""

ID = 'aeblfdkhhhdcdjpifhhbdiojplfjncoa'


def sp_state(profile):
    p = os.path.join(profile, 'Default', 'Secure Preferences')
    try:
        d = json.load(open(p, 'rb'))
    except Exception as e:
        return 'unreadable(%s)' % e
    e = d.get('extensions', {}).get('settings', {}).get(ID)
    body = os.path.isdir(os.path.join(profile, 'Default', 'Extensions', ID))
    if e is None:
        return 'ABSENT body=%s' % body
    return 'manifest=%s loc=%s dr=%s path=%s body=%s keys=%d' % (
        'manifest' in e, e.get('location'), e.get('disable_reasons'), str(e.get('path'))[:60], body, len(e))


def chrome_pids(profile):
    out = subprocess.run(['pgrep', '-f', '--', '--user-data-dir=' + profile], capture_output=True, text=True).stdout
    return [int(x) for x in out.split()]


class Session:
    def __init__(self, profile, extra=()):
        self.profile = os.path.abspath(profile)
        flags = ' '.join('--chromeArg=%s' % a for a in extra)
        cmd = ['sh', '-c', 'exec npx -y chrome-devtools-mcp@latest --userDataDir="%s" --ignoreDefaultChromeArg=--disable-extensions --chromeArg=--enable-logging --chromeArg=--v=0 --chromeArg=--vmodule=extension*=2 %s' % (self.profile, flags)]
        self.proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, start_new_session=True)
        self.mid = 0
        self.buf = b''
        r = self.rpc('initialize', {'protocolVersion': '2024-11-05', 'capabilities': {}, 'clientInfo': {'name': 'profile-exp', 'version': '0'}})
        assert 'result' in r, r
        self.rpc('notifications/initialized', notify=True)

    def _readline(self, end):
        fd = self.proc.stdout.fileno()
        while b'\n' not in self.buf:
            left = end - time.time()
            if left <= 0:
                return None
            if not select.select([fd], [], [], left)[0]:
                return None
            chunk = os.read(fd, 65536)
            if not chunk:
                return ''
            self.buf += chunk
        line, self.buf = self.buf.split(b'\n', 1)
        return line.decode('utf-8', 'replace')

    def rpc(self, method, params=None, notify=False, timeout=90):
        msg = {'jsonrpc': '2.0', 'method': method}
        if params is not None:
            msg['params'] = params
        if not notify:
            self.mid += 1
            msg['id'] = self.mid
        self.proc.stdin.write(json.dumps(msg) + '\n')
        self.proc.stdin.flush()
        if notify:
            return None
        end = time.time() + timeout
        while True:
            line = self._readline(end)
            if line is None:
                break
            if not line:
                return {'error': 'eof'}
            try:
                r = json.loads(line)
            except ValueError:
                continue
            if r.get('id') == self.mid:
                return r
        return {'error': 'timeout'}

    def call(self, name, args=None, timeout=90):
        r = self.rpc('tools/call', {'name': name, 'arguments': args or {}}, timeout=timeout)
        if 'result' in r:
            return '\n'.join(c.get('text', '') for c in r['result'].get('content', []))
        return 'ERR ' + json.dumps(r)[:300]

    def tools(self):
        r = self.rpc('tools/list')
        return [t['name'] for t in r.get('result', {}).get('tools', [])]

    def close(self):
        try:
            self.proc.stdin.close()
        except Exception:
            pass
        time.sleep(3)
        try:
            os.killpg(self.proc.pid, signal.SIGTERM)
        except Exception:
            pass
        t = time.time() + 15
        while time.time() < t and chrome_pids(self.profile):
            time.sleep(1)
        return len(chrome_pids(self.profile))


BASE = os.environ.get('PROFILES_DIR', os.path.expanduser('~/.cache/chrome-devtools-mcp/profiles'))
BK = os.environ.get('BACKUP_DIR', os.path.expanduser('~/.cache/chrome-devtools-mcp/profile-backups'))
STATE = BK
if len(sys.argv) != 3 or sys.argv[1] not in ('pre', 'edit', 'install', 'check'):
    sys.exit(USAGE)
cmd, name = sys.argv[1], sys.argv[2]
P = os.path.join(BASE, name)
D = os.path.join(P, 'Default')


def sha(p):
    return hashlib.sha256(open(p, 'rb').read()).hexdigest()[:12] if os.path.exists(p) else None


def du(p):
    return subprocess.run(['du', '-sk', p], capture_output=True, text=True).stdout.split()[0] if os.path.exists(p) else None


def running():
    return chrome_pids(P) or [f for f in os.listdir(P) if f.startswith('Singleton')]


def cookies_path():
    for c in ('Network/Cookies', 'Cookies'):
        if os.path.exists(os.path.join(D, c)):
            return os.path.join(D, c)


def q(db, sql):
    t = tempfile.mkdtemp()
    shutil.copy(db, t + '/db')
    for s in ('-wal', '-shm'):
        if os.path.exists(db + s):
            shutil.copy(db + s, t + '/db' + s)
    c = sqlite3.connect('file:%s/db?mode=ro' % t, uri=True)
    r = c.execute(sql).fetchall()
    c.close()
    shutil.rmtree(t)
    return r


def snapshot():
    cp = cookies_path()
    now_us = int((time.time() + 11644473600) * 1e6)
    s = {'cookies_file': cp and cp.replace(D, ''),
         'cookies_valid': cp and q(cp, "select count(*) from cookies where has_expires=0 or expires_utc>%d" % now_us)[0][0],
         'login_rows': q(os.path.join(D, 'Login Data'), 'select count(*) from logins')[0][0],
         'login_sha': sha(os.path.join(D, 'Login Data')), 'cookies_sha': cp and sha(cp),
         'ext_settings_kb': du(os.path.join(D, 'Local Extension Settings', ID)),
         'ext_idb_kb': du(os.path.join(D, 'IndexedDB', 'chrome-extension_%s_0.indexeddb.leveldb' % ID)),
         'sp': sp_state(P)}
    prefs = json.load(open(os.path.join(D, 'Preferences')))
    sp = json.load(open(os.path.join(D, 'Secure Preferences')))
    s['other_ext'] = sorted(k for k in sp.get('extensions', {}).get('settings', {}) if k != ID)
    s['home'] = {k: prefs.get(k) for k in ('homepage', 'homepage_is_newtabpage')}
    s['startup'] = prefs.get('session', {}).get('startup_urls')
    s['search'] = (prefs.get('default_search_provider_data') or {}).get('template_url_data', {}).get('short_name')
    return s


def auth_url():
    rows = q(os.path.join(D, 'History'), "select url from urls where url like 'https://%' and url not like '%google.com/%' and url not like '%chromewebstore%' and url not like '%accounts.%' and url not like '%login%' and url not like '%signin%' order by last_visit_time desc limit 1")
    return rows[0][0] if rows else None


def page_probe(url, extra=()):
    s = Session(P, extra=extra)
    s.call('list_pages')
    out = {}
    if url:
        s.call('navigate_page', {'pageId': 1, 'type': 'url', 'url': url})
        time.sleep(8)
        out['page'] = s.call('list_pages').replace('\n', ' | ')[:200]
    mf = None
    ed = os.path.join(D, 'Extensions', ID)
    if os.path.isdir(ed):
        v = sorted(os.listdir(ed))[-1]
        m = json.load(open(os.path.join(ed, v, 'manifest.json')))
        mf = (m.get('action') or {}).get('default_popup')
    out['popup_path'] = mf
    if mf:
        s.call('navigate_page', {'pageId': 1, 'type': 'url', 'url': 'chrome-extension://%s/%s' % (ID, mf)})
        time.sleep(5)
        snap = s.call('take_snapshot', {'pageId': 1})
        out['popup_text'] = re.sub(r'\s+', ' ', ' '.join(re.findall(r'"([^"]+)"', snap)))[:300]
    out['closed_left'] = s.close()
    return out


if cmd == 'pre':
    assert not running(), 'running'
    ts = time.strftime('%Y%m%d-%H%M%S')
    au = auth_url()
    s = snapshot()
    print('BASELINE', json.dumps(s, ensure_ascii=False))
    print('AUTH_URL_HOST', au and au.split('/')[2])
    os.makedirs(BK, exist_ok=True)
    json.dump(dict(s, auth_url=au, ts=ts), open('%s/%s.baseline.json' % (STATE, name), 'w'))
    dst = os.path.join(BK, '%s-%s' % (name, ts))
    subprocess.run(['cp', '-Rc', P, dst], check=True)
    print('BACKUP', dst, du(dst), 'KB vs', du(P))
    print('PROBE0', json.dumps(page_probe(au), ensure_ascii=False))
elif cmd == 'edit':
    assert not running(), 'running'
    p = os.path.join(D, 'Secure Preferences')
    d = json.load(open(p))
    d['extensions']['settings'].pop(ID, None)
    d.pop('protection', None)
    json.dump(d, open(p, 'w'), separators=(',', ':'))
    e = os.path.join(D, 'Extensions', ID)
    if os.path.exists(e):
        subprocess.run(['trash', e], check=True)
    print('EDIT done', sp_state(P))
elif cmd == 'install':
    s = Session(P, extra=['--apps-gallery-install-auto-confirm-for-tests=accept'])
    s.call('list_pages')
    s.call('navigate_page', {'pageId': 1, 'type': 'url', 'url': 'https://chromewebstore.google.com/detail/1password-%E2%80%93-password-mana/' + ID})
    time.sleep(6)
    snap = s.call('take_snapshot', {'pageId': 1})
    m = re.search(r'uid=(\S+) button "(Chrome に追加|Add to Chrome|Chrome から削除|Remove from Chrome)"', snap)
    print('button:', m and m.group(0))
    st = ''
    if m and m.group(2) in ('Chrome に追加', 'Add to Chrome'):
        s.call('click', {'pageId': 1, 'uid': m.group(1)})
        for i in range(50):
            time.sleep(3)
            st = sp_state(P)
            if 'manifest=True' in st:
                break
    time.sleep(4)
    print('install:', st, '| closed_left', s.close(), '|', sp_state(P))
elif cmd == 'check':
    assert not running(), 'running'
    b = json.load(open('%s/%s.baseline.json' % (STATE, name)))
    s = snapshot()
    print('NOW', json.dumps(s, ensure_ascii=False))
    for k in ('login_rows', 'other_ext', 'home', 'startup', 'search'):
        print('  same' if s[k] == b[k] else '  DIFF', k, b[k], '->', s[k])
    print('  cookies_valid', b['cookies_valid'], '->', s['cookies_valid'], '| login_sha same', s['login_sha'] == b['login_sha'], '| cookies_sha same', s['cookies_sha'] == b['cookies_sha'])
    print('  ext_settings_kb', b['ext_settings_kb'], '->', s['ext_settings_kb'], '| ext_idb_kb', b['ext_idb_kb'], '->', s['ext_idb_kb'])
    print('PROBE', json.dumps(page_probe(b['auth_url']), ensure_ascii=False))
