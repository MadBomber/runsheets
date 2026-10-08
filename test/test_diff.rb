# frozen_string_literal: true

require "test_helper"

class TestDiff < Minitest::Test
  Diff = Runsheets::Diff

  def test_identical_text_is_all_context
    lines = Diff.lines("a\nb\n", "a\nb\n")
    assert_equal [" ", " "], lines.map(&:tag)
    refute Diff.changed?("a\n", "a\n")
  end

  def test_added_removed_and_changed_lines
    before = "one\ntwo\nthree\n"
    after  = "one\n2\nthree\nfour\n"
    assert_equal [" one", "-two", "+2", " three", "+four"], Diff.lines(before, after).map(&:to_s)
    assert Diff.changed?(before, after)
    assert_equal " one\n-two\n+2\n three\n+four", Diff.unified(before, after)
  end

  def test_empty_sides
    assert_equal ["+x"], Diff.lines("", "x\n").map(&:to_s)
    assert_equal ["-x"], Diff.lines("x\n", "").map(&:to_s)
    assert_empty Diff.lines("", "")
  end

  def test_line_predicates
    line = Diff.lines("a\n", "b\n")
    assert line[0].removed?
    assert line[1].added?
    refute line[0].unchanged?
  end
end
