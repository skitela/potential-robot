# Family Scenario Tests And Operator Reports

## Purpose

This layer adds two institutional-style controls without affecting runtime
latency:

- family scenario coverage tests
- operator-grade family reports

## Family scenario tests

These tests verify that each trading family retains the expected strategic
coverage.

Examples:

- `FX_MAIN` must keep trend and breakout support plus at least one rejection or reversal path
- `FX_ASIA` must keep asia-specific labels and at least one range-aware member
- `FX_CROSS` must keep trend, breakout, pullback, and at least one range-aware member

Runner:

- `TESTS/RUN_FAMILY_SCENARIO_TESTS.ps1`

Outputs:

- `EVIDENCE/family_scenario_test_report.json`
- `EVIDENCE/family_scenario_test_report.txt`

## Family operator report

This report summarizes the live runtime state per family from Common Files:

- latency
- execution pressure
- learning confidence
- runtime mode
- spread context

Runner:

- `TOOLS/GENERATE_FAMILY_OPERATOR_REPORT.ps1`

Outputs:

- `EVIDENCE/family_operator_report.json`
- `EVIDENCE/family_operator_report.txt`

## Why it matters

This improves:

- execution-quality test evidence
- operator visibility
- family-level tuning discipline
- benchmark credibility against institutional practice
