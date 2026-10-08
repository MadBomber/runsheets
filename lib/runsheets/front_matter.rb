# frozen_string_literal: true

module Runsheets
  # Splits a markdown document into its YAML front matter and body.
  module FrontMatter
    Result = Data.define(:data, :body)

    PATTERN = /\A---[ \t]*\r?\n(.*?)^---[ \t]*(?:\r?\n|\z)/m

    # Returns a Result whose data is a Hash with string keys (empty when the
    # document has no front matter) and whose body is the remaining text.
    def self.parse(text)
      match = text.match(PATTERN)
      return Result.new(data: {}, body: text) unless match

      data = YAML.safe_load(match[1], permitted_classes: [Date, Time], aliases: true) || {}
      raise RunbookError, "front matter must be a YAML mapping" unless data.is_a?(Hash)

      Result.new(data:, body: match.post_match)
    rescue Psych::SyntaxError => e
      raise RunbookError, "front matter is not valid YAML: #{e.message}"
    end
  end
end
