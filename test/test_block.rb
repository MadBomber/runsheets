# frozen_string_literal: true

require "test_helper"

class TestBlock < Minitest::Test
  def block(info, code = "echo\n") = Runsheets::Block.new(id: "s-1", index: 0, info:, code:)

  def test_display_by_default
    b = block("bash")
    assert_equal :display, b.kind
    refute b.executable?
    assert_empty b.warnings
  end

  def test_run
    b = block("bash run")
    assert_equal :run, b.kind
    assert b.executable?
    assert_equal "bash run", b.label
  end

  def test_destructive_implies_run
    assert_equal :destructive, block("bash destructive").kind
    assert_equal :destructive, block("bash run destructive").kind
    assert block("bash destructive").executable?
    assert_empty block("bash run destructive").warnings
  end

  def test_background_is_executable
    b = block("bash background")
    assert_equal :background, b.kind
    assert b.executable?
    assert b.background?
    refute b.destructive?
  end

  def test_terminal_and_expect_are_not_executable
    %w[terminal expect].each do |flag|
      b = block("bash #{flag}")
      assert_equal flag.to_sym, b.kind
      refute b.executable?
    end
    assert block("bash terminal").acknowledgeable?
    refute block("bash run").acknowledgeable?
    assert block("text expect").expect?
  end

  def test_expect_for_is_settable_and_serialised
    b = block("text expect")
    assert_nil b.expect_for
    b.expect_for = "s-1"
    assert_equal "s-1", b.to_h[:expect_for]
  end

  def test_unknown_flag_warns
    b = block("bash run frobnicate")
    assert_equal :run, b.kind
    assert_equal ["unknown flag: frobnicate"], b.warnings
  end

  def test_conflicting_flags_warn
    b = block("bash background terminal")
    assert_equal :background, b.kind
    assert_match(/conflicting flags/, b.warnings.first)
  end

  def test_unsupported_language_cannot_execute
    b = block("sql run")
    assert_equal :run, b.kind
    refute b.executable?
    assert_match(/sql blocks cannot execute/, b.warnings.first)
  end

  def test_a_mapped_language_can_execute
    interpreters = Runsheets::Block::INTERPRETERS.merge("sql" => %w[psql -f])
    b = Runsheets::Block.new(id: "s-1", index: 0, info: "sql run", code: "select 1;\n", interpreters:)
    assert b.executable?
    assert_empty b.warnings
    assert_equal %w[psql -f], b.interpreters["sql"]
  end

  def test_no_language
    b = block("")
    assert_equal "", b.lang
    assert_equal :display, b.kind
  end

  def test_referenced_variables
    b = block("bash run", "echo $NAME ${OTHER} $1 $$\n")
    assert_equal %w[NAME OTHER], b.referenced_variables
  end

  def test_to_h
    h = block("ruby run").to_h
    assert_equal "ruby", h[:lang]
    assert_equal ["run"], h[:flags]
    assert h[:executable]
  end
end
