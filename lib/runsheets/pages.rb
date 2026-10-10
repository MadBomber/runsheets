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

    def self.layout(session, title:, body:, kind:, step: nil, nonce: nil, query: "")
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
          #{header(session, step:, kind:, query:)}
          <div class="rs-shell">
            #{sidebar(session, step:, kind:)}
            <main class="rs-main">
              #{body}
            </main>
          </div>
          <footer class="rs-footer">
            <span>#{h APP_NAME} · #{h APP_FULL} · #{h runbook.dir}</span>
            <span class="keys"><kbd>f</kbd> search <kbd>h</kbd> home <kbd>←</kbd><kbd>→</kbd> prev/next step <kbd>s</kbd> sidebar</span>
          </footer>
          <script#{nonce_attr}>#{Assets.javascript}</script>
        </body>
        </html>
      HTML
    end

    # The search box in every header: a plain GET form, so it works
    # without script. [f] focuses it.
    def self.search_box(query = "")
      "<form class=\"rs-search\" action=\"/search\" method=\"get\" role=\"search\">#{ICONS[:search]}" \
        "<input type=\"search\" name=\"q\" id=\"rs-search\" value=\"#{h query}\" placeholder=\"Search runbooks\" " \
        "aria-label=\"Search runbooks\" autocomplete=\"off\" spellcheck=\"false\"><kbd>f</kbd></form>"
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

    def self.header(session, step:, kind:, query: "")
      runbook   = session.runbook
      prev, nxt = step ? runbook.neighbors(step) : [nil, nil]
      crumbs    = library_crumbs(session)
      crumbs << (kind == :landing ? "<span class=\"current\">#{h runbook.title}</span>" : "<a href=\"/\">#{h runbook.title}</a>")
      crumbs << "<span class=\"current\">#{h step.title}</span>" if step
      crumbs << '<span class="current">Runsheet</span>' if kind == :run
      crumbs << '<span class="current">Checks</span>' if kind == :verify
      crumbs << '<span class="current">Session</span>' if kind == :session

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
            #{search_box(query)}
            #{nav_button('Runbooks', '/library', :book, key: 'r', title: 'Choose another runbook') if session.library}
            #{nav_button('Prev', prev && step_href(prev), :prev, key: '←', title: prev&.title)}
            #{nav_button('Next', nxt && step_href(nxt), :next, key: '→', title: nxt&.title)}
            #{session_pill(session)}
          </nav>
        </header>
      HTML
    end

    # The session in the header: who, for how long, how many runbooks,
    # linking to the session page.
    def self.session_pill(session)
      runs  = session.runs.size
      title = "Session #{session.id}: #{session.why}"
      "<a class=\"run-pill active\" href=\"/session\" title=\"#{h title}\"><span class=\"dot\"></span>" \
        "#{h session.engineer} · #{h duration_text(session.elapsed)}#{" · #{runs} runbook#{'s' unless runs == 1}" if runs.positive?}</a>"
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
          #{rollback_panel(session, kind)}
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

    def self.rollback_panel(session, kind)
      rollback = session.runbook.rollback
      return "" unless rollback && kind == :step

      <<~HTML
        <section>
          <details>
            <summary>Rollback</summary>
            <div class="rollback-body markdown-body">#{document_html(session, rollback)}</div>
          </details>
        </section>
      HTML
    end

    # Processes still running anywhere in the session, each with a Stop
    # button. The page's JavaScript keeps the entries current.
    def self.running_panel(session)
      running = session.running
      return "" if running.empty?

      items = running.map do |run, ex|
        here = run == session.current
        step = here && run.runbook.step(ex.step_slug)
        href = step ? "#{step_href(step)}#block-#{Rack::Utils.escape_path(ex.block_id)}" : Chooser.href(run.slug)
        <<~LI
          <li data-execution="#{h ex.id}">
            <a href="#{h href}" title="#{h run.slug} · #{h ex.step_slug}"><code>#{h ex.block_id}</code>#{" <small>#{h run.slug}</small>" unless here}</a>
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
          <p class="sub">#{runbook.steps.size} step#{'s' unless runbook.steps.size == 1}</p>
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
    # on its own and passes the rows without it.
    def self.meta_table(runbook, rows = meta_rows(runbook))
      return "" if rows.empty?

      "<table class=\"meta-table\">#{rows.map { |k, v| "<tr><th>#{k}</th><td>#{v}</td></tr>" }.join}</table>"
    end

    # label => html for each front-matter fact the runbook states.
    def self.meta_rows(runbook)
      rows = {}
      rows["When to use"] = h(runbook.when_to_use) if runbook.when_to_use
      rows["Prerequisites"] = "<ul>#{runbook.prerequisites.map { "<li>#{h it}</li>" }.join}</ul>" if runbook.prerequisites.any?
      rows["Blast radius"] = "<span class=\"badge destructive\">destructive</span> #{h runbook.blast_radius}" if runbook.blast_radius
      rows["Escalation"] = h(runbook.escalation) if runbook.escalation
      rows
    end

    # Start-run form, or the active run's controls.
    def self.run_panel(session)
      session.active? ? active_run_panel(session) : start_panel(session)
    end

    def self.active_run_panel(session)
      record  = session.run
      runbook = session.runbook
      <<~HTML
        <section class="panel">
          <h2>Run open</h2>
          <p><strong>#{h record.id}</strong> opened #{h record.started_at.strftime('%Y-%m-%d %H:%M:%S')} · #{run_progress(record, runbook)} · <a href="/run">view runsheet</a></p>
          #{inputs_line(record.inputs, session.secret_inputs_set)}
          <p class="meta">Work through the steps in order, or open any step and run only that. The run stays open until the session ends.</p>
          <div class="btn-row">#{go_buttons(runbook)}</div>
          #{change_inputs_form(session) if runbook.inputs.any?}
        </section>
      HTML
    end

    def self.run_progress(record, runbook)
      "#{record.executions.size} execution#{'s' unless record.executions.size == 1} · #{record.steps_done} of #{runbook.steps.size} steps done"
    end

    # Work through the steps from the first, or go to the checks.
    def self.go_buttons(runbook)
      first  = runbook.steps.first
      checks = runbook.verify_blocks.size
      buttons = []
      buttons << "<a class=\"btn primary\" href=\"#{h step_href(first)}\">#{ICONS[:next]} Work through the steps</a>" if first
      buttons << "<a class=\"btn\" href=\"/verify\">#{ICONS[:check]} Go to checks (#{checks})</a>" if checks.positive?
      buttons.join
    end

    KEEP_SECRET = "leave blank to keep the current value"

    # The start form's fields, prefilled with +values+.
    def self.input_fields(runbook, values) = runbook.inputs.map { input_field(it, values[it.name]) }.join

    # The change form's fields: secrets are left empty, and an empty one
    # keeps the value the run already has, so a secret never comes back to
    # the page.
    def self.change_input_fields(runbook, values)
      runbook.inputs.map { it.secret? ? input_field(it, "", KEEP_SECRET) : input_field(it, values[it.name]) }.join
    end

    # One input as a labelled field; a secret is a password field.
    def self.input_field(input, value, placeholder = "")
      name   = h input.name
      secret = input.secret?
      <<~FIELD
        <div class="field">
          <label for="input-#{name}">#{h input.prompt}<code>$#{name}#{' · secret, not recorded' if secret}</code></label>
          <input type="#{secret ? 'password' : 'text'}" id="input-#{name}" name="inputs[#{name}]" value="#{h value}" placeholder="#{h placeholder}" autocomplete="off">
        </div>
      FIELD
    end

    def self.change_inputs_form(session)
      <<~HTML
        <details class="change-inputs">
          <summary>Change inputs</summary>
          <form method="post" action="/run/inputs">
            <input type="hidden" name="_token" value="#{h session.token}">
            #{change_input_fields(session.runbook, session.current.inputs)}
            <div class="btn-row"><button class="btn" type="submit">Change inputs</button><span class="meta">Blocks run from now on see the new values; the change is recorded.</span></div>
          </form>
        </details>
      HTML
    end

    def self.start_panel(session)
      runbook = session.runbook
      <<~HTML
        <section class="panel">
          <h2>Start a run</h2>
          <form method="post" action="/runs">
            <input type="hidden" name="_token" value="#{h session.token}">
            <input type="hidden" name="slug" value="#{h runbook.slug}">
            #{input_fields(runbook, session.resolve_inputs)}
            <div class="btn-row"><button class="btn primary" type="submit">Start run</button><span class="meta">The run stays open until the session ends. Its runsheet goes under #{h session.runs_root}</span></div>
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
      verdict = s[:status]
      <<~LI
        <li class="#{h verdict}">
          <a href="/runs/#{h s[:id]}">#{h s[:id]}</a>
          #{run.verify? ? '<span class="badge verify">verify</span>' : '<span></span>'}
          <span class="meta verdict">#{h verdict}</span>
          <span class="meta">#{h run.started_at.strftime('%Y-%m-%d %H:%M')} · #{h duration_text(s[:duration])}</span>
          <span class="meta">#{s[:executions]} exec · #{s[:failures]} failed</span>
          <span class="meta">#{history_progress(run, s, total)}</span>
        </li>
      LI
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
        <article class="markdown-body">#{document_html(session, step)}</article>
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
      if step.executable_blocks.any? && !session.active?
        banners << info_banner('No run for this runbook yet. Blocks can be read and copied but not executed. <a href="/">Start the run</a> first.')
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

    # A document's rendered markdown with every button that cannot work right
    # now rendered disabled, its title saying why.
    def self.document_html(session, doc)
      locks = { "execute" => execute_lock(session, doc), "acknowledge" => acknowledge_lock(session) }
      locks.compact.reduce(doc.html) { |html, (action, reason)| lock_buttons(html, action, reason) }
    end

    # Why blocks cannot execute right now, or nil if they can.
    def self.execute_lock(session, _doc) = session.active? ? nil : "Start a run to execute blocks"

    # Why terminal blocks cannot be confirmed right now, or nil if they can.
    def self.acknowledge_lock(session) = session.active? ? nil : "Start a run to confirm terminal blocks"

    # Every button in +html+ with this data-action, disabled, marked
    # data-locked, and titled with +reason+.
    def self.lock_buttons(html, action, reason)
      html.gsub(%(data-action="#{action}"), %(data-action="#{action}" data-locked disabled title="#{h reason}"))
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
                 "<div class=\"banner info\">#{ICONS[:alert]}<div>No run for this runbook yet. <a href=\"/\">Start the run</a> to run these checks.</div></div>"
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
            <article class="markdown-body">#{document_html(session, doc)}</article>
          </section>
        SECTION
      end
      body = <<~HTML
        <div class="page-head">
          <h1>#{ICONS[:check]} Checks</h1>
          <p class="sub">#{docs.size} verify document#{'s' unless docs.size == 1} · #{checks} executable check#{'s' unless checks == 1}</p>
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

    # A plain markdown document the runbook links to: rendered, with nothing
    # executable, its front matter (if any) left out.
    # Its relative links resolve from the library, or from the open
    # runbook's root. With a runbook open the page sits in its layout; in a library with
    # none open yet, in the library's frame beside the tree.
    def self.document(session, path, library: nil, token: nil, nonce: nil)
      root  = library&.dir || session.runbook.root
      text  = FrontMatter.parse(File.read(path, encoding: "UTF-8")).body
      title = Renderer.title_of(text) || File.basename(path, ".*")
      base  = File.dirname(path).delete_prefix(Runbook.real_path(root)).delete_prefix("/")
      html  = Renderer.rewrite_relative_urls(Renderer.render_plain(text), base)
      body  = <<~HTML
        <div class="banner info">#{ICONS[:alert]}<div>A document linked from a runbook, not a step: nothing here executes.</div></div>
        <article class="markdown-body">#{html}</article>
      HTML
      return layout(session, title:, body:, kind: :document, nonce:) if session&.runbook

      Chooser.frame(Chooser::View.new(library:, session:, token:, node: library.root), title:, main: body, nonce:)
    end

    # ------------------------------------------------------------------
    # The session: starting it, the notebook, and its end
    # ------------------------------------------------------------------

    # A page with no runbook around it: the start page and the end page.
    def self.bare(title:, body:, token:, nonce: nil)
      nonce_attr = nonce ? %( nonce="#{h nonce}") : ""
      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="rs-token" content="#{h token}">
          <title>#{h title} · #{h APP_NAME}</title>
          <style#{nonce_attr}>#{Assets.stylesheet}</style>
        </head>
        <body class="kind-bare">
          <main class="bare-main">#{body}</main>
          <script#{nonce_attr}>#{Assets.javascript}</script>
        </body>
        </html>
      HTML
    end

    # Who is starting the session, and why. +error+ explains a refused form.
    def self.session_new(token, engineer: nil, why: nil, error: nil, nonce: nil)
      body = <<~HTML
        <section class="panel session-start">
          <h1>#{ICONS[:book]} Start a session</h1>
          <p class="meta">Everything from now until runsheets stops is one session: the runbooks you open, what you run, and your notes, written to a log as it happens.</p>
          #{"<div class=\"banner danger\">#{ICONS[:alert]}<div>#{h error}</div></div>" if error}
          <form method="post" action="/session">
            <input type="hidden" name="_token" value="#{h token}">
            <div class="field"><label for="engineer">Who are you?</label><input type="text" id="engineer" name="engineer" value="#{h engineer}" required autocomplete="name"></div>
            <div class="field"><label for="why">Why are you starting this session?<code>the first note</code></label><textarea id="why" name="why" rows="3" required placeholder="Monthly maintenance on the app database">#{h why}</textarea></div>
            <div class="btn-row"><button class="btn primary" type="submit">#{ICONS[:next]} Start the session</button></div>
          </form>
        </section>
      HTML
      bare(title: "Start a session", body:, token:, nonce:)
    end

    # The notebook so far: who, why, the notes, the runs, the log.
    def self.session(session, library, token, nonce: nil)
      body = session_body(session)
      return layout(session, title: "Session", body:, kind: :session, nonce:) if session.runbook

      Chooser.frame(Chooser::View.new(library:, session:, token:, node: library.root), title: "Session", main: body, nonce:)
    end

    def self.session_body(session)
      <<~HTML
        <div class="page-head">
          <h1>#{ICONS[:log]} Session #{h session.id}</h1>
          <p class="sub">#{h session.engineer} · #{h session.host} · started #{h session.started_at.strftime('%Y-%m-%d %H:%M:%S')} · #{h duration_text(session.elapsed)}#{" · #{h session.status}" if session.ended?}</p>
        </div>
        #{session_notes(session)}
        #{session_runs(session)}
        #{session_end_panel(session) unless session.ended?}
        #{session_log_tail(session)}
      HTML
    end

    def self.session_notes(session)
      items = session.notes.map { "<li><time>#{h it[:at].strftime('%H:%M:%S')}</time><div>#{h(it[:text]).gsub("\n", '<br>')}</div></li>" }
      form = if session.ended?
               ""
             else
               <<~FORM
                 <form method="post" action="/session/notes" class="note-form">
                   <input type="hidden" name="_token" value="#{h session.token}">
                   <textarea name="note" rows="2" required placeholder="What happened, what you decided, what changed"></textarea>
                   <button class="btn" type="submit">Add note</button>
                 </form>
               FORM
             end
      "<section class=\"panel\" id=\"notes\"><h2>Notes</h2><ol class=\"notes\">#{items.join}</ol>#{form}</section>"
    end

    def self.session_runs(session)
      return '<section class="panel"><h2>Runs</h2><p class="empty">No runbook selected yet.</p></section>' if session.runs.empty?

      rows = session.runs.map do |run|
        record = run.record
        <<~LI
          <li class="#{h record.status}">
            <span><strong>#{h run.runbook.title}</strong> <code>#{h run.slug}</code></span>
            <span class="meta verdict">#{h record.active? ? record.closing_status(run.runbook.steps.map(&:slug)) + ' so far' : record.status}</span>
            <span class="meta">#{h run_progress(record, run.runbook)}</span>
            <span>#{run_link(session, run)}</span>
          </li>
        LI
      end
      "<section class=\"panel\"><h2>Runs</h2><ul class=\"history session-runs\">#{rows.join}</ul></section>"
    end

    # Back to a run: its page when it is on screen, else select it again.
    def self.run_link(session, run)
      return '<a class="btn" href="/">On screen</a>' if run == session.current
      return "" if session.ended?

      "<form method=\"post\" action=\"/runs\"><input type=\"hidden\" name=\"_token\" value=\"#{h session.token}\">" \
        "<input type=\"hidden\" name=\"slug\" value=\"#{h run.slug}\"><button class=\"btn\" type=\"submit\">Return to it</button></form>"
    end

    def self.session_end_panel(session)
      <<~HTML
        <section class="panel">
          <h2>End the session</h2>
          <p class="meta">Every run closes with the status its work earns (completed, partial, or opened), anything still running is stopped, and runsheets exits. Ctrl-C in the terminal does the same.</p>
          <form method="post" action="/session/end">
            <input type="hidden" name="_token" value="#{h session.token}">
            <button class="btn danger" type="submit">End session</button>
          </form>
        </section>
      HTML
    end

    # The last lines of the session log.
    def self.session_log_tail(session, lines: 200)
      path = session.log.path
      text = File.file?(path) ? File.readlines(path).last(lines).join : ""
      <<~HTML
        <section class="panel">
          <h2>Session log</h2>
          <p class="meta"><code>#{h path}</code> · the last #{lines} lines; <code>tail -f</code> it for the rest</p>
          <pre class="session-log">#{h text}</pre>
        </section>
      HTML
    end

    # What the browser shows after End session.
    def self.session_ended(session, nonce: nil)
      runs = session.runs.map { "<li><strong>#{h it.runbook.title}</strong> · #{h it.record.status}</li>" }
      body = <<~HTML
        <section class="panel session-start">
          <h1>#{ICONS[:check]} Session ended</h1>
          <p>#{h session.engineer} · #{h duration_text(session.elapsed)} · runsheets is stopping.</p>
          #{"<ul>#{runs.join}</ul>" unless runs.empty?}
          <p class="meta">The record and the log are in <code>#{h session.dir}</code>.</p>
        </section>
      HTML
      bare(title: "Session ended", body:, token: session.token, nonce:)
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
require_relative "pages/search"
