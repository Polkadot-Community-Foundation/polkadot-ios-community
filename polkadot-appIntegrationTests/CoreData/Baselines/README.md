# Core Data benchmark baselines

One directory per library version, one JSON per scenario and stack variant. Numbers are comparable
only across runs on the same machine; run twice and keep the second run.

## How to read the columns

Each measure is a set of `n` individual operation latencies (one fetch, one save, one save-to-delivery
interval). `LatencyRecorder` sorts them and reports positions in that sorted list rather than the mean,
because contention shows up as a long tail that a mean hides.

| Column | Meaning | What it tells you |
|---|---|---|
| `n` | number of operations measured | the sample size behind the percentiles |
| `p50` | median: half of the operations were faster than this | the typical, uncontended cost of one operation |
| `p95` | 95% of operations were faster than this; 1 in 20 was slower | the cost users hit regularly; where queue waits and blocked reads appear first |
| `p99` | 99% were faster; 1 in 100 was slower | the tail: an operation that queued behind a long transaction |
| `max` | the slowest single operation | the worst case; usually one read stuck behind a bulk write |
| `wall` | time from the first operation's start to the last operation's end | how long the whole scenario phase took; the number a user feels |
| `ops/s` | `n / wall` | sustained throughput of the queue, all readers or writers combined |

Two patterns to look for:

- **p50 far below p95** (B2 read: 12 ms vs 69 ms) means most operations are cheap and a minority wait
  behind something; the gap is the queue wait. Compare p95 with the p50 of whatever else was running
  (B2 write p50 is 66 ms) to see what they waited for.
- **p50 much larger than `ops/s` implies** (B1: 11 ms latency but 700 ops/s, so a fetch does about
  1.4 ms of work) means the latency is mostly time spent in line, not time spent working; the operations
  are serialized on one queue.

Percentile position is `sorted[min(n - 1, floor(n × q))]`, so with `n = 1` every column shows the same
value (B4 registration and wall are single measurements).

## 2026-09-18-operation-ios-2.7.0

- Machine: Apple M2 Max, 32 GB, macOS 26.2, Xcode 26.6 (17F113)
- Simulator: iPhone 16 (`F6327B69-0673-48AE-9515-C22A4B8CE8CE`); use the id, the name is ambiguous across runtimes
- Operation-iOS 2.7.0, `StackVariant.serial` only
- Scale: `BenchmarkScale.default` (embedded in each JSON)
- Command:

```bash
set -o pipefail && TEST_RUNNER_COREDATA_BENCH_OUT="$PWD/polkadot-appIntegrationTests/CoreData/Baselines/2026-09-18-operation-ios-2.7.0" \
  xcodebuild test -project polkadot-app.xcodeproj -scheme polkadot-appIntegrationTests \
  -destination 'platform=iOS Simulator,id=F6327B69-0673-48AE-9515-C22A4B8CE8CE' \
  -parallel-testing-enabled NO \
  -only-testing:polkadot-appIntegrationTests/CoreDataBenchmarks \
  -only-testing:polkadot-appIntegrationTests/CoreDataTopologySpike 2>&1 | xcbeautify --quiet
```

`-parallel-testing-enabled NO` matters: the scheme allows parallel testing, and with it on xcodebuild ran
every scenario on two simulator clones at once and the timings measured the contention between clones.

### Results

| Scenario | Measure | n | p50 ms | p95 ms | p99 ms | max ms | ops/s |
|---|---|---|---|---|---|---|---|
| B1 concurrent reads | read | 1600 | 11.34 | 11.91 | 12.41 | 15.88 | 699.5 |
| B2 reads under write load | read | 1600 | 12.36 | 68.63 | 82.37 | 85.08 | 308.8 |
| B2 reads under write load | write (100-row batch) | 50 | 65.98 | 76.64 | 84.98 | 84.98 | 15.0 |
| B3 subscription fan-out | save (1 row) | 100 | 61.97 | 64.96 | 80.72 | 80.72 | 16.1 |
| B3 subscription fan-out | save → delivery | 100 | 61.98 | 64.97 | 80.73 | 80.73 | 16.1 |
| B4 recycling replica | voucher save | 500 | 18.04 | 33.19 | 35.73 | 48.87 | 54.0 |
| B4 recycling replica | registration (500 tx) | 1 | 585.61 | | | | |
| B4 recycling replica | status save | 1000 | 1.09 | 2.74 | 5.00 | 9.65 | 759.1 |
| B4 recycling replica | concurrent chat read | 367 | 6.74 | 18.35 | 23.42 | 569.64 | 32.9 |
| B4 recycling replica | wall | 1 | 11164 | | | | |
| S1 nested child reader | read during write | 200 | 0.73 | 238.62 | 285.77 | 291.63 | |
| S1 sibling auto-merge reader | read during write | 200 | 0.52 | 0.96 | 4.71 | 10.58 | |

Counters: B3 `chatMapperCalls` 225,663 for 100 single-row saves (about 2,300 transforms per save: the
unfiltered message subscription re-maps all 2,000 rows plus six per-chat subscriptions re-map 50 each).
B4 `assetMapperCalls` 376,760 for 500 voucher saves (three unfiltered voucher subscriptions each re-map
every voucher on every save, so cost grows quadratically with voucher count); `voucherDeliveries` 501.

### Reading

- B1: eight readers see 11 ms each while the whole queue sustains 700 fetches/s, so a fetch costs
  about 1.4 ms and the other 10 ms is queue wait behind the other seven. Reads are serialized.
- B2: reader p95 (68.6 ms) equals a single write batch (66 ms). A read waits for whatever write is in
  front of it. Hypothesis H2 confirmed.
- B3: a one-row insert takes 62 ms with the production subscription floor live, and the subscriber
  receives its snapshot at the same instant the save completes, because mapping runs inside the
  save's critical section. Hypothesis H1 confirmed.
- B4: 500 coins take 11.2 s end to end, split as voucher saves 9.26 s (83%), registration 0.59 s,
  status saves 1.32 s. A voucher save and a status save are the same write shape (fetch by id, one row,
  commit) and the status save shows that shape costs about 1 ms. The other 17 ms of every voucher save
  is the three unfiltered voucher subscriptions each re-mapping every voucher row, synchronously,
  inside the save: save number i re-maps 3 × i rows, 375,750 transforms over the run, so the phase is
  quadratic in voucher count (1,000 coins would take about 37 s here; in production the multiplier is
  the whole voucher table). The chat reader's worst case (570 ms) is the one fetch that queued behind
  the 586 ms registration transaction. Expected after the split: the loop no longer waits for the
  mapping, so wall time drops toward 2.5 s, while the mapping CPU moves to the observer queue as
  delivery lag until phase 4 replaces re-mapping with diffing.
- S1: a child context's fetch waits for the parent's write (p95 239 ms against a 338 ms write); a
  sibling on the coordinator does not (p95 0.96 ms). Nested readers would not remove the contention.
