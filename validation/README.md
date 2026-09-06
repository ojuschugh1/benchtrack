# Validation

This directory demonstrates that BenchTrack's gate behaves correctly on known inputs: it passes when nothing changed, fails on an injected regression well above the threshold, and passes on an injected slowdown below the threshold. A repeated no-change control measures the observed false-positive rate over 30 independent runs. All scenarios run against a synthetic fixture repository so the injected effect sizes are known in advance, and the raw JSON reports from the published runs are committed under `results/`.

## The fixture

`build_fixture.rb` creates a throwaway git repository containing a tiny project: a `Gemfile` with only `benchmark-ips`, a pure CPU work function in `lib/work.rb`, and a two-entry benchmark-ips suite at `bench/ips.rb`. The base state is tagged `v-base`. Two branches inject slowdowns by scaling the amount of busy work, not by sleeping: `big-regression` does 1.2x the work (roughly a 17% ips drop) and `small-slowdown` does 1.02x (roughly 2%). Against BenchTrack's default 5% practical threshold, the first sits well above the gate and the second well below it.

## Reproducing the results

All commands run from the root of a BenchTrack source checkout unless noted otherwise.

One-shot run of all three scenarios (the script builds its own fixture, runs each comparison with `--seed 42`, asserts the expected exit statuses, and copies the JSON reports into `validation/results/`):

```
ruby validation/run_all.rb
```

The repeated no-change control (30 runs by default, each with a distinct seed, reports saved to `validation/results/control/`, false-positive rate printed at the end):

```
ruby validation/run_control.rb
```

The run count can be passed explicitly:

```
ruby validation/run_control.rb 30
```

To run a single scenario by hand, build the fixture first. The script prints the path of the repository it created:

```
ruby validation/build_fixture.rb
cd <printed fixture path>
```

Then, from inside the fixture repository, run the comparison for the scenario you want. With the gem installed this is `benchtrack compare ...`; from a source checkout, invoke the executable directly, substituting `/path/to/benchtrack` with the location of your checkout:

```
ruby -I/path/to/benchtrack/lib /path/to/benchtrack/exe/benchtrack compare v-base v-base --suite bench/ips.rb --seed 42
ruby -I/path/to/benchtrack/lib /path/to/benchtrack/exe/benchtrack compare v-base big-regression --suite bench/ips.rb --seed 42
ruby -I/path/to/benchtrack/lib /path/to/benchtrack/exe/benchtrack compare v-base small-slowdown --suite bench/ips.rb --seed 42
```

Add `--json <path>` to any of these to save the machine-readable report.

## Results

| Scenario | Expected verdict | Observed verdict |
|---|---|---|
| no-change | pass (exit 0) | pass (exit 0) |
| big-regression | fail (exit 1) | fail (exit 1) |
| small-slowdown | pass (exit 0) | pass (exit 0) |

Observed false-positive rate over the 30-run no-change control: 0/30 (0.0%).

## Interpretation

The gate behaved as designed on all three scenarios. The no-change comparison passed with both entries showing changes under 1.5% and Holm-adjusted p-values of 0.61, and the injected ~17% regression failed with both entries at -17.1% and -16.7% (Holm p 0.004, the smallest value 10 blocks can produce). The small-slowdown scenario is the most informative case: the `work` entry came out at -2.0% with a Holm-adjusted p of 0.004, meaning the ~2% injected slowdown was statistically detected, but the entry still passed because the estimated slowdown sits below the 5% practical threshold. The second entry (`work twice`, -1.0%, Holm p 0.145) was neither significant nor above the threshold. This is exactly the behavior the two-condition gate is meant to produce: statistical significance alone does not fail a build unless the effect is also practically large. Across the 30 independent no-change control runs, each with a distinct seed, no run produced a fail verdict, for an observed false-positive rate of 0/30 (0.0%) in this environment.

## Environment

All published runs (the three scenarios and the 30 control runs) were executed on the same machine:

| Field | Value |
|---|---|
| CPU | Apple M4 Pro (14 cores) |
| OS | macOS 26.6.2 |
| Kernel | Darwin 25.6.0 |
| Ruby | ruby 3.4.7 (2025-10-08 revision 7a5688e2a2) +PRISM [arm64-darwin25] |
| JIT | none |
| Blocks | 10 |

The three scenario runs used `--seed 42`; the control runs used seeds 1000 through 1029, one per run, each recorded in that run's fingerprint.

## Scope of these numbers

The observed false-positive rate was measured in a single environment. A cross-runner calibration study is planned grant-period work.
