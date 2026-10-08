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
    def self.unified(before, after) = lines(before, after).map(&:to_s).join("\n")

    def self.changed?(before, after) = before.to_s != after.to_s

    def self.lcs_table(a, b)
      table = Array.new(a.size + 1) { Array.new(b.size + 1, 0) }
      a.each_index.reverse_each do |i|
        b.each_index.reverse_each do |j|
          table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : [table[i + 1][j], table[i][j + 1]].max
        end
      end
      table
    end
    private_class_method :lcs_table

    def self.walk(a, b, table)
      out = []
      i = j = 0
      while i < a.size && j < b.size
        if a[i] == b[j]
          out << Line.new(" ", a[i])
          i += 1
          j += 1
        elsif table[i + 1][j] >= table[i][j + 1]
          out << Line.new("-", a[i])
          i += 1
        else
          out << Line.new("+", b[j])
          j += 1
        end
      end
      out.concat(a[i..].map { Line.new("-", it) })
      out.concat(b[j..].map { Line.new("+", it) })
    end
    private_class_method :walk
  end
end
