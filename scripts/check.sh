#!/usr/bin/env bash
set -euo pipefail

expected_version="nightly-2026-09-07-14d9829"
roc_bin="${ROC:-roc}"
actual_version="$("$roc_bin" version)"

if [[ "$actual_version" != "Roc compiler version $expected_version" ]]; then
    echo "error: terrocotta requires $expected_version; '$roc_bin' reports '$actual_version'" >&2
    echo "set ROC to the pinned compiler, for example:" >&2
    echo "  ROC=/home/lbw/roc_nightly-linux_x86_64-2026-09-07-14d9829/roc scripts/check.sh" >&2
    exit 1
fi

"$roc_bin" test package/main.roc

for example in \
    examples/counter.roc \
    examples/floating.roc \
    examples/image.roc \
    examples/scrollable.roc \
    examples/text_wrap.roc \
    examples/widgets.roc \
    examples/screwbot/main.roc
do
    "$roc_bin" check "$example"
done
