# frozen_string_literal: true

require "open3"
require "fileutils"
require "tmpdir"

module BuildFixture
  BASE_K  = 100
  BIG_K   = 120
  SMALL_K = 102

  GEMFILE = <<~RUBY
    source "https://rubygems.org"

    gem "benchmark-ips"
  RUBY

  BENCH = <<~RUBY
    require "benchmark/ips"
    require_relative "../lib/work"

    Benchmark.ips do |x|
      x.config(warmup: 0.1, time: 0.1)
      x.report("work") { Work.run }
      x.report("work twice") { Work.run; Work.run }
    end
  RUBY

  module_function

  def build(path = nil)
    repo = File.expand_path(path || Dir.mktmpdir("benchtrack-fixture"))
    FileUtils.mkdir_p(repo)

    git repo, "init", "--quiet"
    git repo, "symbolic-ref", "HEAD", "refs/heads/main"
    git repo, "config", "user.name", "benchtrack fixture"
    git repo, "config", "user.email", "fixture@benchtrack.invalid"
    git repo, "config", "commit.gpgsign", "false"

    File.write(File.join(repo, "Gemfile"), GEMFILE)
    FileUtils.mkdir_p(File.join(repo, "bench"))
    File.write(File.join(repo, "bench", "ips.rb"), BENCH)
    write_work(repo, BASE_K)
    git repo, "add", "-A"
    git repo, "commit", "--quiet", "-m", "base"
    git repo, "tag", "v-base"

    git repo, "checkout", "--quiet", "-b", "big-regression", "v-base"
    write_work(repo, BIG_K)
    git repo, "commit", "--quiet", "-am", "increase work by 20%"

    git repo, "checkout", "--quiet", "-b", "small-slowdown", "v-base"
    write_work(repo, SMALL_K)
    git repo, "commit", "--quiet", "-am", "increase work by 2%"

    git repo, "checkout", "--quiet", "main"
    repo
  end

  def write_work(repo, k)
    FileUtils.mkdir_p(File.join(repo, "lib"))
    File.write(File.join(repo, "lib", "work.rb"), <<~RUBY)
      module Work
        K = #{k}

        def self.run
          acc = 0
          K.times do |i|
            s = +""
            16.times { |j| s << ((i + j) % 10).to_s }
            acc ^= s.hash
          end
          acc
        end
      end
    RUBY
  end

  def git(repo, *args)
    out, status = Open3.capture2e("git", "-C", repo, *args)
    raise "git #{args.join(" ")} failed:\n#{out}" unless status.success?
    out
  end
end

puts BuildFixture.build(ARGV[0]) if __FILE__ == $PROGRAM_NAME
