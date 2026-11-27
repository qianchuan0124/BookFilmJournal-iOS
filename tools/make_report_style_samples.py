from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = Path('/Users/luqiuyang/Desktop/report/movie_month_2026-10.html')
BOOK_SOURCE = Path('/Users/luqiuyang/Desktop/report/book_year_2026_light.html')
OUT = ROOT / 'prototype' / 'report-styles'

BASE = r'''
* { box-sizing:border-box; }
html, body { overflow-x:hidden; }
body { margin:0; line-height:1.55; font-family:-apple-system,BlinkMacSystemFont,"PingFang SC","Hiragino Sans GB",sans-serif; }
a { color:inherit; text-decoration:none; }
img { display:block; }
.wrap { margin:0 auto; padding:0 16px 48px; width:100%; max-width:390px; }
.brand { display:flex; align-items:center; gap:10px; }
.avatar { width:38px; height:38px; border-radius:50%; display:flex; align-items:center; justify-content:center; font-family:Georgia,serif; font-size:17px; }
.brand-name { font-size:14px; font-weight:600; }
.brand-line { font-size:8px; letter-spacing:.18em; text-transform:uppercase; }
.period-block { min-width:0; text-align:right; }
.big-period { white-space:nowrap; line-height:.82; letter-spacing:-.055em; font-weight:800; font-size:58px; font-variant-numeric:tabular-nums; }
.period-sub { margin:7px 0 0; font-size:10.5px; }
.kpis { display:grid; grid-template-columns:repeat(2,1fr); }
.kpi { min-width:0; padding:10px 11px 11px; border-left:1px solid var(--line); }
.kpi:nth-child(2n+1) { border-left:none; }
.kpi:nth-child(n+3) { border-top:1px solid var(--line); }
.kpi-label { display:block; font-size:8.5px; letter-spacing:.12em; color:var(--dim); text-transform:uppercase; }
.kpi-value { display:block; margin-top:3px; font-size:18px; font-weight:700; font-variant-numeric:tabular-nums; }
.kpi-value small { font-size:9px; color:var(--muted); font-weight:400; margin-left:2px; }
.kpi-sub { display:block; margin-top:2px; font-size:9px; color:var(--dim); }
.feature { margin-top:20px; }
.top-panel { min-width:0; margin-top:12px; background:var(--panel); border:1px solid var(--line); border-radius:14px; padding:13px 14px 8px; }
.panel-head { display:flex; align-items:baseline; gap:7px; margin-bottom:3px; }
.panel-head h3 { margin:0; font-size:13px; }
.panel-head .en { font-size:8px; letter-spacing:.16em; color:var(--dim); text-transform:uppercase; }
.featured-card { min-width:0; position:relative; display:grid; grid-template-columns:112px minmax(0,1fr); gap:7px 12px; padding:12px; border:1px solid rgba(229,180,95,.32); border-radius:14px; background:var(--feature); }
.featured-tag { position:static; grid-column:1/-1; justify-self:start; font-size:8.5px; letter-spacing:.12em; color:var(--gold); background:rgba(8,11,17,.62); border:1px solid rgba(229,180,95,.5); border-radius:4px; padding:2px 6px; text-transform:uppercase; }
.featured-card > a { display:block; grid-column:1; grid-row:2 / span 2; }
.featured-card > .featured-poster { grid-column:1; grid-row:2 / span 2; width:112px; }
.featured-title { grid-column:2; }
.featured-poster { width:112px; aspect-ratio:2/3; object-fit:cover; border-radius:7px; background:rgba(255,255,255,.04); }
.featured-title { grid-column:2; align-self:end; margin:0; font-size:16px; font-weight:700; line-height:1.35; }
.featured-meta { grid-column:2; display:flex; gap:5px; flex-wrap:wrap; align-items:center; font-size:9.5px; color:var(--muted); }
.featured-comment { grid-column:1/-1; margin:2px 0 0; font-size:11px; line-height:1.65; color:var(--muted); display:-webkit-box; -webkit-line-clamp:4; -webkit-box-orient:vertical; overflow:hidden; }
.top-row { min-width:0; display:grid; grid-template-columns:25px 30px minmax(0,1fr) auto; gap:8px; align-items:center; padding:8px 0; border-top:1px solid var(--line-soft); }
.top-row:first-child { border-top:none; }
.rank { font-size:15px; font-weight:800; color:var(--gold); font-variant-numeric:tabular-nums; }
.top-thumb { width:30px; height:42px; object-fit:cover; border-radius:4px; }
.top-main { min-width:0; display:flex; flex-direction:column; gap:2px; }
.top-title { font-size:11.5px; font-weight:600; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.top-meta { font-size:9px; color:var(--muted); white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.top-stars { font-size:9px; white-space:nowrap; }
.stars, .gold { color:var(--gold); }
.highlights { display:grid; grid-template-columns:1fr; gap:7px; margin-top:12px; }
.highlight { display:grid; grid-template-columns:48px minmax(0,1fr); gap:9px; padding:10px; background:var(--panel); border:1px solid var(--line); border-radius:11px; }
.highlight img { width:48px; height:68px; object-fit:cover; border-radius:4px; }
.highlight-main { min-width:0; display:flex; flex-direction:column; gap:2px; }
.highlight-kind { font-size:7.5px; letter-spacing:.12em; color:var(--gold); text-transform:uppercase; }
.highlight h4 { margin:1px 0; font-size:11.5px; line-height:1.35; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.highlight-meta { font-size:8.5px; color:var(--muted); }
.highlight p { margin:1px 0 0; font-size:9px; line-height:1.5; color:var(--muted); display:-webkit-box; -webkit-line-clamp:2; -webkit-box-orient:vertical; overflow:hidden; }
.section { margin-top:24px; }
.section-head { display:flex; align-items:baseline; gap:7px; margin-bottom:10px; }
.section-head::before { content:''; width:6px; height:6px; border-radius:2px; background:var(--gold); display:inline-block; }
.section-head h3 { margin:0; font-size:16px; font-weight:700; }
.section-head .en { font-size:8px; letter-spacing:.16em; color:var(--dim); text-transform:uppercase; }
.section-head .count { margin-left:auto; font-size:9px; color:var(--muted); }
.poster-wall-image-wrap { width:100%; overflow:hidden; background:var(--panel); border:1px solid var(--line); border-radius:13px; }
.poster-wall-image { display:block; width:100%; max-width:100%; height:auto; }
.poster-grid { display:grid; grid-template-columns:repeat(3,1fr); gap:7px; }
.poster { position:relative; overflow:hidden; border:1px solid var(--line); border-radius:7px; background:rgba(255,255,255,.035); }
.poster img { width:100%; aspect-ratio:2/3; object-fit:cover; }
.poster-caption { position:absolute; inset:auto 0 0; padding:18px 5px 5px; font-size:8px; line-height:1.35; background:linear-gradient(transparent, rgba(5,7,11,.94)); white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.poster-caption small { display:block; color:var(--muted); font-size:7px; }
.years-scroll { overflow-x:auto; }
.years-calendar { min-width:0; background:var(--panel); border:1px solid var(--line); border-radius:13px; padding:10px 9px; }
.years-head, .year-row { display:grid; grid-template-columns:52px repeat(12,minmax(0,1fr)); gap:2px; }
.years-head { padding:3px 0 6px; border-bottom:1px solid var(--line-soft); font-size:7px; color:var(--dim); text-align:center; }
.years-head span:first-child { text-align:left; }
.year-row { padding:6px 0; border-top:1px solid var(--line-soft); }
.year-label { display:flex; flex-direction:column; justify-content:center; }
.year-label b { font-size:11px; color:var(--gold); }
.year-label span { font-size:7px; color:var(--muted); }
.year-month { position:relative; min-height:48px; overflow:hidden; padding:3px; border:1px solid var(--line-soft); border-radius:5px; background:rgba(255,255,255,.015); }
.year-month.is-quiet { color:var(--dim); }
.ym-month { font-size:7px; color:var(--muted); }
.ym-count { position:absolute; top:3px; right:4px; font-size:7px; color:var(--gold); }
.ym-thumbs { position:absolute; left:3px; right:3px; bottom:3px; display:flex; gap:1px; }
.ym-thumbs img { width:13px; height:18px; object-fit:cover; border-radius:2px; opacity:.9; }
.year-calendar-block { background:var(--panel); border:1px solid var(--line); border-radius:13px; padding:10px; }
.year-calendar-head { display:flex; align-items:baseline; gap:6px; margin-bottom:8px; font-size:9px; color:var(--muted); }
.year-calendar-head b { font-size:16px; color:var(--gold); }
.year-calendar-head span { display:none; }
.year-months { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:7px; }
.mini-month { border:1px solid var(--line-soft); border-radius:7px; padding:5px; background:rgba(255,255,255,.015); overflow:hidden; }
.mini-month-head { display:flex; justify-content:space-between; align-items:baseline; margin-bottom:3px; font-size:8px; color:var(--muted); }
.mini-month-head b { font-size:9px; color:var(--text); }
.mini-month-head span { display:none; }
.mini-weekhead { display:grid; grid-template-columns:repeat(7,1fr); gap:1px; margin-bottom:2px; font-size:5.5px; color:var(--dim); text-align:center; }
.mini-grid { display:grid; grid-template-columns:repeat(7,1fr); gap:1px; }
.mini-day { position:relative; overflow:hidden; aspect-ratio:1; border-radius:2px; background:rgba(255,255,255,.02); }
.mini-day.is-blank { background:transparent; }
.mini-day.is-weekend { background:rgba(223,96,83,.06); }
.mini-day img { position:absolute; inset:0; width:100%; height:100%; object-fit:cover; opacity:.82; }
.mini-num { position:absolute; top:1px; right:2px; left:auto; z-index:2; font-size:5.5px; color:#e4e1d8; opacity:.5; text-shadow:0 1px 2px #000; }
.mini-day.is-quiet .mini-num { color:var(--dim); text-shadow:none; }
.mini-count { display:none; }
.calendar-card { background:var(--panel); border:1px solid var(--line); border-radius:13px; padding:12px 10px; }
.cal-weekhead { display:grid; grid-template-columns:repeat(7,1fr); gap:3px; margin-bottom:5px; font-size:8px; color:var(--dim); text-align:center; }
.cal-grid { display:grid; grid-template-columns:repeat(7,1fr); gap:3px; }
.cal-cell { position:relative; min-height:43px; overflow:hidden; border:1px solid var(--line); border-radius:6px; background:rgba(255,255,255,.015); }
.cal-cell.is-weekend { background:rgba(223,96,83,.045); border-color:rgba(223,96,83,.14); }
.cal-cell.is-blank { border-color:transparent; background:transparent; }
.cal-cell.is-quiet { padding:4px; }
.cal-cell.is-quiet .cal-day { position:absolute; top:3px; right:5px; left:auto; color:var(--dim); text-shadow:none; }
.cal-day { position:absolute; top:3px; right:5px; left:auto; z-index:3; font-size:8px; color:#e4e1d8; opacity:.62; text-shadow:0 1px 4px #000; }
.cal-cell.has-items .cal-day { padding:0; background:none; }
.cal-strip { position:absolute; inset:0; display:grid; grid-template-columns:repeat(var(--n),1fr); gap:1px; }
.cal-strip img { width:100%; height:100%; object-fit:cover; opacity:.92; }
.cal-cell.has-items::after { content:''; position:absolute; inset:0; z-index:1; background:linear-gradient(180deg, rgba(5,7,11,.6), transparent 42%, transparent 68%, rgba(5,7,11,.3)); }
.cal-count, .ym-count { display:none; }
.prefs { margin-top:24px; padding:16px 0 18px; border-top:1px solid var(--line); border-bottom:1px solid var(--line); }
.prefs-block + .prefs-block { margin-top:16px; }
.prefs-block h3 { margin:0 0 9px; font-size:13px; font-weight:600; }
.prefs-block h3 .en { margin-left:6px; font-size:8px; letter-spacing:.14em; color:var(--dim); text-transform:uppercase; }
.decade-bar { display:flex; height:20px; border-radius:5px; overflow:hidden; background:rgba(255,255,255,.05); margin-bottom:8px; }
.decade-seg { display:flex; align-items:center; justify-content:center; height:100%; min-width:0; }
.decade-seg em { font-style:normal; font-size:8px; font-weight:600; color:rgba(8,11,17,.82); }
.decade-legend { display:flex; flex-wrap:wrap; gap:5px 10px; }
.decade-item { display:flex; align-items:center; gap:4px; font-size:9px; color:var(--muted); }
.decade-item b { color:var(--text); font-weight:600; }
.decade-dot { width:7px; height:7px; border-radius:2px; display:inline-block; flex:none; }
.d2020 { background:var(--gold); } .d2010 { background:#d98a4a; } .d2000 { background:var(--purple); } .d1990 { background:var(--blue); } .d1980 { background:var(--teal); } .d1970 { background:#6b7a99; } .dother { background:#4b5262; }
.prefs-note { margin:7px 0 0; font-size:9px; color:var(--dim); line-height:1.5; }
.genre-tags { display:flex; flex-wrap:wrap; gap:6px 10px; }
.genre-tag { font-size:12px; font-weight:600; color:var(--gold); }
.genre-tag sup { margin-left:2px; font-size:7px; opacity:.7; vertical-align:super; }
.genre-tag.g0 { color:var(--gold); } .genre-tag.g1 { color:var(--red); } .genre-tag.g2 { color:var(--teal); } .genre-tag.g3 { color:var(--blue); } .genre-tag.g4 { color:var(--purple); } .genre-tag.g5 { color:#d98a4a; } .genre-tag.g6 { color:#7fae68; } .genre-tag.g7 { color:#c76c9a; }
.quotes-grid { display:grid; grid-template-columns:1fr; gap:9px; }
.quote-card { display:flex; flex-direction:column; gap:6px; padding:12px; background:var(--panel); border:1px solid var(--line); border-radius:11px; }
.quote-mark { font-family:Georgia,serif; font-size:26px; line-height:.55; color:var(--gold); opacity:.55; }
.quote-text { margin:0; font-size:10px; line-height:1.65; color:var(--muted); display:-webkit-box; -webkit-line-clamp:5; -webkit-box-orient:vertical; overflow:hidden; }
.quote-foot { display:grid; grid-template-columns:minmax(0,1fr) auto auto; align-items:center; gap:5px; margin-top:auto; padding-top:6px; border-top:1px solid var(--line-soft); font-size:8.5px; color:var(--muted); }
.quote-source { min-width:0; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.quote-date, .quote-stars { white-space:nowrap; }
.muted { color:var(--muted); }
.panel-empty { margin:0; font-size:10px; color:var(--dim); }
footer { margin-top:28px; padding-top:12px; border-top:1px solid var(--line); font-size:8.5px; color:var(--dim); display:flex; justify-content:space-between; gap:10px; flex-wrap:wrap; }
'''

DARK = r'''
:root { --bg:#080b11; --panel:#121722; --panel2:#151b27; --line:rgba(255,255,255,.08); --line-soft:rgba(255,255,255,.04); --text:#eae7de; --muted:#8d95a5; --dim:#5d6474; --gold:#e5b45f; --red:#df6053; --teal:#55b7a5; --blue:#5f92d8; --purple:#9d7ed8; --feature:linear-gradient(180deg, rgba(229,180,95,.08), rgba(18,23,34,.96) 46%); }
body { color:var(--text); background:radial-gradient(600px 300px at 8% -6%, rgba(229,180,95,.12), transparent 58%), radial-gradient(500px 280px at 96% -4%, rgba(223,96,83,.09), transparent 58%), var(--bg); }
.wrap { padding-top:24px; }
.hero { display:flex; flex-wrap:wrap; justify-content:space-between; align-items:flex-end; gap:10px; padding:6px 0 16px; border-bottom:1px solid var(--line); }
.avatar { width:42px; height:42px; border-radius:14px; color:#241804; font-size:20px; font-weight:700; background:linear-gradient(135deg, #F4D083, #BC7C1D); border:none; }
.brand-line { color:var(--gold); }
.big-period { color:var(--gold); font-family:Georgia,"Songti SC",serif; font-size:54px; }
.kpis { border-bottom:1px solid var(--line); }
.kpi { background:var(--panel); }
.section-head h3, .prefs-block h3 { color:var(--text); }
'''

LIGHT = r'''
:root { --bg:#f3eee3; --panel:#fffdf8; --panel2:#f7f1e5; --line:rgba(43,37,29,.11); --line-soft:rgba(43,37,29,.06); --text:#2b251d; --muted:#8a7e6c; --dim:#a89b87; --gold:#b57a22; --red:#b8483e; --teal:#2e8775; --blue:#4c7ed6; --purple:#7d62b3; --feature:linear-gradient(160deg, rgba(181,122,34,.13), rgba(255,253,248,.96) 52%); }
body { color:var(--text); background:radial-gradient(700px 360px at 8% -8%, rgba(181,122,34,.14), transparent 58%), radial-gradient(520px 300px at 96% -4%, rgba(184,72,62,.06), transparent 58%), var(--bg); }
.wrap { padding-top:24px; }
.hero { display:flex; flex-wrap:wrap; justify-content:space-between; align-items:flex-end; gap:10px; padding:6px 0 16px; border-bottom:1px solid var(--line); }
.avatar { width:42px; height:42px; border-radius:14px; color:#241804; font-size:20px; font-weight:700; background:linear-gradient(135deg, #F4D083, #BC7C1D); border:none; }
.brand-line { color:var(--gold); }
.big-period { color:var(--gold); font-family:Georgia,"Songti SC",serif; font-size:54px; }
.period-sub { max-width:190px; margin-left:auto; }
.kpis { border-top:1px solid var(--line); border-bottom:1px solid var(--line); }
.kpi { background:var(--panel); }
.kpi:nth-child(n+3) { border-top:1px solid var(--line); }
.kpi:nth-child(2n) { border-left:1px solid var(--line); }
.kpi:nth-child(n+3) { margin-top:0; }
.section-head h3, .prefs-block h3, .featured-title { font-family:Georgia,"Songti SC",serif; }
.featured-card { border-color:rgba(181,122,34,.30); }
.featured-tag { color:var(--gold); background:rgba(255,253,248,.84); border-color:rgba(181,122,34,.45); }
.featured-poster, .top-thumb, .highlight img { background:rgba(43,37,29,.05); }
.cal-day { color:#3b3024; opacity:.5; text-shadow:0 1px 3px rgba(255,255,255,.8); }
.cal-cell.has-items::after { background:linear-gradient(180deg, rgba(255,253,248,.45), transparent 38%, transparent 70%, rgba(43,37,29,.18)); }
.cal-count { display:none; }
.decade-bar { background:rgba(43,37,29,.08); }
.quote-text { color:var(--text); }
'''

COMPACT = r'''
:root { --bg:#0d1119; --panel:#151c29; --panel2:#1b2432; --line:rgba(255,255,255,.085); --line-soft:rgba(255,255,255,.045); --text:#f0eadf; --muted:#a1a7b2; --dim:#697180; --gold:#e6b45f; --red:#df6053; --teal:#55b7a5; --blue:#5f92d8; --purple:#9d7ed8; --feature:linear-gradient(135deg, rgba(230,180,95,.18), rgba(21,28,41,.98) 56%); }
body { color:var(--text); background:radial-gradient(500px 280px at 10% -4%, rgba(230,180,95,.13), transparent 60%), var(--bg); }
.wrap { padding-top:20px; }
.hero { display:flex; justify-content:space-between; align-items:center; gap:10px; padding:4px 0 12px; }
.avatar { color:var(--gold); background:#1b2432; border:1px solid rgba(230,180,95,.4); }
.brand-line { color:var(--gold); }
.big-period { color:var(--gold); font-size:50px; }
.period-sub { max-width:190px; margin-left:auto; }
.kpis { border-top:1px solid var(--line); border-bottom:1px solid var(--line); }
.kpi { padding:8px 10px; }
.kpi-label { font-size:8px; }
.kpi-value { font-size:16px; }
.kpi-sub { display:none; }
.feature { margin-top:14px; }
.featured-card { grid-template-columns:104px minmax(0,1fr); padding:10px; background:var(--feature); }
.featured-poster { width:104px; }
.featured-title { font-size:17px; }
.featured-comment { -webkit-line-clamp:3; }
.top-panel { padding-top:10px; }
.section { margin-top:20px; }
.highlights { gap:5px; }
.highlight { grid-template-columns:42px minmax(0,1fr); padding:8px; }
.highlight img { width:42px; height:60px; }
.highlight p { display:none; }
.calendar-card { padding:9px 8px; }
.cal-cell { min-height:38px; }
.prefs { margin-top:20px; }
.quote-text { -webkit-line-clamp:4; }
'''

def body_html(source, media):
    text = source.read_text()
    body = text.split('<body>', 1)[1].split('</body>', 1)[0]
    if media == 'movie':
        body = body.replace('../../cache/covers/movie_', '../assets/covers/movie-')
        body = body.replace('movie_month_2026-10_wall.jpg', './movie_month_2026-10_wall.jpg')
    else:
        body = body.replace('../../cache/covers/book_', '../assets/covers/book-')
        body = body.replace('book_year_2026_light_wall.jpg', './book_year_2026_light_wall.jpg')
    body = body.replace(' loading="lazy"', '')
    body = body.replace('整合海报', '海报墙')
    body = body.replace('<div class="avatar">我</div>', '<div class="avatar">猫</div>')
    body = body.replace('<div class="brand-name">我</div>', '<div class="brand-name">猫九</div>')
    import re
    body = re.sub(r'<p class="period-sub">.*?</p>', '', body)
    body = re.sub(r'<p class="prefs-note">共 .*?评分最高.*?</p>', '', body)
    body = re.sub(r'(<div class="decade-legend">.*?</div>)<p class="prefs-note">.*?</p>', r'\1', body, flags=re.S)
    body = re.sub(r'\s*<div class="cal-summary">.*?</div>\s*', '', body, count=1, flags=re.S)
    body = re.sub(r'<span class="cal-count">.*?</span>', '', body)
    body = re.sub(r'<span class="ym-count">.*?</span>', '', body)
    body = body.replace('<span class="kpi-label">有记录天数</span><span class="kpi-value">10 <small>天</small></span>', '<span class="kpi-label">有记录天数</span><span class="kpi-value">10 <small>天</small></span><span class="kpi-sub">10 个有记录的日子</span>')
    body = body.replace('<span class="kpi-label">总片长</span><span class="kpi-value">31 <small>小时</small> 30 <small>分</small></span>', '<span class="kpi-label">总片长</span><span class="kpi-value">31 <small>小时</small> 30 <small>分</small></span><span class="kpi-sub">14 部合计</span>')
    body = body.replace('<span class="kpi-label">总页数</span><span class="kpi-value">16,450 <small>页</small></span>', '<span class="kpi-label">总页数</span><span class="kpi-value">16,450 <small>页</small></span><span class="kpi-sub">平均每天 45.1 页</span>')
    body = body.replace('<span class="kpi-label">总字数</span><span class="kpi-value">978.2 <small>万字</small></span>', '<span class="kpi-label">总字数</span><span class="kpi-value">978.2 <small>万字</small></span><span class="kpi-sub">平均每天 26,800 字</span>')
    return body


def page(css, source, media):
    return f'''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><style>{BASE}{css}</style></head>
<body>{body_html(source, media)}</body></html>'''


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, css, source, media in [
        ('v1-noir.html', DARK, SOURCE, 'movie'),
        ('v2-paper.html', LIGHT, SOURCE, 'movie'),
        ('v3-compact.html', COMPACT, SOURCE, 'movie'),
        ('v4-book-dark.html', DARK, BOOK_SOURCE, 'book'),
        ('v5-book-light.html', LIGHT, BOOK_SOURCE, 'book'),
    ]:
        (OUT / name).write_text(page(css, source, media))
        print('wrote', OUT / name)


if __name__ == '__main__':
    main()
