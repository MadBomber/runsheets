# frozen_string_literal: true

module Runsheets
  # A small line diff, enough to show how a block's code changed between a
  # recorded run and the runbook as it is now. Standard library only.
  module Diff
    Line = Data.define(:tag, :text) do
      def unchanged? = tag == " "
      def removed?   = tag == "-"
      def added?     = tag == "+"
      def to_s       = "#{tag}#{text}"
    end

    # Lines of +before+ and +after+ tagged " " (same), "-" (only in before)
    # or "+" (only in after), in order. Longest-common-subsequence based.
    def self.lines(before, after)
      a = before.to_s.lines(chomp: true)
      b = after.to_s.lines(chomp: true)
      table = lcs_table(a, b)
      walk(a, b, table)
    end

    # Unified-style text, one tagged line per row.
    def self.unified(before, after) = lines(before, after).join("\n")

    def self.changed?(before, after) = before.to_s != after.to_s

    def self.lcs_table(before, after)
      table = Array.new(before.size + 1) { Array.new(after.size + 1, 0) }
      before.each_index.reverse_each do |i|
        after.each_index.reverse_each do |j|
          table[i][j] = before[i] == after[j] ? table[i + 1][j + 1] + 1 : [table[i + 1][j], table[i][j + 1]].max
        end
      end
      table
    end
    private_class_method :lcs_table

    def self.walk(before, after, table)
      out = []
      i = j = 0
      while i < before.size && j < after.size
        tag, text, di, dj = choose(before, after, table, i, j)
        out << Line.new(tag, text)
        i += di
        j += dj
      end
      out.concat(tail(before, i, "-")).concat(tail(after, j, "+"))
    end
    private_class_method :walk

    # Which line to emit at (i, j): [tag, text, advance before, advance after].
    def self.choose(before, after, table, i, j)
      return [" ", before[i], 1, 1] if before[i] == after[j]
      return ["-", before[i], 1, 0] if table[i + 1][j] >= table[i][j + 1]

      ["+", after[j], 0, 1]
    end
    private_class_method :choose

    def self.tail(lines, from, tag) = lines[from..].map { Line.new(tag, it) }
    private_class_method :tail
  end
end
