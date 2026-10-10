# frozen_string_literal: true

module Runsheets
  # A directory tree of runbooks. Every markdown file that starts with
  # front matter holding a title is a single-file runbook, and every
  # directory holding runbook.md is a runbook directory; other markdown
  # files are plain documents and stay out of the tree. Any other directory
  # is a folder, searched the same way, to any depth.
  # The web page shows the tree for the operator to choose from.
  #
  #   ops/                      <- the library
  #     README.md               <- describes the folder, not a runbook
  #     deploy.md               <- runbook "deploy"
  #     glossary.md             <- no front matter: a document, not listed
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
      def title        = runbook&.title || name
      def when_to_use  = runbook&.when_to_use
      def tags         = runbook&.tags || []
      def steps        = runbook&.steps&.size || 0
      def warnings     = runbook&.warnings || []
      def destructive? = runbook&.destructive? || false
      def main_path    = single_file ? path : File.join(path, Runbook::MAIN_FILE)
      def depth        = slug.count("/")
      def runbook?     = true
      def folder?      = false
    end

    # A folder of the tree: its own runbooks and folders, in title order,
    # the README's HTML when it has one, and the directory's mtime when it
    # was scanned. The root has the empty slug.
    Folder = Data.define(:slug, :name, :path, :folders, :entries, :readme_html, :mtime) do
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

    # Putting a folder's contents in order, and noticing a README edit.
    module Tidy
      module_function

      # Has the README in +dir+ been edited since +time+? (A folder's mtime
      # does not change when a file in it is edited in place.)
      def readme_changed?(dir, time)
        file = Dir.children(dir).find { it.casecmp?(README) }
        file ? File.mtime(File.join(dir, file)) > time : false
      rescue SystemCallError
        true
      end

      # Folders or entries in title order, then by name.
      def by_title(nodes) = nodes.sort_by { [it.title.downcase, it.name] }.freeze

      # Runbooks in one folder whose slugs clash, with each other (deploy.md
      # beside deploy/runbook.md) or with a folder (backup.md beside backup/),
      # become broken entries saying so; the first of a clash keeps the slug.
      def unclash(entries, folder_slugs)
        seen = folder_slugs.to_set
        entries.map do |entry|
          clash = seen.include?(entry.slug)
          seen << entry.slug
          clash ? entry.with(runbook: nil, error: "another runbook or a folder here already has the name #{entry.slug}; rename one") : entry
        end
      end
    end

    # Something found while scanning: where it is, its slug and name, and
    # the slug of the folder holding it. Becomes an Entry or a Folder.
    Found = Data.define(:slug, :name, :folder, :path)

    attr_reader :dir, :root, :entries, :folders, :scanned_at

    # Is path a directory of runbooks rather than a runbook?
    def self.library?(path)
      path = File.expand_path(path)
      File.directory?(path) && !File.file?(File.join(path, Runbook::MAIN_FILE))
    end

    def self.load(dir) = new(dir)

    def initialize(dir)
      @dir       = File.expand_path(dir)
      @documents = []
      @scanned   = {}
      raise RunbookError, "no such directory: #{@dir}" unless File.directory?(@dir)

      scan!
      raise RunbookError, "no runbooks in #{@dir}: expected .md files with a front matter title, or directories holding #{Runbook::MAIN_FILE}" if entries.empty?
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
      Runbook.load(entry.path, slug: entry.slug, root: dir)
    end

    # The runbook whose files include +path+: a single-file runbook that is
    # that file, or a runbook directory holding it. nil for anything else.
    def entry_at(path)
      real = Runbook.real_path(path)
      entries.find do |entry|
        base = Runbook.real_path(entry.path)
        entry.single_file? ? base == real : real.start_with?("#{base}/")
      end
    end

    def size = entries.size

    # True once a folder has gained or lost a child, or a runbook's or a
    # plain document's files have changed, since the last scan. A document
    # edited into a runbook joins the tree.
    def stale?
      return true if @scanned.any? { |path, mtime| folder_mtime(path) != mtime }
      return true if @documents.any? { changed_since_scan?(it) }
      return true if [root, *folders].any? { Tidy.readme_changed?(it.path, scanned_at) }

      entries.any? { entry_stale?(it) }
    end

    # Rescan the directory if anything changed. Returns self.
    def refresh!
      scan! if stale?
      self
    end

    private

    def scan!
      @scanned_at = Time.now
      @documents  = []
      @scanned    = {}
      root        = scan_folder(dir, slug: "", visited: [File.realpath(dir)])
      @root       = root
      @folders    = root.subfolders.sort_by(&:slug).freeze
      @entries    = root.runbooks.sort_by(&:slug).freeze
    end

    # One folder: its direct runbooks and the folders beneath that hold
    # any, each sorted by title. visited holds the real paths above, so a
    # symlink cycle ends here instead of recursing forever.
    # What one child of a folder is: a Folder, an Entry, or nil (a plain
    # document, recorded for staleness, or anything else).
    def scan_child(found, visited:)
      return scan_directory(found, visited:) if File.directory?(found.path)

      name = found.name
      return nil unless name.end_with?(".md") && !name.casecmp?(README)
      return (@documents << found.path) && nil unless Runbook.runbook_file?(found.path)

      entry_for(found.with(name: File.basename(name, ".md"), slug: found.slug.delete_suffix(".md")), single_file: true)
    end

    def scan_folder(path, slug:, visited:)
      mtime = folder_mtime(path)
      @scanned[path] = mtime # every directory looked in, runbooks or not
      entries = []
      folders = []
      Dir.children(path).sort.each do |name|
        next if name.start_with?(".")

        found = Found.new(slug: slug.empty? ? name : "#{slug}/#{name}", name:, folder: slug, path: File.join(path, name))
        node  = scan_child(found, visited:)
        (node.is_a?(Folder) ? folders : entries) << node if node
      end
      entries = Tidy.unclash(entries, folders.map(&:slug))
      Folder.new(slug:, name: File.basename(path), path:, folders: Tidy.by_title(folders), entries: Tidy.by_title(entries), readme_html: readme_html(path),
                 mtime:)
    end

    # A directory is a runbook when it holds runbook.md, a folder when any
    # runbook lies beneath it, and nothing otherwise.
    def scan_directory(found, visited:)
      path = found.path
      return entry_for(found, single_file: false) if File.file?(File.join(path, Runbook::MAIN_FILE))

      real = File.realpath(path)
      return nil if visited.include?(real) || visited.size > MAX_DEPTH

      sub = scan_folder(path, slug: found.slug, visited: [*visited, real])
      sub.size.positive? ? sub : nil
    rescue SystemCallError
      nil
    end

    def entry_for(found, single_file:)
      runbook = Runbook.load(found.path, slug: found.slug, root: dir)
      Entry.new(**found.to_h, single_file:, runbook:, error: nil)
    rescue RunbookError, SystemCallError => e # an unreadable file is shown as broken, not dropped
      Entry.new(**found.to_h, single_file:, runbook: nil, error: e.message)
    end

    def readme_html(path)
      file = Dir.children(path).find { it.casecmp?(README) }
      file && Renderer.render_plain(File.read(File.join(path, file), encoding: "UTF-8"))
    rescue SystemCallError
      nil
    end

    def changed_since_scan?(path)
      !File.file?(path) || File.mtime(path) > scanned_at
    rescue SystemCallError
      true
    end

    def folder_mtime(path)
      File.mtime(path)
    rescue SystemCallError
      nil
    end

    def entry_stale?(entry)
      return entry.runbook.stale? if entry.ok?

      files = entry.single_file? ? [entry.path] : Dir.glob(File.join(entry.path, "**", "*.md"))
      files.empty? || files.any? { changed_since_scan?(it) }
    end
  end
end
