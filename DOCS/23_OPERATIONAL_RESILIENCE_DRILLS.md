# Operational Resilience Drills

## Purpose

This layer documents and verifies the minimum operator-grade resilience checks
for `MAKRO_I_MIKRO_BOT`.

It is intentionally lightweight and evidence-based.

## What is drilled

1. Runtime state continuity
- every symbol should persist `runtime_state.csv`

2. Kill-switch continuity
- every symbol should have a token directory in Common Files

3. Recovery artifacts
- package manifest
- handoff manifest
- backup ZIP

4. Post-restart expert recovery
- MT5 log should show successful `MicroBot_*` loads after restart

5. Runtime summary continuity
- every symbol should expose `execution_summary.json`

## Runner

- `TOOLS/RUN_RESILIENCE_DRILLS.ps1`

## Outputs

- `EVIDENCE/resilience_drill_report.json`
- `EVIDENCE/resilience_drill_report.txt`

## Why it matters

This improves:

- operational resilience
- audit trail
- recovery evidence
- institutional benchmark credibility

without adding load to runtime decision flow.
