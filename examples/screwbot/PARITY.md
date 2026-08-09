# Screwbot parity and benchmark runbook

This runbook keeps source-level assertions separate from GPU image comparison.
It records no benchmark results.

## Automated source checks

Run:

```sh
roc test examples/screwbot/main.roc
```

The `expect`s in `main.roc` cover the deterministic scene contract:

- the default arm and target at `0ns` and `2_500_000_000ns`;
- an unreachable target at `{ x: 500, y: 0, z: 0 }`;
- target UV, reachability, and normalized error values;
- the compact/wide boundary at widths `999` and `1000`.

`Text.Metrics` has its own platform-level pure and headless tests for the
proportional `iii`/`WWW`, multibyte, newline, NUL, and font-lifetime rules. The
Screwbot renderer receives that prepared scalar snapshot; it does not implement
another text measurement algorithm.

## Native visual fixture matrix

Native captures require a GPU-backed, fixed-step recording. Do not use the
host's `--headless` mode: it intentionally renders no pixels. Use the default
camera and arm `{ upper_length: 132, fore_length: 118, elbow_up: False }`.

| Fixture | Window | Timestamp | Target | Required observation |
| --- | --- | --- | --- | --- |
| reachable-start | `1280 × 900` | `0ns` | `{145, 145, 60}` | Reachable floor ring and robot status |
| reachable-later | `1280 × 900` | `2_500_000_000ns` | `{145, 145, 60}` | Same geometry; time-driven shader phase changes |
| unreachable | `1280 × 900` | `2_500_000_000ns` | `{500, 0, 0}` | Raw out-of-range floor UV and error status |
| compact | `999 × 900` | `0ns` | `{145, 145, 60}` | Stacked compact workspace/sidebar layout |
| wide | `1000 × 900` | `0ns` | `{145, 145, 60}` | Side-by-side wide workspace/sidebar layout |
| proportional-text | `1280 × 900` | `0ns` | `{145, 145, 60}` | `iii`, `WWW`, `é`, and a newline specimen using the loaded UI font |

The capture fixture must script those model values and window dimensions before
each frame. The text specimen is a visual fixture, not a second measurement
implementation: it verifies that layout and drawing both consume the same
prepared font metrics.

For each row, capture matching images from the pre-change and candidate native
builds on the same OS, GPU, driver, framebuffer scale, and fixed-step cadence.
Hide the system pointer. Compare linearized RGBA images after removing capture
metadata. Accept at most a two-level channel difference for 99.9% of pixels and
an eight-level difference for the remaining edge pixels; any larger difference,
changed text wrapping/baseline, or changed compact/wide arrangement fails the
fixture. Cross-driver captures are separate baselines, not inputs to this
comparison.

## Future native benchmark record

Only collect a performance record after the matching visual fixture passes.
Warm up the same fixed-step scenario, then record a steady-state sample with
separate update and render trace ranges. Each sample must include:

- update duration and render duration;
- retained command count and retained command payload bytes/capacity;
- metric-snapshot bytes retained by layout callbacks;
- allocations and reallocations in update and render when allocator probes are
  available;
- the number of scene uniform writes, including the two resolution writes, two
  blur-direction writes, and the bloom sampler binding.

The current public API exposes none of the timing, command-byte, or allocator
probes required to publish those values. This repository therefore contains no
native timing, allocation, command-count, or comparative-performance result.
