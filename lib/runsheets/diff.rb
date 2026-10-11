# frozen_string_literal: true

module Runsheets
  # A small line diff, enough to show how a block's code changed between a
  # recorded run and the runbook as it is now, or how a block's output
  # differs from its expect block. Standard library only.
  module Diff
    Line = Data.define(:tag, :text) do
      def unchanged? = tag == " "
      def removed?   = tag == "-"
      def added?     = tag == "+"
      def to_s       = "#{tag}#{text}"
    end

    SAME = ->(a, b) { a == b }

    # Lines of +before+ and +after+ tagged " " (same), "-" (only in before)
    # or "+" (only in after), in order. Longest-common-subsequence based.
    def self.lines(before, after)
      ops(before.to_s.lines(chomp: true), after.to_s.lines(chomp: true)).map do |tag, old, new|
        Line.new(tag, tag == "+" ? new : old)
      end
    end

    # The edit script between two arrays of lines, one [tag, before_line,
    # after_line] per row: " " when +same+ says the pair is the same, "-"
    # with a nil after_line, "+" with a nil before_line.
    def self.ops(before, after, same: SAME)
      table = lcs_table(before, after, same)
      walk(before, after, table, same)
    end

    # Unified-style text, one tagged line per row.
    def self.unified(before, after) = lines(before, after).join("\n")

    def self.changed?(before, after) = before.to_s != after.to_s

    def self.lcs_table(before, after, same)
      table = Array.new(before.size + 1) { Array.new(after.size + 1, 0) }
      before.each_index.reverse_each do |i|
        after.each_index.reverse_each do |j|
          table[i][j] = same.call(before[i], after[j]) ? table[i + 1][j + 1] + 1 : [table[i + 1][j], table[i][j + 1]].max
        end
      end
      table
    end
    private_class_method :lcs_table

    def self.walk(before, after, table, same)
      out = []
      i = j = 0
      while i < before.size && j < after.size
        tag, di, dj = same.call(before[i], after[j]) ? [" ", 1, 1] : choose(table, i, j)
        out << [tag, (before[i] unless tag == "+"), (after[j] unless tag == "-")]
        i += di
        j += dj
      end
      out.concat(before[i..].map { ["-", it, nil] }).concat(after[j..].map { ["+", nil, it] })
    end
    private_class_method :walk

    # Which row to emit at (i, j) when the lines there differ: [tag,
    # advance before, advance after].
    def self.choose(table, i, j) = table[i + 1][j] >= table[i][j + 1] ? ["-", 1, 0] : ["+", 0, 1]
    private_class_method :choose
  end
end
