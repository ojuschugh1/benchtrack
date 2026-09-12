# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"
require "bundler"
require "benchtrack"

class OrchestratorTest < Minitest::Test
  BARE_IPS_AVAILABLE = Bundler.with_unbundled_env do
    system(RbConfig.ruby, "-e", "require 'benchmark/ips'", out: File::NULL, err: File::NULL)
  end

  PREPARED_SUITE = {
    "gen.rb" => "File.write(\"generated.rb\", \"GENERATED = 41\")\n",
    "bench.rb" => <<~RUBY
      require "benchmark/ips"
      require_relative "generated"

      Benchmark.ips do |x|
        x.config(warmup: 0.05, time: 0.05)
        x.report("gen") { GENERATED + 1 }
      end
    RUBY
  }.freeze

  BUNDLED_SUITE = {
    "Gemfile" => "source \"https://rubygems.org\"\n\ngem \"benchmark-ips\"\n",
    "bench.rb" => <<~RUBY
      require "benchmark/ips"

      Benchmark.ips do |x|
        x.config(warmup: 0.05, time: 0.05)
        x.report("plus") { 1 + 1 }
      end
    RUBY
  }.freeze

  def setup
    @tmp = Dir.mktmpdir("benchtrack-orchestrator")
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def test_prepare_runs_in_each_worktree_before_the_suite
    require_bare_ips
    repo = build_repo(PREPARED_SUITE)

    comparison = compare(repo, prepare: "#{RbConfig.ruby} gen.rb")

    assert_equal "pass", comparison.overall
    assert_equal ["gen"], comparison.results.map(&:label)
    assert_match(/\A\h{40}\z/, comparison.base_sha)
    assert_equal comparison.base_sha, comparison.head_sha
    assert_equal 1, git(repo, "worktree", "list").lines.length
  end

  def test_suite_failure_without_prepare_raises_suite_error
    require_bare_ips
    repo = build_repo(PREPARED_SUITE)

    assert_raises(BenchTrack::SuiteError) { compare(repo) }
  end

  def test_failing_prepare_command_raises_prepare_error_naming_the_side
    require_bare_ips
    repo = build_repo(PREPARED_SUITE)

    error = assert_raises(BenchTrack::PrepareError) { compare(repo, prepare: "exit 3") }
    assert_match(/prepare command failed for (base|head)/, error.message)
  end

  def test_gemfile_repo_is_bundled_per_side_and_lockfiles_are_fingerprinted
    repo = build_repo(BUNDLED_SUITE)

    comparison = compare(repo)

    assert_equal "pass", comparison.overall
    assert_equal ["plus"], comparison.results.map(&:label)
    hashes = comparison.fingerprint.fetch("lockfile_sha256")
    assert_equal %w[base head], hashes.keys.sort
    hashes.each_value { |sha| assert_match(/\A\h{64}\z/, sha) }
  end

  private

  def require_bare_ips
    return if BARE_IPS_AVAILABLE

    skip "benchmark-ips is not installed for #{RbConfig.ruby} outside a bundle"
  end

  def compare(repo, prepare: nil)
    config = BenchTrack::Config.new(command: "compare", suite: "bench.rb", base: "HEAD", head: "HEAD",
                                    threshold_pct: 5.0, blocks: 2, seed: 20_260_214,
                                    json_path: "unused.json", prepare: prepare)
    Dir.chdir(repo) { BenchTrack::Orchestrator.compare(config) }
  end

  def build_repo(files)
    repo = File.join(@tmp, "repo")
    FileUtils.mkdir_p(repo)
    git(repo, "init", "-q")
    git(repo, "config", "user.name", "benchtrack test")
    git(repo, "config", "user.email", "test@benchtrack.invalid")
    git(repo, "config", "commit.gpgsign", "false")
    files.each { |name, content| File.write(File.join(repo, name), content) }
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", "base")
    repo
  end

  def git(repo, *args)
    out, status = Open3.capture2e("git", "-C", repo, *args)
    flunk "git #{args.join(' ')} failed:\n#{out}" unless status.success?
    out
  end
end
