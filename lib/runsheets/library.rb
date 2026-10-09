# frozen_string_literal: true

module Runsheets
  # A directory tree of runbooks. Every markdown file is a single-file
  # runbook and every directory holding runbook.md is a runbook directory;
  # any other directory is a folder, searched the same way, to any depth.
  # The web page shows the tree for the operator to choose from.
  #
  #   ops/                      <- the library
  #     README.md               <- describes the folder, not a runbook
  #     deploy.md               <- runbook "deploy"
  #     database/
  #       backup/runbook.md     <- runbook "database/backup"
  #       restore.md            <- runbook "database/restore"
  #
  # A runbook's slug is its path inside the library, so run records of
  # database/backup and network/backup never share a directory. Folders
  # that hold no runbooks anywhere beneath them are left out; hidden
  # entries are skipped. A directory that itself holds runbook.md is a
  # runbook, not a library.
  class Library
    README    = "README.md"
    MAX_DEPTH = 16

    # One runbook in the tree. runbook is the loaded Runbook, or nil with
    # error set when it does not load; the reading methods then fall back
    # to what the file system says.
    Entry = Data.define(:slug, :name, :folder, :path, :single_file, :runbook, :error) do
      def single_file? = single_file
      def ok?          = error.nil?
      def title        = runbook ? runbook.title : name
      def when_to_use  = runbook&.when_to_use
      def tags         = runbook ? runbook.tags : []
      def steps        = runbook ? runbook.steps.size : 0
      def warnings     = runbook ? runbook.warnings : []
      def destructive? = runbook&.destructive? || false
      def main_path    = single_file ? path : File.join(path, Runbook::MAIN_FILE)
      def depth        = slug.count("/")
      def runbook?     = true
      def folder?      = false
    end

    # A folder of the tree: its own runbooks and folders, in title order,
    # and the README's HTML when it has one. The root has the empty slug.
    Folder = Data.define(:slug, :name, :path, :folders, :entries, :readme_html) do
      def root?    = slug.empty?
      def title    = name
      def depth    = root? ? 0 : slug.count("/") + 1
      def runbook? = false
      def folder?  = true
      def readme?  = !readme_html.nil?

      # Every runbook beneath this folder, nearest first.
      def runbooks = entries + folders.flat_map(&:runbooks)

      # Every folder beneath this one, nearest first.
      def subfolders = folders + folders.flat_map(&:subfolders)

      def size = runbooks.size
    end

    attr_reader :dir, :root, :entries, :folders, :scanned_at

    # Is path a directory of runbooks rather than a runbook?
    def self.library?(path)
      path = File.expand_path(path)
      File.directory?(path) && !File.file?(File.join(path, Runbook::MAIN_FILE))
    end

    def self.load(dir) = new(dir)

    def initialize(dir)
      @dir = File.expand_path(dir)
      raise RunbookError, "no such directory: #{@dir}" unless File.directory?(@dir)

      scan!
      raise RunbookError, "no runbooks in #{@dir}: expected .md files or directories holding #{Runbook::MAIN_FILE}" if @entries.empty?
    end

    # The runbook with this slug, or nil.
    def find(slug) = entries.find { it.slug == slug }

    # The folder with this slug; "" (or nil) is the root. nil when unknown.
    def folder(slug)
      slug = slug.to_s
      return root if slug.empty?

      folders.find { it.slug == slug }
    end

    # Whatever this slug names: an Entry, a Folder, or nil.
    def node(slug) = find(slug.to_s) || folder(slug)

    # The folders above a slug, outermost first, the root excluded. Works
    # for a runbook's slug and for a folder's.
    def ancestors(slug)
      parts = slug.to_s.split("/")
      parts.pop
      parts.each_index.filter_map { folder(parts[0..it].join("/")) }
    end

    # Load the runbook an entry stands for, afresh, carrying its library slug.
    def runbook(slug)
      entry = find(slug) or raise RunbookError, "no runbook named #{slug} in #{dir}"
      Runbook.load(entry.path, slug: entry.slug)
    end

    def size = entries.size

    # True once a folder has gained or lost a child, or a runbook's files
    # have changed, since the last scan.
    def stale?
      return true if [root, *folders].any? { folder_mtime(it.path) != @folder_mtimes[it.path] }

      entries.any? { entry_stale?(it) }
    end

    # Rescan the directory if anything changed. Returns self.
    def refresh!
      scan! if stale?
      self
    end

    private

    def scan!
      @folder_mtimes = {}
      @scanned_at    = Time.now
      @root          = scan_folder(dir, slug: "", visited: [File.realpath(dir)])
      @folders       = @root.subfolders.sort_by(&:slug).freeze
      @entries       = @root.runbooks.sort_by(&:slug).freeze
    end

    # One folder: its direct runbooks and the folders beneath that hold
    # any, each sorted by title. visited holds the real paths above, so a
    # symlink cycle ends here instead of recursing forever.
    def scan_folder(path, slug:, visited:)
      @folder_mtimes[path] = folder_mtime(path)
      entries = []
      folders = []
      Dir.children(path).sort.each do |name|
        next if name.start_with?(".")

        child      = File.join(path, name)
        child_slug = slug.empty? ? name : "#{slug}/#{name}"
        if File.directory?(child)
          node = scan_directory(child, name:, slug: child_slug, folder: slug, visited:)
          (node.is_a?(Folder) ? folders : entries) << node if node
        elsif name.end_with?(".md") && !name.casecmp?(README)
          entries << entry_for(child, name: File.basename(name, ".md"), slug: child_slug.delete_suffix(".md"), folder: slug, single_file: true)
        end
      end
      Folder.new(slug:, name: File.basename(path), path:, folders: by_title(folders), entries: by_title(entries), readme_html: readme_html(path))
    end

    # A directory is a runbook when it holds runbook.md, a folder when any
    # runbook lies beneath it, and nothing otherwise.
    def scan_directory(path, name:, slug:, folder:, visited:)
      return entry_for(path, name:, slug:, folder:, single_file: false) if File.file?(File.join(path, Runbook::MAIN_FILE))

      real = File.realpath(path)
      return nil if visited.include?(real) || visited.size > MAX_DEPTH

      sub = scan_folder(path, slug:, visited: [*visited, real])
      sub.size.positive? ? sub : nil
    rescue SystemCallError
      nil
    end

    def entry_for(path, name:, slug:, folder:, single_file:)
      runbook = Runbook.load(path, slug:)
      Entry.new(slug:, name:, folder:, path:, single_file:, runbook:, error: nil)
    rescue RunbookError => e
      Entry.new(slug:, name:, folder:, path:, single_file:, runbook: nil, error: e.message)
    end

    def by_title(nodes) = nodes.sort_by { [it.title.downcase, it.name] }.freeze

    def readme_html(path)
      file = Dir.children(path).find { it.casecmp?(README) }
      file && Renderer.render_plain(File.read(File.join(path, file), encoding: "UTF-8"))
    rescue SystemCallError
      nil
    end

    def folder_mtime(path)
      File.mtime(path)
    rescue SystemCallError
      nil
    end

    def entry_stale?(entry)
      return entry.runbook.stale? if entry.ok?

      !File.file?(entry.main_path) || File.mtime(entry.main_path) > scanned_at
    rescue SystemCallError
      true
    end
  end
end
