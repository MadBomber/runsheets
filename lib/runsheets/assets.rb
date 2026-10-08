# frozen_string_literal: true

module Runsheets
  # Inline CSS and JavaScript for the pages. Kept as strings so the gem has
  # no static file handling and a page is one self-contained response.
  module Assets
    def self.stylesheet = @stylesheet ||= CSS + Renderer.code_stylesheet
    def self.javascript = JS

    CSS = <<~'CSS'
      :root {
        --bg: #0e1117; --panel: #151a23; --panel-2: #1b2130; --border: #273040;
        --text: #d9dee8; --muted: #8b95a8; --accent: #5ab0ff; --accent-2: #a78bfa;
        --ok: #3ddc97; --warn: #ffb454; --danger: #ff6b6b; --mark: #3b3200;
        --header-h: 56px; --sidebar-w: 300px; --radius: 10px;
        --font: -apple-system, BlinkMacSystemFont, "Segoe UI", Inter, Roboto, Helvetica, Arial, sans-serif;
        --mono: ui-monospace, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;
      }
      * { box-sizing: border-box; }
      html, body { margin: 0; background: var(--bg); color: var(--text); font: 15px/1.6 var(--font); }
      a { color: var(--accent); text-decoration: none; }
      a:hover { text-decoration: underline; }
      svg.icon { width: 1.1em; height: 1.1em; fill: none; stroke: currentColor; stroke-width: 1.8; stroke-linecap: round; stroke-linejoin: round; flex: none; vertical-align: -0.2em; }
      button { font: inherit; }

      /* ---------- header ---------- */
      .rs-header {
        position: sticky; top: 0; z-index: 20; height: var(--header-h);
        display: grid; grid-template-columns: auto 1fr auto; align-items: center; gap: 18px;
        padding: 0 16px; background: linear-gradient(180deg, #1a2130 0%, #121722 100%);
        border-bottom: 1px solid var(--border); box-shadow: 0 1px 0 rgba(255,255,255,.03), 0 6px 20px rgba(0,0,0,.35);
      }
      .rs-header::before { content: ""; position: absolute; left: 0; right: 0; top: 0; height: 3px; background: linear-gradient(90deg, var(--accent), var(--accent-2), var(--ok)); }
      .brand { display: flex; align-items: center; gap: 6px; }
      .brand .home { display: flex; align-items: center; gap: 9px; padding: 6px 12px 6px 8px; border-radius: 999px; color: var(--text); font-weight: 600; letter-spacing: .3px; background: rgba(90,176,255,.10); border: 1px solid rgba(90,176,255,.25); }
      .brand .home:hover { text-decoration: none; background: rgba(90,176,255,.22); border-color: var(--accent); }
      .brand .home svg { width: 1.3em; height: 1.3em; color: var(--accent); }
      .brand-name { font-weight: 800; background: linear-gradient(90deg, var(--accent), var(--accent-2)); -webkit-background-clip: text; background-clip: text; color: transparent; }
      .brand-tag { color: var(--muted); font-weight: 500; font-size: 12px; max-width: 32vw; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
      .icon-btn { display: inline-flex; align-items: center; justify-content: center; width: 34px; height: 34px; border-radius: 8px; border: 1px solid transparent; background: transparent; color: var(--muted); cursor: pointer; }
      .icon-btn:hover { color: var(--text); background: var(--panel-2); border-color: var(--border); }
      .crumbs { display: flex; align-items: center; gap: 6px; min-width: 0; overflow: hidden; white-space: nowrap; font-size: 14px; }
      .crumbs a, .crumbs .current { padding: 3px 8px; border-radius: 6px; }
      .crumbs a { color: var(--muted); }
      .crumbs a:hover { color: var(--text); background: var(--panel-2); text-decoration: none; }
      .crumbs .current { color: var(--text); font-weight: 600; background: var(--panel-2); overflow: hidden; text-overflow: ellipsis; }
      .crumbs .sep { color: #3d4759; }
      .actions { display: flex; align-items: center; gap: 6px; }
      .nav-btn { display: inline-flex; align-items: center; gap: 6px; padding: 6px 10px; border-radius: 8px; font-size: 13px; color: var(--text); border: 1px solid var(--border); background: var(--panel); cursor: pointer; }
      .nav-btn:hover { text-decoration: none; background: var(--panel-2); border-color: var(--accent); }
      .nav-btn.disabled { opacity: .35; cursor: default; }
      .run-pill { display: inline-flex; align-items: center; gap: 8px; margin-left: 8px; padding: 5px 12px; border-radius: 999px; font: 600 12px var(--mono); border: 1px solid var(--border); color: var(--muted); background: var(--panel); }
      .run-pill.active { color: var(--ok); border-color: rgba(61,220,151,.4); background: rgba(61,220,151,.08); }
      .run-pill .dot { width: 8px; height: 8px; border-radius: 50%; background: currentColor; }
      .run-pill.active .dot { animation: pulse 1.6s infinite; }
      @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: .3; } }

      /* ---------- shell ---------- */
      .rs-shell { display: grid; grid-template-columns: var(--sidebar-w) 1fr; min-height: calc(100vh - var(--header-h) - 40px); }
      body.no-sidebar .rs-shell { grid-template-columns: 1fr; }
      body.no-sidebar .rs-sidebar { display: none; }
      .rs-sidebar { position: sticky; top: var(--header-h); align-self: start; height: calc(100vh - var(--header-h)); overflow: auto; padding: 18px 12px 24px; border-right: 1px solid var(--border); background: var(--panel); font-size: 13.5px; }
      .rs-sidebar h2 { display: flex; align-items: center; gap: 6px; margin: 0 8px 8px; font-size: 11px; font-weight: 700; letter-spacing: .12em; text-transform: uppercase; color: var(--muted); }
      .rs-sidebar section + section { margin-top: 22px; padding-top: 18px; border-top: 1px solid var(--border); }
      .rs-sidebar ol, .rs-sidebar ul { list-style: none; margin: 0; padding: 0; }
      .rs-sidebar li a { display: grid; grid-template-columns: 1.6em 1fr auto; align-items: center; gap: 8px; padding: 5px 8px; border-radius: 6px; color: var(--text); }
      .rs-sidebar li a:hover { background: var(--panel-2); text-decoration: none; }
      .rs-sidebar li.active > a { background: rgba(90,176,255,.14); color: #fff; box-shadow: inset 3px 0 0 var(--accent); }
      .rs-sidebar .num { color: var(--muted); font: 600 11px var(--mono); }
      .rs-sidebar .name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
      .rs-sidebar .mark { font: 700 11px var(--mono); }
      .mark.done { color: var(--ok); } .mark.skipped { color: var(--warn); } .mark.failed { color: var(--danger); } .mark.ran { color: var(--accent); } .mark.pending { color: var(--border); }
      .rs-sidebar details { margin: 0 8px; }
      .rs-sidebar summary { cursor: pointer; color: var(--warn); font-weight: 600; }
      .rs-sidebar .rollback-body { font-size: 13px; color: var(--muted); max-height: 40vh; overflow: auto; padding: 6px 0; }
      .rs-sidebar .rollback-body pre { font-size: 11.5px; }
      #outline a { grid-template-columns: 1fr; color: var(--muted); }
      #outline a.h3 { padding-left: 24px; font-size: 12.5px; }
      #outline li.active a { color: var(--text); background: var(--panel-2); }

      .rs-main { min-width: 0; padding: 32px 40px 64px; }
      .rs-footer { display: flex; justify-content: space-between; align-items: center; gap: 12px; padding: 10px 16px; border-top: 1px solid var(--border); color: var(--muted); font-size: 12px; background: var(--panel); }
      kbd { display: inline-block; min-width: 1.4em; margin: 0 2px; padding: 0 5px; border-radius: 4px; border: 1px solid var(--border); background: var(--panel-2); font: 11px var(--mono); text-align: center; color: var(--text); }

      /* ---------- landing + step chrome ---------- */
      .page-head h1 { display: flex; align-items: center; gap: 12px; margin: 0 0 6px; font-size: 28px; line-height: 1.2; }
      .page-head .sub { color: var(--muted); margin: 0 0 18px; }
      .badges { display: flex; flex-wrap: wrap; gap: 6px; margin: 0 0 16px; }
      .badge { padding: 2px 9px; border-radius: 999px; font: 600 11px var(--mono); text-transform: uppercase; letter-spacing: .05em; background: rgba(139,149,168,.14); color: var(--muted); }
      .badge.automated { color: var(--accent); background: rgba(90,176,255,.12); }
      .badge.manual { color: var(--warn); background: rgba(255,180,84,.12); }
      .badge.verify { color: var(--accent-2); background: rgba(167,139,250,.14); }
      .badge.destructive { color: var(--danger); background: rgba(255,107,107,.14); }
      .badge.tag { text-transform: none; }
      .meta-table { border-collapse: collapse; margin: 0 0 24px; width: 100%; max-width: 900px; }
      .meta-table th { text-align: left; vertical-align: top; width: 150px; padding: 8px 12px 8px 0; color: var(--muted); font-weight: 600; font-size: 13px; }
      .meta-table td { padding: 8px 0; border-top: 1px solid var(--border); }
      .meta-table tr:first-child td, .meta-table tr:first-child th { border-top: 0; }
      .meta-table th { border-top: 1px solid var(--border); }
      .meta-table ul { margin: 0; padding-left: 1.2em; }
      .banner { display: flex; gap: 12px; align-items: flex-start; padding: 12px 16px; margin: 0 0 20px; border-radius: var(--radius); border: 1px solid; }
      .banner svg { margin-top: 3px; }
      .banner.danger { border-color: rgba(255,107,107,.45); background: rgba(255,107,107,.08); color: #ffd3d3; }
      .banner.warn { border-color: rgba(255,180,84,.45); background: rgba(255,180,84,.08); color: #ffe3b8; }
      .banner.info { border-color: rgba(90,176,255,.35); background: rgba(90,176,255,.07); }
      .banner ul { margin: 4px 0 0; padding-left: 1.2em; }
      .panel { padding: 18px 20px; margin: 0 0 24px; border-radius: var(--radius); border: 1px solid var(--border); background: var(--panel); max-width: 900px; }
      .panel h2 { margin: 0 0 12px; font-size: 13px; letter-spacing: .12em; text-transform: uppercase; color: var(--muted); }
      .panel form { display: flex; flex-direction: column; gap: 12px; }
      .field { display: grid; grid-template-columns: 220px 1fr; gap: 12px; align-items: center; }
      .field label { font-weight: 600; font-size: 14px; }
      .field label code { display: block; font: 12px var(--mono); color: var(--muted); font-weight: 400; }
      .field input[type=text], .field input[type=password], .field textarea, .field select { width: 100%; padding: 8px 10px; border-radius: 8px; border: 1px solid var(--border); background: var(--bg); color: var(--text); font: inherit; outline: 0; }
      .field input:focus, .field textarea:focus { border-color: var(--accent); }
      .btn { display: inline-flex; align-items: center; gap: 8px; padding: 8px 16px; border-radius: 8px; border: 1px solid var(--border); background: var(--panel-2); color: var(--text); font-weight: 600; cursor: pointer; }
      .btn:hover { border-color: var(--accent); }
      .btn.primary { background: rgba(90,176,255,.18); border-color: var(--accent); }
      .btn.ok { background: rgba(61,220,151,.14); border-color: rgba(61,220,151,.5); }
      .btn.danger { background: rgba(255,107,107,.12); border-color: rgba(255,107,107,.5); }
      .btn-row { display: flex; gap: 10px; flex-wrap: wrap; align-items: center; }
      .steps-list { list-style: none; margin: 0 0 24px; padding: 0; border: 1px solid var(--border); border-radius: var(--radius); overflow: hidden; background: var(--panel); max-width: 900px; }
      .steps-list li { display: grid; grid-template-columns: 3em 1fr auto auto; align-items: center; gap: 14px; padding: 10px 16px; border-top: 1px solid var(--border); }
      .steps-list li:first-child { border-top: 0; }
      .steps-list li:hover { background: var(--panel-2); }
      .steps-list .num { color: var(--muted); font: 600 12px var(--mono); }
      .steps-list .title { color: var(--text); font-weight: 600; }
      .steps-list .title small { display: block; color: var(--muted); font-weight: 400; font-size: 12px; }
      .history { list-style: none; margin: 0; padding: 0; }
      .history li { display: grid; grid-template-columns: 1fr auto auto auto; gap: 16px; padding: 8px 0; border-top: 1px solid var(--border); font-size: 13.5px; align-items: center; }
      .history li:first-child { border-top: 0; }
      .history .meta { color: var(--muted); font: 12px var(--mono); }
      .empty { color: var(--muted); font-style: italic; }
      .step-nav { display: flex; justify-content: space-between; gap: 12px; margin-top: 36px; padding-top: 20px; border-top: 1px solid var(--border); }

      /* ---------- markdown ---------- */
      .markdown-body { max-width: 900px; font-size: 16px; }
      .markdown-body h1, .markdown-body h2, .markdown-body h3, .markdown-body h4 { scroll-margin-top: calc(var(--header-h) + 16px); line-height: 1.25; margin: 1.6em 0 .6em; }
      .markdown-body h1 { margin-top: 0; font-size: 1.8em; padding-bottom: .3em; border-bottom: 1px solid var(--border); }
      .markdown-body h2 { font-size: 1.4em; padding-bottom: .25em; border-bottom: 1px solid var(--border); }
      .markdown-body h3 { font-size: 1.15em; }
      .markdown-body p, .markdown-body ul, .markdown-body ol { margin: 0 0 1em; }
      .markdown-body li + li { margin-top: .25em; }
      .markdown-body code { font: 85% var(--mono); background: var(--panel-2); padding: .15em .4em; border-radius: 5px; }
      .markdown-body pre { margin: 0; padding: 14px 16px; border-radius: var(--radius); border: 1px solid var(--border); overflow: auto; line-height: 1.5; }
      .markdown-body pre code { background: none; padding: 0; font-size: 13.5px; }
      .markdown-body .highlight { background: #0b0e14 !important; }
      .markdown-body > pre, .markdown-body > .highlighter-rouge, .markdown-body li > pre, .markdown-body li > .highlighter-rouge { margin: 0 0 1em; }
      .markdown-body blockquote { margin: 0 0 1em; padding: .4em 1em; border-left: 4px solid var(--accent-2); background: var(--panel); color: var(--muted); border-radius: 0 8px 8px 0; }
      .markdown-body table { border-collapse: collapse; margin: 0 0 1em; display: block; overflow: auto; }
      .markdown-body th, .markdown-body td { padding: 6px 12px; border: 1px solid var(--border); }
      .markdown-body th { background: var(--panel-2); text-align: left; }
      .markdown-body img { max-width: 100%; height: auto; }
      .markdown-body hr { border: 0; border-top: 1px solid var(--border); margin: 2em 0; }

      /* ---------- executable blocks ---------- */
      .rs-block { margin: 0 0 1.2em; border-radius: var(--radius); border: 1px solid var(--border); background: var(--panel); overflow: hidden; }
      .rs-block > pre, .rs-block > .highlighter-rouge { margin: 0; }
      .rs-block .highlighter-rouge > .highlight > pre, .rs-block > pre { border: 0; border-radius: 0; }
      .rs-executable { border-color: rgba(90,176,255,.35); }
      .rs-destructive { border-color: rgba(255,107,107,.45); }
      .rs-block.rs-ok { border-color: rgba(61,220,151,.5); }
      .rs-block.rs-failed { border-color: var(--danger); }
      .rs-toolbar { display: flex; align-items: center; gap: 8px; padding: 6px 10px; border-bottom: 1px solid var(--border); background: var(--panel-2); font-size: 12px; flex-wrap: wrap; }
      .rs-spacer { flex: 1; }
      .rs-badge { padding: 1px 8px; border-radius: 999px; font: 600 11px var(--mono); letter-spacing: .04em; background: rgba(139,149,168,.14); color: var(--muted); }
      .rs-badge.rs-run { color: var(--accent); background: rgba(90,176,255,.12); }
      .rs-badge.rs-destructive { color: var(--danger); background: rgba(255,107,107,.14); }
      .rs-badge.rs-terminal { color: var(--warn); background: rgba(255,180,84,.14); }
      .rs-badge.rs-expect { color: var(--accent-2); background: rgba(167,139,250,.14); }
      .rs-badge.rs-background { color: var(--ok); background: rgba(61,220,151,.12); }
      .rs-note { color: var(--muted); font-style: italic; }
      .rs-warning { color: var(--warn); font-weight: 600; }
      .rs-warning::before { content: "⚠ "; }
      .rs-btn { padding: 3px 10px; border-radius: 6px; border: 1px solid var(--border); background: var(--panel); color: var(--text); font-size: 12px; font-weight: 600; cursor: pointer; }
      .rs-btn:hover { border-color: var(--accent); }
      .rs-btn:disabled { opacity: .5; cursor: progress; }
      .rs-run { background: rgba(90,176,255,.18); border-color: var(--accent); }
      .rs-run.rs-danger { background: rgba(255,107,107,.14); border-color: var(--danger); }
      .rs-status { font: 600 12px var(--mono); color: var(--muted); min-width: 6em; text-align: right; }
      .rs-status.ok { color: var(--ok); } .rs-status.failed { color: var(--danger); } .rs-status.running { color: var(--accent); }
      .rs-result { border-top: 1px solid var(--border); background: #0b0e14; }
      .rs-output { margin: 0; padding: 12px 16px; max-height: 420px; overflow: auto; font: 12.5px/1.5 var(--mono); color: #c9d1d9; white-space: pre-wrap; word-break: break-word; border: 0 !important; border-radius: 0 !important; }
      .rs-output:empty::before { content: "(no output)"; color: var(--muted); font-style: italic; }
      .rs-exit { padding: 6px 16px; border-top: 1px solid var(--border); font: 11.5px var(--mono); color: var(--muted); }

      @media (max-width: 900px) {
        .rs-header { grid-template-columns: auto 1fr; height: auto; padding: 8px 12px; row-gap: 6px; }
        .brand-tag, .nav-btn span { display: none; }
        .actions { grid-column: 1 / -1; flex-wrap: wrap; }
        .rs-shell { grid-template-columns: 1fr; }
        .rs-sidebar { position: static; height: auto; max-height: none; border-right: 0; border-bottom: 1px solid var(--border); }
        .rs-main { padding: 20px 16px 48px; }
        .rs-footer .keys { display: none; }
        .field { grid-template-columns: 1fr; }
      }
    CSS

    JS = <<~'JS'
      (() => {
        const body  = document.body;
        const token = document.querySelector('meta[name="rs-token"]')?.content || '';
        const LS    = 'runsheets.sidebar';
        const fmt   = s => (s == null ? '' : s < 10 ? s.toFixed(2) + 's' : Math.round(s) + 's');

        // Sidebar toggle (remembered across pages).
        try { if (localStorage.getItem(LS) === 'off') body.classList.add('no-sidebar'); } catch (e) {}
        const toggleSidebar = () => {
          body.classList.toggle('no-sidebar');
          try { localStorage.setItem(LS, body.classList.contains('no-sidebar') ? 'off' : 'on'); } catch (e) {}
        };
        document.querySelector('.sidebar-toggle')?.addEventListener('click', toggleSidebar);

        // "On this page" outline.
        const outline = document.getElementById('outline');
        if (outline) {
          const heads = [...document.querySelectorAll('.markdown-body :is(h2,h3)[id]')];
          if (heads.length === 0) outline.closest('section')?.remove();
          heads.forEach(h => {
            const li = document.createElement('li');
            const a  = document.createElement('a');
            a.href = '#' + h.id; a.textContent = h.textContent; a.className = h.tagName.toLowerCase();
            li.appendChild(a); outline.appendChild(li);
          });
          const items = [...outline.children];
          const mark = () => {
            const y = window.scrollY + 90;
            let idx = heads.findIndex(h => h.offsetTop > y) - 1;
            if (idx < -1) idx = heads.length - 1;
            items.forEach((li, i) => li.classList.toggle('active', i === idx));
          };
          window.addEventListener('scroll', mark, { passive: true }); mark();
        }

        // Executable blocks.
        const prior = (() => { try { return JSON.parse(document.getElementById('rs-prior')?.textContent || '{}'); } catch (e) { return {}; } })();

        const show = (block, data) => {
          const status = block.querySelector('[data-role="status"]');
          const result = block.querySelector('.rs-result');
          const output = block.querySelector('[data-role="output"]');
          const exit   = block.querySelector('[data-role="exit"]');
          const button = block.querySelector('[data-action="execute"]');
          result.hidden = false;
          output.textContent = data.output || '';
          output.scrollTop = output.scrollHeight;
          block.classList.remove('rs-ok', 'rs-failed');
          status.className = 'rs-status';
          if (data.state === 'running') {
            const elapsed = data.started_at ? (Date.now() - Date.parse(data.started_at)) / 1000 : null;
            status.classList.add('running'); status.textContent = 'running ' + (elapsed != null ? fmt(elapsed) : '');
            exit.textContent = 'pid ' + data.pid + ' · ' + data.command.join(' ');
            if (button) button.disabled = true;
            return true;
          }
          const ok = data.state === 'finished' && data.exit_status === 0;
          block.classList.add(ok ? 'rs-ok' : 'rs-failed');
          status.classList.add(ok ? 'ok' : 'failed');
          status.textContent = data.state === 'timed_out' ? 'timed out' : data.state === 'failed' ? 'failed to start' : (ok ? 'ok' : 'exit ' + data.exit_status);
          exit.textContent = [
            data.state === 'failed' ? data.error : 'exit ' + data.exit_status,
            data.duration != null ? fmt(data.duration) : null,
            data.finished_at ? 'finished ' + new Date(data.finished_at).toLocaleTimeString() : null,
            data.log ? 'log ' + data.log : null
          ].filter(Boolean).join(' · ');
          if (button) button.disabled = false;
          return false;
        };

        const poll = async (block, id) => {
          try {
            const res  = await fetch('/executions/' + encodeURIComponent(id), { headers: { 'X-Runsheets-Token': token } });
            const data = await res.json();
            if (!res.ok) throw new Error(data.error || res.statusText);
            if (show(block, data)) setTimeout(() => poll(block, id), 500);
          } catch (err) {
            const status = block.querySelector('[data-role="status"]');
            status.className = 'rs-status failed'; status.textContent = 'poll failed';
            block.querySelector('[data-role="exit"]').textContent = String(err);
            const button = block.querySelector('[data-action="execute"]'); if (button) button.disabled = false;
          }
        };

        document.querySelectorAll('.rs-block').forEach(block => {
          const id   = block.dataset.block;
          const code = block.querySelector('pre');
          block.querySelector('[data-action="copy"]')?.addEventListener('click', async e => {
            try { await navigator.clipboard.writeText(code ? code.innerText : ''); e.target.textContent = 'Copied'; setTimeout(() => e.target.textContent = 'Copy', 1200); }
            catch (err) { e.target.textContent = 'Copy failed'; }
          });
          const button = block.querySelector('[data-action="execute"]');
          if (button) button.addEventListener('click', async () => {
            if (block.dataset.kind === 'destructive') {
              const word = Math.random().toString(36).slice(2, 6);
              const typed = prompt('This block is destructive. Type ' + word + ' to run it.');
              if (typed !== word) return;
            }
            button.disabled = true;
            const status = block.querySelector('[data-role="status"]');
            status.className = 'rs-status running'; status.textContent = 'starting';
            try {
              const res  = await fetch('/blocks/' + encodeURIComponent(id) + '/execute', { method: 'POST', headers: { 'X-Runsheets-Token': token, 'Accept': 'application/json' } });
              const data = await res.json();
              if (!res.ok) throw new Error(data.error || res.statusText);
              if (show(block, data)) poll(block, data.id);
            } catch (err) {
              status.className = 'rs-status failed'; status.textContent = 'not run';
              const result = block.querySelector('.rs-result'); result.hidden = false;
              block.querySelector('[data-role="exit"]').textContent = String(err.message || err);
              button.disabled = false;
            }
          });
          if (prior[id]) { if (show(block, prior[id])) poll(block, prior[id].id); }
        });

        // Keyboard shortcuts.
        const go = key => { const a = document.querySelector(`a[data-key="${key}"]`); if (a) location.href = a.href; };
        document.addEventListener('keydown', e => {
          if (e.metaKey || e.ctrlKey || e.altKey) return;
          const tag = e.target.tagName;
          if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || e.target.isContentEditable) { if (e.key === 'Escape') e.target.blur(); return; }
          switch (e.key) {
            case 'h': go('h'); break;
            case 'ArrowLeft':  go('←'); break;
            case 'ArrowRight': go('→'); break;
            case 's': toggleSidebar(); break;
          }
        });
      })();
    JS
  end
end
