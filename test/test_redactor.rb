# frozen_string_literal: true

require "test_helper"

class TestRedactor < Minitest::Test
  include RunsheetsTest

  Redactor = Runsheets::Redactor

  def test_empty_redactor_passes_text_through
    r = Redactor.new({})
    assert r.empty?
    assert_equal "hunter2\n", r.redact("hunter2\n")
    assert_equal "hun", r.feed("hun")
    assert_equal "", r.flush
  end

  def test_redacts_every_occurrence_of_every_secret
    r = Redactor.new("PW" => "swordfish", "TOKEN" => "abc123")
    assert_equal "pw=[redacted PW] again [redacted PW] token=[redacted TOKEN]\n",
                 r.redact("pw=swordfish again swordfish token=abc123\n")
  end

  def test_longer_secret_wins_when_one_contains_another
    r = Redactor.new("SHORT" => "fish", "LONG" => "swordfish")
    assert_equal "[redacted LONG] and [redacted SHORT]", r.redact("swordfish and fish")
  end

  def test_blank_secrets_are_ignored
    r = Redactor.new("A" => "", "B" => nil)
    assert r.empty?
  end

  def test_streaming_holds_back_a_partial_secret_across_chunks
    r = Redactor.new("PW" => "swordfish")
    assert_equal "say: ", r.feed("say: swor")
    assert_equal "[redacted PW] done\n", r.feed("dfish done\n")
    assert_equal "", r.flush
  end

  def test_streaming_releases_a_tail_that_turns_out_not_to_be_a_secret
    r = Redactor.new("PW" => "swordfish")
    assert_equal "a ", r.feed("a swo")
    assert_equal "swords are sharp", r.feed("rds are sharp")
    assert_equal "", r.flush
  end

  def test_flush_redacts_what_was_held_back
    r = Redactor.new("PW" => "swordfish")
    assert_equal "", r.feed("swordfis")
    assert_equal "swordfis", r.flush
    assert_equal "x", r.feed("x")
  end

  def test_for_picks_secret_inputs_with_values
    r = Redactor.for({ "NAME" => "world", "SECRET_WORD" => "hunter2" }, example_runbook)
    assert_equal({ "SECRET_WORD" => "hunter2" }, r.secrets)
    assert Redactor.for({ "NAME" => "world", "SECRET_WORD" => "" }, example_runbook).empty?
  end

  def test_binary_output_survives
    r = Redactor.new("PW" => "swordfish")
    out = r.redact("\xFF\xFEswordfish\xFF".b)
    assert_equal "\xFF\xFE[redacted PW]\xFF".b, out
    assert_equal Encoding::BINARY, out.encoding
  end

  def test_partial_secret_length
    r = Redactor.new("PW" => "swordfish", "T" => "abc")
    assert_equal 0, r.partial_secret_length("nothing here")
    assert_equal 3, r.partial_secret_length("xx swo")
    assert_equal 2, r.partial_secret_length("zzab")
    assert_equal 0, r.partial_secret_length("swordfish")
  end
end
