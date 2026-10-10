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
    set :rs_token, nil

    # Wire a Session into the app and record the bind address the Host
    # check should honour. With a library (a directory of runbooks) the
    # session may be nil until the operator chooses one; every session
    # opened from the library shares one token. Returns the class.
    def self.configure_for(session, bind: "127.0.0.1", port: 4567, library: nil)
      raise ArgumentError, "a session or a library is needed" if session.nil? && library.nil?

      set :rs_session, session
      set :rs_library, library
      set :rs_token, session&.token || SecureRandom.hex(16)
      set :bind, bind
      set :port, port
      set :rs_bind, bind
      self
    end

    # The session being served right now, if a runbook is open.
    def self.session = settings.rs_session

    # Open one of the library's runbooks: it becomes the session served.
    # Refused while a run is active, since a session holds the run.
    def self.open_runbook(slug)
      library = settings.rs_library or raise RunbookError, "no library to choose from"
      raise RunError, "a run is active (#{session.run.id}); finish it before opening another runbook" if session&.active?

      runbook = library.runbook(slug)
      set :rs_session, Session.new(runbook:, token: settings.rs_token, library:)
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

      # Pages that work before any runbook is open in a library.
      def open_route? = library_route? || (library && request.path_info == "/search")

      def wants_json? = request.path_info.start_with?("/blocks/", "/executions/") || request.accept?("application/json")

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

      # Without a session there is no runbook to lay a page out around, so
      # the error is plain text.
      def fail_with(message, status)
        body = if wants_json? then json({ error: message }, status:)
               elsif rs        then page { Pages.error(rs, message, status, nonce: it) }
               else
                 content_type :text
                 "#{status}: #{message}\n"
               end
        halt status, body
      end

      def execution_json(execution)
        size = execution.output_size
        execution.to_h.merge(output: execution.output(tail: OUTPUT_TAIL), output_size: size,
                             output_truncated: size > OUTPUT_TAIL, success: execution.success?)
      end

      def after_step_href(step)
        _, nxt = runbook.neighbors(step)
        nxt ? Pages.step_href(nxt) : "/"
      end
    end

    before do
      reading = request.get? || request.head?
      fail_with("missing or invalid session token", 403) unless reading || token_ok?
      next if open_route?

      unless rs
        redirect "/library" if library
        fail_with("runsheets has no runbook loaded", 503)
      end
      rs.refresh_runbook! if reading
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

    post "/library/open" do
      slug = params["slug"].to_s
      fail_with("no runbook named #{slug}", 404) unless library.find(slug)
      Web.open_runbook(slug)
      redirect "/"
    end

    # A runbook or a folder selected in the tree, by its path in the library.
    get "/library/*" do
      slug = params["splat"].first.to_s.delete_suffix("/")
      fail_with("nothing named #{slug} in the library", 404) unless library.node(slug)
      page { Pages.library(library, rs, settings.rs_token, nonce: it, selected: slug) }
    end

    # A destructive block without its typed confirmation: tell the page the
    # code to ask for. 428 Precondition Required.
    error Session::ConfirmationRequired do
      e = env["sinatra.error"]
      json({ error: e.message, challenge: e.challenge, block_id: e.block_id }, status: 428)
    end

    error RunError do
      fail_with(env["sinatra.error"].message, 409)
    end

    error RunbookError do
      fail_with(env["sinatra.error"].message, 500)
    end

    not_found do
      fail_with("not found: #{request.path_info}", 404)
    end

    # -- search ---------------------------------------------------------

    # Full-text search over every runbook in the library, or over the one
    # runbook the server was started on.
    get "/search" do
      library&.refresh!
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
      path = Web.resolve_file(runbook.root, params["splat"].first) or fail_with("no such file", 404)
      send_file path
    end

    # A markdown file the runbook links to. One of the runbook's own files
    # goes to its page, another runbook in the library to its library page,
    # and anything else is rendered as a plain document.
    get "/docs/*" do
      path = Web.resolve_file(runbook.root, params["splat"].first) or fail_with("no such file", 404)
      fail_with("not a markdown document", 404) unless Renderer.markdown_path?(path)
      if (doc = runbook.document_at(path))
        redirect(doc == runbook.landing ? "/" : Pages.step_href(doc))
      end
      entry = library&.entry_at(path) and redirect(Pages::Chooser.href(entry.slug))
      page { Pages.document(rs, path, nonce: it) }
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

    # -- run lifecycle --------------------------------------------------

    post "/run" do
      inputs = params["inputs"].is_a?(Hash) ? params["inputs"] : {}
      kind   = params["kind"] == "verify" ? "verify" : "run"
      rs.start_run(inputs:, kind:)
      first = runbook.steps.first
      redirect(kind == "verify" ? "/verify" : (first ? Pages.step_href(first) : "/"))
    end

    post "/run/finish" do
      status = params["status"] || "completed"
      fail_with("status must be completed or abandoned", 422) unless RunRecord::FINAL_STATUSES.include?(status)
      rs.finish_run(status:)
      redirect "/"
    end

    post "/steps/:slug/mark" do
      step = runbook.step(params["slug"]) or fail_with("no step named #{params['slug']}", 404)
      fail_with("#{step.slug} is not a numbered step", 422) unless step.position
      status = params["status"]
      fail_with("status must be done or skipped", 422) unless %w[done skipped].include?(status)
      rs.mark_step(step.slug, status:, note: params["note"])
      redirect after_step_href(step)
    end

    # -- execution ------------------------------------------------------

    post "/blocks/:id/execute" do
      execution = rs.execute(params["id"], confirm: params["confirm"])
      json execution_json(execution), status: 202
    end

    post "/blocks/:id/acknowledge" do
      ack = rs.acknowledge(params["id"], note: params["note"])
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
