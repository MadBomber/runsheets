# frozen_string_literal: true

module Runsheets
  # The text rules shared by steps, single-file sections and the --new
  # wizard, so each kind of name is made the same way everywhere.
  module Slug
    module_function

    # "DB Refresh!" => "db-refresh": lowercase letters and digits joined by
    # single hyphens. Text with nothing usable in it gives "".
    def of(text) = text.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")

    # "020-take-a-backup" => "take-a-backup": a step slug without its number.
    def bare(slug) = slug.to_s.sub(/\A\d+[-_]?/, "")

    # "db-refresh" => "Db refresh": the title a slug or name suggests.
    def title(text) = text.to_s.tr("-_", " ").capitalize
  end
end
