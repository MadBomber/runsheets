# frozen_string_literal: true

module Runsheets
  # Full-text search over runbooks. A query is words and "quoted phrases",
  # matched case-insensitively; a runbook matches when every one of them
  # appears somewhere in it: its title, its front matter text, or any of
  # its documents (the preamble, the steps, verify and rollback), code
  # included. Plain documents are not searched.
  #
  # Every function takes the pieces it needs and returns plain data, so
  # each can be tested on its own.
  module Search
    # One runbook that matched: +hits+ are the documents that hold at least
    # one term, best first.
    Result = Data.define(:runbook, :slug, :score, :hits)

    # One document of a runbook (the preamble, a step, verify or rollback)
    # that holds a term.
    Hit = Data.define(:step, :title, :snippet, :score)

    # How much a term found in each place counts toward a runbook's rank.
    WEIGHTS = { title: 10, meta: 5, step_title: 3, body: 1 }.freeze

    # Characters of context kept on each side of a match in a snippet.
    CONTEXT = 70

    # A parsed query: its terms, and what can be asked of a text about them.
    Query = Data.define(:words) do
      def self.parse(query) = new(words: Search.terms(query))

      def empty? = words.empty?

      # Does +text+ (already lowercased) hold every term?
      def all_in?(text) = words.all? { text.include?(it) }

      # How many times the terms occur in +text+, all together.
      def count(text)
        haystack = text.to_s.downcase
        words.sum { haystack.scan(it).size }
      end

      # A line of +text+ around the first match, whitespace collapsed and
      # markdown syntax dropped, with "…" where it was cut. nil when nothing
      # matches.
      def snippet(text, context: CONTEXT)
        flat  = Search.plain(text).gsub(/\s+/, " ").strip
        first = words.filter_map { flat.downcase.index(it) }.min
        return nil unless first

        from = [first - context, 0].max
        to   = [first + context, flat.size].min
        "#{'…' if from.positive?}#{flat[from...to].strip}#{'…' if to < flat.size}"
      end

      # +text+ HTML-escaped, with each term wrapped in <mark>. Longer terms
      # are tried first, so a phrase wins over a word inside it.
      def highlight(text)
        return Renderer.h(text) if empty?

        pattern = Regexp.union(words.sort_by { -it.size }.map { Regexp.new(Regexp.escape(it), Regexp::IGNORECASE) })
        text.to_s.split(/(#{pattern})/).each_slice(2).map do |plain, match|
          "#{Renderer.h(plain)}#{"<mark>#{Renderer.h(match)}</mark>" if match}"
        end.join
      end
    end

    module_function

    # The terms of a query: "quoted phrases" whole, other words one by one,
    # lowercased, blanks and duplicates dropped.
    def terms(query)
      query.to_s.scan(/"([^"]*)"|(\S+)/).map { |phrase, word| (phrase || word).strip.downcase }
           .reject(&:empty?).uniq
    end

    # Search +runbooks+ (a list of [slug, Runbook] pairs) for the query
    # string. Results are best first; ties go by title.
    def run(runbooks, query)
      query = Query.parse(query)
      return [] if query.empty?

      runbooks.filter_map { |slug, runbook| result_for(slug, runbook, query) }
              .sort_by { [-it.score, it.runbook.title.downcase] }
    end

    # The Result for one runbook, or nil when some term appears nowhere in it.
    def result_for(slug, runbook, query)
      return nil unless query.all_in?(text_of(runbook))

      hits  = hits_for(runbook, query)
      score = (query.count(runbook.title) * WEIGHTS[:title]) + (query.count(meta_text(runbook)) * WEIGHTS[:meta]) + hits.sum(&:score)
      Result.new(runbook:, slug:, score:, hits:)
    end

    # Everything searchable in a runbook, lowercased, as one string.
    def text_of(runbook)
      [runbook.title, meta_text(runbook), *runbook.documents.values.flat_map { [it.title, it.body] }].join("\n").downcase
    end

    # The runbook's front matter prose: what an engineer reads before the
    # first step.
    def meta_text(runbook)
      [runbook.when_to_use, *runbook.prerequisites, runbook.blast_radius, runbook.escalation, *runbook.tags,
       *runbook.inputs.flat_map { [it.name, it.prompt] }].compact.join("\n")
    end

    # The documents that hold a term, best first, each with a snippet.
    def hits_for(runbook, query)
      hits = runbook.documents.values.filter_map do |doc|
        score = (query.count(doc.title) * WEIGHTS[:step_title]) + (query.count(doc.body) * WEIGHTS[:body])
        next if score.zero?

        Hit.new(step: doc, title: doc.title, snippet: query.snippet(doc.body) || doc.title, score:)
      end
      hits.sort_by { -it.score }
    end

    # Markdown reduced to the words a reader sees: link text without its
    # target, no fence lines, heading marks or HTML comments.
    def plain(text)
      text.to_s.gsub(/<!--.*?-->/m, " ").gsub(/^\s*(```|~~~).*$/, " ").gsub(/^\s*\#{1,6}\s+/, "")
          .gsub(/!?\[([^\]]*)\]\([^)]*\)/, '\1')
    end
  end
end
