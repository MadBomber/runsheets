# frozen_string_literal: true

require "test_helper"

class TestSearch < Minitest::Test
  include RunsheetsTest

  Search = Runsheets::Search

  EXAMPLES = File.expand_path("../examples", __dir__)

  def examples = Runsheets::Library.load(EXAMPLES).entries.map { [it.slug, it.runbook] }

  def test_terms_split_words_keep_quoted_phrases_and_lowercase
    assert_equal ["stop", "the pipeline", "ecs"], Search.terms('Stop "the pipeline"  ECS stop')
    assert_empty Search.terms("   ")
    assert_empty Search.terms('""')
  end

  def test_every_term_must_appear_somewhere_in_the_runbook
    slugs = Search.run(examples, "vacuum").map(&:slug)
    assert_equal ["db-maintenance"], slugs
    assert_empty Search.run(examples, "vacuum hostname"), "no runbook has both"
    assert_equal ["db-maintenance"], Search.run(examples, "VACUUM psql").map(&:slug), "case-insensitive, across documents and front matter"
  end

  def test_code_in_blocks_is_searched
    assert_includes Search.run(examples, "du -sh").map(&:slug), "disk-space-triage"
  end

  def test_a_title_match_outranks_a_body_match
    results = Search.run(examples, "disk")
    assert_equal "disk-space-triage", results.first.slug
  end

  def test_hits_name_the_matching_documents_best_first
    result = Search.run(examples, "threshold").find { it.slug == "disk-space-triage" }
    titles = result.hits.map(&:title)
    assert_includes titles, "Verify"
    refute_includes titles, "Find what is using it", "a document without the term is not a hit"
    assert_equal result.hits.map(&:score).sort.reverse, result.hits.map(&:score)
  end

  def test_an_empty_query_finds_nothing
    assert_empty Search.run(examples, "  ")
  end

  def test_snippet_shows_context_around_the_first_match
    text = "#{'a ' * 60}needle here #{'b ' * 60}"
    snip = Search.snippet(text, ["needle"], context: 20)
    assert snip.start_with?("…")
    assert snip.end_with?("…")
    assert_includes snip, "needle here"
    assert_equal "short needle", Search.snippet("short\n  needle", ["needle"])
    assert_nil Search.snippet("nothing", ["needle"])
  end

  def test_plain_drops_markdown_syntax_but_keeps_the_words
    text = "# Title\n<!-- kind: verify -->\nSee [df and du](glossary.md#df) and ![a diagram](d.svg).\n```bash run\ndf -h\n```\n"
    plain = Runsheets::Search.plain(text)
    assert_includes plain, "Title"
    assert_includes plain, "See df and du and a diagram."
    assert_includes plain, "df -h"
    %w[# <!-- glossary.md ```].each { refute_includes plain, it }
  end

  def test_highlight_escapes_and_marks_every_term
    assert_equal "&lt;b&gt; <mark>Disk</mark> and <mark>disk</mark> space", Search.highlight("<b> Disk and disk space", ["disk"])
    assert_equal "<mark>df -h</mark>", Search.highlight("df -h", ["df -h", "df"]), "longest term first"
    assert_equal "a &amp; b", Search.highlight("a & b", [])
  end

  def test_count_adds_up_every_term
    assert_equal 3, Search.count("Disk disk DISK space", ["disk"])
    assert_equal 0, Search.count(nil, ["disk"])
  end
end
