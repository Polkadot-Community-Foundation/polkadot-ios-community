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
set -o pipefail && TEST_RUNNER_COREDATA_BENCH_OUT="$PWD/docs/benchmarks/coredata/2026-09-18-operation-ios-2.7.0" \
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

## 2026-09-18-operation-ios-3.0.0-653010d

Same machine, simulator, scale and command as the 2.7.0 run (output directory changed accordingly). Library
pinned to commit `653010d` (the 3.0.0 change set); every scenario ran in `serial`, `concurrent2` and
`concurrent4`. Cells are p50 / p95 ms unless marked.

| Measure | 2.7.0 serial | 3.0.0 serial | 3.0.0 concurrent2 | 3.0.0 concurrent4 |
|---|---|---|---|---|
| B1 read | 11.3 / 11.9 | 11.5 / 12.1 | 7.9 / 8.4 | 6.8 / 9.2 |
| B2 read (writer active) | 12.4 / 68.6 | 11.8 / 60.9 | 8.5 / 9.9 | 10.1 / 11.0 |
| B2 write (100-row batch) | 66.0 / 76.6 | 59.6 / 67.8 | 50.2 / 53.9 | 61.5 / 64.4 |
| B3 save (1 row, 20 subscriptions) | 62.0 / 65.0 | 63.1 / 69.0 | 1.7 / 2.6 | 1.7 / 2.2 |
| B3 save → delivery | 62.0 / 65.0 | 63.1 / 69.0 | 65.1 / 69.6 | 65.2 / 68.8 |
| B3 chatMapperCalls (total) | 225,663 | 225,663 | 225,432 | 225,432 |
| B4 voucher save | 18.0 / 33.2 | 17.0 / 32.5 | 1.0 / 1.3 | 1.0 / 1.2 |
| B4 registration (500 tx, 1 tx) | 586 | 588 | 623 | 613 |
| B4 status save | 1.1 / 2.7 | 1.1 / 2.6 | 1.1 / 1.4 | 1.1 / 1.8 |
| B4 concurrent chat read | 6.7 / 18.4 | 7.3 / 19.7 | 2.3 / 2.7 | 2.3 / 2.5 |
| B4 wall (ms) | 11,164 | 10,608 | 2,369 | 2,361 |
| B4 assetMapperCalls (total) | 376,760 | 376,760 | 100,894 | 100,755 |
| B4 voucher deliveries | 501 | 501 | 248 | 247 |
| S1 nested-child read (during write) | 0.7 / 238.6 | 0.9 / 235.2 | | |
| S1 sibling read (during write) | 0.5 / 1.0 | 0.5 / 1.0 | | |

### Reading

- **`.serial` is 2.7.0.** Every 3.0.0-serial number sits within run-to-run noise of the 2.7.0 baseline, so the
  compatibility mode carries no regression and the extension's behaviour is unchanged.
- **Reads no longer wait for writes (H2).** B2 reader p95 goes from one write batch (68.6 ms) to 9.9 ms; the
  B4 chat reader's p95 from 18.4 ms to 2.7 ms. B1 improves less (11.3 → 7.9 ms p50) because uncontended reads
  are bounded by the shared coordinator and store, not by the queue; that residual is the tier-2 question and
  is not worth a second coordinator at these numbers.
- **Saves stop paying for subscribers (H1).** A one-row insert with the 20-subscription floor drops from 62 ms
  to 1.7 ms; a voucher save from 18 ms to 1.0 ms. The recycling replica finishes in 2.37 s instead of 11.2 s,
  the 4.7× the phase 0 README predicted.
- **The mapping cost moved, it did not shrink.** B3 save-to-delivery stays at ~65 ms and total mapper calls
  are unchanged: the same re-mapping now runs on the observer queue, after the save has returned. In B4 the
  observer's asynchronous merge coalesced consecutive saves into half as many deliveries (501 → 248) and a
  quarter of the transforms (377k → 101k), because mapping is slower than the writer. That is a side effect,
  not a design: delivery lag under sustained writes is what phase 4 (diff instead of re-map) addresses.
- **2 readers vs 4.** Indistinguishable everywhere except B1 (6.8 vs 7.9 ms p50, with a worse p95). The
  writer under B2 is slower with 4 readers competing for the coordinator (61.5 vs 50.2 ms). Stay at 2.
- **No reader pool needed.** Per-read context creation does not show up: B4 reads average 2.3 ms end to end.

### Decisions (phase 3)

- Reader concurrency stays at 2 (`CoreDataConcurrencyPolicy.appReaderConcurrency`).
- No pooled readers, no second coordinator.
- Phase 4 (snapshot subscriber diffing) is justified by B3 delivery lag and B4 transform counts, but it is a
  latency-of-delivery improvement, not a throughput one; the throughput goal of issue #156 is met here.

## 2026-09-18-operation-ios-3.0.0-653010d-diff

Same library commit, same machine, scale and command; the only change is phase 4 of the app:
`CoreDataSnapshotSubscriber` invalidates the cached model of each row the fetched results controller
reports and maps rows on demand at delivery, keyed by permanent object ID. Cells are p50 / p95 ms.

| Measure | 3.0.0 concurrent2 | 3.0.0-diff serial | 3.0.0-diff concurrent2 | 3.0.0-diff concurrent4 |
|---|---|---|---|---|
| B3 save (1 row, 20 subscriptions) | 1.7 / 2.6 | 3.1 / 4.3 | 1.3 / 2.8 | 1.3 / 2.6 |
| B3 save → delivery | 65.1 / 69.6 | 3.1 / 4.3 | 2.5 / 4.0 | 2.4 / 3.7 |
| B3 chatMapperCalls (total) | 225,432 | 3,163 | 3,062 | 3,062 |
| B4 voucher save | 1.0 / 1.3 | 1.6 / 3.4 | 1.1 / 1.3 | 1.1 / 1.5 |
| B4 concurrent chat read | 2.3 / 2.7 | 2.5 / 5.1 | 2.2 / 2.4 | 2.2 / 2.5 |
| B4 wall (ms) | 2,369 | 2,750 | 2,336 | 2,375 |
| B4 assetMapperCalls (total) | 100,894 | 4,007 | 2,510 | 2,510 |
| B4 voucher deliveries | 248 | 500 | 489 | 490 |
| B1 read | 7.9 / 8.4 | | 8.3 / 10.0 | |
| B2 read (writer active) | 8.5 / 9.9 | | 8.9 / 10.4 | |

### Reading

- **Delivery latency is now the save latency.** B3 save → delivery drops from 65 ms to 2.5 ms; the
  subscriber's cost per change is one map per changed row plus dictionary lookups. B1 and B2 are unchanged
  within noise, as expected: they have no subscriptions.
- **Mapper calls are two orders of magnitude lower.** B3: 3,062 for 100 saves. That is the initial map of
  2,300 rows, then per save: the new row in the unfiltered and in the chat-filtered message subscription,
  the updated chat row in the three chat subscriptions, and the new row mapped once more when its object ID
  turns permanent (see below). B4: 2,510 for 500 voucher saves against 100,894 before.
- **Deliveries went back up** (B4 vouchers 248 → 489). With mapping this cheap the observer no longer falls
  behind the writer, so consecutive saves are no longer coalesced by accident; every save is delivered.
  B4 wall time did not move (2.34 s vs 2.37 s), so per-delivery work is not a cost worth debouncing: D2 stands.
- **Temporary object IDs.** With the controller on the writer (`.serial`), an inserted row is reported during
  the save under a temporary ID and becomes permanent afterwards. The first phase 4 build cached rows by
  that ID and every later snapshot missed them (B3 serial hung waiting for n+2 rows). The shipped subscriber
  never caches a temporary ID and maps such rows again at the next delivery: one extra transform per insert,
  visible as B4 serial's 4,007 against concurrent's 2,510. In concurrent mode the observer only sees
  permanent IDs.
- **Serial is still slower per save** (B3 3.1 ms vs 1.3 ms) because mapping runs inside the writer's save
  there; it is the extension's mode and has no subscriptions in production.

### Decisions (phase 4)

- No delivery coalescing (D2 confirmed by numbers).
- Related-object changes are not tracked (D1); derived-state subscriptions rely on parent-row touches.
