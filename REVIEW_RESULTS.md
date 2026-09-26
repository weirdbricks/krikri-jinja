# Review follow-up results (worktree code-review-2026-09-26)

Baseline at start: `7a1c7fc`, 228 examples / 0 failures. Final state: 233
examples / 0 failures (3 new regression specs for the kwargs fix and the parse
cache). Every change was benchmarked with `--release` snippets in `bench/`
(before numbers measured on the unmodified code via `git stash`).

## Implemented

| Finding | Change | Before | After | Speedup |
|---|---|---|---|---|
| CQ-0 | `eval_call` no longer appends `**kwargs` to the shared AST node; builds a local kwargs list (evaluator.cr) + regression specs rendering one parsed node repeatedly | correctness bug (kwargs leak/accumulate across renders) | fixed | n/a |
| PERF-1 | Parsed-template / parsed-expression cache on `Engine` (`parsed_template`, `parsed_expression`), keyed by source + lexer options, capped at 4096 entries; wired into `render_variables`, `evaluate_expression_value`, `load`, `{% include %}`, `{% import %}`. `FileSystemLoader#get_source` now caches file contents with mtime invalidation | template parse 20k×: 170.4 ms (107k parses/s); expression parse 20k×: 89.5 ms (223k parses/s); include-loop render 2k×: 97.2 ms (20,583 renders/s) | cached lookup 20k×: 1.3 ms (~15M/s); expression lookup 20k×: 1.0 ms (~20M/s); include-loop render 2k×: 25.5 ms (78,501 renders/s) | ~75–170× on raw parse; ~3.5× end-to-end on include-heavy renders |
| PERF-2 | Render contexts share the engine's globals hash by reference instead of `@globals.dup` (safe: template writes go through scopes, never globals) | render with 1000 registered globals, 20k×: 164.2 ms (121,780 renders/s) | 14.1 ms (1,416,056 renders/s) | ~11.6× (scales with globals count) |
| PERF-3 | Lexer tag search replaced with a single byte-level forward scan for the earliest of the three openers (no per-tag array, no triple `String#index`) | combined lexer bench below | | |
| PERF-4 | `scan_tag_end` now does allocation-free byte comparisons for the closer (was one substring allocation per character); `read_operator` uses char lookahead instead of two substring slices per operator | combined lexer bench below | | |
| PERF-5 | Newline normalization `\r`→`\n` gsubs and the trailing-newline strip are guarded by cheap `includes?`/`ends_with?` checks (no full-source copies in the common case) | combined lexer bench below | | |
| PERF-3/4/5 combined | lexing a 9,540 B template with 300 tags ×300 passes | ~1,540–1,556 ms (~194 lexes/s) | ~51–67 ms (~4,500–5,800 lexes/s) | ~28× |
| PERF-7 | `percent_encode` uses a memoized 256-entry byte lookup table (plus tiny `extra_safe` byte list) instead of a linear scan of the safe string per byte; hex output without per-byte string churn | 1,880 B string ×5,000: 133.9 ms (37,345 encodes/s) | 56.6 ms (88,358 encodes/s) | ~2.4× |
| PERF-9 | `groupby` groups via a `Hash(String, Int32)` index instead of linearly scanning all accumulated groups per item (O(n·g) → O(n)) | 2,000 items / 50 groups render ×200: ~336–358 ms (~560–596 renders/s) | ~307–312 ms (~640–651 renders/s) | ~1.10× (sort dominates the rest) |
| PERF-10 | `format_float` parses the exponent form by hand instead of regex match + two `sub`s | 8 float values ×200k rounds: 596.8–627.7 ms (~320–335k rounds/s) | 401.7–408.4 ms (~490–498k rounds/s) | ~1.5× |
| PERF-11 | `escape_html` pre-scan is a plain byte check for the five special characters instead of a regex match | clean 100 B ×200k: 26.6–30.2 ms (6.6–7.5M escapes/s); dirty 84 B ×200k: 104.0–126.7 ms | clean: 7.5–8.2 ms (24–27M escapes/s); dirty: 90.7–91.6 ms | ~3.4× clean, ~1.2× dirty |
| PERF-13 (partial) | `Context` memoizes hintless named undefineds and exposes a pre-boxed shared `undefined_any`; subscript/attribute miss paths reuse it instead of allocating `Undefined` + `AnyValue` per miss | miss-heavy render 20k×: ~83–99 ms | ~86–93 ms | no measurable end-to-end gain; kept as a low-risk allocation/GC-pressure reduction |

## Skipped (with reasons)

| Finding | Reason |
|---|---|
| PERF-6 | Attribute access inherently returns a callable; the suggested fix is mostly "capture less / document". The real fix means restructuring the ~250-line `string_method` dispatch and changing allocation patterns across every method-style attribute, high churn for a modest win. Left as-is. |
| PERF-8 | Implemented a single-pass version of `py_format` (validation scan + one scan reused for count and build) and benchmarked it: no measurable improvement (~79–89 ms/20k before vs ~75–89 ms after) because the saved regex pass is offset by collecting MatchData objects. Reverted to the original code. |
| PERF-12 | `unique`'s O(n²) unhashable fallback: a canonical-string key (e.g. JSON) risks false dedup for semantically-equal-but-differently-ordered dicts, changing behavior. Left as-is per the review's own "acceptable for small inputs" assessment. |
| PERF-13 (remainder) | `Parser#peek` EOF sentinel is negligible per the review itself; `random`'s per-call RNG reseeding was left alone because a shared RNG changes the randomness/seeding contract for little gain. |

## Notes / caveats

- The parse cache (PERF-1) is safe only because CQ-0 removed the last AST
  mutation; a regression spec asserts the same parsed object is returned
  repeatedly and renders correctly with different inputs.
- Cache eviction is "clear all at 4096 entries" — simple and bounded; templates
  whose source text changes every call (dynamic content) will not benefit but
  are not penalized beyond one extra hash lookup and key build.
- `FileSystemLoader` cache is keyed by name and invalidated by mtime, so edited
  template files on disk are still picked up.
- Benchmark sources live in `bench/` (`bench_parse.cr`, `bench_include.cr`,
  `bench_globals.cr`, `bench_lexer.cr`, `bench_percent_encode.cr`,
  `bench_py_format.cr`, `bench_groupby.cr`, `bench_value_helpers.cr`,
  `bench_undefined_miss.cr`); run with `crystal run --release bench/<file>.cr`.
- A stray untracked `CODE_REVIEW.md` appeared in the worktree during the pass
  (not created by these changes); it was left untouched.
