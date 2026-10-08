# frozen_string_literal: true

module Runsheets
  # Replaces secret input values in captured output before it is stored.
  #
  # Plain string replacement: a secret that a command prints base64-encoded,
  # URL-encoded or split across lines is not caught. Output arrives in
  # chunks, so #feed holds back any tail that could be the start of a
  # secret until the next chunk (or #flush) settles it.
  class Redactor
    # The redactor for a run: every secret input that has a value.
    def self.for(inputs, runbook)
      secrets = inputs.to_h.select { |name, value| runbook.input(name)&.secret? && !value.to_s.empty? }
      new(secrets)
    end

    attr_reader :secrets

    # +secrets+ maps an input name to its value.
    def initialize(secrets)
      @secrets = secrets.to_h { |name, value| [name.to_s, value.to_s.b] }.reject { |_, v| v.empty? }.freeze
      @values  = @secrets.sort_by { |_, v| -v.bytesize }.freeze
      @pending = +"".b
    end

    def empty? = @secrets.empty?

    # Longest tail of a chunk that could still be the start of a secret.
    def hold_back = @values.map { |_, v| v.bytesize }.max.to_i - 1

    # Every occurrence of every secret replaced. Longer secrets first, so a
    # secret that contains another is replaced whole.
    def redact(text)
      return text if empty?

      out = text.b
      @values.each { |name, value| out = out.gsub(value, "[redacted #{name}]") }
      out.force_encoding(text.encoding)
    end

    # Streaming: returns the part of the output so far that is safe to
    # write, keeping back a tail that may be a partial secret.
    def feed(chunk)
      return chunk if empty?

      @pending << chunk.b
      keep = partial_secret_length(@pending)
      safe = @pending.byteslice(0, @pending.bytesize - keep)
      @pending = @pending.byteslice(@pending.bytesize - keep, keep) || +"".b
      redact(safe)
    end

    # Whatever #feed was holding back, redacted. Call at end of stream.
    def flush
      out = redact(@pending)
      @pending = +"".b
      out
    end

    # Length of the longest suffix of +text+ that is a proper prefix of
    # some secret.
    def partial_secret_length(text)
      limit = [hold_back, text.bytesize].min
      limit.downto(1) do |k|
        tail = text.byteslice(-k, k)
        return k if @values.any? { |_, v| v.bytesize > k && v.start_with?(tail) }
      end
      0
    end
  end
end
