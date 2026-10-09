# frozen_string_literal: true

module Runsheets
  # Inline CSS and JavaScript for the pages. Kept as strings so the gem has
  # no static file handling and a page is one self-contained response.
  module Assets
    def self.stylesheet = @stylesheet ||= CSS + Renderer.code_stylesheet
    def self.javascript = JS

    CSS = <<~CSS
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
      .rs-block.rs-stopped { border-color: rgba(255,180,84,.5); }
      .rs-block.rs-acked { border-color: rgba(61,220,151,.5); }
      .rs-status.stopped { color: var(--warn); } .rs-status.acked { color: var(--ok); }
      .rs-stop { background: rgba(255,180,84,.14); border-color: rgba(255,180,84,.6); }
      .rs-ack { background: rgba(61,220,151,.14); border-color: rgba(61,220,151,.5); }
      .rs-panes { display: grid; grid-template-columns: 1fr; }
      .rs-panes.has-expected { grid-template-columns: 1fr 1fr; }
      .rs-expected { border-left: 1px solid var(--border); min-width: 0; }
      .rs-expected .rs-pane-title { padding: 4px 16px 0; font: 600 10.5px var(--mono); letter-spacing: .08em; text-transform: uppercase; color: var(--accent-2); }
      .rs-expected pre { margin: 0; padding: 8px 16px 12px; max-height: 420px; overflow: auto; font: 12.5px/1.5 var(--mono); color: var(--muted); white-space: pre-wrap; word-break: break-word; border: 0 !important; border-radius: 0 !important; }
      .rs-expected.match { border-left-color: rgba(61,220,151,.5); } .rs-expected.match .rs-pane-title { color: var(--ok); }
      .rs-expected.mismatch { border-left-color: rgba(255,180,84,.5); } .rs-expected.mismatch .rs-pane-title { color: var(--warn); }
      .rs-sidebar .running h2 { color: var(--ok); }
      .rs-sidebar .running li { display: grid; grid-template-columns: 1fr auto; gap: 4px 8px; align-items: center; padding: 6px 8px; border-radius: 6px; }
      .rs-sidebar .running li a { display: inline; padding: 0; }
      .rs-sidebar .running li code { font: 600 11.5px var(--mono); }
      .rs-sidebar .running li .meta { grid-column: 1; color: var(--muted); font: 11px var(--mono); }
      .rs-sidebar .running li button { grid-column: 2; grid-row: 1 / span 2; }
      .rs-sidebar .running li.ended { opacity: .55; }
      .meta code.secret { color: var(--warn); }
      .history li { grid-template-columns: auto auto auto auto auto 1fr; }
      .history li .verdict { font-weight: 700; }
      .history li.verified .verdict { color: var(--ok); } .history li.abandoned .verdict { color: var(--warn); } .history li.running .verdict { color: var(--accent); }
      .badge.run { color: var(--accent); background: rgba(90,176,255,.12); }
      .panel.stamp { border-color: rgba(61,220,151,.5); background: rgba(61,220,151,.05); }
      .panel.stamp h2 { color: var(--ok); display: flex; align-items: center; gap: 6px; }
      .panel.drift { border-color: rgba(255,180,84,.5); max-width: none; }
      .panel.drift h2 { color: var(--warn); display: flex; align-items: center; gap: 6px; }
      .panel.drift ul { list-style: none; margin: 0; padding: 0; }
      .panel.drift li + li { margin-top: 14px; }
      pre.diff { margin: 6px 0 0; padding: 10px 14px; border-radius: 8px; border: 1px solid var(--border); background: #0b0e14; font: 12.5px/1.5 var(--mono); overflow: auto; white-space: pre; }
      pre.diff .add { color: var(--ok); display: block; background: rgba(61,220,151,.08); }
      pre.diff .del { color: var(--danger); display: block; background: rgba(255,107,107,.08); }
      pre.diff .ctx { color: var(--muted); display: block; }
      .verify-toolbar { margin: 0 0 24px; }
      .verify-toolbar .meta.ok { color: var(--ok); } .verify-toolbar .meta.failed { color: var(--danger); }
      .check-doc { margin: 0 0 32px; padding: 0 0 8px; border-bottom: 1px solid var(--border); }
      .check-doc > h2 { display: flex; align-items: center; gap: 10px; font-size: 20px; margin: 0 0 12px; }
      @media (max-width: 700px) { .rs-panes.has-expected { grid-template-columns: 1fr; } .rs-expected { border-left: 0; border-top: 1px solid var(--border); } }

      /* ---------- library: the tree ---------- */
      .lib-tree { padding-top: 12px; }
      .lib-filter { position: relative; display: flex; align-items: center; margin: 0 4px 14px; }
      .lib-filter > svg { position: absolute; left: 10px; color: var(--muted); pointer-events: none; }
      .lib-filter > kbd { position: absolute; right: 8px; opacity: .7; }
      .lib-filter input { width: 100%; padding: 8px 34px 8px 34px; border-radius: 8px; border: 1px solid var(--border); background: var(--bg); color: var(--text); font: inherit; font-size: 13.5px; outline: 0; }
      .lib-filter input:focus { border-color: var(--accent); box-shadow: 0 0 0 3px rgba(90,176,255,.15); }
      .lib-filter input:focus ~ kbd { display: none; }
      .lib-filter input::-webkit-search-cancel-button { cursor: pointer; }
      .tree ul { list-style: none; margin: 0; padding: 0; }
      .tree ul ul { margin-left: 14px; padding-left: 8px; border-left: 1px solid var(--border); }
      .tree li { margin: 1px 0; }
      .tree li[hidden] { display: none; }
      .tree .node, .tree summary { display: grid; grid-template-columns: auto 1fr auto; align-items: center; gap: 8px; min-height: 30px; padding: 3px 8px; border-radius: 6px; color: var(--text); cursor: pointer; }
      .tree summary { grid-template-columns: auto auto 1fr auto; gap: 6px; list-style: none; user-select: none; }
      .tree summary::-webkit-details-marker { display: none; }
      .tree summary svg, .tree .node svg { color: var(--muted); }
      .tree summary .name { color: var(--text); font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
      .tree summary .name:hover { color: var(--accent); text-decoration: none; }
      .tree .twisty { display: inline-flex; width: 16px; height: 16px; align-items: center; justify-content: center; border-radius: 4px; color: var(--muted); transition: transform .15s ease; }
      .tree .twisty svg { width: .9em; height: .9em; }
      .tree details[open] > summary .twisty { transform: rotate(90deg); }
      .tree .node:hover, .tree summary:hover { background: var(--panel-2); text-decoration: none; }
      .tree .node .name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
      .tree li.active > .node, .tree li.active > details > summary { background: rgba(90,176,255,.14); color: #fff; box-shadow: inset 3px 0 0 var(--accent); }
      .tree li.active > .node svg { color: var(--accent); }
      .tree li.focus > .node, .tree li.focus > details > summary { outline: 1px solid var(--accent); outline-offset: -1px; }
      .tree .root > .node { margin-bottom: 6px; font-weight: 600; }
      .tree-mark { font: 600 11px var(--mono); color: var(--muted); }
      .tree-mark.count { min-width: 1.6em; text-align: right; }
      .tree-mark.broken { color: var(--danger); font-weight: 800; }
      .tree-mark.current { display: inline-flex; color: var(--ok); }
      .tree-mark.current .dot { width: 8px; height: 8px; border-radius: 50%; background: currentColor; animation: pulse 1.6s infinite; }
      .tree li.current > .node .name { color: var(--ok); }
      .tree li.broken > .node .name { color: var(--muted); text-decoration: line-through; text-decoration-color: rgba(255,107,107,.6); }
      .tree li.destructive > .node svg { color: var(--danger); }
      .tree-empty { margin: 12px 8px; color: var(--muted); font-style: italic; }
      body.filtering .tree details > summary .twisty { visibility: hidden; }

      /* ---------- library: the main pane ---------- */
      .lib-main .page-head h1 svg { color: var(--accent); }
      .lib-main .page-head .sub code { font: 12.5px var(--mono); color: var(--muted); background: var(--panel-2); padding: 1px 6px; border-radius: 5px; }
      .lib-readme { margin: 0 0 28px; padding: 4px 0 16px; border-bottom: 1px solid var(--border); color: var(--text); }
      .lib-readme > :first-child { margin-top: 0; }
      .lib-readme h1 { font-size: 1.35em; border-bottom: 0; padding-bottom: 0; }
      .lib-readme h2 { font-size: 1.15em; border-bottom: 0; }
      .lib-section { margin: 0 0 28px; max-width: 900px; }
      .lib-section > h2 { display: flex; align-items: baseline; gap: 10px; margin: 0 0 12px; font-size: 13px; letter-spacing: .12em; text-transform: uppercase; color: var(--muted); }
      .lib-section > h2 .meta { font: 12px var(--mono); text-transform: none; letter-spacing: 0; }
      .lib-section .steps-list, .lib-section .meta-table { margin-bottom: 0; }
      .lib-section > .meta { margin: 8px 0 0; color: var(--muted); font-size: 13px; }
      .lib-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 14px; }
      .lib-card { display: flex; flex-direction: column; min-width: 0; border-radius: var(--radius); border: 1px solid var(--border); background: var(--panel); color: var(--text); transition: border-color .12s ease, transform .12s ease, box-shadow .12s ease; }
      .lib-card:hover { border-color: var(--accent); text-decoration: none; transform: translateY(-1px); box-shadow: 0 8px 24px rgba(0,0,0,.3); }
      .lib-card h3 { display: flex; align-items: center; gap: 8px; margin: 0 0 6px; font-size: 15.5px; line-height: 1.3; }
      .lib-card h3 svg { color: var(--accent); }
      .lib-card.folder { padding: 16px 18px; }
      .lib-card.folder h3 svg { color: var(--warn); }
      .lib-card .desc { margin: 0; color: var(--muted); font-size: 13.5px; line-height: 1.5; }
      .lib-card .names { margin: 8px 0 0; font-size: 12.5px; color: var(--muted); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
      .lib-card .card-link { display: block; flex: 1; padding: 16px 18px 12px; color: inherit; }
      .lib-card .card-link:hover { text-decoration: none; }
      .lib-card .card-link .badges { margin: 12px 0 0; }
      .lib-card .card-foot { display: flex; justify-content: space-between; align-items: center; gap: 10px; padding: 10px 18px; border-top: 1px solid var(--border); font-size: 12.5px; color: var(--muted); }
      .lib-card .card-foot .btn { padding: 5px 12px; font-size: 13px; }
      .lib-card.current { border-color: rgba(61,220,151,.5); }
      .lib-card.broken { border-color: rgba(255,107,107,.45); }
      .lib-card.broken h3 svg { color: var(--danger); }
      .lib-card.broken .desc { color: #ffd3d3; font: 12.5px var(--mono); }
      .lib-card.locked .card-foot .btn.disabled { opacity: .5; cursor: not-allowed; }
      .lib-open { display: grid; grid-template-columns: 1fr auto; gap: 24px; align-items: center; border-color: rgba(90,176,255,.35); background: linear-gradient(135deg, rgba(90,176,255,.08), rgba(167,139,250,.06)); }
      .lib-open.current { border-color: rgba(61,220,151,.5); background: linear-gradient(135deg, rgba(61,220,151,.08), rgba(90,176,255,.05)); }
      .lib-open.broken { border-color: rgba(255,107,107,.45); background: rgba(255,107,107,.05); grid-template-columns: 1fr; }
      .lib-open .lib-open-text > :last-child { margin-bottom: 0; }
      .lib-open .lib-open-text p { margin: 0; font-size: 15.5px; line-height: 1.55; }
      .lib-open .banner { margin: 0; }
      .lib-open .btn.primary { padding: 10px 22px; font-size: 15px; white-space: nowrap; }
      .lib-open-form { display: inline; }
      .lib-hint { max-width: 900px; margin: 0; color: var(--muted); font-size: 13.5px; }
      .meta-table.inputs { width: 100%; }
      .meta-table.inputs th { width: auto; white-space: nowrap; font: 600 13px var(--mono); color: var(--text); padding-right: 24px; }
      .meta-table.inputs td:last-child { width: 30%; }
      .meta-table.inputs thead th { font: 600 11px var(--mono); letter-spacing: .1em; text-transform: uppercase; color: var(--muted); border-top: 0; padding: 0 24px 8px 0; }
      .meta-table.inputs td { padding: 8px 24px 8px 0; }
      .badge.current { color: var(--ok); background: rgba(61,220,151,.14); }
      .steps-list .title { display: block; }
      @media (max-width: 700px) { .lib-open { grid-template-columns: 1fr; } }

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
        const prior = (() => {
          try { const p = JSON.parse(document.getElementById('rs-prior')?.textContent || '{}'); return { executions: p.executions || {}, acks: p.acks || {} }; }
          catch (e) { return { executions: {}, acks: {} }; }
        })();
        const headers = { 'X-Runsheets-Token': token, 'Accept': 'application/json' };
        const post = async (path, fields) => {
          const body = fields ? new URLSearchParams(fields) : null;
          const res  = await fetch(path, { method: 'POST', headers, body });
          const data = await res.json();
          return { res, data };
        };
        const TRUNCATED = '[… earlier output omitted; the .out file in the run directory is complete]\n';
        const norm = s => (s || '').replace(/[ \t]+$/gm, '').replace(/\s+$/, '');

        // Fill the "expected" pane from the expect block that follows this one
        // and say whether the actual output matches it. A hint, not a verdict.
        const compare = (block, id, actual) => {
          const pane   = block.querySelector('[data-role="expected"]');
          const panes  = block.querySelector('.rs-panes');
          const source = document.querySelector('.rs-expect[data-expect-for="' + CSS.escape(id) + '"] pre');
          if (!pane || !source) return null;
          const expected = source.innerText;
          pane.querySelector('pre').textContent = expected;
          pane.hidden = false; panes.classList.add('has-expected');
          const match = norm(actual) === norm(expected);
          pane.classList.toggle('match', match); pane.classList.toggle('mismatch', !match);
          return match ? 'matches expected' : 'differs from expected';
        };

        const show = (block, data) => {
          const status  = block.querySelector('[data-role="status"]');
          const result  = block.querySelector('.rs-result');
          const output  = block.querySelector('[data-role="output"]');
          const exit    = block.querySelector('[data-role="exit"]');
          const button  = block.querySelector('[data-action="execute"]');
          const stop    = block.querySelector('[data-action="stop"]');
          const id      = block.dataset.block;
          result.hidden = false;
          output.textContent = (data.output_truncated ? TRUNCATED : '') + (data.output || '');
          output.scrollTop = output.scrollHeight;
          block.classList.remove('rs-ok', 'rs-failed', 'rs-stopped');
          status.className = 'rs-status';
          if (data.state === 'running') {
            const elapsed = data.started_at ? (Date.now() - Date.parse(data.started_at)) / 1000 : null;
            status.classList.add('running'); status.textContent = 'running ' + (elapsed != null ? fmt(elapsed) : '');
            exit.textContent = 'pid ' + data.pid + ' · ' + data.command.join(' ');
            if (button) button.disabled = true;
            if (stop) { stop.hidden = false; stop.disabled = false; stop.dataset.execution = data.id; }
            return true;
          }
          const ok = data.state === 'finished' && data.exit_status === 0;
          const stopped = data.state === 'stopped';
          block.classList.add(ok ? 'rs-ok' : stopped ? 'rs-stopped' : 'rs-failed');
          status.classList.add(ok ? 'ok' : stopped ? 'stopped' : 'failed');
          status.textContent = data.state === 'timed_out' ? 'timed out' : data.state === 'failed' ? 'failed to start' : stopped ? 'stopped' : (ok ? 'ok' : 'exit ' + data.exit_status);
          const verdict = data.state === 'failed' ? null : compare(block, id, data.output);
          exit.textContent = [
            data.state === 'failed' ? data.error : (stopped ? 'stopped' : 'exit ' + data.exit_status),
            data.duration != null ? fmt(data.duration) : null,
            data.finished_at ? 'finished ' + new Date(data.finished_at).toLocaleTimeString() : null,
            data.log ? 'log ' + data.log : null,
            verdict
          ].filter(Boolean).join(' · ');
          if (button) button.disabled = false;
          if (stop) stop.hidden = true;
          return false;
        };

        const showAck = (block, ack) => {
          const status = block.querySelector('[data-role="status"]');
          const result = block.querySelector('.rs-result');
          const exit   = block.querySelector('[data-role="exit"]');
          const button = block.querySelector('[data-action="acknowledge"]');
          block.classList.add('rs-acked');
          status.className = 'rs-status acked'; status.textContent = 'confirmed';
          result.hidden = false;
          exit.textContent = ['confirmed ' + new Date(ack.at).toLocaleTimeString(), ack.note ? 'note: ' + ack.note : null].filter(Boolean).join(' · ');
          if (button) button.textContent = 'Confirm again';
        };

        const fail = (block, label, err) => {
          const status = block.querySelector('[data-role="status"]');
          status.className = 'rs-status failed'; status.textContent = label;
          block.querySelector('.rs-result').hidden = false;
          block.querySelector('[data-role="exit"]').textContent = String(err.message || err);
          block.querySelectorAll('[data-action="execute"], [data-action="acknowledge"]').forEach(b => b.disabled = false);
        };

        const sleep = ms => new Promise(r => setTimeout(r, ms));

        // Poll until the execution ends. Resolves with its final state, or null if polling failed.
        const poll = async (block, id) => {
          try {
            for (;;) {
              const res  = await fetch('/executions/' + encodeURIComponent(id), { headers });
              const data = await res.json();
              if (!res.ok) throw new Error(data.error || res.statusText);
              if (!show(block, data)) return data;
              await sleep(500);
            }
          } catch (err) {
            fail(block, 'poll failed', err);
            return null;
          }
        };

        // Run the block; a destructive one needs the server's confirmation code typed back.
        // Resolves with the final execution state, or null if it did not run.
        const execute = async (block, id, button) => {
          button.disabled = true;
          const status = block.querySelector('[data-role="status"]');
          status.className = 'rs-status running'; status.textContent = 'starting';
          try {
            let { res, data } = await post('/blocks/' + encodeURIComponent(id) + '/execute');
            if (res.status === 428 && data.challenge) {
              const typed = prompt('This block is destructive. Type the code ' + data.challenge + ' to run it.');
              if (typed === null || typed.trim() !== data.challenge) { status.className = 'rs-status'; status.textContent = typed === null ? 'cancelled' : 'code did not match'; button.disabled = false; return null; }
              ({ res, data } = await post('/blocks/' + encodeURIComponent(id) + '/execute', { confirm: typed.trim() }));
            }
            if (!res.ok) throw new Error(data.error || res.statusText);
            return show(block, data) ? poll(block, data.id) : data;
          } catch (err) {
            fail(block, 'not run', err);
            return null;
          }
        };

        // Checks page: run every plain `run` block on the page, in order, one at a time.
        const runAll = document.querySelector('[data-action="run-all"]');
        if (runAll) runAll.addEventListener('click', async () => {
          const status = document.querySelector('[data-role="run-all-status"]');
          const blocks = [...document.querySelectorAll('.rs-block.rs-executable[data-kind="run"]')];
          runAll.disabled = true;
          let ok = 0, failed = 0, skipped = 0;
          for (const [i, block] of blocks.entries()) {
            const button = block.querySelector('[data-action="execute"]');
            if (!button) { skipped++; continue; }
            status.textContent = 'running check ' + (i + 1) + ' of ' + blocks.length + '…';
            block.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
            const data = await execute(block, block.dataset.block, button);
            if (data && data.state === 'finished' && data.exit_status === 0) ok++; else failed++;
          }
          status.textContent = blocks.length + ' check' + (blocks.length === 1 ? '' : 's') + ': ' + ok + ' ok, ' + failed + ' failed' + (skipped ? ', ' + skipped + ' skipped' : '');
          status.className = 'meta ' + (failed ? 'failed' : 'ok');
          runAll.disabled = false;
        });

        const stopExecution = async (executionId, button) => {
          button.disabled = true;
          try {
            const { res, data } = await post('/executions/' + encodeURIComponent(executionId) + '/stop');
            if (!res.ok) throw new Error(data.error || res.statusText);
            button.textContent = 'Stopping…';
          } catch (err) {
            button.disabled = false; button.textContent = String(err.message || err);
          }
        };

        const acknowledge = async (block, id, button) => {
          const note = prompt('Confirm that you ran this in your terminal. Add a note if you like, or leave it blank.', '');
          if (note === null) return;
          button.disabled = true;
          try {
            const { res, data } = await post('/blocks/' + encodeURIComponent(id) + '/acknowledge', { note });
            if (!res.ok) throw new Error(data.error || res.statusText);
            showAck(block, data);
            button.disabled = false;
          } catch (err) {
            fail(block, 'not confirmed', err);
          }
        };

        document.querySelectorAll('.rs-block').forEach(block => {
          const id   = block.dataset.block;
          const code = block.querySelector('pre');
          block.querySelector('[data-action="copy"]')?.addEventListener('click', async e => {
            try { await navigator.clipboard.writeText(code ? code.innerText : ''); e.target.textContent = 'Copied'; setTimeout(() => e.target.textContent = 'Copy', 1200); }
            catch (err) { e.target.textContent = 'Copy failed'; }
          });
          const run = block.querySelector('[data-action="execute"]');
          if (run) run.addEventListener('click', () => execute(block, id, run));
          const stop = block.querySelector('[data-action="stop"]');
          if (stop) stop.addEventListener('click', () => stopExecution(stop.dataset.execution, stop));
          const ack = block.querySelector('[data-action="acknowledge"]');
          if (ack) ack.addEventListener('click', () => acknowledge(block, id, ack));
          const last = prior.executions[id];
          if (last) { if (show(block, last)) poll(block, last.id); }
          if (prior.acks[id]) showAck(block, prior.acks[id]);
        });

        // Running-processes panel in the sidebar.
        document.querySelectorAll('#rs-running li[data-execution]').forEach(li => {
          const executionId = li.dataset.execution;
          const stop   = li.querySelector('[data-action="stop"]');
          const status = li.querySelector('[data-role="running-status"]');
          stop?.addEventListener('click', () => stopExecution(executionId, stop));
          const tick = async () => {
            try {
              const res  = await fetch('/executions/' + encodeURIComponent(executionId), { headers });
              const data = await res.json();
              if (!res.ok) throw new Error(data.error || res.statusText);
              if (data.state === 'running') {
                const elapsed = data.started_at ? (Date.now() - Date.parse(data.started_at)) / 1000 : null;
                status.textContent = (data.background ? 'background' : 'running') + (elapsed != null ? ' · ' + fmt(elapsed) : '') + ' · pid ' + data.pid;
                setTimeout(tick, 1000);
              } else {
                li.classList.add('ended');
                status.textContent = data.state === 'stopped' ? 'stopped' : data.state === 'finished' ? 'exit ' + data.exit_status : data.state.replace('_', ' ');
                if (stop) stop.remove();
              }
            } catch (err) { status.textContent = String(err.message || err); }
          };
          tick();
        });

        // Library tree: filter box, and a keyboard cursor over the visible
        // nodes. Filtering opens every folder and hides what does not
        // match; clearing it puts the folders back the way they were.
        const tree = document.getElementById('lib-tree-nav');
        const lib  = tree ? (() => {
          const filter  = document.getElementById('lib-filter');
          const empty   = document.getElementById('lib-tree-empty');
          const items   = [...tree.querySelectorAll('li')];
          const folders = items.filter(li => li.querySelector(':scope > details'));
          let saved = null, cursor = -1;
          const visible = () => items.filter(li => !li.hidden && li.offsetParent !== null);
          const node = li => li.querySelector(':scope > .node, :scope > details > summary');
          const apply = () => {
            const q = filter.value.trim().toLowerCase();
            if (q && !saved) saved = new Map(folders.map(li => [li, li.querySelector(':scope > details').open]));
            body.classList.toggle('filtering', !!q);
            let shown = 0;
            items.filter(li => li.classList.contains('tree-runbook')).forEach(li => {
              const hit = !q || (li.dataset.search || '').includes(q);
              li.hidden = !hit; if (hit) shown++;
            });
            [...folders].reverse().forEach(li => {
              const details = li.querySelector(':scope > details');
              if (q) { details.open = true; li.hidden = !li.querySelector('ul li.tree-runbook:not([hidden])'); }
              else { li.hidden = false; if (saved) details.open = saved.get(li); }
            });
            if (!q) saved = null;
            if (empty) empty.hidden = !(q && shown === 0);
            setCursor(-1);
          };
          const setCursor = i => {
            items.forEach(li => li.classList.remove('focus'));
            const list = visible();
            cursor = list.length ? Math.max(-1, Math.min(i, list.length - 1)) : -1;
            if (cursor >= 0) { list[cursor].classList.add('focus'); node(list[cursor])?.scrollIntoView({ block: 'nearest' }); }
          };
          const move = delta => {
            const list = visible();
            const from = cursor >= 0 ? cursor : list.findIndex(li => li.classList.contains('active'));
            setCursor(from + delta);
          };
          const select = () => {
            const list = visible();
            const li = cursor >= 0 ? list[cursor] : null;
            if (!li) return;
            const a = li.querySelector(':scope > .node, :scope > details > summary > .name');
            if (a) location.href = a.href;
          };
          const toggle = open => {
            const li = visible()[cursor];
            const details = li?.querySelector(':scope > details');
            if (details) details.open = open;
          };
          filter.addEventListener('input', apply);
          filter.addEventListener('keydown', e => {
            if (e.key === 'ArrowDown') { e.preventDefault(); filter.blur(); move(1); }
            if (e.key === 'Escape') { filter.value = ''; apply(); }
          });
          return { filter, move, select, toggle };
        })() : null;

        // Keyboard shortcuts.
        const go = key => { const a = document.querySelector(`a[data-key="${key}"]`); if (a) location.href = a.href; };
        const press = key => { const b = document.querySelector(`button[data-key="${key}"]`); if (b) b.click(); };
        document.addEventListener('keydown', e => {
          if (e.metaKey || e.ctrlKey || e.altKey) return;
          const tag = e.target.tagName;
          if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || e.target.isContentEditable) { if (e.key === 'Escape') e.target.blur(); return; }
          if (lib) {
            switch (e.key) {
              case '/': e.preventDefault(); lib.filter.focus(); lib.filter.select(); return;
              case 'ArrowDown': case 'j': e.preventDefault(); lib.move(1); return;
              case 'ArrowUp':   case 'k': e.preventDefault(); lib.move(-1); return;
              case 'ArrowRight': lib.toggle(true); return;
              case 'ArrowLeft':  lib.toggle(false); return;
              case 'Enter': lib.select(); return;
              case 'o': press('o'); return;
              case 'b': go('b'); return;
            }
          }
          switch (e.key) {
            case 'h': go('h'); break;
            case 'r': go('r'); break;
            case 'ArrowLeft':  go('←'); break;
            case 'ArrowRight': go('→'); break;
            case 's': toggleSidebar(); break;
          }
        });
      })();
    JS
  end
end
