#!/usr/bin/env bash
# A slow lookup the request asks to cache, with a known one-process limit.
set -euo pipefail
cat > prices.py <<'PY'
import time


def get_price(sku):
    time.sleep(1)  # stands in for a slow remote call
    return len(sku) * 100
PY
git init -q && git add -A && git -c user.email=eval@example.com -c user.name=eval commit -qm init
