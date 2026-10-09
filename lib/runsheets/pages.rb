# frozen_string_literal: true

require "rack/utils"

module Runsheets
  # Pure functions that build the HTML pages from a Session. No HTTP here, so
  # every page can be rendered and inspected in a test.
  #
  # Every page function takes +nonce:+, the Content-Security-Policy nonce the
  # web layer put in the response header; the page's one inline script and
  # stylesheet carry it, and nothing else on the page can run script.
  module Pages
    APP_NAME = "runsheets"
    APP_FULL = "executable runbooks"

    ICONS = {
      home:   '<svg class="icon" viewBox="0 0 24 24"><path d="M3 11.5 12 4l9 7.5"/><path d="M5.5 10v9.5h4.5V14h4v5.5h4.5V10"/></svg>',
      prev:   '<svg class="icon" viewBox="0 0 24 24"><path d="M19 12H5"/><path d="m11 18-6-6 6-6"/></svg>',
      next:   '<svg class="icon" viewBox="0 0 24 24"><path d="M5 12h14"/><path d="m13 6 6 6-6 6"/></svg>',
      menu:   '<svg class="icon" viewBox="0 0 24 24"><path d="M4 7h16M4 12h16M4 17h16"/></svg>',
      book:   '<svg class="icon" viewBox="0 0 24 24"><path d="M4 4h7a3 3 0 0 1 3 3v13a2 2 0 0 0-2-2H4z"/><path d="M20 4h-7a3 3 0 0 0-3 3v13a2 2 0 0 1 2-2h8z"/></svg>',
      alert:  '<svg class="icon" viewBox="0 0 24 24"><path d="M12 3 2.5 20h19z"/><path d="M12 10v5"/><path d="M12 18h.01"/></svg>',
      log:    '<svg class="icon" viewBox="0 0 24 24"><path d="M5 4h14v16H5z"/><path d="M8 9h8M8 13h8M8 17h5"/></svg>',
      check:  '<svg class="icon" viewBox="0 0 24 24"><path d="M12 3a9 9 0 1 0 9 9"/><path d="m8.5 12 2.5 2.5L21 4.5"/></svg>',
      stamp:  '<svg class="icon" viewBox="0 0 24 24"><path d="M5 20h14"/><path d="M7 16h10v-3H7z"/><path d="M10 13V9a2 2 0 1 1 4 0v4"/></svg>',
      folder: '<svg class="icon" viewBox="0 0 24 24"><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/></svg>',
      file:   '<svg class="icon" viewBox="0 0 24 24"><path d="M6 3h8l5 5v13H6z"/><path d="M14 3v5h5"/><path d="M9 13h6M9 17h6"/></svg>',
      search: '<svg class="icon" viewBox="0 0 24 24"><circle cx="11" cy="11" r="6"/><path d="m20 20-4.5-4.5"/></svg>',
      chevron: '<svg class="icon" viewBox="0 0 24 24"><path d="m9 6 6 6-6 6"/></svg>'
    }.freeze

    STATUS_MARKS = { "done" => "✓", "skipped" => "↷", "failed" => "✗", "ran" => "•", "pending" => "·" }.freeze

    def self.h(value) = Renderer.h(value)

    # ------------------------------------------------------------------
    # Layout
    # ------------------------------------------------------------------

    def self.layout(session, title:, body:, kind:, step: nil, nonce: nil)
      runbook = session.runbook
      nonce_attr = nonce ? %( nonce="#{h nonce}") : ""
      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="rs-token" content="#{h session.token}">
          <meta name="rs-runbook" content="#{h runbook.slug}">
          <title>#{h title} · #{h runbook.title}</title>
          <style#{nonce_attr}>#{Assets.stylesheet}</style>
        </head>
        <body class="kind-#{kind}">
          #{header(session, step:, kind:)}
          <div class="rs-shell">
            #{sidebar(session, step:, kind:)}
            <main class="rs-main">
              #{body}
            </main>
          </div>
          <footer class="rs-footer">
            <span>#{h APP_NAME} · #{h APP_FULL} · #{h runbook.dir}</span>
            <span class="keys"><kbd>h</kbd> home <kbd>←</kbd><kbd>→</kbd> prev/next step <kbd>s</kbd> sidebar</span>
          </footer>
          <script#{nonce_attr}>#{Assets.javascript}</script>
        </body>
        </html>
      HTML
    end

    def self.nav_button(label, href, icon, key: nil, title: nil)
      tip   = h([title || label, key && "[#{key}]"].compact.join(" "))
      inner = "#{ICONS[icon]}<span>#{h label}</span>"
      if href
        "<a class=\"nav-btn\" href=\"#{h href}\" title=\"#{tip}\" data-key=\"#{h key}\">#{inner}</a>"
      else
        "<span class=\"nav-btn disabled\" title=\"#{tip}\">#{inner}</span>"
      end
    end

    def self.step_href(step) = "/steps/#{Rack::Utils.escape_path(step.slug)}"

    def self.header(session, step:, kind:)
      runbook   = session.runbook
      prev, nxt = step ? runbook.neighbors(step) : [nil, nil]
      crumbs    = library_crumbs(session)
      crumbs << (kind == :landing ? "<span class=\"current\">#{h runbook.title}</span>" : "<a href=\"/\">#{h runbook.title}</a>")
      crumbs << "<span class=\"current\">#{h step.title}</span>" if step
      crumbs << '<span class="current">Runsheet</span>' if kind == :run
      crumbs << '<span class="current">Checks</span>' if kind == :verify

      pill = if session.active?
               "<a class=\"run-pill active\" href=\"/run\" title=\"Active run\"><span class=\"dot\"></span>#{session.verifying? ? 'verify' : 'run'} #{h session.run.id}</a>"
             else
               '<span class="run-pill"><span class="dot"></span>no active run</span>'
             end

      <<~HTML
        <header class="rs-header">
          <div class="brand">
            <button class="icon-btn sidebar-toggle" type="button" title="Toggle sidebar [s]" aria-label="Toggle sidebar">#{ICONS[:menu]}</button>
            <a class="home" href="/" title="Runbook home [h]" data-key="h">
              #{ICONS[:home]}
              <span class="brand-name">#{h APP_NAME}</span>
              <span class="brand-tag">#{h runbook.slug}</span>
            </a>
          </div>
          <nav class="crumbs" aria-label="Breadcrumb">#{crumbs.join('<span class="sep">/</span>')}</nav>
          <nav class="actions" aria-label="Step navigation">
            #{nav_button('Runbooks', '/library', :book, key: 'r', title: 'Choose another runbook') if session.library}
            #{nav_button('Prev', prev && step_href(prev), :prev, key: '←', title: prev&.title)}
            #{nav_button('Next', nxt && step_href(nxt), :next, key: '→', title: nxt&.title)}
            #{pill}
          </nav>
        </header>
      HTML
    end

    # When the runbook was opened from a library, the crumbs start with the
    # library and the folders above the runbook, each a link into the tree.
    def self.library_crumbs(session)
      library = session.library
      return [] unless library

      ['<a href="/library" title="Runbooks [r]">Runbooks</a>',
       *library.ancestors(session.runbook.slug).map { "<a href=\"#{h Chooser.href(it.slug)}\">#{h it.name}</a>" }]
    end

    # Sidebar: the step list with run status marks, extra documents, the
    # rollback panel, and an outline for the current page.
    def self.sidebar(session, step:, kind:)
      extras = also_items(session, step, kind)
      <<~HTML
        <aside class="rs-sidebar">
          #{running_panel(session)}
          <section>
            <h2>Steps</h2>
            <ol class="steps">#{step_items(session, step).join}</ol>
          </section>
          #{"<section><h2>Also</h2><ul>#{extras.join}</ul></section>" unless extras.empty?}
          #{rollback_panel(session.runbook, kind)}
          <section class="outline"><h2>On this page</h2><ol id="outline"></ol></section>
        </aside>
      HTML
    end

    # One sidebar entry per numbered step, with its status mark.
    def self.step_items(session, current)
      session.runbook.steps.map do |s|
        status = step_mark(session, s)
        <<~LI
          <li#{' class="active"' if s == current}><a href="#{h step_href(s)}" title="#{h s.title}">
            <span class="num">#{h(s.number || s.position)}</span>
            <span class="name">#{h s.title}</span>
            <span class="mark #{status}" title="#{status}">#{STATUS_MARKS[status]}</span>
          </a></li>
        LI
      end
    end

    # The "Also" entries: checks, extra documents, the active runsheet.
    def self.also_items(session, current, kind)
      runbook = session.runbook
      items = runbook.extras.values.map { also_item(step_href(it), ICONS[:book], it.title, active: it == current) }
      items.unshift(also_item("/verify", ICONS[:check], "Checks", active: kind == :verify)) if runbook.verify_documents.any?
      items << also_item("/run", ICONS[:log], "Runsheet") if session.active?
      items
    end

    def self.also_item(href, icon, name, active: false)
      "<li#{' class="active"' if active}><a href=\"#{h href}\"><span class=\"num\">#{icon}</span><span class=\"name\">#{h name}</span><span></span></a></li>"
    end

    def self.rollback_panel(runbook, kind)
      return "" unless runbook.rollback && kind == :step

      <<~HTML
        <section>
          <details>
            <summary>Rollback</summary>
            <div class="rollback-body markdown-body">#{runbook.rollback.html}</div>
          </details>
        </section>
      HTML
    end

    # Processes still running in the active run, each with a Stop button.
    # The page's JavaScript keeps the entries current.
    def self.running_panel(session)
      running = session.running_executions
      return "" if running.empty?

      items = running.map do |ex|
        step = session.runbook.step(ex.step_slug)
        href = step ? "#{step_href(step)}#block-#{Rack::Utils.escape_path(ex.block_id)}" : "#"
        <<~LI
          <li data-execution="#{h ex.id}">
            <a href="#{h href}" title="#{h ex.step_slug}"><code>#{h ex.block_id}</code></a>
            <span class="meta" data-role="running-status">#{ex.background? ? 'background' : 'running'} · pid #{ex.pid}</span>
            <button type="button" class="rs-btn rs-stop" data-action="stop" data-execution="#{h ex.id}">Stop</button>
          </li>
        LI
      end
      <<~HTML
        <section class="running" id="rs-running">
          <h2>Running</h2>
          <ul>#{items.join}</ul>
        </section>
      HTML
    end

    # done | skipped | failed | ran | pending for the sidebar and step list.
    def self.step_mark(session, step)
      marked = session.step_status(step.slug)
      return marked if marked

      run = session.run
      return "pending" unless run

      executions = run.refresh!.executions.select { it[:step] == step.slug }
      acked      = run.acks.values.any? { it[:step] == step.slug }
      return "pending" if executions.empty? && !acked

      executions.any? { RunRecord.failure?(it) } ? "failed" : "ran"
    end

    # ------------------------------------------------------------------
    # Landing page
    # ------------------------------------------------------------------

    def self.landing(session, nonce: nil)
      runbook = session.runbook
      body = [page_head(runbook), warnings_banner(runbook.warnings), meta_table(runbook),
              run_panel(session), steps_list(session), history_panel(session),
              "<article class=\"markdown-body\">#{runbook.preamble_html}</article>"].join("\n")
      layout(session, title: "Home", body:, kind: :landing, nonce:)
    end

    def self.page_head(runbook)
      badges = runbook.tags.map { "<span class=\"badge tag\">#{h it}</span>" }
      badges.unshift('<span class="badge destructive">destructive</span>') if runbook.destructive?
      <<~HTML
        <div class="page-head">
          <h1>#{ICONS[:book]} #{h runbook.title}</h1>
          <p class="sub">#{runbook.steps.size} step#{'s' unless runbook.steps.size == 1}#{" · last verified #{h runbook.last_verified}" if runbook.last_verified}</p>
          #{"<div class=\"badges\">#{badges.join}</div>" unless badges.empty?}
        </div>
      HTML
    end

    def self.warnings_banner(warnings)
      return "" if warnings.empty?

      <<~HTML
        <div class="banner warn">#{ICONS[:alert]}<div><strong>Authoring warnings</strong><ul>#{warnings.map { "<li>#{h it}</li>" }.join}</ul></div></div>
      HTML
    end

    # The front-matter facts as a table. The library page shows when_to_use
    # on its own and leaves it out here.
    def self.meta_table(runbook, when_to_use: true)
      rows = []
      rows << ["When to use", h(runbook.when_to_use)] if when_to_use && runbook.when_to_use
      rows << ["Prerequisites", "<ul>#{runbook.prerequisites.map { "<li>#{h it}</li>" }.join}</ul>"] if runbook.prerequisites.any?
      rows << ["Blast radius", "<span class=\"badge destructive\">destructive</span> #{h runbook.blast_radius}"] if runbook.blast_radius
      rows << ["Escalation", h(runbook.escalation)] if runbook.escalation
      rows << ["Last verified", h(runbook.last_verified)] if runbook.last_verified
      return "" if rows.empty?

      "<table class=\"meta-table\">#{rows.map { |k, v| "<tr><th>#{k}</th><td>#{v}</td></tr>" }.join}</table>"
    end

    # Start-run form, or the active run's controls.
    def self.run_panel(session)
      session.active? ? active_run_panel(session) : stamp_panel(session) + start_panel(session)
    end

    def self.active_run_panel(session)
      run  = session.run
      noun = run.verify? ? "verification" : "run"
      <<~HTML
        <section class="panel">
          <h2>Active #{noun}</h2>
          <p><strong>#{h run.id}</strong> started #{h run.started_at.strftime('%Y-%m-%d %H:%M:%S')} · #{run_progress(run, session.runbook)} · <a href="/run">view runsheet</a></p>
          #{inputs_line(run.inputs, session.secret_inputs_set)}
          <div class="btn-row">
            #{go_button(run, session.runbook)}
            #{finish_form(session.token, 'completed', "Finish #{noun}", 'ok')}
            #{finish_form(session.token, 'abandoned', 'Abandon', 'danger')}
          </div>
        </section>
      HTML
    end

    def self.run_progress(run, runbook)
      if run.verify?
        checks = runbook.verify_blocks.size
        "#{run.executions.size} of #{checks} check#{'s' unless checks == 1} run · #{run.unresolved_failures.size} failing"
      else
        "#{run.executions.size} execution#{'s' unless run.executions.size == 1} · #{run.steps_done} of #{runbook.steps.size} steps done"
      end
    end

    def self.go_button(run, runbook)
      return '<a class="btn primary" href="/verify">Go to checks</a>' if run.verify?

      first = runbook.steps.first
      first ? "<a class=\"btn primary\" href=\"#{h step_href(first)}\">Go to first step</a>" : ""
    end

    def self.finish_form(token, status, label, style)
      "<form method=\"post\" action=\"/run/finish\"><input type=\"hidden\" name=\"_token\" value=\"#{h token}\">" \
        "<input type=\"hidden\" name=\"status\" value=\"#{status}\"><button class=\"btn #{style}\" type=\"submit\">#{h label}</button></form>"
    end

    # Offer to write last_verified after a run that verified the runbook.
    def self.stamp_panel(session)
      run = session.stamp_candidate
      return "" unless run

      runbook = session.runbook
      what = run.verify? ? "Verification #{h run.id} ran every check with nothing left failing" : "Run #{h run.id} completed with all #{runbook.steps.size} steps done"
      <<~HTML
        <section class="panel stamp">
          <h2>#{ICONS[:stamp]} Record the verification</h2>
          <p>#{what}. Stamp <code>last_verified: #{h session.stamp_date}</code> into <code>runbook.md</code>?#{" It currently says <code>#{h runbook.last_verified}</code>." if runbook.last_verified} This is the only change runsheets ever makes to a runbook, and only when you ask.</p>
          <div class="btn-row">
            <form method="post" action="/run/stamp"><input type="hidden" name="_token" value="#{h session.token}"><button class="btn ok" type="submit">Stamp runbook.md</button></form>
            <form method="post" action="/run/stamp/dismiss"><input type="hidden" name="_token" value="#{h session.token}"><button class="btn" type="submit">Not now</button></form>
          </div>
        </section>
      HTML
    end

    def self.start_panel(session)
      runbook = session.runbook
      fields = runbook.inputs.map do |input|
        name  = h input.name
        value = session.resolve_inputs[input.name]
        type  = input.secret? ? "password" : "text"
        <<~FIELD
          <div class="field">
            <label for="input-#{name}">#{h input.prompt}<code>$#{name}#{' · secret, not recorded' if input.secret?}</code></label>
            <input type="#{type}" id="input-#{name}" name="inputs[#{name}]" value="#{h value}" autocomplete="off">
          </div>
        FIELD
      end
      checks = runbook.verify_blocks.size
      verify = if checks.positive?
                 "<button class=\"btn\" type=\"submit\" name=\"kind\" value=\"verify\" title=\"Run only the verify steps and verify.md\">#{ICONS[:check]} Verify only (#{checks} check#{'s' unless checks == 1})</button>"
               else
                 ""
               end
      <<~HTML
        <section class="panel">
          <h2>Start a run</h2>
          <form method="post" action="/run">
            <input type="hidden" name="_token" value="#{h session.token}">
            #{fields.join}
            <div class="btn-row"><button class="btn primary" type="submit" name="kind" value="run">Start run</button>#{verify}<span class="meta">Writes the runsheet (the run record) under #{h session.runs_root}</span></div>
          </form>
        </section>
      HTML
    end

    # The active run's inputs: values for plain inputs, "set" for secrets.
    def self.inputs_line(inputs, secrets_set)
      parts = inputs.map { |k, v| "<code>#{h k}=#{h v}</code>" }
      parts += secrets_set.map { "<code class=\"secret\" title=\"secret, not recorded\">#{h it}=•••</code>" }
      return "" if parts.empty?

      "<p class=\"meta\">Inputs: #{parts.join(' ')}</p>"
    end

    def self.steps_list(session)
      runbook = session.runbook
      return '<p class="empty">This runbook has no steps yet. Add markdown files under steps/.</p>' if runbook.steps.empty?

      rows = runbook.steps.map do |step|
        status = step_mark(session, step)
        badges = ["<span class=\"badge #{h step.kind}\">#{h step.kind}</span>"]
        badges << '<span class="badge destructive">destructive</span>' if step.destructive?
        <<~LI
          <li>
            <span class="num">#{h(step.number || step.position)}</span>
            <a class="title" href="#{h step_href(step)}">#{h step.title}<small>#{step.executable_blocks.size} executable block#{'s' unless step.executable_blocks.size == 1}</small></a>
            <span class="badges">#{badges.join}</span>
            <span class="mark #{status}" title="#{status}">#{STATUS_MARKS[status]}</span>
          </li>
        LI
      end
      "<ol class=\"steps-list\">#{rows.join}</ol>"
    end

    # Seconds as "0.4s", "12s", "3m 05s", "1h 02m".
    def self.duration_text(seconds)
      s = seconds.to_f
      return format("%.1fs", s) if s < 10
      return "#{s.round}s" if s < 60
      return format("%<m>dm %<s>02ds", m: s / 60, s: s % 60) if s < 3600

      format("%<h>dh %<m>02dm", h: s / 3600, m: (s % 3600) / 60)
    end

    def self.history_panel(session)
      runs = session.history
      return "" if runs.empty?

      total = session.runbook.steps.size
      rows  = runs.first(20).map { history_row(it, total) }
      "<section class=\"panel\"><h2>Previous runs</h2><ul class=\"history\">#{rows.join}</ul></section>"
    end

    def self.history_row(run, total)
      s       = run.summary
      verdict = history_verdict(run, s, total)
      kind    = run.verify? ? "verify" : "run"
      <<~LI
        <li class="#{h verdict}">
          <a href="/runs/#{h s[:id]}">#{h s[:id]}</a>
          <span class="badge #{kind}">#{kind}</span>
          <span class="meta verdict">#{h verdict}#{' · stamped' if s[:stamped]}</span>
          <span class="meta">#{h run.started_at.strftime('%Y-%m-%d %H:%M')} · #{h duration_text(s[:duration])}</span>
          <span class="meta">#{s[:executions]} exec · #{s[:failures]} failed</span>
          <span class="meta">#{history_progress(run, s, total)}</span>
        </li>
      LI
    end

    def self.history_verdict(run, summary, total)
      return "running" if summary[:status] == "running"

      run.verified?(steps: total) ? "verified" : summary[:status]
    end

    def self.history_progress(run, summary, total)
      checks = summary[:executions]
      return "#{checks} check#{'s' unless checks == 1}, #{summary[:unresolved]} failing" if run.verify?

      done    = summary[:steps_done]
      stopped = summary[:last_step] && done < total ? ", stopped at #{h summary[:last_step]}" : ""
      "#{done} of #{total} steps done#{stopped}"
    end

    # ------------------------------------------------------------------
    # Step page
    # ------------------------------------------------------------------

    def self.step(session, step, nonce: nil)
      body = <<~HTML
        <div class="page-head">
          <h1>#{"<span class=\"num\">#{h(step.number || step.position)}</span>" if step.position} #{h step.title}</h1>
          <div class="badges">#{step_badges(step).join}</div>
        </div>
        #{warnings_banner(step.warnings)}
        #{step_banners(session, step)}
        <article class="markdown-body">#{step.html}</article>
        #{mark_panel(session, step)}
        #{step_nav(session.runbook, step)}
        <script type="application/json" id="rs-prior">#{prior_executions_json(session, step)}</script>
      HTML
      layout(session, title: step.title, body:, kind: :step, step:, nonce:)
    end

    def self.step_badges(step)
      badges = ["<span class=\"badge #{h step.kind}\">#{h step.kind}</span>"]
      badges << '<span class="badge destructive">destructive</span>' if step.destructive?
      badges << "<span class=\"badge\">timeout #{step.timeout}s</span>" if step.executable_blocks.any?
      badges
    end

    # The blast-radius banner for a destructive step, then any banner about
    # why its blocks cannot run right now.
    def self.step_banners(session, step)
      banners = [destructive_banner(session.runbook, step)]
      if step.executable_blocks.any?
        banners << info_banner('No active run. Blocks can be read and copied but not executed. <a href="/">Start a run</a> first.') unless session.active?
        if session.verifying? && !session.runbook.verify_document?(step)
          banners << info_banner('This is a verification run: only verify steps and verify.md execute. <a href="/verify">Go to the checks</a>, ' \
                                 'or finish the verification on the <a href="/">home page</a> to start a full run.')
        end
      end
      banners.join
    end

    def self.destructive_banner(runbook, step)
      return "" unless step.destructive?

      confirm = "Running a destructive block asks you to type a confirmation code first."
      body = if runbook.blast_radius
               escalation = runbook.escalation ? "<br><strong>Escalation</strong><br>#{h runbook.escalation}" : ""
               "<strong>Blast radius</strong><br>#{h runbook.blast_radius}#{escalation}<br>#{confirm}"
             else
               "<strong>This step is destructive.</strong> Read it fully before running anything. #{confirm}"
             end
      "<div class=\"banner danger\">#{ICONS[:alert]}<div>#{body}</div></div>"
    end

    def self.info_banner(html) = "<div class=\"banner info\">#{ICONS[:alert]}<div>#{html}</div></div>"

    def self.mark_panel(session, step)
      return "" unless session.active? && step.position

      status  = session.step_status(step.slug)
      heading = step.manual? ? "Acknowledge this step" : "Step status"
      done    = step.manual? ? "I have done this, continue" : "Mark done and continue"
      hint    = step.manual? ? "A manual step is complete when you say so. The acknowledgement and your note go into the runsheet." : ""
      <<~HTML
        <section class="panel">
          <h2>#{heading}#{": #{h status}" if status}</h2>
          #{"<p class=\"meta\">#{hint}</p>" unless hint.empty?}
          <form method="post" action="#{h step_href(step)}/mark">
            <input type="hidden" name="_token" value="#{h session.token}">
            <div class="field"><label for="note">Note (optional)</label><input type="text" id="note" name="note" placeholder="What you checked, what you saw"></div>
            <div class="btn-row">
              <button class="btn ok" type="submit" name="status" value="done">#{done}</button>
              <button class="btn" type="submit" name="status" value="skipped">Skip</button>
            </div>
          </form>
        </section>
      HTML
    end

    def self.step_nav(runbook, step)
      prev, nxt = runbook.neighbors(step)
      left  = prev ? "<a class=\"btn\" href=\"#{h step_href(prev)}\">#{ICONS[:prev]} #{h prev.title}</a>" : "<a class=\"btn\" href=\"/\">#{ICONS[:home]} Home</a>"
      right = nxt ? "<a class=\"btn primary\" href=\"#{h step_href(nxt)}\">#{h nxt.title} #{ICONS[:next]}</a>" : (step.position ? "<a class=\"btn primary\" href=\"/\">Finish on the home page #{ICONS[:next]}</a>" : "")
      "<nav class=\"step-nav\">#{left}#{right}</nav>"
    end

    # The last execution of each block on these documents, and the terminal
    # blocks the operator has confirmed, for the page to restore.
    def self.prior_executions_json(session, *steps)
      run = session.run
      return "{}" unless run

      mine = ->(block_id) { steps.any? { it.block(block_id) } }
      latest = {}
      run.executions.each { latest[it[:block_id]] = it if mine.call(it[:block_id]) }
      executions = latest.transform_values do |hash|
        live = session.execution(hash[:id])
        (live ? live.to_h : hash).merge(output: output_for(run, live, hash), success: hash[:state] == "finished" && hash[:exit_status] == 0)
      end
      acks = run.acks.select { |block_id, _| mine.call(block_id) }
      JSON.generate({ executions:, acks: }).gsub("</", "<\\/")
    end

    # ------------------------------------------------------------------
    # Checks page: every verify document on one page
    # ------------------------------------------------------------------

    def self.verify(session, nonce: nil)
      runbook = session.runbook
      docs    = runbook.verify_documents
      checks  = runbook.verify_blocks.size
      banner = if session.active?
                 ""
               else
                 "<div class=\"banner info\">#{ICONS[:alert]}<div>No active run. <a href=\"/\">Start a verification</a> from the home page to run these checks on their own, or start a full run.</div></div>"
               end
      toolbar = if session.active? && checks.positive?
                  "<div class=\"btn-row verify-toolbar\"><button type=\"button\" class=\"btn primary\" data-action=\"run-all\">#{ICONS[:check]} Run all #{checks} check#{'s' unless checks == 1}</button><span class=\"meta\" data-role=\"run-all-status\"></span></div>"
                else
                  ""
                end
      sections = docs.map do |doc|
        label = doc.position ? "Step #{h(doc.number || doc.position)}" : "verify.md"
        <<~SECTION
          <section class="check-doc">
            <h2 id="check-#{h doc.slug}"><span class="badge verify">#{label}</span> <a href="#{h step_href(doc)}">#{h doc.title}</a></h2>
            #{warnings_banner(doc.warnings)}
            <article class="markdown-body">#{doc.html}</article>
          </section>
        SECTION
      end
      body = <<~HTML
        <div class="page-head">
          <h1>#{ICONS[:check]} Checks</h1>
          <p class="sub">#{docs.size} verify document#{'s' unless docs.size == 1} · #{checks} executable check#{'s' unless checks == 1}#{" · last verified #{h runbook.last_verified}" if runbook.last_verified}</p>
        </div>
        #{banner}
        #{toolbar}
        #{sections.join}
        <script type="application/json" id="rs-prior">#{prior_executions_json(session, *docs)}</script>
      HTML
      layout(session, title: "Checks", body:, kind: :verify, nonce:)
    end

    def self.output_for(run, live, hash)
      return live.output(tail: Web::OUTPUT_TAIL) if live

      path = hash[:log] && File.join(run.blocks_dir, hash[:log])
      path && File.file?(path) ? File.binread(path).force_encoding("UTF-8").scrub : ""
    end

    # ------------------------------------------------------------------
    # Runsheet (run record) page and errors
    # ------------------------------------------------------------------

    def self.run(session, record, nonce: nil)
      html = Renderer.render(record.transcript, id_prefix: "run").html
      body = <<~HTML
        <div class="page-head">
          <h1>#{ICONS[:log]} Runsheet #{h record.id}</h1>
          <p class="sub">#{record.verify? ? 'verification' : 'full run'} · #{h record.status} · #{record.executions.size} execution#{'s' unless record.executions.size == 1} · #{record.failed_executions.size} failed · #{h duration_text(record.duration)} · <code>#{h record.dir}</code></p>
        </div>
        #{drift_panel(session, record)}
        <article class="markdown-body">#{html}</article>
      HTML
      layout(session, title: "Runsheet #{record.id}", body:, kind: :run, nonce:)
    end

    # Blocks whose code has changed, or that are gone, since this run.
    def self.drift_panel(session, record)
      return "" if record.active?

      drift = record.drift(session.runbook)
      return "" if drift.empty?

      items = drift.map do |entry|
        if entry[:status] == :missing
          "<li><code>#{h entry[:block_id]}</code> is no longer in the runbook.<pre class=\"diff\">#{entry[:recorded].lines.map { "<span class=\"del\">-#{h it.chomp}</span>" }.join("\n")}</pre></li>"
        else
          rows = entry[:diff].map do |line|
            cls = line.added? ? "add" : line.removed? ? "del" : "ctx"
            "<span class=\"#{cls}\">#{h line.to_s}</span>"
          end
          "<li><code>#{h entry[:block_id]}</code> has changed since it ran.<pre class=\"diff\">#{rows.join("\n")}</pre></li>"
        end
      end
      <<~HTML
        <section class="panel drift">
          <h2>#{ICONS[:alert]} Runbook changed since this run</h2>
          <p class="meta">What ran is in the record; this is how the runbook reads now.</p>
          <ul>#{items.join}</ul>
        </section>
      HTML
    end

    def self.error(session, message, status, nonce: nil)
      body = <<~HTML
        <div class="page-head">
          <h1>#{status}</h1>
          <p class="sub">#{h message}</p>
          <p><a class="btn" href="/">#{ICONS[:home]} Home</a></p>
        </div>
      HTML
      layout(session, title: "Error #{status}", body:, kind: :error, nonce:)
    end
  end
end

require_relative "pages/chooser"
require_relative "pages/tree"
