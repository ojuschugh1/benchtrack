# BenchTrack

[![CI](https://github.com/ojuschugh1/benchtrack/actions/workflows/ci.yml/badge.svg)](https://github.com/ojuschugh1/benchtrack/actions/workflows/ci.yml)

BenchTrack is pull-request-time performance regression testing for Ruby libraries. It takes an existing benchmark-ips suite, unmodified, and turns it into a paired base-versus-head comparison: both git refs are checked out into worktrees, measured in interleaved randomized blocks under one pinned Ruby, and the check fails only when a slowdown is both larger than a practical threshold and statistically supported. BenchTrack is Ruby-native and service-free: no hosted backend, no runtime gem dependencies, everything runs on the machine you invoke it on.

## Install

```
gem install benchtrack
```

Requires Ruby 3.1 or newer, Linux or macOS, and git. The measured project needs benchmark-ips in its bundle; BenchTrack itself declares zero runtime dependencies.

You can also run it straight from a checkout without installing anything: clone the repository and invoke `ruby -I/path/to/benchtrack/lib /path/to/benchtrack/exe/benchtrack ...`. There is nothing to build and no dependency beyond a Ruby that can load benchmark-ips for the project being measured.

## Quickstart

Run your suite once to check that BenchTrack can execute and parse it:

```
benchtrack run bench/ips.rb
```

Then compare two refs:

```
benchtrack compare main my-branch --suite bench/ips.rb
```

`--suite` is required and is a path relative to the repository root. Optional flags: `--blocks N` (measurement blocks, default 10), `--threshold PCT` (practical slowdown threshold in percent, default 5.0), `--seed N` (integer seed for reproducible runs, generated and recorded when absent), `--json PATH` (report path, default `benchtrack-report.json`), and `--prepare CMD` (shell command run in each worktree after bundle install).

Gems with C extensions need a build step in each worktree before the suite can load them, for example `--prepare 'bundle exec rake compile'`. The command runs with the worktree as its working directory and with the Ruby being measured first on `PATH`, and a nonzero exit aborts the comparison.

A suite file may call `Benchmark.ips` more than once. A report name that repeats across calls gets the call number appended, so the `json` report of the third call is labelled `json [3]`, while names that appear only once in the file are left alone.

The exit status is 0 when every benchmark passes, 1 when at least one supported regression is found, and 2 on operational errors such as unresolvable refs, failed dependency installs, or unparseable suite output. Every completed comparison also writes a JSON report with per-entry statistics and an environment fingerprint, so CI can archive it and scripts can parse it.

## How it measures

Measurements are collected in paired randomized blocks: each block runs one base invocation and one head invocation in random order, so time-varying system noise hits both sides roughly equally instead of biasing one. Every invocation is a fresh Ruby subprocess running your suite with the benchmark-ips warmup phase, so JIT, GC, and heap state never carry over between measurements. For each benchmark entry, BenchTrack computes the per-block log ratio of head to base, then applies an exact paired sign-flip permutation test with Holm adjustment across entries. An entry fails only when the estimated slowdown exceeds the practical threshold and the adjusted p-value is below 0.05, so neither noise alone nor a trivial difference alone can fail your build.

The full rationale is in [methodology.md](methodology.md). Reproducible pass and fail demonstrations, including a repeated no-change control, are in [validation/README.md](validation/README.md).

## Statistical floor

With n blocks, the minimum achievable two-sided permutation p-value is 2/2^n. Block counts below 6 therefore cannot produce a fail verdict: at 5 blocks the floor is 0.0625, which is above the 0.05 significance level, so the gate mathematically cannot fire. The default of 10 blocks gives a floor of about 0.002.

## Roadmap

None of the following exists yet; it is planned next work:

- benchmark-driver adapter
- packaged GitHub Action
- cross-runner calibration study
- real-gem case studies
- historical tracking and dashboards
- allocation tracking
- JIT-mode matrices (YJIT/ZJIT/no-JIT)

## License

MIT. See [LICENSE.txt](LICENSE.txt).
