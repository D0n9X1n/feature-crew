---
description: The writer reuses the slugify helper the project already has instead of writing a new one.
tags: [smallest-change]
max_turns: 25
allowed_tools: [Read, Glob, Grep, Skill, Edit, Write]
---

Article URLs in app.py break when the title has spaces or capitals. Make article_url produce clean URL slugs. Just fix it, no questions.
