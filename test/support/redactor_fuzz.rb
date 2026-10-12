# frozen_string_literal: true

module RunsheetsTest
  # Random streams for Redactor: short secrets over a two-letter alphabet,
  # so secrets overlap themselves and each other, fed in random pieces.
  module RedactorFuzz
    Case = Data.define(:secrets, :text, :pieces)

    # +count+ cases from a fixed +seed+, so a failure reproduces.
    def self.cases(count, seed: 20_261_011)
      rng = Random.new(seed)
      Array.new(count) { random_case(rng) }
    end

    def self.random_case(rng)
      secrets = Array.new(rng.rand(1..3)) { |i| ["S#{i}", word(rng, "ab", 1..6)] }.to_h
      text    = word(rng, "abx", 0..30)
      cuts    = Array.new(rng.rand(0..4)) { rng.rand(0..text.size) }.sort
      Case.new(secrets:, text:, pieces: [0, *cuts, text.size].each_cons(2).map { |a, b| text[a...b] })
    end

    def self.word(rng, letters, sizes) = Array.new(rng.rand(sizes)) { letters[rng.rand(letters.size)] }.join

    # The redacted stream for a case: its pieces fed one at a time, then flushed.
    def self.stream(kase)
      redactor = Runsheets::Redactor.new(kase.secrets)
      kase.pieces.sum("") { redactor.feed(it) } + redactor.flush
    end

    # The cases whose stream lets a secret through between the markers, or
    # (with one secret, where the answer is unambiguous) differs from
    # redacting the whole text at once.
    def self.failures(cases)
      cases.reject do |kase|
        out    = stream(kase)
        parts  = out.split(/\[redacted S\d\]/)
        clean  = parts.none? { |part| kase.secrets.each_value.any? { part.include?(it) } }
        clean && (kase.secrets.size > 1 || out == Runsheets::Redactor.new(kase.secrets).redact(kase.text))
      end
    end
  end
end
