# frozen_string_literal: true

require "rack/test"

module RunsheetsTest
  # Rack::Test against Runsheets::Web on a session for one runbook (the hello
  # example unless a test serves another). Call serve_web from setup and
  # stop_web from teardown; runbook directories made here go with it.
  module WebFixtures
    include Rack::Test::Methods
    include RunsheetsTest

    def app = Runsheets::Web

    def serve_web(runbook = example_runbook)
      @runs_root    = Dir.mktmpdir("runsheets-web")
      @runbook_dirs = []
      @stopper      = StopCounter.new(0)
      Runsheets::Web.set :rs_stopper, @stopper
      header "Host", "localhost"
      serve(runbook)
    end

    def stop_web
      @session&.end!("teardown")
      Runsheets::Web.set :rs_stopper, nil
      FileUtils.rm_rf([@runs_root, *@runbook_dirs])
    end

    # Point the app at a session on +runbook+ instead.
    def serve(runbook)
      @session&.end!("switching")
      @session = start_session(@runs_root, runbook:)
      Runsheets::Web.configure_for(@session)
    end

    # A runbook directory built from a hash of relative path => text.
    def runbook_from(files)
      dir = runbook_dir
      files.each do |rel, text|
        path = File.join(dir, rel)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, text)
      end
      Runsheets::Runbook.load(dir)
    end

    def serve_files(files) = serve(runbook_from(files))

    # A copy of the hello example to change on disk; returns its directory.
    def example_copy
      dir = runbook_dir
      FileUtils.cp_r(File.join(EXAMPLE_DIR, "."), dir)
      dir
    end

    def runbook_dir = Dir.mktmpdir("runsheets-web-rb").tap { @runbook_dirs << it }

    def with_token = header("X-Runsheets-Token", "tok")

    def start_run(inputs = nil) = post("/runs", { "_token" => "tok", "inputs" => inputs }.compact)

    # POST an execute for +block_id+ with the token; returns the response.
    def execute(block_id, params = {})
      with_token
      post "/blocks/#{block_id}/execute", params
    end

    def json(response = last_response) = JSON.parse(response.body)

    # Poll execution +id+ until it stops running; returns its last state.
    def finish(id)
      wait_for { json(get("/executions/#{id}"))["state"] != "running" }
      json
    end
  end

  # Sessions on throwaway runbooks for the hardening regressions.
  module HardeningFixtures
    include RunsheetsTest

    # A session with a run open on a runbook built from +files+.
    def with_session_on(files, inputs: {})
      with_runbook(files) do |rb|
        with_runs_dir { |root| yield open_session(root, runbook: rb, inputs:) }
      end
    end

    # End +session+ on another thread, give it a moment to start closing,
    # and return the thread.
    def end_in_background(session)
      Thread.new { session.end!("test") }.tap { sleep 0.05 }
    end
  end
end
