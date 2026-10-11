# frozen_string_literal: true

module RunsheetsTest
  # Libraries of runbooks on disk, for the library and web library tests.
  module LibraryFixtures
    EXAMPLES = File.expand_path("../../examples", __dir__)

    # A one-step single-file runbook, with a tags line only when given +tags+.
    def single_runbook(title, tags = nil)
      tag_line = tags ? "tags: [#{tags}]\n" : ""
      "---\ntitle: #{title}\n#{tag_line}---\n\n## Only step\n<!-- kind: manual -->\n\nDo it.\n"
    end

    def manual_step(title) = "---\ntitle: #{title}\nkind: manual\n---\nDo it.\n"

    # Write +text+ to +rel+ under +dir+, making its folders.
    def write_file(dir, rel, text)
      path = File.join(dir, rel)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, text)
      path
    end

    # Rewrite +rel+ with +text+ and move its mtime on, so a change is seen
    # even within the same second.
    def rewrite_file(dir, rel, text)
      touch_later(write_file(dir, rel, text))
    end

    def touch_later(path) = FileUtils.touch(path, mtime: Time.now + 2)

    def remove_file(dir, rel) = FileUtils.rm(File.join(dir, rel))

    # A throwaway directory holding +files+ (relative path => text).
    def with_files(files)
      Dir.mktmpdir("runsheets-lib") do |dir|
        files.each { |rel, text| write_file(dir, rel, text) }
        yield dir
      end
    end

    # The nested library: folders to any depth, READMEs in any case, a
    # folder holding no runbooks, and a hidden folder.
    def nested_library_files
      {
        "README.md" => "# Ops\n\nEverything we run **by hand**.\n",
        "deploy.md" => single_runbook("Deploy", "release"),
        "database/backup/runbook.md" => "---\ntitle: Backup the database\n---\n",
        "database/backup/steps/010-dump.md" => manual_step("Dump"),
        "database/backup/steps/020-copy.md" => manual_step("Copy"),
        "database/restore.md" => single_runbook("Restore the database", "postgres"),
        "database/readme.md" => "Lower-case readme counts too.\n",
        "network/edge/teardown/runbook.md" => "---\ntitle: Tear down the edge\n---\n",
        "network/edge/teardown/steps/010-go.md" => manual_step("Go"),
        "network/backup.md" => single_runbook("Backup the routers", "network"),
        "empty/deeper/notes.txt" => "nothing here",
        ".hidden/secret.md" => single_runbook("Hidden", "x")
      }
    end

    # Yields the nested library's directory and the library loaded from it.
    def with_nested
      with_files(nested_library_files) { |dir| yield dir, Runsheets::Library.load(dir) }
    end
  end

  # The web app serving a library, for Rack::Test cases. The includer
  # provides Rack::Test::Methods.
  module WebLibraryFixtures
    include LibraryFixtures

    # The examples library served with a session started by "Tester".
    def serve_examples_library
      @runs_root = Dir.mktmpdir("runsheets-web")
      Runsheets.runs_dir = @runs_root
      @library = Runsheets::Library.load(EXAMPLES)
      serve_library_without_session
      Runsheets::Web.start_session(engineer: "Tester", why: "testing")
      header "Host", "localhost"
    end

    # The library served with no session yet, the token "tok".
    def serve_library_without_session
      Runsheets::Web.configure_for(nil, library: @library)
                    .prepare_start(session_options: { runs_root: @runs_root, echo: nil }, engineer: "Prefilled")
      Runsheets::Web.set :rs_token, "tok"
      Runsheets::Web.set :rs_stopper, StopCounter.new(0)
    end

    # End the running session and serve the library as if just started.
    def restart_without_session
      Runsheets::Web.session.end!("restart")
      serve_library_without_session
    end

    # Serve a single runbook (the hello example) instead of the library.
    def serve_one_runbook
      Runsheets::Web.session.end!("switching")
      Runsheets::Web.configure_for(start_session(@runs_root))
    end

    def nested_web_files
      {
        "README.md" => "# Ops\n\nThe **root** readme.\n",
        "deploy.md" => single_runbook("Deploy"),
        "platform/README.md" => "Platform things.\n",
        "platform/database/backup/runbook.md" => "---\ntitle: Backup the database\nwhen_to_use: Nightly.\n---\n\nPreamble here.\n",
        "platform/database/backup/steps/010-dump.md" => manual_step("Dump"),
        "platform/network/backup.md" => single_runbook("Backup the routers"),
        "platform/broken.md" => "---\ntitle: [oops\n---\n"
      }
    end

    # A nested library (with a broken runbook) served with a session started.
    def serve_nested_library
      @runs_root = Dir.mktmpdir("runsheets-web")
      @dir       = Dir.mktmpdir("runsheets-nested")
      Runsheets.runs_dir = @runs_root
      nested_web_files.each { |rel, text| write_file(@dir, rel, text) }
      @library = Runsheets::Library.load(@dir)
      serve_library_without_session
      Runsheets::Web.start_session(engineer: "Tester", why: "testing")
      header "Host", "localhost"
    end

    def stop_library_server
      Runsheets::Web.session&.end!("teardown")
      Runsheets::Web.set :rs_stopper, nil
      Runsheets.runs_dir = nil
      FileUtils.rm_rf(@runs_root)
      FileUtils.rm_rf(@dir) if @dir
    end

    def open_runbook(slug, inputs: {}) = post("/runs", "_token" => "tok", "slug" => slug, "inputs" => inputs)
  end
end
