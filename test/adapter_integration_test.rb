# frozen_string_literal: true

require "minitest/autorun"
require "benchtrack"

class AdapterIntegrationTest < Minitest::Test
  FIXTURES = File.expand_path("fixtures", __dir__)
  GEM_ROOT = File.expand_path("..", __dir__)

  def run_fixture(name)
    BenchTrack::SuiteRunner.run_suite(File.join(FIXTURES, name),
                                      chdir: FIXTURES,
                                      env: BenchTrack::SuiteRunner.bundler_env(GEM_ROOT))
  end

  def test_real_suite_yields_normalized_entries
    entries = run_fixture("suite_ok.rb")

    assert_equal 2, entries.size
    assert_equal ["string concat", "string upcase"], entries.map(&:label)
    entries.each do |entry|
      assert_instance_of Float, entry.ips
      assert_predicate entry.ips, :finite?
      assert_predicate entry.ips, :positive?
    end
  end

  def test_raising_suite_surfaces_exit_status_and_output
    error = assert_raises(BenchTrack::SuiteError) { run_fixture("suite_raises.rb") }

    assert_match(/exited with status [1-9]\d*/, error.message)
    assert_includes error.message, "kaboom from suite"
  end

  def test_suite_without_ips_call_surfaces_missing_result_and_output
    error = assert_raises(BenchTrack::SuiteError) { run_fixture("suite_no_ips.rb") }

    assert_includes error.message, "no result file"
    assert_includes error.message, "did nothing"
  end
end
