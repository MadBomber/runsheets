# frozen_string_literal: true

module Runsheets
  module Pages
    # The search page: every runbook that matches a query, best first, each
    # with the documents that matched and a snippet from each. In a library
    # it sits in the library's frame beside the tree; on a single runbook,
    # in that runbook's layout.
    module SearchPage
      # Matching documents listed per runbook before "and N more".
      HITS_SHOWN = 5

      module_function

      def h(value) = Renderer.h(value)

      # The page's main pane for +query+ over +results+. +open_slug+ is the
      # runbook open now, whose steps link straight to their pages.
      def main(results, query, open_slug: nil)
        words = Search.terms(query)
        <<~HTML
          <div class="page-head">
            <h1>#{ICONS[:search]} Search</h1>
            <p class="sub">#{summary(results, query)}</p>
          </div>
          #{form(query)}
          #{list(results, words, open_slug:) unless words.empty?}
        HTML
      end

      def summary(results, query)
        return "Search the text of every runbook: titles, front matter, steps and their code." if Search.terms(query).empty?

        "#{results.size} runbook#{'s' unless results.size == 1} match <strong>#{h query.strip}</strong>"
      end

      def form(query)
        <<~HTML
          <form class="search-form" action="/search" method="get" role="search">
            <input type="search" name="q" value="#{h query}" placeholder="Words, or a &quot;quoted phrase&quot;" aria-label="Search runbooks" autocomplete="off" spellcheck="false" autofocus>
            <button class="btn primary" type="submit">#{ICONS[:search]} Search</button>
          </form>
        HTML
      end

      def list(results, words, open_slug:)
        return '<p class="empty">No runbook contains every word. Try fewer words, or check the spelling.</p>' if results.empty?

        "<ol class=\"search-results\">#{results.map { result(it, words, open_slug:) }.join}</ol>"
      end

      def result(result, words, open_slug:)
        runbook = result.runbook
        shown   = result.hits.first(HITS_SHOWN)
        more    = result.hits.size - shown.size
        hits    = shown.map { hit(result, it, words, open_slug:) }.join
        <<~HTML
          <li class="search-result">
            <h2><a href="#{h href(result.slug, nil, open_slug:)}">#{Search.highlight(runbook.title, words)}</a>#{' <span class="badge current">open now</span>' if result.slug == open_slug}</h2>
            <p class="meta">#{h result.slug} · #{runbook.steps.size} step#{'s' unless runbook.steps.size == 1}#{" · #{h runbook.tags.join(', ')}" if runbook.tags.any?}</p>
            #{"<ul class=\"search-hits\">#{hits}</ul>" unless hits.empty?}
            #{"<p class=\"meta\">and #{more} more</p>" if more.positive?}
          </li>
        HTML
      end

      def hit(result, hit, words, open_slug:)
        step  = hit.step
        label = step.position ? "Step #{step.number || step.position}" : (step.slug == "runbook" ? "Preamble" : step.slug)
        <<~HTML
          <li>
            <a href="#{h href(result.slug, step, open_slug:)}"><span class="num">#{h label}</span> #{Search.highlight(hit.title, words)}</a>
            <p class="snippet">#{Search.highlight(hit.snippet, words)}</p>
          </li>
        HTML
      end

      # Where a result links. The runbook open now goes straight to the
      # step's page; any other runbook to its page in the library, at the
      # step when it is a numbered one.
      def href(slug, step, open_slug:)
        if slug == open_slug
          step.nil? || step.slug == "runbook" ? "/" : Pages.step_href(step)
        else
          anchor = step&.position ? "#step-#{step.slug}" : ""
          "#{Chooser.href(slug)}#{anchor}"
        end
      end
    end

    # The search page for +query+. In a library it searches every runbook
    # that loads and sits in the library frame; otherwise it searches the
    # session's runbook.
    def self.search(session, library, query, token:, nonce: nil)
      open_slug = session&.runbook&.slug
      if library
        runbooks = library.entries.select(&:ok?).map { [it.slug, it.runbook] }
        main     = SearchPage.main(Search.run(runbooks, query), query, open_slug:)
        view     = Chooser::View.new(library:, session:, token:, node: library.root)
        Chooser.frame(view, title: "Search", main:, nonce:, query:)
      else
        main = SearchPage.main(Search.run([[open_slug, session.runbook]], query), query, open_slug:)
        layout(session, title: "Search", body: main, kind: :search, nonce:, query:)
      end
    end
  end
end
