# frozen_string_literal: true

require "ipaddr"
require "sinatra/base"

module Runsheets
  # The local web application. Binds to loopback, serves the runbook pages,
  # and exposes the execute/poll endpoints the page JavaScript uses.
  #
  # Security posture:
  # - Host header must be a loopback name or the bind address (rack-protection
  #   HostAuthorization), which defeats DNS rebinding. A wildcard bind cannot
  #   enumerate its hosts, so the check is off for one; the CLI warns.
  # - Every non-GET request must carry the session token, either in the
  #   X-Runsheets-Token header (fetch) or the _token form field. A page on
  #   another origin cannot read the token or send the custom header without
  #   a CORS preflight this app never answers.
  # - Every page carries a Content-Security-Policy whose script and style
  #   sources are a per-response nonce held only by the page's own inline
  #   script and stylesheet. Raw HTML in runbook markdown renders, but a
  #   <script> in it does not run, so a runbook cannot drive the token.
  class Web < Sinatra::Base
    OUTPUT_TAIL    = 256 * 1024
    RUN_ID         = /\A[\w.-]+\z/
    LOOPBACK_HOSTS = ["localhost", IPAddr.new("127.0.0.1"), IPAddr.new("::1")].freeze
    WILDCARDS      = %w[0.0.0.0 :: [::]].freeze
    # Served files run no script and load nothing, even inline.
    FILE_CSP       = "default-src 'none'; img-src 'self' data:; style-src 'unsafe-inline'; sandbox"

    set :rs_session, nil
    set :static, false
    set :show_exceptions, false
    set :raise_errors, false
    set :dump_errors, false
    set :logging, false
    set :server, %w[puma webrick]
    set :rs_bind, "127.0.0.1"
    # The loopback names are always permitted. Anything the bind address
    # adds is decided per request (see .bind_allows?), because the
    # middleware stack captures this hash the first time the app is built.
    set :host_authorization, { permitted_hosts: LOOPBACK_HOSTS.dup, allow_if: ->(env) { Web.bind_allows?(env) } }

    set :rs_library, nil
    set :rs_runbook, nil
    set :rs_token, nil
    set :rs_session_options, {}
    set :rs_engineer, nil
    set :rs_stopper, nil

    # Wire the app up and record the bind address the Host check should
    # honour. +session+ is the engineering session when it has already
    # started, else nil and the start page asks who and why (see
    # .prepare_start). The server serves a +library+ of runbooks or one
    # +runbook+. Returns the class.
    def self.configure_for(session, bind: "127.0.0.1", port: 4567, library: nil, runbook: nil)
      runbook ||= session&.runbook unless library
      raise ArgumentError, "a library or a runbook is needed" if library.nil? && runbook.nil?

      set :rs_session, session
      set :rs_library, library
      set :rs_runbook, runbook
      set :rs_token, session&.token || SecureRandom.hex(16)
      set :bind, bind
      set :port, port
      set :rs_bind, bind
      self
    end

    # What a session started from the start page is built with (runs_root,
    # log_level, echo), and who the page suggests as the engineer.
    def self.prepare_start(session_options: {}, engineer: nil)
      set :rs_session_options, session_options
      set :rs_engineer, engineer
      self
    end

    # What End session does once the session is closed: stop this process,
    # just after the response is sent, the way Ctrl-C would. A test sets
    # :rs_stopper to anything with #call that is not a Proc (Sinatra calls a
    # Proc setting when it is read).
    def self.stop_process = Thread.new { sleep 0.5; Process.kill("INT", Process.pid) } # rubocop:disable Style/Semicolon

    # The engineering session, once it has started.
    def self.session = settings.rs_session

    # Start the session from the start page's answers.
    def self.start_session(engineer:, why:)
      set :rs_session, Session.new(engineer:, why:, library: settings.rs_library, runbook: settings.rs_runbook,
                                   token: settings.rs_token, **settings.rs_session_options)
    end

    # Does the bind address let this request's Host through, beyond the
    # loopback names? A non-loopback bind permits its own address. A
    # wildcard bind answers on every interface, so no host list can be
    # right and the check is off; the CLI warns about that.
    def self.bind_allows?(env)
      bind = settings.rs_bind
      return true if wildcard?(bind)
      return false if loopback?(bind)

      same_host?(Rack::Request.new(env).host, bind)
    rescue StandardError
      false
    end

    def self.same_host?(host, bind)
      return true if host == bind

      IPAddr.new(host.to_s) == IPAddr.new(bind.to_s)
    rescue IPAddr::Error
      false
    end

    def self.wildcard?(bind) = WILDCARDS.include?(bind.to_s)

    def self.loopback?(bind)
      return true if bind.nil? || bind == "localhost"

      IPAddr.new(bind.to_s).loopback?
    rescue IPAddr::Error
      false
    end

    # Resolve a relative path inside root. Returns nil when it escapes root
    # (through ".." or a symlink), names a hidden entry, or is not a
    # regular file. The returned path is the real path.
    def self.resolve_file(root, relpath)
      parts = relpath.to_s.split("/").reject { it.empty? || it == "." }
      return nil if parts.any? { it.start_with?(".") }

      root = File.realpath(root)
      path = File.expand_path(parts.join("/"), root)
      return nil unless path.start_with?("#{root}/") && File.file?(path)

      real = File.realpath(path)
      real.start_with?("#{root}/") ? real : nil
    rescue SystemCallError
      nil
    end

    # inline for an image, a PDF or plain text; attachment for anything
    # else, so an HTML or XML file in a runbook directory can never become a
    # page on this origin.
    def self.disposition_for(path) = %w[.png .jpg .jpeg .gif .webp .svg .pdf .txt].include?(File.extname(path).downcase) ? "inline" : "attachment"

    # A fresh CSP nonce for one response.
    def self.nonce = SecureRandom.base64(16)

    def self.csp(nonce)
      "default-src 'none'; script-src 'nonce-#{nonce}'; style-src 'nonce-#{nonce}'; style-src-attr 'unsafe-inline'; " \
        "img-src 'self' data: https: http:; connect-src 'self'; form-action 'self'; base-uri 'none'; object-src 'none'; frame-ancestors 'none'"
    end

    helpers do
      def rs      = settings.rs_session
      def library = settings.rs_library
      def runbook = rs.runbook

      def token_ok?
        token = settings.rs_token
        [request.env["HTTP_X_RUNSHEETS_TOKEN"], params["_token"]].any? { it.is_a?(String) && Rack::Utils.secure_compare(it, token) }
      end

      def library_route? = request.path_info == "/library" || request.path_info.start_with?("/library/")

      # The start page and its form: the only pages before a session exists.
      def start_route? = request.path_info == "/session/new" || (request.post? && request.path_info == "/session")

      # Pages about the session itself, which need no runbook on screen.
      def session_route? = request.path_info == "/session" || request.path_info.start_with?("/session/")

      # Pages that work before any runbook is on screen: the library, the
      # session, selecting a runbook, search, and the files and documents
      # runbooks link to, which the library's runbook pane already shows.
      def open_route?
        path = request.path_info
        library_route? || session_route? || path == "/runs" || (library && (path == "/search" || path.start_with?("/docs/", "/files/")))
      end

      # The directory /files/ and /docs/ serve from: the library, or the
      # one runbook's root.
      def content_root = library&.dir || runbook.root

      # The page's script asks for JSON; a browser navigating asks for HTML
      # (its Accept ends in */*, which matches JSON too, so ask which it prefers).
      def wants_json?
        request.path_info.start_with?("/blocks/", "/executions/") || request.preferred_type("text/html", "application/json") == "application/json"
      end

      def json(data, status: 200)
        content_type :json
        self.status status
        JSON.generate(data)
      end

      # Render a page: yields the nonce the page must put on its inline
      # script and style, and sets the headers that go with it. Pages carry
      # the session token, so they are never cached.
      def page
        nonce = Web.nonce
        headers "Content-Security-Policy" => Web.csp(nonce), "Cache-Control" => "no-store"
        content_type :html
        yield nonce
      end

      # An error as JSON for the page's script; otherwise as a page, in the
      # runbook's layout, the library's frame, or alone.
      def fail_with(message, status)
        env["runsheets.failed"] = true
        body = if wants_json?   then json({ error: message }, status:)
               elsif rs&.runbook then page { Pages.error(rs, message, status, nonce: it) }
               else page { Pages.error_page(message, status, library:, session: rs, nonce: it) }
               end
        halt status, body
      end

      # The run an action from a page belongs to. A page says which runbook
      # it shows (the runbook field), so a tab left on one runbook keeps
      # acting on it after another tab has opened a different one.
      def target_run
        slug = params["runbook"].to_s
        return rs.current! if slug.empty?

        rs.run_for(slug) or raise RunError, "#{slug} has no run in this session; start it first"
      end

      def execution_json(execution)
        size = execution.output_size
        execution.to_h.merge(output: execution.output(tail: OUTPUT_TAIL), output_size: size,
                             output_truncated: size > OUTPUT_TAIL, success: execution.success?)
      end

      # The runbook POST /runs selects: by slug from the library, freshly
      # loaded, or the one runbook served.
      def runbook_to_open = (settings.rs_runbook && rs.runbook) || library_runbook(params["slug"].to_s)

      def library_runbook(slug)
        fail_with("no runbook named #{slug}", 404) unless library.find(slug)
        library.runbook(slug)
      end

      def after_step_href(step)
        _, nxt = runbook.neighbors(step)
        nxt ? Pages.step_href(nxt) : "/"
      end
    end

    before do
      reading = request.get? || request.head?
      fail_with("missing or invalid session token", 403) unless reading || token_ok?
      if start_route?
        redirect "/session" if rs
        next
      end

      unless rs
        redirect "/session/new" if reading
        fail_with("start the session first: who is starting it, and why", 409)
      end
      fail_with("this session has ended; start runsheets again for a new one", 410) if rs.ended? && request.path_info != "/session"
      rs.log.debug("#{request.request_method} #{request.fullpath}", tags: ["web"])
      next if open_route?

      redirect "/library" unless rs.runbook
      rs.refresh_runbook! if reading
    end

    # -- the session ----------------------------------------------------

    # Who is starting the session, and why. Once it has started, the
    # session page instead.
    get "/session/new" do
      page { Pages.session_new(settings.rs_token, engineer: settings.rs_engineer, nonce: it) }
    end

    post "/session" do
      engineer = params["engineer"].to_s
      why      = params["why"].to_s
      if engineer.strip.empty? || why.strip.empty?
        status 422
        next page { Pages.session_new(settings.rs_token, engineer:, why:, error: "Both are needed: who you are, and why the session is starting.", nonce: it) }
      end
      Web.start_session(engineer:, why:)
      redirect(library ? "/library" : "/")
    end

    # The notebook so far: the engineer, the notes, the runs, the log.
    get "/session" do
      page { Pages.session(rs, library, settings.rs_token, nonce: it) }
    end

    post "/session/notes" do
      if params["note"].to_s.strip.empty?
        status 422
        next page { Pages.session(rs, library, settings.rs_token, error: "A note needs some text.", nonce: it) }
      end
      rs.note!(params["note"])
      redirect(params["back"].to_s.start_with?("/") ? params["back"] : "/session#notes")
    end

    # End the session: every run closes with the status its work earns,
    # and the server stops.
    post "/session/end" do
      rs.end!("End session button")
      (settings.rs_stopper || Web.method(:stop_process)).call
      page { Pages.session_ended(rs, nonce: it) }
    end

    # -- library: choosing a runbook -----------------------------------

    # The library, or a 404 when the server was started on one runbook.
    # Reading it picks up runbooks added, removed or edited since.
    before "/library*" do
      fail_with("runsheets was started on one runbook, not a directory of them", 404) unless library
      library.refresh! if request.get? || request.head?
    end

    # The tree with nothing selected: the root folder in the main pane.
    get "/library" do
      page { Pages.library(library, rs, settings.rs_token, nonce: it) }
    end

    # A runbook or a folder selected in the tree, by its path in the library.
    get "/library/*" do
      slug = params["splat"].first.to_s.delete_suffix("/")
      fail_with("nothing named #{slug} in the library", 404) unless library.node(slug)
      page { Pages.library(library, rs, settings.rs_token, nonce: it, selected: slug) }
    end

    # A destructive block without its typed confirmation: tell the page the
    # code to ask for. 428 Precondition Required.
    error Run::ConfirmationRequired do
      e = env["sinatra.error"]
      json({ error: e.message, challenge: e.challenge, block_id: e.block_id }, status: 428)
    end

    error RunError do
      message = env["sinatra.error"].message
      rs&.log&.warn("refused #{request.request_method} #{request.path_info}: #{message}", tags: ["web"])
      fail_with(message, 409)
    end

    error RunbookError do
      message = env["sinatra.error"].message
      rs&.log&.error(message, tags: ["web"])
      fail_with(message, 500)
    end

    error StandardError do
      e = env["sinatra.error"]
      rs&.log&.error("#{e.class}: #{e.message} at #{e.backtrace&.first}", tags: ["web"])
      fail_with("internal error: #{e.message}", 500)
    end

    not_found do
      next if env["runsheets.failed"] # fail_with already said what was not found

      fail_with("not found: #{request.path_info}", 404)
    end

    # -- search ---------------------------------------------------------

    # Full-text search over every runbook in the library, or over the one
    # runbook the server was started on.
    get "/search" do
      library&.refresh!
      rs.log.debug("search #{params['q'].to_s.inspect}", tags: ["web"])
      page { Pages.search(rs, library, params["q"].to_s, token: settings.rs_token, nonce: it) }
    end

    # -- pages ----------------------------------------------------------

    get "/" do
      page { Pages.landing(rs, nonce: it) }
    end

    get "/steps/:slug" do
      step = runbook.step(params["slug"]) or fail_with("no step named #{params['slug']}", 404)
      page { Pages.step(rs, step, nonce: it) }
    end

    get "/files/*" do
      path = Web.resolve_file(content_root, params["splat"].first) or fail_with("no such file", 404)
      headers "Content-Security-Policy" => FILE_CSP, "X-Content-Type-Options" => "nosniff"
      send_file path, disposition: Web.disposition_for(path)
    end

    # A markdown file the runbook links to. One of the runbook's own files
    # goes to its page, another runbook in the library to its library page,
    # and anything else is rendered as a plain document.
    get "/docs/*" do
      path = Web.resolve_file(content_root, params["splat"].first) or fail_with("no such file", 404)
      fail_with("not a markdown document", 404) unless Renderer.markdown_path?(path)
      if (doc = rs&.runbook&.document_at(path))
        redirect(doc == runbook.landing ? "/" : Pages.step_href(doc))
      end
      entry = library&.entry_at(path) and redirect(Pages::Chooser.href(entry.slug))
      page { Pages.document(rs, path, library:, token: settings.rs_token, nonce: it) }
    end

    get "/verify" do
      fail_with("this runbook has no verify steps or verify.md", 404) if runbook.verify_documents.empty?
      page { Pages.verify(rs, nonce: it) }
    end

    get "/run" do
      record = rs.run || rs.history.first or fail_with("no run has been started", 404)
      page { Pages.run(rs, record, nonce: it) }
    end

    get "/runs/:id" do
      id = params["id"]
      fail_with("bad run id", 404) unless id.match?(RUN_ID)
      dir = File.join(rs.runs_root, runbook.slug, id)
      fail_with("no run #{id}", 404) unless File.file?(File.join(dir, "run.json"))
      page { Pages.run(rs, RunRecord.load(dir), nonce: it) }
    end

    # -- runs -------------------------------------------------------------

    # Select a runbook: establish its run with the inputs given, or return
    # to the run it already has, and land on its page. In a library the
    # slug names the runbook; otherwise it is the one runbook served.
    post "/runs" do
      inputs = params["inputs"].is_a?(Hash) ? params["inputs"] : {}
      rs.open(runbook_to_open, inputs:)
      redirect "/"
    end

    # Change the inputs of the run on screen partway.
    post "/run/inputs" do
      target_run.change_inputs(params["inputs"].is_a?(Hash) ? params["inputs"] : {})
      redirect "/"
    end

    post "/steps/:slug/mark" do
      run  = target_run
      step = run.runbook.step(params["slug"]) or fail_with("no step named #{params['slug']}", 404)
      fail_with("#{step.slug} is not a numbered step", 422) unless step.position
      status = params["status"]
      fail_with("status must be done or skipped", 422) unless %w[done skipped].include?(status)
      run.mark_step(step.slug, status:, note: params["note"])
      rs.show(run.runbook) unless run == rs.current
      redirect after_step_href(step)
    end

    # -- execution ------------------------------------------------------

    post "/blocks/:id/execute" do
      execution = target_run.execute(params["id"], confirm: params["confirm"])
      json execution_json(execution), status: 202
    end

    post "/blocks/:id/acknowledge" do
      ack = target_run.acknowledge(params["id"], note: params["note"])
      json ack.merge(block_id: params["id"]), status: 201
    end

    get "/executions/:id" do
      execution = rs.execution(params["id"]) or fail_with("no execution #{params['id']}", 404)
      json execution_json(execution)
    end

    post "/executions/:id/stop" do
      execution = rs.stop(params["id"])
      json execution_json(execution), status: 202
    end
  end
end
