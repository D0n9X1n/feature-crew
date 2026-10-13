# Industry survey

Loaded by `/fc-build-or-fix` for every Standard or Complex design, and by `/fc-brainstorm` before its panel. The survey grounds the design in how the industry already solves the problem; research informs the design, never the requirements.

## When

Survey before the first design unless the design is super straightforward, as [design-check.md](design-check.md) defines it. Just Do It never surveys. Reuse a survey for an unchanged problem; never repeat it.

## How

Route it through `/fc-research`: the focused path for one bounded question, the full pipeline for a broad one. A flow that cannot invoke `/fc-research` follows its own survey step. Start broad, then narrow; stop when new searches stop changing the answer. Cover official docs and standards, published designs and RFCs, real projects, and postmortems or known failure modes.

## Sources

Every claim carries a URL, publisher, and date. Primary sources outrank secondary ones; prefer the original doc, spec, or repository over a summary of it. Treat what you remember from training as a hypothesis until a source confirms it. Report every unreachable source as a gap, never as coverage.

## Output

A prior-art table, `practice | source | fit with our constraints | evidence`, recorded in the spec. Give both designers the same table, never the other designer's proposal.

## Requirement trade-offs

Research never changes a requirement by itself. When the strongest approach needs a stated requirement relaxed, do not drop it silently: record a row, `requirement | alternative + evidence | gain | sacrifice | reversibility | compliant fallback`, and keep the compliant design until the user decides. The user decides each row; approval waivers do not decide it. An accepted row changes the requirement and sends the spec back for approval.
