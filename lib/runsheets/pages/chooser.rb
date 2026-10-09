# frozen_string_literal: true

module Runsheets
  module Pages
    # The library page: the home of a server started on a directory of
    # runbooks. The folder tree sits in the left pane; the right pane shows
    # whatever is selected in it, a folder (its README and cards for what
    # it holds) or a runbook (everything worth knowing before opening it,
    # and the Open button). Nothing selected shows the root folder.
    #
    # Every function takes the pieces it needs, so each can be rendered
    # and inspected on its own.
    module Chooser
      # How much of when_to_use a card shows.
      BLURB = 160

      # The badge each state of a runbook adds to its pane. :current is open
      # now, :broken does not load, :locked waits for the active run to
      # finish, :ready can be opened (see .action).
      BADGES = {
        current: '<span class="badge current">open now</span>',
        broken:  '<span class="badge destructive">does not load</span>',
        locked:  "",
        ready:   ""
      }.freeze

      module_function

      def h(value) = Renderer.h(value)

      def href(slug) = slug.to_s.empty? ? "/library" : "/library/#{slug.to_s.split('/').map { Rack::Utils.escape_path(it) }.join('/')}"

      # The state a runbook is in for this session (see STATES).
      def state_of(entry, session)
        if entry.slug == session&.runbook&.slug then :current
        elsif !entry.ok?                         then :broken
        elsif session&.active?                   then :locked
        else :ready
        end
      end

      # ----------------------------------------------------------------
      # Page
      # ----------------------------------------------------------------

      # +selected+ is the slug of a runbook or a folder, or nil for the root.
      def page(library, session, token, nonce: nil, selected: nil)
        node       = library.node(selected.to_s) || library.root
        nonce_attr = nonce ? %( nonce="#{h nonce}") : ""
        title      = node.folder? && node.root? ? "Runbooks" : node.title
        main       = node.folder? ? folder_pane(library, node, session, token) : runbook_pane(library, node, session, token)
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
          <body class="kind-library">
            #{header(library, node, session)}
            <div class="rs-shell">
              #{Tree.pane(library, node, session)}
              <main class="rs-main lib-main">
                #{main}
              </main>
            </div>
            <footer class="rs-footer">
              <span>#{h APP_NAME} · #{h APP_FULL} · #{h library.dir}</span>
              <span class="keys"><kbd>/</kbd> filter <kbd>↑</kbd><kbd>↓</kbd> move <kbd>↵</kbd> select <kbd>o</kbd> open <kbd>s</kbd> tree</span>
            </footer>
            <script#{nonce_attr}>#{Assets.javascript}</script>
          </body>
          </html>
        HTML
      end

      def header(library, node, session)
        <<~HTML
          <header class="rs-header">
            <div class="brand">
              <button class="icon-btn sidebar-toggle" type="button" title="Toggle the tree [s]" aria-label="Toggle the tree">#{ICONS[:menu]}</button>
              <a class="home" href="/library" title="Runbooks [h]" data-key="h">
                #{ICONS[:book]}
                <span class="brand-name">#{h APP_NAME}</span>
                <span class="brand-tag">#{h File.basename(library.dir)}</span>
              </a>
            </div>
            <nav class="crumbs" aria-label="Breadcrumb">#{crumbs(library, node).join('<span class="sep">/</span>')}</nav>
            <nav class="actions">
              #{Pages.nav_button('Back to runbook', '/', :next, key: 'b', title: session.runbook.title) if session}
              #{pill(session)}
            </nav>
          </header>
        HTML
      end

      # Runbooks / folder / folder / selected. Every crumb but the last is a link.
      def crumbs(library, node)
        chain = node.folder? && node.root? ? [] : [*library.ancestors(node.slug), node]
        links = chain.map { "<a href=\"#{h href(it.slug)}\">#{h it.title}</a>" }
        links.unshift('<a href="/library">Runbooks</a>')
        links[-1] = links[-1].sub(/\A<a href="[^"]*">/, '<span class="current">').sub(%r{</a>\z}, "</span>")
        links
      end

      def pill(session)
        return '<span class="run-pill"><span class="dot"></span>no runbook open</span>' unless session

        label = session.active? ? "#{session.verifying? ? 'verify' : 'run'} #{h session.run.id}" : "open"
        "<a class=\"run-pill#{' active' if session.active?}\" href=\"/\" title=\"#{h session.runbook.title}\">" \
          "<span class=\"dot\"></span>#{h session.runbook.slug} · #{label}</a>"
      end

      # ----------------------------------------------------------------
      # Right pane: a folder
      # ----------------------------------------------------------------

      def folder_pane(library, folder, session, token)
        [folder_head(library, folder), locked_banner(session), readme(folder),
         cards_section("Folders", folder.folders.map { folder_card(it) }),
         cards_section("Runbooks", folder.entries.map { runbook_card(it, session, token) }),
         folder.root? ? HINT : ""].join("\n")
      end

      HINT = '<p class="lib-hint">Pick a runbook in the tree, or a card above, to read about it before opening it. ' \
             "A folder's <code>README.md</code> is shown as its description.</p>"

      def folder_head(library, folder)
        title   = folder.root? ? "Runbooks" : folder.name
        where   = folder.root? ? library.dir : folder.slug
        folders = folder.subfolders.size
        <<~HTML
          <div class="page-head">
            <h1>#{ICONS[:folder]} #{h title}</h1>
            <p class="sub">#{count(folder.size, 'runbook')}#{" in #{count(folders, 'folder')}" if folders.positive?} · <code>#{h where}</code></p>
          </div>
        HTML
      end

      def readme(folder)
        return "" unless folder.readme?

        "<article class=\"markdown-body lib-readme\">#{folder.readme_html}</article>"
      end

      def cards_section(heading, cards)
        return "" if cards.empty?

        "<section class=\"lib-section\"><h2>#{h heading}</h2><div class=\"lib-grid\">#{cards.join}</div></section>"
      end

      def folder_card(folder)
        names = folder.runbooks.first(3).map(&:title)
        more  = folder.size - names.size
        <<~HTML
          <a class="lib-card folder" href="#{h href(folder.slug)}" data-slug="#{h folder.slug}">
            <h3>#{ICONS[:folder]} #{h folder.name}</h3>
            <p class="desc">#{count(folder.size, 'runbook')}#{" in #{count(folder.subfolders.size, 'folder')}" if folder.folders.any?}</p>
            <p class="names">#{h names.join(', ')}#{" and #{more} more" if more.positive?}</p>
          </a>
        HTML
      end

      def runbook_card(entry, session, token)
        state = state_of(entry, session)
        <<~HTML
          <article class="lib-card runbook #{state}" data-slug="#{h entry.slug}">
            <a class="card-link" href="#{h href(entry.slug)}">
              <h3>#{entry.single_file? ? ICONS[:file] : ICONS[:book]} #{h entry.title}</h3>
              <p class="desc">#{h blurb(entry)}</p>
              <div class="badges">#{badges(entry, state).join}</div>
            </a>
            <div class="card-foot"><span class="meta">#{detail(entry)}</span>#{action(entry, state, token)}</div>
          </article>
        HTML
      end

      def blurb(entry)
        return entry.error unless entry.ok?

        text = entry.when_to_use.to_s.strip.gsub(/\s+/, " ")
        return "No description. Add when_to_use to the front matter." if text.empty?

        text.size > BLURB ? "#{text[0, BLURB].sub(/\s+\S*\z/, '')}…" : text
      end

      # ----------------------------------------------------------------
      # Right pane: a runbook
      # ----------------------------------------------------------------

      def runbook_pane(_library, entry, session, token)
        state   = state_of(entry, session)
        runbook = entry.runbook
        parts   = [runbook_head(entry, state), locked_banner(session), open_panel(entry, state, token)]
        if runbook
          parts << Pages.warnings_banner(runbook.warnings) << Pages.meta_table(runbook, when_to_use: false) << inputs_table(runbook)
          parts << steps_list(runbook) << history(entry, session)
          parts << "<article class=\"markdown-body\">#{runbook.preamble_html}</article>"
        end
        parts.join("\n")
      end

      def runbook_head(entry, state)
        <<~HTML
          <div class="page-head">
            <h1>#{entry.single_file? ? ICONS[:file] : ICONS[:book]} #{h entry.title}</h1>
            <p class="sub">#{detail(entry)} · <code>#{h entry.slug}</code></p>
            <div class="badges">#{badges(entry, state).join}</div>
          </div>
        HTML
      end

      # The description and the one action, side by side.
      def open_panel(entry, state, token)
        text = if !entry.ok?
                 "<div class=\"banner danger\">#{ICONS[:alert]}<div><strong>This runbook does not load.</strong><br>#{h entry.error}</div></div>"
               elsif entry.when_to_use
                 "<h2>When to use</h2><p>#{h entry.when_to_use}</p>"
               else
                 "<h2>When to use</h2><p class=\"empty\">Not said. Add <code>when_to_use</code> to the front matter.</p>"
               end
        action = action(entry, state, token, primary: true)
        <<~HTML
          <section class="panel lib-open #{state}">
            <div class="lib-open-text">#{text}</div>
            #{"<div class=\"btn-row\">#{action}</div>" unless action.empty?}
          </section>
        HTML
      end

      # The one thing the operator can do with a runbook in this state. The
      # primary button (the runbook pane's) answers the o key; a card's does not.
      def action(entry, state, token, primary: false)
        case state
        when :current then "<a class=\"btn primary\" href=\"/\">#{ICONS[:next]} Continue</a>"
        when :broken  then ""
        when :locked  then '<span class="btn disabled" title="Finish the active run first">Open</span>'
        else
          "<form method=\"post\" action=\"/library/open\" class=\"lib-open-form\"><input type=\"hidden\" name=\"_token\" value=\"#{h token}\">" \
          "<input type=\"hidden\" name=\"slug\" value=\"#{h entry.slug}\">" \
          "<button class=\"btn primary\" type=\"submit\"#{' data-key="o"' if primary}>#{ICONS[:next]} Open</button></form>"
        end
      end

      def locked_banner(session)
        return "" unless session&.active?

        "<div class=\"banner info\">#{ICONS[:alert]}<div>A #{session.verifying? ? 'verification' : 'run'} is active on " \
          "<strong>#{h session.runbook.title}</strong>. <a href=\"/run\">Finish or abandon it</a> before opening another runbook.</div></div>"
      end

      def inputs_table(runbook)
        return "" if runbook.inputs.empty?

        rows = runbook.inputs.map do |input|
          value = input.secret? ? '<span class="badge">secret</span>' : (input.default ? "<code>#{h input.default}</code>" : '<span class="empty">none</span>')
          "<tr><th><code>$#{h input.name}</code></th><td>#{h input.prompt}</td><td>#{value}</td></tr>"
        end
        <<~HTML
          <section class="lib-section">
            <h2>Inputs</h2>
            <table class="meta-table inputs"><thead><tr><th>Variable</th><th>Prompt</th><th>Default</th></tr></thead><tbody>#{rows.join}</tbody></table>
          </section>
        HTML
      end

      def steps_list(runbook)
        return '<p class="empty">This runbook has no steps yet.</p>' if runbook.steps.empty?

        rows = runbook.steps.map do |step|
          badges = ["<span class=\"badge #{h step.kind}\">#{h step.kind}</span>"]
          badges << '<span class="badge destructive">destructive</span>' if step.destructive?
          blocks = step.executable_blocks.size
          <<~LI
            <li>
              <span class="num">#{h(step.number || step.position)}</span>
              <span class="title">#{h step.title}<small>#{count(blocks, 'executable block')}</small></span>
              <span class="badges">#{badges.join}</span>
              <span></span>
            </li>
          LI
        end
        extras = runbook.extras.keys.map { "<code>#{h it}</code>" }
        <<~HTML
          <section class="lib-section">
            <h2>Steps</h2>
            <ol class="steps-list">#{rows.join}</ol>
            #{"<p class=\"meta\">Also: #{extras.join(', ')}</p>" if extras.any?}
          </section>
        HTML
      end

      # The last few runs of this runbook, wherever records are kept.
      def history(entry, session)
        root = session&.runs_root || Runsheets.runs_dir
        runs = RunRecord.list(root, entry.slug)
        return "" if runs.empty?

        total = entry.steps
        rows  = runs.first(5).map do |run|
          s       = run.summary
          verdict = Pages.history_verdict(run, s, total)
          kind    = run.verify? ? "verify" : "run"
          <<~LI
            <li class="#{h verdict}">
              <span>#{h s[:id]}</span>
              <span class="badge #{kind}">#{kind}</span>
              <span class="meta verdict">#{h verdict}#{' · stamped' if s[:stamped]}</span>
              <span class="meta">#{h run.started_at.strftime('%Y-%m-%d %H:%M')} · #{h Pages.duration_text(s[:duration])}</span>
              <span class="meta">#{h Pages.history_progress(run, s, total)}</span>
              <span></span>
            </li>
          LI
        end
        <<~HTML
          <section class="lib-section">
            <h2>Previous runs <span class="meta">#{count(runs.size, 'run')}</span></h2>
            <ul class="history">#{rows.join}</ul>
          </section>
        HTML
      end

      # ----------------------------------------------------------------
      # Shared bits
      # ----------------------------------------------------------------

      def badges(entry, state)
        list = ["<span class=\"badge\">#{entry.single_file? ? 'single file' : 'directory'}</span>"]
        list << '<span class="badge destructive">destructive</span>' if entry.destructive?
        list << BADGES.fetch(state)
        list.concat(entry.tags.map { "<span class=\"badge tag\">#{h it}</span>" })
        list.reject(&:empty?)
      end

      # "6 steps · 2 warnings · last verified 2026-10-01", or the error.
      def detail(entry)
        return "does not load" unless entry.ok?

        parts = [count(entry.steps, "step")]
        parts << count(entry.warnings.size, "warning") unless entry.warnings.empty?
        parts << "last verified #{h entry.runbook.last_verified}" if entry.runbook.last_verified
        parts.join(" · ")
      end

      def count(n, noun) = "#{n} #{noun}#{'s' unless n == 1}"
    end

    # The library page (see Pages::Chooser.page).
    def self.library(library, session, token, nonce: nil, selected: nil)
      Chooser.page(library, session, token, nonce:, selected:)
    end
  end
end
