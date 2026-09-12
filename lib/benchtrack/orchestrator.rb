# frozen_string_literal: true

require "open3"
require "tmpdir"
require "fileutils"
require "digest"
require "rbconfig"
require "bundler"

module BenchTrack
  module Orchestrator
    module_function

    def compare(config)
      repo = Dir.pwd
      _, status = Open3.capture2e("git", "rev-parse", "--git-dir", chdir: repo)
      raise GitError, "not inside a git repository: #{repo}" unless status.success?

      shas = { base: resolve_ref!(config.base), head: resolve_ref!(config.head) }

      Dir.mktmpdir("benchtrack") do |tmp|
        created = []
        begin
          worktrees = shas.to_h do |side, sha|
            dir = File.join(tmp, side.to_s)
            git("worktree", "add", "--detach", dir, sha, chdir: repo)
            created << dir
            [side, dir]
          end

          envs = {}
          lockfile_hashes = {}
          worktrees.each do |side, dir|
            envs[side] = install_bundle(side, dir, tmp)
            lockfile_hashes[side.to_s] = lockfile_hash(dir)
            prepare_worktree(side, dir, envs[side], config.prepare) if config.prepare
          end

          worktrees.each do |side, dir|
            next if File.file?(File.expand_path(config.suite, dir))

            raise SuiteError, "suite file not found in #{side} worktree: #{config.suite}"
          end

          invokers = worktrees.to_h do |side, dir|
            [side, -> { SuiteRunner.run_suite(config.suite, chdir: dir, env: envs[side]) }]
          end

          runs = Measurement.collect(blocks: config.blocks, rng: Random.new(config.seed)) do |side|
            invokers[side].call
          end
          pairing = Measurement.pair(runs[:base], runs[:head])
          results = Stats.analyze(pairing.series, seed: config.seed,
                                  threshold_pct: config.threshold_pct)

          Comparison.new(
            base_ref: config.base,
            head_ref: config.head,
            base_sha: shas[:base],
            head_sha: shas[:head],
            results: results,
            base_only: pairing.base_only,
            head_only: pairing.head_only,
            overall: results.any? { |result| result.verdict == "fail" } ? "fail" : "pass",
            fingerprint: Report.fingerprint(seed: config.seed, blocks: config.blocks,
                                            lockfile_hashes: lockfile_hashes),
            config: config
          )
        ensure
          created.each { |dir| remove_worktree(repo, dir) }
          prune_worktrees(repo)
        end
      end
    end

    def resolve_ref!(ref)
      out, status = Open3.capture2e("git", "rev-parse", "--verify", "--quiet", "#{ref}^{commit}")
      raise GitError, "cannot resolve git ref: #{ref}" unless status.success?

      out.strip
    end

    def git(*args, chdir:)
      out, status = Open3.capture2e("git", *args, chdir: chdir)
      raise GitError, "git #{args.join(' ')} failed:\n#{out}" unless status.success?

      out
    end

    def run_command(env, *argv, chdir:)
      Bundler.with_unbundled_env { Open3.capture2e(env, *argv, chdir: chdir) }
    end

    def install_bundle(side, worktree, tmp)
      gemfile = File.join(worktree, "Gemfile")
      return {} unless File.file?(gemfile)

      env = { "BUNDLE_GEMFILE" => gemfile, "BUNDLE_PATH" => File.join(tmp, "bundle-#{side}") }
      out, status = run_command(env, RbConfig.ruby, Gem.bin_path("bundler", "bundle"), "install",
                                chdir: worktree)
      raise BundleError, "bundle install failed for #{side}:\n#{out}" unless status.success?

      env
    end

    def prepare_worktree(side, worktree, env, command)
      path = "#{File.dirname(RbConfig.ruby)}#{File::PATH_SEPARATOR}#{ENV['PATH']}"
      out, status = run_command(env.merge("PATH" => path), "sh", "-c", command, chdir: worktree)
      raise PrepareError, "prepare command failed for #{side}:\n#{out}" unless status.success?
    end

    def lockfile_hash(worktree)
      lockfile = File.join(worktree, "Gemfile.lock")
      return "unknown" unless File.file?(lockfile)

      Digest::SHA256.hexdigest(File.read(lockfile))
    end

    def remove_worktree(repo, worktree)
      git("worktree", "remove", "--force", worktree, chdir: repo)
    rescue StandardError => e
      warn "benchtrack: could not remove worktree #{worktree}: #{e.message}"
      begin
        FileUtils.rm_rf(worktree)
      rescue StandardError => rm_error
        warn "benchtrack: could not delete #{worktree}: #{rm_error.message}"
      end
    end

    def prune_worktrees(repo)
      git("worktree", "prune", chdir: repo)
    rescue StandardError => e
      warn "benchtrack: git worktree prune failed: #{e.message}"
    end
  end
end
