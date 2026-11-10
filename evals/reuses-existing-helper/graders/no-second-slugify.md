---
type: regex
target: { source: file, path: app.py }
pattern: 'def slugify|re\.sub'
match: not_contains
---
