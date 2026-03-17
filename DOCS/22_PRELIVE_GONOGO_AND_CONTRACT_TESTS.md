# Prelive Go-NoGo And Contract Tests

## Purpose

This layer adds lightweight engineering governance without affecting runtime
latency.

It gives the project:

- a repeatable contract-test pack
- a formal `prelive` decision gate
- evidence for deployment, benchmark, and operator review

## Contract tests

The contract suite checks stable engineering boundaries:

- project layout
- symbol-policy consistency
- family-policy bounds
- family-reference validity
- preset safety
- learning / anti-overfit policy

Runner:

- `TESTS/RUN_CONTRACT_TESTS.ps1`

Outputs:

- `EVIDENCE/contract_test_report.json`
- `EVIDENCE/contract_test_report.txt`

## Prelive gate

The prelive gate is a thin final decision layer.

It requires:

- contract tests to pass
- deployment readiness to pass
- transfer package validation to pass

Runner:

- `TOOLS/VALIDATE_PRELIVE_GONOGO.ps1`

Outputs:

- `EVIDENCE/prelive_gonogo_report.json`
- `EVIDENCE/prelive_gonogo_report.txt`

## Why this matters

This improves:

- change governance
- operational resilience
- audit trail
- institutional benchmark credibility

without adding measurable load to:

- `OnTick`
- `OnTimer`
- execution hot path
