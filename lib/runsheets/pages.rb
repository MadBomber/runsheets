# frozen_string_literal: true

module Runsheets
  # Pure functions that build the HTML pages from a Session. No HTTP here, so
  # every page can be rendered and inspected in a test.
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
      log:    '<svg class="icon" viewBox="0 0 24 24"><path d="M5 4h14v16H5z"/><path d="M8 9h8M8 13h8M8 17h5"/></svg>'
    }.freeze

    STATUS_MARKS = { "done" => "✓", "skipped" => "↷", "failed" => "✗", "ran" => "•", "pending" => "·" }.freeze

    def self.h(value) = Renderer.h(value)

    # ------------------------------------------------------------------
    # Layout
    # ------------------------------------------------------------------

    def self.layout(session, title:, body:, kind:, step: nil)
      runbook = session.runbook
      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="rs-token" content="#{h session.token}">
          <meta name="rs-runbook" content="#{h runbook.slug}">
          <title>#{h title} · #{h runbook.title}</title>
          <style>#{Assets.stylesheet}</style>
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
          <script>#{Assets.javascript}</script>
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
      crumbs    = [kind == :landing ? "<span class=\"current\">#{h runbook.title}</span>" : "<a href=\"/\">#{h runbook.title}</a>"]
      crumbs << "<span class=\"current\">#{h step.title}</span>" if step
      crumbs << '<span class="current">Run record</span>' if kind == :run

      pill = if session.active?
               "<a class=\"run-pill active\" href=\"/run\" title=\"Active run\"><span class=\"dot\"></span>run #{h session.run.id}</a>"
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
            #{nav_button('Prev', prev && step_href(prev), :prev, key: '←', title: prev&.title)}
            #{nav_button('Next', nxt && step_href(nxt), :next, key: '→', title: nxt&.title)}
            #{pill}
          </nav>
        </header>
      HTML
    end

    # Sidebar: the step list with run status marks, extra documents, the
    # rollback panel, and an outline for the current page.
    def self.sidebar(session, step:, kind:)
      runbook = session.runbook
      items = runbook.steps.map do |s|
        status = step_mark(session, s)
        active = s == step ? ' class="active"' : ""
        <<~LI
          <li#{active}><a href="#{h step_href(s)}" title="#{h s.title}">
            <span class="num">#{h(s.number || s.position)}</span>
            <span class="name">#{h s.title}</span>
            <span class="mark #{status}" title="#{status}">#{STATUS_MARKS[status]}</span>
          </a></li>
        LI
      end

      extras = runbook.extras.values.map do |s|
        active = s == step ? ' class="active"' : ""
        "<li#{active}><a href=\"#{h step_href(s)}\"><span class=\"num\">#{ICONS[:book]}</span><span class=\"name\">#{h s.title}</span><span></span></a></li>"
      end
      extras << "<li><a href=\"/run\"><span class=\"num\">#{ICONS[:log]}</span><span class=\"name\">Run record</span><span></span></a></li>" if session.active?

      rollback = runbook.rollback && kind == :step ? <<~HTML : ""
        <section>
          <details>
            <summary>Rollback</summary>
            <div class="rollback-body markdown-body">#{runbook.rollback.html}</div>
          </details>
        </section>
      HTML

      <<~HTML
        <aside class="rs-sidebar">
          #{running_panel(session)}
          <section>
            <h2>Steps</h2>
            <ol class="steps">#{items.join}</ol>
          </section>
          #{extras.empty? ? '' : "<section><h2>Also</h2><ul>#{extras.join}</ul></section>"}
          #{rollback}
          <section class="outline"><h2>On this page</h2><ol id="outline"></ol></section>
        </aside>
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

    def self.landing(session)
      runbook = session.runbook
      body = [page_head(runbook), warnings_banner(runbook.warnings), meta_table(runbook),
              run_panel(session), steps_list(session), history_panel(session),
              "<article class=\"markdown-body\">#{runbook.preamble_html}</article>"].join("\n")
      layout(session, title: "Home", body:, kind: :landing)
    end

    def self.page_head(runbook)
      badges = runbook.tags.map { "<span class=\"badge tag\">#{h it}</span>" }
      badges.unshift('<span class="badge destructive">destructive</span>') if runbook.destructive?
      <<~HTML
        <div class="page-head">
          <h1>#{ICONS[:book]} #{h runbook.title}</h1>
          <p class="sub">#{runbook.steps.size} step#{'s' unless runbook.steps.size == 1}#{" · last verified #{h runbook.last_verified}" if runbook.last_verified}</p>
          #{badges.empty? ? '' : "<div class=\"badges\">#{badges.join}</div>"}
        </div>
      HTML
    end

    def self.warnings_banner(warnings)
      return "" if warnings.empty?

      <<~HTML
        <div class="banner warn">#{ICONS[:alert]}<div><strong>Authoring warnings</strong><ul>#{warnings.map { "<li>#{h it}</li>" }.join}</ul></div></div>
      HTML
    end

    def self.meta_table(runbook)
      rows = []
      rows << ["When to use", h(runbook.when_to_use)] if runbook.when_to_use
      rows << ["Prerequisites", "<ul>#{runbook.prerequisites.map { "<li>#{h it}</li>" }.join}</ul>"] if runbook.prerequisites.any?
      rows << ["Blast radius", "<span class=\"badge destructive\">destructive</span> #{h runbook.blast_radius}"] if runbook.blast_radius
      rows << ["Escalation", h(runbook.escalation)] if runbook.escalation
      rows << ["Last verified", h(runbook.last_verified)] if runbook.last_verified
      return "" if rows.empty?

      "<table class=\"meta-table\">#{rows.map { |k, v| "<tr><th>#{k}</th><td>#{v}</td></tr>" }.join}</table>"
    end

    # Start-run form, or the active run's controls.
    def self.run_panel(session)
      runbook = session.runbook
      if session.active?
        run = session.run
        <<~HTML
          <section class="panel">
            <h2>Active run</h2>
            <p><strong>#{h run.id}</strong> started #{h run.started_at.strftime('%Y-%m-%d %H:%M:%S')} · #{run.executions.size} execution#{'s' unless run.executions.size == 1} · #{run.steps_done} of #{runbook.steps.size} steps done · <a href="/run">view record</a></p>
            #{inputs_line(run.inputs, session.secret_inputs_set)}
            <div class="btn-row">
              #{runbook.steps.first ? "<a class=\"btn primary\" href=\"#{h step_href(runbook.steps.first)}\">Go to first step</a>" : ''}
              <form method="post" action="/run/finish"><input type="hidden" name="_token" value="#{h session.token}"><input type="hidden" name="status" value="completed"><button class="btn ok" type="submit">Finish run</button></form>
              <form method="post" action="/run/finish"><input type="hidden" name="_token" value="#{h session.token}"><input type="hidden" name="status" value="abandoned"><button class="btn danger" type="submit">Abandon run</button></form>
            </div>
          </section>
        HTML
      else
        fields = runbook.inputs.map do |input|
          value = session.resolve_inputs[input.name]
          type  = input.secret? ? "password" : "text"
          <<~FIELD
            <div class="field">
              <label for="input-#{h input.name}">#{h input.prompt}<code>$#{h input.name}#{' · secret, not recorded' if input.secret?}</code></label>
              <input type="#{type}" id="input-#{h input.name}" name="inputs[#{h input.name}]" value="#{h value}" autocomplete="off">
            </div>
          FIELD
        end
        <<~HTML
          <section class="panel">
            <h2>Start a run</h2>
            <form method="post" action="/run">
              <input type="hidden" name="_token" value="#{h session.token}">
              #{fields.join}
              <div class="btn-row"><button class="btn primary" type="submit">Start run</button><span class="meta">Creates a run record under #{h session.runs_root}</span></div>
            </form>
          </section>
        HTML
      end
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
        badges = ["<span class=\"badge #{step.kind}\">#{step.kind}</span>"]
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

    def self.history_panel(session)
      runs = session.history
      return "" if runs.empty?

      rows = runs.first(20).map do |run|
        s = run.summary
        <<~LI
          <li>
            <a href="/runs/#{h s[:id]}">#{h s[:id]}</a>
            <span class="meta">#{h s[:status]}</span>
            <span class="meta">#{s[:executions]} exec · #{s[:failures]} failed</span>
            <span class="meta">#{s[:steps_done]} steps done</span>
          </li>
        LI
      end
      "<section class=\"panel\"><h2>Previous runs</h2><ul class=\"history\">#{rows.join}</ul></section>"
    end

    # ------------------------------------------------------------------
    # Step page
    # ------------------------------------------------------------------

    def self.step(session, step)
      runbook = session.runbook
      badges  = ["<span class=\"badge #{step.kind}\">#{step.kind}</span>"]
      badges << '<span class="badge destructive">destructive</span>' if step.destructive?
      badges << "<span class=\"badge\">timeout #{step.timeout}s</span>" if step.executable_blocks.any?

      confirm = " Running a destructive block asks you to type a confirmation code first."
      banner = if step.destructive? && runbook.blast_radius
                 "<div class=\"banner danger\">#{ICONS[:alert]}<div><strong>Blast radius</strong><br>#{h runbook.blast_radius}#{runbook.escalation ? "<br><strong>Escalation</strong><br>#{h runbook.escalation}" : ''}<br>#{confirm}</div></div>"
               elsif step.destructive?
                 "<div class=\"banner danger\">#{ICONS[:alert]}<div><strong>This step is destructive.</strong> Read it fully before running anything.#{confirm}</div></div>"
               else
                 ""
               end
      banner += "<div class=\"banner info\">#{ICONS[:alert]}<div>No active run. Blocks can be read and copied but not executed. <a href=\"/\">Start a run</a> first.</div></div>" if step.executable_blocks.any? && !session.active?

      body = <<~HTML
        <div class="page-head">
          <h1>#{step.position ? "<span class=\"num\">#{h(step.number || step.position)}</span>" : ''} #{h step.title}</h1>
          <div class="badges">#{badges.join}</div>
        </div>
        #{warnings_banner(step.warnings)}
        #{banner}
        <article class="markdown-body">#{step.html}</article>
        #{mark_panel(session, step)}
        #{step_nav(runbook, step)}
        <script type="application/json" id="rs-prior">#{prior_executions_json(session, step)}</script>
      HTML
      layout(session, title: step.title, body:, kind: :step, step:)
    end

    def self.mark_panel(session, step)
      return "" unless session.active? && step.position

      status  = session.step_status(step.slug)
      heading = step.manual? ? "Acknowledge this step" : "Step status"
      done    = step.manual? ? "I have done this, continue" : "Mark done and continue"
      hint    = step.manual? ? "A manual step is complete when you say so. The acknowledgement and your note go into the run record." : ""
      <<~HTML
        <section class="panel">
          <h2>#{heading}#{status ? ": #{h status}" : ''}</h2>
          #{hint.empty? ? '' : "<p class=\"meta\">#{hint}</p>"}
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

    # The last execution of each block on this step, and the terminal
    # blocks the operator has confirmed, for the page to restore.
    def self.prior_executions_json(session, step)
      run = session.run
      return "{}" unless run

      latest = {}
      run.executions.each { latest[it[:block_id]] = it if step.block(it[:block_id]) }
      executions = latest.transform_values do |hash|
        live = session.execution(hash[:id])
        (live ? live.to_h : hash).merge(output: output_for(run, live, hash), success: hash[:state] == "finished" && hash[:exit_status] == 0)
      end
      acks = run.acks.select { |block_id, _| step.block(block_id) }
      JSON.generate({ executions:, acks: }).gsub("</", "<\\/")
    end

    def self.output_for(run, live, hash)
      return live.output(tail: Web::OUTPUT_TAIL) if live

      path = hash[:log] && File.join(run.blocks_dir, hash[:log])
      path && File.file?(path) ? File.binread(path).force_encoding("UTF-8").scrub : ""
    end

    # ------------------------------------------------------------------
    # Run record page and errors
    # ------------------------------------------------------------------

    def self.run(session, record)
      html = Renderer.render(record.transcript, id_prefix: "run").html
      body = <<~HTML
        <div class="page-head">
          <h1>#{ICONS[:log]} Run #{h record.id}</h1>
          <p class="sub">#{h record.status} · #{record.executions.size} execution#{'s' unless record.executions.size == 1} · #{record.failed_executions.size} failed · <code>#{h record.dir}</code></p>
        </div>
        <article class="markdown-body">#{html}</article>
      HTML
      layout(session, title: "Run #{record.id}", body:, kind: :run)
    end

    def self.error(session, message, status)
      body = <<~HTML
        <div class="page-head">
          <h1>#{status}</h1>
          <p class="sub">#{h message}</p>
          <p><a class="btn" href="/">#{ICONS[:home]} Home</a></p>
        </div>
      HTML
      layout(session, title: "Error #{status}", body:, kind: :error)
    end
  end
end
