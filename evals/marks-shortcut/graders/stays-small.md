---
type: regex
target: { source: file, path: prices.py }
pattern: 'redis|memcache|class \w*Cache'
flags: i
match: not_contains
---
