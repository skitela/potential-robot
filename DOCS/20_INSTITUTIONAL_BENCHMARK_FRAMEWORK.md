# Institutional Benchmark Framework V1

## Purpose

This framework replaces the legacy `OANDA_MT5_SYSTEM` benchmark for evaluating
`C:\MAKRO_I_MIKRO_BOT`.

It is not based on the legacy hybrid architecture. It is anchored in external,
recognizable institutional references used for low-latency trading systems,
algorithmic controls, operational resilience, and model governance.

## External anchors

1. `STAC-T1`
Purpose:
- tick-to-trade benchmarking for low-latency trading systems.

Source:
- https://docs.stacresearch.com/t1

2. `ESMA MiFID II Article 17`
Purpose:
- algorithmic trading systems, controls, testing, record keeping.

Source:
- https://www.esma.europa.eu/publications-and-data/interactive-single-rulebook/mifid-ii/article-17-algorithmic-trading

3. `MiFID II RTS 25`
Purpose:
- UTC traceability, timestamp discipline, reconstruction of event sequence.

Source:
- https://ec.europa.eu/finance/securities/docs/isd/mifid/rts/160607-rts-25_en.pdf

4. `SEC Rule 15c3-5`
Purpose:
- market access controls, documented pre-trade risk controls, recurring review.

Sources:
- https://www.sec.gov/file/small-entity-compliance-guide-27
- https://www.sec.gov/rules-regulations/staff-guidance/trading-markets-frequently-asked-questions/divisionsmarketregfaq-0

5. `DORA`
Purpose:
- ICT risk management, resilience, incident handling, operational testing.

Source:
- https://www.eba.europa.eu/activities/direct-supervision-and-oversight/digital-operational-resilience-act

6. `FIX Trading Community Algorithmic Trading WG`
Purpose:
- industry reference point for algorithm testing and disorder testing workflows.

Source:
- https://www.fixtrading.org/groups/algotrading/

7. `NIST AI RMF 1.0`
Purpose:
- AI/model governance, trustworthy AI, control and evaluation of learning systems.

Source:
- https://www.nist.gov/publications/artificial-intelligence-risk-management-framework-ai-rmf-10

8. `Federal Reserve SR 11-7`
Purpose:
- model risk management, validation, documentation, back-testing discipline.

Source:
- https://www.federalreserve.gov/supervisionreg/srletters/sr1107.htm

## Benchmark structure

Scale:
- `0-100`

Target bands:
- `85-100`: institutional strong
- `75-84.9`: institutional acceptable / production-grade
- `60-74.9`: advanced RnD / controlled pre-production
- `45-59.9`: promising but incomplete
- `<45`: structurally incomplete for institutional comparison

## Categories and weights

1. `Tick-to-Trade and Time Discipline` - `15%`
Measures:
- local decision latency
- tail latency stability
- timestamp consistency
- UTC traceability readiness
- event sequencing discipline

Anchors:
- `STAC-T1`
- `RTS 25`

2. `Pre-Trade Risk and Capital Protection` - `15%`
Measures:
- pre-trade vetoes
- kill-switch
- margin and spread protections
- daily/session limits
- risk sizing discipline

Anchors:
- `ESMA Article 17`
- `SEC 15c3-5`

3. `Operational Resilience` - `12%`
Measures:
- restart safety
- incident tolerance
- deploy/rollback readiness
- token/control continuity
- recovery path

Anchors:
- `DORA`

4. `Audit Trail and Traceability` - `10%`
Measures:
- time-sequenced event history
- order/deal traceability
- ability to reconstruct actions
- file/document evidence chain

Anchors:
- `RTS 25`
- `ESMA Article 17`

5. `Execution Quality and Algo Testing` - `10%`
Measures:
- precheck quality
- execution-quality guards
- slippage/retry tracking
- explicit paper/live separation
- scenario-based algorithm testability

Anchors:
- `STAC-T1`
- `FIX Algorithmic Trading WG`

6. `Change, Deployment, and Test Governance` - `10%`
Measures:
- build reproducibility
- rollout preflight
- transfer validation
- family propagation control
- regression safety

Anchors:
- `DORA`
- `FIX Algorithmic Trading WG`

7. `Learning / Model Risk Governance` - `12%`
Measures:
- learning scope control
- anti-overfit discipline
- validation of adaptive mechanisms
- documented update boundaries
- model-risk transparency

Anchors:
- `NIST AI RMF`
- `SR 11-7`

8. `Monitoring and Incident Diagnostics` - `8%`
Measures:
- latency telemetry
- decision logs
- incident journaling
- execution summaries
- operator-facing evidence

Anchors:
- `DORA`
- `ESMA Article 17`

9. `Market Data Integrity` - `4%`
Measures:
- tick freshness
- spread anomaly handling
- quote tolerance
- symbol-specific market state discipline

Anchors:
- `RTS 25`
- market-data portions of institutional low-latency practice

10. `Scalability and Segregation of Control` - `4%`
Measures:
- one-bot-per-symbol isolation
- thin-core / thick-microbot separation
- family references and bounded propagation
- MT5-only deployability

Anchors:
- institutional architecture practice
- operational implications of `DORA` and `Article 17`

## Scoring method

For each category:
- assign `0-10`
- multiply by category weight
- divide sum by `10`

Formula:

`score_100 = sum(category_score_0_10 * weight_pct) / 10`

## Preliminary reading of MAKRO_I_MIKRO_BOT

This is a first-pass institutional reading, not a final certification.

### Category scores

1. `Tick-to-Trade and Time Discipline`: `8.5/10`
Reason:
- very low measured local latency
- strong per-symbol runtime isolation
- timestamp traceability exists
- not yet backed by formal UTC compliance evidence in the `RTS 25` sense

2. `Pre-Trade Risk and Capital Protection`: `6.5/10`
Reason:
- real protections exist in code and runtime
- paper bypass lowers strictness intentionally for learning mode
- still needs stronger formal risk policy and proof pack

3. `Operational Resilience`: `5.0/10`
Reason:
- deploy tooling and handoff are good
- local restart path is good
- still missing stronger formal resilience testing and richer recovery evidence

4. `Audit Trail and Traceability`: `6.0/10`
Reason:
- strong event logs and transaction logs
- better than old score implied
- still not yet shaped as a full institutional reconstruction package

5. `Execution Quality and Algo Testing`: `6.5/10`
Reason:
- execution precheck, telemetry, paper/live separation, execution quality guard
- needs richer scenario test suite and benchmark-style algorithm test evidence

6. `Change, Deployment, and Test Governance`: `5.5/10`
Reason:
- rollout and packaging are strong
- family propagation model is strong
- missing stronger automated test coverage and formal regression suite

7. `Learning / Model Risk Governance`: `3.5/10`
Reason:
- lightweight adaptive learning exists
- governance, validation, anti-overfit, and documentation are not yet mature enough

8. `Monitoring and Incident Diagnostics`: `6.0/10`
Reason:
- runtime visibility is real and useful
- needs a more formal operator-grade monitoring pack

9. `Market Data Integrity`: `5.5/10`
Reason:
- tick freshness and spread guards exist
- still needs stronger evidence around data-quality controls and time discipline

10. `Scalability and Segregation of Control`: `7.0/10`
Reason:
- architecture is strong
- family control is strong
- one-bot-per-symbol is clean
- still needs more formal proof pack to score higher institutionally

### Preliminary total

Weighted score:
- `60.5 / 100`

Interpretation:
- `advanced RnD / controlled pre-production`

This is materially more realistic for the current system than the legacy
hybrid-oriented benchmark result.

## What would move the score toward 75-85 without harming latency

1. Formal `prelive/go-no-go` evidence for this new project
2. Real regression tests and a `tests` package
3. Stronger model-risk and anti-overfit documentation
4. UTC/timestamp traceability evidence aligned to `RTS 25`
5. More formal incident/recovery drills and reports
6. Structured scenario testing for algorithms per family

## Progress update - 2026-03-12

The project now has a first explicit `learning / anti-overfit` contract:

- minimum sample gates before adaptive updates
- confidence-weighted impact of learning on risk
- explicit decay of learning state toward neutral
- persisted counters for sample count, wins, and losses

This directly strengthens:

- learning / model risk governance
- pre-trade risk and capital protection
- audit trail and traceability
