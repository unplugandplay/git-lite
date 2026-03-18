require_relative 'test_helper'

class UITest < GitLite::TestCase
  def test_color_returns_escape_sequence
    refute_empty GitLite::UI.color(:red)
    refute_empty GitLite::UI.color(:green)
    refute_empty GitLite::UI.color(:yellow)
  end

  def test_color_unknown_returns_empty
    assert_equal '', GitLite::UI.color(:unknown)
  end

  def test_reset_returns_reset_sequence
    refute_empty GitLite::UI.reset
  end

  def test_colored_wraps_text
    colored = GitLite::UI.colored("test", :red)

    assert_includes colored, "test"
    assert_includes colored, GitLite::UI.color(:red)
    assert_includes colored, GitLite::UI.reset
  end

  def test_success_wraps_in_green
    text = GitLite::UI.success("Success!")

    assert_includes text, "Success!"
    assert_includes text, GitLite::UI.color(:green)
  end

  def test_error_wraps_in_red
    text = GitLite::UI.error("Error!")

    assert_includes text, "Error!"
    assert_includes text, GitLite::UI.color(:red)
  end

  def test_warning_wraps_in_yellow
    text = GitLite::UI.warning("Warning!")

    assert_includes text, "Warning!"
    assert_includes text, GitLite::UI.color(:yellow)
  end

  def test_info_wraps_in_cyan
    text = GitLite::UI.info("Info!")

    assert_includes text, "Info!"
    assert_includes text, GitLite::UI.color(:cyan)
  end

  def test_format_bytes_zero
    assert_equal "0 B", GitLite::UI.format_bytes(0)
  end

  def test_format_bytes_bytes
    assert_equal "100 B", GitLite::UI.format_bytes(100)
  end

  def test_format_bytes_kilobytes
    assert_includes GitLite::UI.format_bytes(2048), "KB"
  end

  def test_format_bytes_megabytes
    assert_includes GitLite::UI.format_bytes(5 * 1024 * 1024), "MB"
  end

  def test_format_bytes_gigabytes
    assert_includes GitLite::UI.format_bytes(3 * 1024 * 1024 * 1024), "GB"
  end

  def test_format_count_small
    assert_equal "123", GitLite::UI.format_count(123)
  end

  def test_format_count_thousands
    assert_equal "1,234", GitLite::UI.format_count(1234)
  end

  def test_format_count_millions
    assert_equal "1,234,567", GitLite::UI.format_count(1234567)
  end

  def test_progress_bar_zero
    bar = GitLite::UI.progress_bar(0, 100)

    assert_includes bar, "0%"
    assert_includes bar, "["
    assert_includes bar, "]"
  end

  def test_progress_bar_complete
    bar = GitLite::UI.progress_bar(100, 100)

    assert_includes bar, "100%"
  end

  def test_progress_bar_halfway
    bar = GitLite::UI.progress_bar(50, 100)

    assert_includes bar, "50%"
    assert_includes bar, "="
  end

  def test_progress_bar_with_counts
    bar = GitLite::UI.progress_bar(75, 100)

    assert_includes bar, "(75/100)"
  end

  def test_table_empty
    result = GitLite::UI.table(['col1', 'col2'], [])

    assert_equal "No data", result
  end

  def test_table_single_row
    result = GitLite::UI.table(['Name', 'Value'], [['test', '123']])

    assert_includes result, "Name"
    assert_includes result, "Value"
    assert_includes result, "test"
    assert_includes result, "123"
  end

  def test_table_multiple_rows
    rows = [
      ['Alice', '25'],
      ['Bob', '30'],
      ['Charlie', '35']
    ]

    result = GitLite::UI.table(['Name', 'Age'], rows)

    assert_includes result, "Alice"
    assert_includes result, "Bob"
    assert_includes result, "Charlie"
    assert_includes result, "---"
  end

  def test_table_aligns_columns
    rows = [
      ['A', '12345'],
      ['Longer', '1']
    ]

    result = GitLite::UI.table(['Col1', 'Col2'], rows)
    lines = result.split("\n")

    # Header and rows should have same width
    header_width = lines[0].length
    lines.each { |line| assert_equal header_width, line.length }
  end

  def test_table_with_numbers
    rows = [
      [1, 100],
      [2, 200]
    ]

    result = GitLite::UI.table(['ID', 'Count'], rows)

    assert_includes result, "1"
    assert_includes result, "100"
  end
end

MTest::Unit.new.run
