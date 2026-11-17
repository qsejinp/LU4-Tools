// LU4 Tools 실행 중인 사람 세기 (Cloudflare Worker + D1)  - made by DoZ
// 프로그램이 5분마다 /ping 으로 무작위 번호를 보내면, 최근 10분 안에 보낸 번호를 "지금 실행 중"으로 셉니다.
// 저장하는 것: 무작위 번호, 프로그램 종류, 버전, 캐릭터 이름, 처음/마지막 신호 시각 (IP 등은 저장하지 않음)
// 캐릭터 이름은 /json?key=비밀키 로만 볼 수 있음(비밀키는 Cloudflare의 Secret 변수 VIEW_KEY)

const APPS = { chat: '채팅번역', meter: '사냥지표' };
const LIVE_SEC = 600;              // 10분 안에 신호가 오면 실행 중
const KST = 9 * 3600;              // 한국 시간 기준으로 "오늘"
let ready = false;

async function init(db) {
  if (ready) return;
  await db.prepare(
    'CREATE TABLE IF NOT EXISTS pings (id TEXT NOT NULL, app TEXT NOT NULL, ver TEXT, first INTEGER, last INTEGER, PRIMARY KEY (id, app))'
  ).run();
  try { await db.prepare('ALTER TABLE pings ADD COLUMN name TEXT').run(); } catch (e) { /* 이미 있음 */ }
  // 날짜별 사용 기록(한국 시간 날짜 번호): 어제/이번 주를 세기 위함
  await db.prepare('CREATE TABLE IF NOT EXISTS days (id TEXT NOT NULL, app TEXT NOT NULL, d INTEGER NOT NULL, PRIMARY KEY (id, app, d))').run();
  // 처음 한 번: 예전 기록(처음/마지막 신호 날짜)으로 채워 둠
  await db.prepare('INSERT OR IGNORE INTO days (id, app, d) SELECT id, app, CAST((last + ?1) / 86400 AS INTEGER) FROM pings').bind(KST).run();
  await db.prepare('INSERT OR IGNORE INTO days (id, app, d) SELECT id, app, CAST((first + ?1) / 86400 AS INTEGER) FROM pings').bind(KST).run();
  ready = true;
}

function esc(s) { return String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c])); }

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    const now = Math.floor(Date.now() / 1000);
    await init(env.DB);

    // 프로그램이 보내는 신호
    if (url.pathname === '/ping') {
      const id = url.searchParams.get('id') || '';
      const app = url.searchParams.get('app') || '';
      const ver = url.searchParams.get('v') || '';
      let name = (url.searchParams.get('n') || '').trim();
      if (!/^[A-Za-z0-9_\uAC00-\uD7A3]{2,24}$/.test(name)) name = '';
      if (!/^[a-f0-9]{16,40}$/.test(id) || !(app in APPS) || (ver && !/^\d{8}\.\d{4}$/.test(ver))) {
        return new Response('bad', { status: 400 });
      }
      await env.DB.prepare(
        'INSERT INTO pings (id, app, ver, first, last, name) VALUES (?1, ?2, ?3, ?4, ?4, ?5) ' +
        "ON CONFLICT (id, app) DO UPDATE SET ver = ?3, last = ?4, name = CASE WHEN ?5 <> '' THEN ?5 ELSE name END"
      ).bind(id, app, ver, now, name).run();
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
    // 캐릭터 이름 목록: 비밀키가 맞을 때만
    const key = url.searchParams.get('key') || '';
    if (env.VIEW_KEY && key === env.VIEW_KEY) {
      const us = await q("SELECT id, MAX(COALESCE(name, '')) name, GROUP_CONCAT(app) apps, MAX(last) last FROM pings WHERE last >= ?1 GROUP BY id ORDER BY name", now - LIVE_SEC);
      data.users = us.map(u => ({ name: u.name || '(이름 확인 전)', apps: String(u.apps || '').split(',').filter(a => a in APPS), ago: now - u.last }));
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
<p class="sub">지금 = 최근 10분 안에 신호가 온 PC · 오늘/어제/이번 주(월요일부터) = 한국 시간 기준 · 1분마다 자동 새로고침</p>
<p class="sub">실행 중인 버전</p><ul>${vrows}</ul>
<p class="sub">made by DoZ</p></body></html>`;
    return new Response(html, { headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' } });
  }
};
