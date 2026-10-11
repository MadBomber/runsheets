# frozen_string_literal: true

require "test_helper"

class TestExpectation < Minitest::Test
  include RunsheetsTest

  Expectation = Runsheets::Expectation

  # 2000 lines of output, and an expected text with {{any}} on every other line.
  LONG_LINES    = Array.new(2_000) { "row #{it}: id #{it * 7919} ok" }.freeze
  LONG_OUTPUT   = LONG_LINES.join("\n").freeze
  LONG_EXPECTED = LONG_LINES.each_with_index.map { |line, i| i.odd? ? "row #{i}: {{any}} ok" : line }.join("\n").freeze

  def test_identical_output_matches_with_trailing_whitespace_ignored
    result = Expectation.compare("one\ntwo\n", "one  \ntwo\n\n")
    assert result.match?
    assert_equal(%w[same same], result.rows.map { it.tag.to_s })
  end

  def test_any_matches_anything_within_one_line
    result = Expectation.compare("in run {{any}}\n{{any}} done", "in run 20261010T221025\nall done")
    assert result.match?
    assert_equal [["in run ", nil], ["{{any}}", "any"]], result.rows.first.expected
    assert_equal [["in run 20261010T221025", nil]], result.rows.first.actual
  end

  def test_any_matches_nothing_but_not_a_second_line
    assert Expectation.compare("a{{any}}b", "ab").match?
    refute Expectation.compare("{{any}}", "one\ntwo").match?
  end

  def test_a_changed_line_marks_the_characters_that_differ
    row = Expectation.compare("in run 20261007T120000", "in run 20261010T221025").rows.first
    assert_equal :changed, row.tag
    assert_equal [["in run 202610", nil], ["07T120000", "diff"]], row.expected
    assert_equal [["in run 202610", nil], ["10T221025", "diff"]], row.actual
  end

  def test_a_changed_line_keeps_its_common_ending
    row = Expectation.compare("Hello, world!", "Hello, web!").rows.first
    assert_equal [["Hello, w", nil], ["orld", "diff"], ["!", nil]], row.expected
    assert_equal [["Hello, w", nil], ["eb", "diff"], ["!", nil]], row.actual
  end

  def test_a_changed_line_with_a_wildcard_is_marked_whole
    row = Expectation.compare("pid {{any}} up", "pid 42 down").rows.first
    assert_equal [["pid ", "diff"], ["{{any}}", "any"], [" up", "diff"]], row.expected
    assert_equal [["pid 42 down", "diff"]], row.actual
  end

  def test_lines_only_one_side_has_get_a_row_with_a_gap
    result = Expectation.compare("a\nb\nc", "a\nc\nd")
    assert_equal(%w[same expected same actual], result.rows.map { it.tag.to_s })
    assert_equal [nil, [%w[b diff]]], [result.rows[1].actual, result.rows[1].expected]
    assert_equal [nil, [%w[d diff]]], [result.rows[3].expected, result.rows[3].actual]
  end

  def test_runs_of_changed_lines_are_paired_off_in_order
    result = Expectation.compare("a\nx\ny\nz", "a\n1\n2")
    assert_equal(%w[same changed changed expected], result.rows.map { it.tag.to_s })
    refute result.match?
  end

  def test_matching_ends_are_trimmed_before_the_diff
    ops = Expectation.ops(%w[a b x c d], %w[a b y z c d], ->(want, got) { want == got })
    assert_equal [[" ", "a", "a"], [" ", "b", "b"]], ops.first(2)
    assert_equal [[" ", "c", "c"], [" ", "d", "d"]], ops.last(2)
    assert_equal [["-", "x", nil], ["+", nil, "y"], ["+", nil, "z"]], ops[2..-3]
  end

  def test_trimming_never_counts_a_line_twice
    same = ->(want, got) { want == got }
    assert_equal [[" ", "a", "a"], ["+", nil, "a"]], Expectation.ops(%w[a], %w[a a], same)
    assert_equal [[" ", "a", "a"], ["-", "a", nil]], Expectation.ops(%w[a a], %w[a], same)
  end

  def test_a_long_matching_output_is_cheap
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result  = Expectation.compare(LONG_EXPECTED, LONG_OUTPUT)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    assert result.match?
    assert_operator elapsed, :<, 0.5, "without trimming the diff builds a 2000 x 2000 table"
  end

  def test_to_h_is_what_the_page_reads
    hash = Expectation.compare("same\nold", "same\nnew").to_h
    refute hash[:match]
    assert_equal({ tag: "same", expected: [["same", nil]], actual: [["same", nil]] }, hash[:rows].first)
  end

  def test_empty_lines_have_no_segments
    row = Expectation.compare("a\n\nb", "a\n\nb").rows[1]
    assert_equal :same, row.tag
    assert_equal [[], []], [row.expected, row.actual]
  end

  def test_for_page_skips_what_has_nothing_to_compare
    assert_nil Expectation.for_page(nil, "out", :finished)
    assert_nil Expectation.for_page("out", "", :running)
    assert_nil Expectation.for_page("out", "", "failed")
    assert Expectation.for_page("out", "out\n", "finished")[:match]
  end

  def test_a_step_finds_the_expect_block_of_an_executable_block
    step = example_runbook.step("010-say-hello")
    assert_includes step.expected_output("010-say-hello-1"), "in run {{any}}"
    assert_nil step.expected_output("010-say-hello-3")
  end
end
