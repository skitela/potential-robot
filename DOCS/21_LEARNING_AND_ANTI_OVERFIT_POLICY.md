# Learning And Anti-Overfit Policy

## Purpose

This policy formalizes the lightweight adaptive layer used by all `MicroBot_*`
experts. It is designed to improve risk discipline without adding measurable
load to the hot path.

## Design rules

1. Learning is updated only from closed deals.
2. No heavy history scan is performed in `OnTick`.
3. Single outcomes cannot immediately move risk aggressively.
4. Adaptive risk stays near neutral until a minimum sample is reached.
5. Older influence decays toward neutral on every closed-deal update.

## Runtime fields

- `learning_sample_count`
- `learning_win_count`
- `learning_loss_count`
- `learning_bias`
- `learning_confidence`
- `adaptive_risk_scale`

## Anti-overfit controls

### Minimum sample gates

- bias updates require at least `3` closed deals
- adaptive risk updates require at least `5` closed deals

### Confidence model

- confidence grows from `0.0` to `1.0`
- full confidence is reached only after `12` closed deals
- before that point, every learning step is damped

### Decay to neutral

On every closed-deal update:

- `learning_bias` decays toward `0`
- `adaptive_risk_scale` decays toward `1.0`

This limits drift and prevents stale history from dominating current behavior.

### Step asymmetry

- wins increase bias/risk more slowly
- losses reduce bias/risk faster

This favors capital protection over aggressive amplification.

## Operational intent

This is not a predictive ML layer. It is a bounded adaptive memory:

- fast enough for `MT5-only`
- auditable
- stable across restarts
- safe for family propagation

## Benchmark impact

This policy primarily strengthens:

- learning / model-risk governance
- pre-trade risk and capital protection
- audit trail and traceability
