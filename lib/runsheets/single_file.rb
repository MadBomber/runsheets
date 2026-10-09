# frozen_string_literal: true

module Runsheets
  # Splits a single-file runbook into its preamble and sections.
  #
  # One markdown file: front matter, a preamble, then one `## Heading` per
  # step. A section headed "Verify" or "Rollback" (or carrying
  # `role: verify` / `role: rollback`) plays the part verify.md and
  # rollback.md play in a directory runbook. Step attributes that a
  # directory runbook puts in front matter go in an HTML comment right
  # after the heading, as a YAML flow mapping:
  #
  #   ## Drain the ECS services
  #   <!-- kind: automated, timeout: 600, destructive: true -->
  #
  # The comment is invisible on GitHub and in any other renderer, so the
  # file stays an ordinary markdown document everywhere else.
  module SingleFile
    Section = Data.define(:title, :data, :body, :line, :warnings) do
      def role = data["role"]&.to_s&.downcase || (ROLES.include?(title.strip.downcase) ? title.strip.downcase : nil)
      def extra? = !role.nil?
    end

    ROLES    = %w[verify rollback].freeze
    HEADING  = /\A##[ \t]+(.+?)[ \t#]*\z/
    # An attribute comment starts with a key; any other comment is prose.
    COMMENT  = /\A[ \t]*<!--([ \t]*[\w-]+[ \t]*:.*?)-->[ \t]*\z/

    # Returns [preamble markdown, sections].
    def self.split(markdown)
      preamble = []
      sections = []
      current  = nil
      open     = nil

      markdown.each_line(chomp: true).with_index(1) do |line, number|
        if open
          open = nil if Fences.closes?(line, open)
          (current ? current[:body] : preamble) << line
        elsif (match = line.match(Fences::OPEN))
          open = { char: match[2][0], len: match[2].size }
          (current ? current[:body] : preamble) << line
        elsif (match = line.match(HEADING))
          current = { title: match[1], body: [], line: number }
          sections << current
        else
          (current ? current[:body] : preamble) << line
        end
      end

      ["#{preamble.join("\n")}\n", sections.map { build(it) }]
    end

    # Pull the attribute comment off the front of a section body.
    def self.build(raw)
      body     = raw[:body].dup
      data     = {}
      warnings = []
      body.shift while body.first&.strip&.empty?
      if body.first && (match = body.first.match(COMMENT))
        data, warning = parse_attributes(match[1])
        warnings << warning if warning
        body.shift
      end
      Section.new(title: raw[:title].strip, data:, body: "#{body.join("\n")}\n", line: raw[:line], warnings:)
    end
    private_class_method :build

    # "kind: verify, timeout: 300" => { "kind" => "verify", "timeout" => 300 }.
    # Returns [data, warning or nil].
    def self.parse_attributes(text)
      inner = text.strip
      return [{}, nil] if inner.empty?

      parsed = YAML.safe_load("{#{inner}}", permitted_classes: [Date], aliases: false)
      return [{}, "attribute comment is not a mapping: <!-- #{inner} -->"] unless parsed.is_a?(Hash)

      [parsed.transform_keys(&:to_s), nil]
    rescue Psych::SyntaxError => e
      [{}, "attribute comment could not be parsed (#{e.message.lines.first&.strip}): <!-- #{inner} -->"]
    end

    # A step slug for a section: position-numbered like a directory step,
    # so block ids and record files look the same either way.
    def self.slug_for(title, position)
      words = title.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
      words = "step" if words.empty?
      format("%<number>03d-%<words>s", number: position * 10, words:)
    end
  end
end
