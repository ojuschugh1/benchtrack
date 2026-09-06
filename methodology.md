# Measurement methodology

BenchTrack's job is to decide whether a code change made a benchmark slower, using measurements taken on ordinary, noisy machines. Every choice below exists to keep environmental noise from being mistaken for a code effect, and to be honest about the noise that remains.

## Why measurements are paired

Benchmark numbers drift over time. Thermal state, background load, and scheduler behavior all change from minute to minute, so the same suite measured an hour apart produces different numbers with no code change at all. Comparing a stored baseline number against a fresh head number attributes all of that drift to the code. BenchTrack instead measures base and head close together in time, in the same session, and compares them pair by pair. Time-varying noise hits both sides, so the comparison cancels the shared drift instead of letting it masquerade as a speedup or slowdown.

## Why measurement is blocked and randomized

Pairing alone is not enough if one side always runs first. Measurements happen in repeated blocks, each containing exactly one base invocation and one head invocation, in an order decided per block by a seeded coin flip (AB or BA). If the machine slowly heats up or a background job ramps up over the run, that drift lands on the first and second position about equally often for each side, so it shows up as symmetric noise rather than a bias against whichever side would otherwise always run second. The seed is recorded in the report, so the exact ordering of any run can be reproduced.

## Why every invocation is a fresh process

Each invocation of the suite runs in a newly started Ruby subprocess. That resets JIT compilation state, GC state, and heap layout, so no side inherits a warmed-up or degraded VM from the other side's run. Inside each invocation, benchmark-ips runs its own warmup phase as usual, and that is the only warmup BenchTrack relies on, because it is already tuned for exactly that job. BenchTrack adds no warmup of its own on top.

## Why the gate requires the practical threshold and statistical significance

The unit of analysis is the per-block log ratio ln(head_ips / base_ips); the effect estimate for an entry is the mean of those logs, which corresponds to the geometric mean speed ratio. An entry fails the gate only when two conditions hold at once: the estimated slowdown exceeds the practical threshold (default 5%), and a paired sign-flip permutation test on the log ratios, Holm-adjusted across entries, gives p below 0.05.

Requiring both is deliberate. A statistically significant but tiny difference does not fail the build, because with enough consistent measurements even a fraction-of-a-percent slowdown becomes significant while staying irrelevant in practice. A large but noisy difference does not fail the build either, because without statistical support it is as likely to be a scheduling artifact as a real regression. Only a slowdown that is both larger than the threshold and supported by the test fails.

## What same-runner execution removes, and what it does not

Base and head are always measured on the same machine in the same session, so differences between machines never enter a comparison. Cross-runner hardware variance is removed by construction.

What remains is everything that varies within one session on one machine: shared-runner scheduling jitter, virtualization effects, and thermal throttling. Same-runner execution does not remove these. They stay in the data as noise, and the block design and the permutation statistics exist to absorb them. That is also why BenchTrack reports an effect estimate with a confidence interval and a p-value rather than trusting any single number: on a noisy runner, the honest output is quantified uncertainty, not a point comparison.
