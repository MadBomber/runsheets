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

      # What the results are drawn for: the parsed query, and the slug of
      # the runbook open now (nil when none is), whose steps link straight
      # to their pages.
      Context = Data.define(:query, :open_slug) do
        def highlight(text) = query.highlight(text)

        def open?(slug) = slug == open_slug

        # Where a result links. The runbook open now goes straight to the
        # step's page; any other runbook to its page in the library, at the
        # step when it is a numbered one.
        def href(slug, step)
          return Chooser.href(slug) + (step&.position ? "#step-#{step.slug}" : "") unless open?(slug)

          step.nil? || step.slug == "runbook" ? "/" : Pages.step_href(step)
        end
      end

      module_function

      def h(value) = Renderer.h(value)

      # The page's main pane for the query string over +results+.
      def main(results, query, open_slug: nil)
        context = Context.new(query: Search::Query.parse(query), open_slug:)
        <<~HTML
          <div class="page-head">
            <h1>#{ICONS[:search]} Search</h1>
            <p class="sub">#{summary(results, query)}</p>
          </div>
          #{form(query)}
          #{list(results, context) unless context.query.empty?}
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

      def list(results, context)
        return '<p class="empty">No runbook contains every word. Try fewer words, or check the spelling.</p>' if results.empty?

        "<ol class=\"search-results\">#{results.map { result(it, context) }.join}</ol>"
      end

      def result(result, context)
        runbook = result.runbook
        slug    = result.slug
        shown   = result.hits.first(HITS_SHOWN)
        more    = result.hits.size - shown.size
        hits    = shown.map { hit(slug, it, context) }.join
        <<~HTML
          <li class="search-result">
            <h2><a href="#{h context.href(slug, nil)}">#{context.highlight(runbook.title)}</a>#{' <span class="badge current">open now</span>' if context.open?(slug)}</h2>
            <p class="meta">#{h slug} · #{runbook.steps.size} step#{'s' unless runbook.steps.size == 1}#{" · #{h runbook.tags.join(', ')}" if runbook.tags.any?}</p>
            #{"<ul class=\"search-hits\">#{hits}</ul>" unless hits.empty?}
            #{"<p class=\"meta\">and #{more} more</p>" if more.positive?}
          </li>
        HTML
      end

      def hit(slug, hit, context)
        step = hit.step
        <<~HTML
          <li>
            <a href="#{h context.href(slug, step)}"><span class="num">#{h label(step)}</span> #{context.highlight(hit.title)}</a>
            <p class="snippet">#{context.highlight(hit.snippet)}</p>
          </li>
        HTML
      end

      # "Step 020", "Preamble", or the slug of verify or rollback.
      def label(step)
        return "Step #{step.number || step.position}" if step.position

        step.slug == "runbook" ? "Preamble" : step.slug
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
        view     = Chooser::View.new(library:, session:, token:, node: library.root, crumb: "Search")
        Chooser.frame(view, title: "Search", main:, nonce:, query:)
      else
        main = SearchPage.main(Search.run([[open_slug, session.runbook]], query), query, open_slug:)
        layout(session, title: "Search", body: main, kind: :search, nonce:, query:)
      end
    end
  end
end
