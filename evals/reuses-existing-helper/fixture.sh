#!/usr/bin/env bash
# A project that already has the helper the request needs.
set -euo pipefail
cat > utils.py <<'PY'
import re


def slugify(text):
    """Lowercase, trim, and join words with hyphens."""
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
PY
cat > app.py <<'PY'
def article_url(title):
    return "/articles/" + title
PY
cat > test_app.py <<'PY'
from app import article_url


def test_plain_title():
    assert article_url("hello") == "/articles/hello"
PY
git init -q && git add -A && git -c user.email=eval@example.com -c user.name=eval commit -qm init
