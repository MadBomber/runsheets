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

    # One document of a runbook that holds a term. +step+ is nil for a hit
    # in the runbook's own title or front matter.
    Hit = Data.define(:step, :title, :snippet, :score)

    # How much a term found in each place counts toward a runbook's rank.
    WEIGHTS = { title: 10, meta: 5, step_title: 3, body: 1 }.freeze

    # Characters of context kept on each side of a match in a snippet.
    CONTEXT = 70

    module_function

    # The terms of a query: "quoted phrases" whole, other words one by one,
    # lowercased, blanks and duplicates dropped.
    def terms(query)
      query.to_s.scan(/"([^"]*)"|(\S+)/).map { |phrase, word| (phrase || word).strip.downcase }
           .reject(&:empty?).uniq
    end

    # Search +runbooks+ (a list of [slug, Runbook] pairs) for +query+.
    # Results are best first; ties go by title.
    def run(runbooks, query)
      words = terms(query)
      return [] if words.empty?

      runbooks.filter_map { |slug, runbook| result_for(slug, runbook, words) }
              .sort_by { [-it.score, it.runbook.title.downcase] }
    end

    # The Result for one runbook, or nil when some term appears nowhere in it.
    def result_for(slug, runbook, words)
      text = text_of(runbook)
      return nil unless words.all? { text.include?(it) }

      hits  = hits_for(runbook, words)
      score = (count(runbook.title, words) * WEIGHTS[:title]) + (count(meta_text(runbook), words) * WEIGHTS[:meta]) + hits.sum(&:score)
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
    def hits_for(runbook, words)
      hits = runbook.documents.values.filter_map do |doc|
        score = (count(doc.title, words) * WEIGHTS[:step_title]) + (count(doc.body, words) * WEIGHTS[:body])
        next if score.zero?

        Hit.new(step: doc, title: doc.title, snippet: snippet(doc.body, words) || doc.title, score:)
      end
      hits.sort_by { -it.score }
    end

    # How many times the terms occur in +text+, all together.
    def count(text, words)
      haystack = text.to_s.downcase
      words.sum { haystack.scan(it).size }
    end

    # A line of text around the first match in +text+, whitespace
    # collapsed, with "…" where it was cut. nil when nothing matches.
    def snippet(text, words, context: CONTEXT)
      flat  = plain(text).gsub(/\s+/, " ").strip
      first = words.filter_map { flat.downcase.index(it) }.min
      return nil unless first

      from = [first - context, 0].max
      to   = [first + context, flat.size].min
      "#{'…' if from.positive?}#{flat[from...to].strip}#{'…' if to < flat.size}"
    end

    # Markdown reduced to the words a reader sees: link text without its
    # target, no fence lines, heading marks or HTML comments.
    def plain(text)
      text.to_s.gsub(/<!--.*?-->/m, " ").gsub(/^\s*(```|~~~).*$/, " ").gsub(/^\s*\#{1,6}\s+/, "")
          .gsub(/!?\[([^\]]*)\]\([^)]*\)/, '\1')
    end

    # +text+ HTML-escaped, with each term wrapped in <mark>.
    def highlight(text, words)
      return Renderer.h(text) if words.empty?

      pattern = Regexp.union(words.sort_by { -it.size }.map { Regexp.new(Regexp.escape(it), Regexp::IGNORECASE) })
      text.to_s.split(/(#{pattern})/).each_with_index.map { |part, i| i.odd? ? "<mark>#{Renderer.h(part)}</mark>" : Renderer.h(part) }.join
    end
  end
end
