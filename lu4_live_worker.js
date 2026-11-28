// LU4 Tools 실행 중인 사람 세기 (Cloudflare Worker + D1)  - made by DoZ
// 프로그램이 5분마다 /ping 으로 무작위 번호를 보내면, 최근 10분 안에 보낸 번호를 "지금 실행 중"으로 셉니다.
// 저장하는 것: 무작위 번호, 프로그램 종류, 버전, 캐릭터 이름(게임 창을 여러 개 켜면 여러 개), 그 PC에서 쓴 이름 기록, 처음/마지막 신호 시각,
//   같은 집(같은 인터넷) PC를 묶기 위한 '집 구분 번호'(접속 주소를 비밀키와 섞어 되돌릴 수 없게 바꾼 12글자. 접속 주소(IP) 자체는 저장하지 않음)
// 캐릭터 이름은 /json?key=비밀키 로만 볼 수 있음(비밀키는 Cloudflare의 Secret 변수 VIEW_KEY)

const APPS = { chat: '채팅번역', meter: '사냥지표', patch: '한글패치' };
const LIVE_SEC = 600;              // 10분 안에 신호가 오면 실행 중
const KST = 9 * 3600;              // 한국 시간 기준으로 "오늘"
let ready = false;

async function init(db) {
  if (ready) return;
  await db.prepare(
    'CREATE TABLE IF NOT EXISTS pings (id TEXT NOT NULL, app TEXT NOT NULL, ver TEXT, first INTEGER, last INTEGER, PRIMARY KEY (id, app))'
  ).run();
  try { await db.prepare('ALTER TABLE pings ADD COLUMN name TEXT').run(); } catch (e) { /* 이미 있음 */ }
  // 한글패치 프로그램이 알려 주는 게임 버전(gv)과, 올려 둔 패치가 맞는 게임 버전(pv)
  try { await db.prepare('ALTER TABLE pings ADD COLUMN gv INTEGER').run(); } catch (e) { /* 이미 있음 */ }
  try { await db.prepare('ALTER TABLE pings ADD COLUMN pv INTEGER').run(); } catch (e) { /* 이미 있음 */ }
  // 날짜별 사용 기록(한국 시간 날짜 번호): 어제/이번 주를 세기 위함
  await db.prepare('CREATE TABLE IF NOT EXISTS days (id TEXT NOT NULL, app TEXT NOT NULL, d INTEGER NOT NULL, PRIMARY KEY (id, app, d))').run();
  // 처음 한 번: 예전 기록(처음/마지막 신호 날짜)으로 채워 둠
  await db.prepare('INSERT OR IGNORE INTO days (id, app, d) SELECT id, app, CAST((last + ?1) / 86400 AS INTEGER) FROM pings').bind(KST).run();
  await db.prepare('INSERT OR IGNORE INTO days (id, app, d) SELECT id, app, CAST((first + ?1) / 86400 AS INTEGER) FROM pings').bind(KST).run();
  // 차단한 PC(고유 번호): 한글패치를 새로 받거나 다시 넣지 못하게
  await db.prepare('CREATE TABLE IF NOT EXISTS blocks (id TEXT PRIMARY KEY, t INTEGER)').run();
  // 같은 집 묶기용 구분 번호 / PC별로 쓴 캐릭터 이름 기록
  try { await db.prepare('ALTER TABLE pings ADD COLUMN net TEXT').run(); } catch (e) { /* 이미 있음 */ }
  await db.prepare('CREATE TABLE IF NOT EXISTS names (id TEXT NOT NULL, name TEXT NOT NULL, last INTEGER, PRIMARY KEY (id, name))').run();
  ready = true;
}

// 개인 상점 글자(Private Store - Sell 등)를 이름으로 잘못 읽은 것
const NOT_NAME = /privat|store|packag|^(sell|buy|sale)$/i;
const NAME_RE = /^[A-Za-z0-9_\uAC00-\uD7A3]{2,24}$/;
const HIST_SEC = 30 * 86400;       // PC별 이름 기록은 30일 동안 보여 줌
async function netCode(req, env) {
  const ip = req.headers.get('CF-Connecting-IP') || '';
  if (!ip) return '';
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(ip + '|' + (env.VIEW_KEY || 'lu4-live')));
  return [...new Uint8Array(buf)].slice(0, 6).map(b => b.toString(16).padStart(2, '0')).join('');
}

function esc(s) { return String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c])); }

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    const now = Math.floor(Date.now() / 1000);
    await init(env.DB);

    const isBlocked = async id => !!(await env.DB.prepare('SELECT 1 x FROM blocks WHERE id = ?1').bind(id).first());
    // 프로그램이 "이 PC가 차단됐는지" 물어봄
    if (url.pathname === '/check') {
      const id = url.searchParams.get('id') || '';
      const b = /^[a-f0-9]{16,40}$/.test(id) && await isBlocked(id);
      return new Response(b ? 'blocked' : 'ok', { headers: { 'cache-control': 'no-store' } });
    }
    // 차단/해제 (비밀키 필요): /block?key=…&id=…&on=1 또는 0
    if (url.pathname === '/block') {
      const id = url.searchParams.get('id') || '';
      if (!env.VIEW_KEY || url.searchParams.get('key') !== env.VIEW_KEY || !/^[a-f0-9]{16,40}$/.test(id)) return new Response('no', { status: 403 });
      if (url.searchParams.get('on') === '0') await env.DB.prepare('DELETE FROM blocks WHERE id = ?1').bind(id).run();
      else await env.DB.prepare('INSERT OR REPLACE INTO blocks (id, t) VALUES (?1, ?2)').bind(id, now).run();
      return new Response('ok', { headers: { 'cache-control': 'no-store' } });
    }
    // 프로그램이 보내는 신호
    if (url.pathname === '/ping') {
      const id = url.searchParams.get('id') || '';
      const app = url.searchParams.get('app') || '';
      const ver = url.searchParams.get('v') || '';
      let name = (url.searchParams.get('n') || '').trim();
      if (!NAME_RE.test(name) || NOT_NAME.test(name)) name = '';
      // 게임 창을 여러 개 켠 PC: ns=이름1,이름2 (최대 4개) -> "이름1, 이름2"로 저장
      const names = (url.searchParams.get('ns') || '').split(',').map(x => x.trim()).filter(x => NAME_RE.test(x) && !NOT_NAME.test(x)).slice(0, 4);
      if (names.length > 1) name = names.join(', ');
      else if (names.length === 1 && !name) name = names[0];
      const num = k => { const v = url.searchParams.get(k) || ''; return /^\d{1,6}$/.test(v) ? parseInt(v, 10) : 0; };
      const gv = num('g'), pv = num('pg');
      if (!/^[a-f0-9]{16,40}$/.test(id) || !(app in APPS) || (ver && !/^\d{8}\.\d{4}$/.test(ver))) {
        return new Response('bad', { status: 400 });
      }
      await env.DB.prepare(
        'INSERT INTO pings (id, app, ver, first, last, name, gv, pv) VALUES (?1, ?2, ?3, ?4, ?4, ?5, ?6, ?7) ' +
        "ON CONFLICT (id, app) DO UPDATE SET ver = ?3, last = ?4, name = CASE WHEN ?5 <> '' THEN ?5 ELSE name END, gv = CASE WHEN ?6 > 0 THEN ?6 ELSE gv END, pv = CASE WHEN ?7 > 0 THEN ?7 ELSE pv END"
      ).bind(id, app, ver, now, name, gv, pv).run();
      try {
        const net = await netCode(req, env);
        if (net) await env.DB.prepare('UPDATE pings SET net = ?1 WHERE id = ?2').bind(net, id).run();
        for (const nm of (name ? name.split(', ') : [])) await env.DB.prepare('INSERT INTO names (id, name, last) VALUES (?1, ?2, ?3) ON CONFLICT (id, name) DO UPDATE SET last = ?3').bind(id, nm, now).run();
      } catch (e) { /* 기록 실패는 무시 */ }
      await env.DB.prepare('INSERT OR IGNORE INTO days (id, app, d) VALUES (?1, ?2, ?3)').bind(id, app, Math.floor((now + KST) / 86400)).run();
      return new Response('ok', { headers: { 'cache-control': 'no-store' } });
    }

    // 숫자만 (JSON)
    const dToday = Math.floor((now + KST) / 86400);
    const dWeek = dToday - ((dToday + 3) % 7);   // 이번 주 월요일(한국 시간)
    const q = async (sql, ...a) => (await env.DB.prepare(sql).bind(...a).all()).results;
    const live = await q('SELECT app, COUNT(*) n FROM pings WHERE last >= ?1 GROUP BY app', now - LIVE_SEC);
    const today = await q('SELECT app, COUNT(*) n FROM days WHERE d = ?1 GROUP BY app', dToday);
    const yday = await q('SELECT app, COUNT(*) n FROM days WHERE d = ?1 GROUP BY app', dToday - 1);
    const week = await q('SELECT app, COUNT(DISTINCT id) n FROM days WHERE d >= ?1 GROUP BY app', dWeek);
    const total = await q('SELECT app, COUNT(*) n FROM pings GROUP BY app');
    const people = await q('SELECT COUNT(DISTINCT id) n FROM pings WHERE last >= ?1', now - LIVE_SEC);
    const vers = await q('SELECT app, ver, COUNT(*) n FROM pings WHERE last >= ?1 GROUP BY app, ver ORDER BY ver DESC', now - LIVE_SEC);
    const pick = (rows, app) => (rows.find(r => r.app === app) || { n: 0 }).n;
    const data = {};
    for (const a in APPS) data[a] = { live: pick(live, a), today: pick(today, a), yday: pick(yday, a), week: pick(week, a), total: pick(total, a) };
    data.livePeople = people[0] ? people[0].n : 0;
    // 게임 버전: 최근 7일 동안 한글패치 프로그램이 알려 준 값 중 가장 높은 것 / 올려 둔 패치가 맞는 게임 버전
    const gm = await q("SELECT MAX(gv) g, MAX(pv) p FROM pings WHERE app = 'patch' AND last >= ?1", now - 7 * 86400);
    data.game = { ver: (gm[0] && gm[0].g) || 0, patchFor: (gm[0] && gm[0].p) || 0 };
    data.game.updated = data.game.ver > 0 && data.game.patchFor > 0 && data.game.ver !== data.game.patchFor;
    // 캐릭터 이름 목록: 비밀키가 맞을 때만
    const key = url.searchParams.get('key') || '';
    if (env.VIEW_KEY && key === env.VIEW_KEY) {
      // 같은 PC가 프로그램마다 이름을 따로 보냄 -> 가장 긴 것(여러 캐릭터가 적힌 것)을 씀
      const us = (await q("SELECT id, GROUP_CONCAT(COALESCE(name, ''), '|') names, GROUP_CONCAT(app) apps, MAX(last) last, MAX(COALESCE(net, '')) net FROM pings WHERE last >= ?1 GROUP BY id", now - LIVE_SEC))
        .map(u => ({ ...u, name: String(u.names || '').split('|').sort((x, y) => y.length - x.length)[0] || '' }))
        .sort((x, y) => x.name.localeCompare(y.name));
      const bl = await q("SELECT b.id id, COALESCE((SELECT MAX(COALESCE(p.name, '')) FROM pings p WHERE p.id = b.id), '') name FROM blocks b ORDER BY b.t");
      const bset = new Set(bl.map(b => b.id));
      // PC별로 예전에 쓴 이름(최근 30일, 지금 쓰는 이름 제외, 최근 순 8개까지)
      const hs = await q('SELECT id, name FROM names WHERE last >= ?1 ORDER BY last DESC', now - HIST_SEC);
      const hist = {};
      for (const h of hs) { if (NOT_NAME.test(h.name)) continue; (hist[h.id] = hist[h.id] || []).push(h.name); }
      data.users = us.map(u => {
        const cur = String(u.name || '').split(', ').filter(x => x && !NOT_NAME.test(x));
        const low = new Set(cur.map(x => x.toLowerCase()));
        return { id: u.id, name: cur.join(', ') || '(이름 확인 전)', on: cur, past: (hist[u.id] || []).filter(x => !low.has(x.toLowerCase())).slice(0, 8),
          net: u.net || '', apps: String(u.apps || '').split(',').filter(a => a in APPS), ago: now - u.last, blocked: bset.has(u.id) };
      });
      data.blocked = bl.map(b => ({ id: b.id, name: b.name || '(이름 확인 전)' }));
    }

    if (url.pathname === '/json') {
      return new Response(JSON.stringify(data), { headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } });
    }

    // 보기 좋은 페이지 (1분마다 새로고침)
    const rows = Object.keys(APPS).map(a =>
      `<tr><td>${APPS[a]}</td><td class="big">${data[a].live}</td><td>${data[a].today}</td><td>${data[a].yday}</td><td>${data[a].week}</td><td>${data[a].total}</td></tr>`).join('');
    const vrows = vers.map(v => `<li>${esc(APPS[v.app] || v.app)} ${esc(v.ver || '?')} : ${v.n}명</li>`).join('') || '<li>없음</li>';
    const html = `<!DOCTYPE html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="60"><title>LU4 Tools 사용자</title>
<style>body{font-family:system-ui,'Malgun Gothic',sans-serif;background:#16181d;color:#e8e8e8;max-width:560px;margin:24px auto;padding:0 16px}
h1{font-size:20px}table{width:100%;border-collapse:collapse;margin:12px 0}td,th{padding:10px;border-bottom:1px solid #333;text-align:center}
th{color:#aaa;font-weight:normal;font-size:13px}td:first-child{text-align:left}.big{font-size:26px;font-weight:bold;color:#6fd36f}
.sub{color:#999;font-size:13px}ul{color:#bbb;font-size:14px}</style></head><body>
<h1>LU4 Tools 사용 현황</h1>
<p>지금 실행 중인 사람: <b style="font-size:22px;color:#6fd36f">${data.livePeople}명</b> <span class="sub">(두 프로그램 합쳐서, 같은 PC는 1명)</span></p>
<table><tr><th>프로그램</th><th>지금</th><th>오늘</th><th>어제</th><th>이번 주</th><th>전체</th></tr>${rows}</table>
${data.game.ver ? `<p class="sub" style="${data.game.updated ? 'color:#ff7a6a;font-weight:bold' : ''}">${data.game.updated ? '게임이 업데이트됨! ' : ''}게임 버전 ${data.game.ver} · 한글패치는 ${data.game.patchFor || '?'}용</p>` : ''}
<p class="sub">지금 = 최근 10분 안에 신호가 온 PC · 오늘/어제/이번 주(월요일부터) = 한국 시간 기준 · 1분마다 자동 새로고침</p>
<p class="sub">실행 중인 버전</p><ul>${vrows}</ul>
<p class="sub">made by DoZ</p></body></html>`;
    return new Response(html, { headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' } });
  }
};
