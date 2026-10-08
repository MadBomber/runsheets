# frozen_string_literal: true

require "ipaddr"
require "sinatra/base"

module Runsheets
  # The local web application. Binds to loopback, serves the runbook pages,
  # and exposes the execute/poll endpoints the page JavaScript uses.
  #
  # Security posture:
  # - Host header must be a loopback name or the bind address (rack-protection
  #   HostAuthorization), which defeats DNS rebinding.
  # - Every non-GET request must carry the session token, either in the
  #   X-Runsheets-Token header (fetch) or the _token form field. A page on
  #   another origin cannot read the token or send the custom header without
  #   a CORS preflight this app never answers.
  class Web < Sinatra::Base
    OUTPUT_TAIL = 256 * 1024
    RUN_ID      = /\A[\w.-]+\z/

    set :rs_session, nil
    set :static, false
    set :show_exceptions, false
    set :raise_errors, false
    set :dump_errors, false
    set :logging, false
    set :server, %w[puma webrick]
    set :host_authorization, { permitted_hosts: ["localhost", IPAddr.new("127.0.0.1"), IPAddr.new("::1")] }

    # Wire a Session into the app and restrict permitted hosts to the bind
    # address. Returns the class for chaining.
    def self.configure_for(session, bind: "127.0.0.1", port: 4567)
      set :rs_session, session
      set :bind, bind
      set :port, port
      hosts = ["localhost", IPAddr.new("127.0.0.1"), IPAddr.new("::1")]
      hosts << (IPAddr.new(bind) rescue bind) if bind && !hosts.include?(bind)
      set :host_authorization, { permitted_hosts: hosts.uniq }
      self
    end

    # Resolve a relative path inside root. Returns nil when it escapes root,
    # names a hidden entry, or is not a regular file.
    def self.resolve_file(root, relpath)
      parts = relpath.to_s.split("/").reject { it.empty? || it == "." }
      return nil if parts.any? { it.start_with?(".") }

      root = File.expand_path(root)
      path = File.expand_path(parts.join("/"), root)
      return nil unless path.start_with?("#{root}/") && File.file?(path)

      path
    end

    helpers do
      def rs      = settings.rs_session
      def runbook = rs.runbook

      def token_ok?
        token = rs.token
        [request.env["HTTP_X_RUNSHEETS_TOKEN"], params["_token"]].any? { it.is_a?(String) && Rack::Utils.secure_compare(it, token) }
      end

      def wants_json? = request.path_info.start_with?("/blocks/", "/executions/") || request.accept?("application/json")

      def json(data, status: 200)
        content_type :json
        self.status status
        JSON.generate(data)
      end

      def html(text)
        content_type :html
        text
      end

      def fail_with(message, status)
        halt status, (wants_json? ? json({ error: message }, status:) : html(Pages.error(rs, message, status)))
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
      fail_with("runsheets has no runbook loaded", 503) unless rs
      next if request.get? || request.head?

      fail_with("missing or invalid session token", 403) unless token_ok?
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

    # -- pages ----------------------------------------------------------

    get "/" do
      html Pages.landing(rs)
    end

    get "/steps/:slug" do
      step = runbook.step(params["slug"]) or fail_with("no step named #{params['slug']}", 404)
      html Pages.step(rs, step)
    end

    get "/files/*" do
      path = Web.resolve_file(runbook.dir, params["splat"].first) or fail_with("no such file", 404)
      send_file path
    end

    get "/run" do
      record = rs.run || rs.history.first or fail_with("no run has been started", 404)
      html Pages.run(rs, record)
    end

    get "/runs/:id" do
      id = params["id"]
      fail_with("bad run id", 404) unless id.match?(RUN_ID)
      dir = File.join(rs.runs_root, runbook.slug, id)
      fail_with("no run #{id}", 404) unless File.file?(File.join(dir, "run.json"))
      html Pages.run(rs, RunRecord.load(dir))
    end

    # -- run lifecycle --------------------------------------------------

    post "/run" do
      inputs = params["inputs"].is_a?(Hash) ? params["inputs"] : {}
      rs.start_run(inputs:)
      first = runbook.steps.first
      redirect(first ? Pages.step_href(first) : "/")
    end

    post "/run/finish" do
      rs.finish_run(status: params["status"] || "completed")
      redirect "/"
    end

    post "/steps/:slug/mark" do
      step = runbook.step(params["slug"]) or fail_with("no step named #{params['slug']}", 404)
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
