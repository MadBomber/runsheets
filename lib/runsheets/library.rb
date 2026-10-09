# frozen_string_literal: true

module Runsheets
  # A directory of runbooks: each child that is a single-file runbook (a
  # .md file) or a runbook directory (holding runbook.md) is one entry. The
  # web page offers them for the operator to choose from, one at a time.
  #
  # A directory that itself holds runbook.md is a runbook, not a library.
  class Library
    # What the chooser shows for one runbook. error is set when the runbook
    # does not load; title then falls back to the slug.
    Entry = Data.define(:slug, :path, :single_file, :title, :when_to_use, :tags, :steps, :warnings, :error) do
      def single_file? = single_file
      def ok?          = error.nil?
    end

    attr_reader :dir, :entries

    # Is path a directory of runbooks rather than a runbook?
    def self.library?(path)
      path = File.expand_path(path)
      File.directory?(path) && !File.file?(File.join(path, Runbook::MAIN_FILE))
    end

    def self.load(dir) = new(dir)

    def initialize(dir)
      @dir = File.expand_path(dir)
      raise RunbookError, "no such directory: #{@dir}" unless File.directory?(@dir)

      @entries = scan.freeze
      raise RunbookError, "no runbooks in #{@dir}: expected .md files or directories holding #{Runbook::MAIN_FILE}" if @entries.empty?
    end

    def find(slug) = entries.find { it.slug == slug }

    # Load the runbook an entry stands for.
    def runbook(slug)
      entry = find(slug) or raise RunbookError, "no runbook named #{slug} in #{dir}"
      Runbook.load(entry.path)
    end

    def size = entries.size

    private

    # Direct children only, hidden ones skipped, sorted by slug.
    def scan
      Dir.children(dir).sort.filter_map do |name|
        next if name.start_with?(".")

        path = File.join(dir, name)
        if File.directory?(path)
          entry_for(path, slug: name, single_file: false) if File.file?(File.join(path, Runbook::MAIN_FILE))
        elsif name.end_with?(".md")
          entry_for(path, slug: File.basename(name, ".md"), single_file: true)
        end
      end
    end

    def entry_for(path, slug:, single_file:)
      runbook = Runbook.load(path)
      Entry.new(slug:, path:, single_file:, title: runbook.title, when_to_use: runbook.when_to_use,
                tags: runbook.tags, steps: runbook.steps.size, warnings: runbook.warnings, error: nil)
    rescue RunbookError => e
      Entry.new(slug:, path:, single_file:, title: slug, when_to_use: nil, tags: [], steps: 0, warnings: [], error: e.message)
    end
  end
end
