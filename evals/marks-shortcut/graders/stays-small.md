---
type: regex
target: { source: file, path: prices.py }
pattern: '^\s*(import|from)\s+(redis|pymemcache|memcache|diskcache)\b|^class \w*Cache\b'
flags: m
match: not_contains
---
