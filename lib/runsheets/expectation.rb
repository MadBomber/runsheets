# frozen_string_literal: true

module Runsheets
  # Compares a block's output with the text of its expect block. Lines are
  # matched in order with trailing whitespace ignored, and `{{any}}` in the
  # expected text matches any characters within one line. The result lines
  # the two up row by row for the page, with the characters that differ
  # marked, so line N of the output sits beside line N of what was expected.
  module Expectation
    ANY  = "{{any}}"
    DIFF = "diff"
    WILD = "any"

    # One row of the side-by-side view. +tag+ is :same, :changed, :expected
    # (a line only the expect block has) or :actual (only the output has).
    # Each side is a list of [text, mark] segments, mark nil, "diff" or
    # "any"; a side is nil when the row has no line there.
    Row = Data.define(:tag, :expected, :actual) do
      def to_h = { tag: tag.to_s, expected:, actual: }
    end

    Result = Data.define(:rows) do
      def match? = rows.all? { it.tag == :same }
      def to_h   = { match: match?, rows: rows.map(&:to_h) }
    end

    def self.compare(expected, actual)
      patterns = Hash.new { |cache, line| cache[line] = pattern(line) }
      Result.new(rows(ops(lines(expected), lines(actual), ->(want, got) { patterns[want].match?(got) })))
    end

    # The edit script, with the lines that match at the start and at the
    # end taken out before the diff, whose cost grows with the product of
    # the two line counts. Output that mostly matches leaves it little to do.
    def self.ops(wants, gots, same)
      head = matching_run(wants, gots, same)
      tail = matching_run(wants.drop(head).reverse, gots.drop(head).reverse, same)
      middle = Diff.ops(wants[head...(wants.size - tail)], gots[head...(gots.size - tail)], same:)
      paired(wants.first(head), gots.first(head)) + middle + paired(wants.last(tail), gots.last(tail))
    end

    # How many lines from the start match, pair by pair.
    def self.matching_run(wants, gots, same) = wants.zip(gots).take_while { |want, got| got && same.call(want, got) }.size

    def self.paired(wants, gots) = wants.zip(gots).map { |want, got| [" ", want, got] }

    # The comparison as a page wants it, or nil when there is nothing to
    # compare: no expect block, or an execution still running or that never
    # started.
    def self.for_page(expected, output, state)
      return nil if expected.nil? || %w[running failed].include?(state.to_s)

      compare(expected, output).to_h
    end

    def self.lines(text) = text.to_s.gsub(/[ \t]+$/, "").rstrip.lines(chomp: true)

    # A line of expected text as a whole-line pattern.
    def self.pattern(line) = /\A#{line.split(ANY, -1).map { Regexp.escape(it) }.join('.*')}\z/

    # Rows from the edit script: unchanged lines as they are, and each run of
    # changed lines paired off expected against actual.
    def self.rows(ops)
      ops.chunk_while { |a, b| (a.first == " ") == (b.first == " ") }.flat_map do |chunk|
        chunk.first.first == " " ? same_rows(chunk) : changed_rows(chunk.filter_map { it[1] }, chunk.filter_map { it[2] })
      end
    end

    def self.same_rows(chunk) = chunk.map { |_, want, got| Row.new(:same, wildcards(want), plain(got)) }

    def self.changed_rows(wants, gots)
      Array.new([wants.size, gots.size].max) { row(wants[it], gots[it]) }
    end

    def self.row(want, got)
      return Row.new(:expected, wildcards(want, DIFF), nil) if got.nil?
      return Row.new(:actual, nil, plain(got, DIFF)) if want.nil?
      return Row.new(:changed, wildcards(want, DIFF), plain(got, DIFF)) if want.include?(ANY)

      prefix = common_prefix(want, got)
      suffix = common_prefix(want[prefix..].reverse, got[prefix..].reverse)
      Row.new(:changed, around(want, prefix, suffix), around(got, prefix, suffix))
    end

    # +text+ in segments, with each {{any}} marked as a wildcard.
    def self.wildcards(text, mark = nil)
      text.split(/(#{Regexp.escape(ANY)})/).reject(&:empty?).map { [it, it == ANY ? WILD : mark] }
    end

    def self.plain(text, mark = nil) = text.empty? ? [] : [[text, mark]]

    # +text+ with the part between its first +prefix+ and last +suffix+
    # characters marked as the difference.
    def self.around(text, prefix, suffix)
      [[text[0, prefix], nil], [text[prefix...(text.size - suffix)], DIFF], [text[(text.size - suffix)..], nil]]
        .reject { it.first.empty? }
    end

    def self.common_prefix(one, other) = one.each_char.zip(other.each_char).take_while { |mine, theirs| mine == theirs }.size
  end
end
