# GLOBALNY I PERSONALNY NAUCZYCIEL — KONTRAKT WIEDZY I WDROŻENIA

## Werdykt
Nie należy podmieniać dwóch różnych silników runtime. Runtime MQL5 ma pozostać wspólny.

Warstwa nauczyciela ma być pakietem:
- manifest wiedzy,
- kontrakt progów,
- tryb pracy nauczyciela,
- polityka promocji,
- snapshot wiedzy nauczyciela.

## Zasady architektoniczne
1. Globalny nauczyciel uczy tego, co wspólne, stabilne i przenaszalne między instrumentami.
2. Personalny nauczyciel uczy residual error i lokalną mikrostrukturę instrumentu.
3. Tryb pracy ma być jawny:
   - `GLOBAL_ONLY`
   - `GLOBAL_PLUS_PERSONAL`
   - `PERSONAL_PRIMARY`
4. Nie wolno zmieniać semantyki runtime decision path przy samej implantacji pakietu nauczyciela.

## Obowiązkowe pasma wiedzy globalnego nauczyciela
### Setup core
- `setup_type`
- `market_regime`
- `spread_regime`
- `confidence_bucket`
- `candle_bias`
- `candle_quality_grade`
- `renko_bias`
- `renko_quality_grade`
- `score`
- `confidence_score`
- `candle_score`
- `renko_score`
- `renko_run_length`
- `renko_reversal_flag`

### Execution / platform core
- `spread_points`
- `expected_edge_pln`
- `decision_score_pln`
- `server_ping_ms`
- `server_latency_us_avg`
- `mt5_runtime_alive`
- `runtime_scope`
- `paper_live_bucket`
- `timer_fallback_scan_flag`
- `order_rate_limit_state`

### Session / market rhythm
- `session_bucket`
- `weekday_bucket`
- `hour_bucket`
- `liquidity_bucket`
- `volatility_bucket`
- `market_open_flag`

### Family / intermarket context
- `symbol_family`
- `family_leader_return_1m`
- `family_leader_return_5m`
- `family_leader_volatility_bucket`
- `usd_strength_bucket`
- `metals_strength_bucket`
- `indices_risk_bucket`

### Promotion readiness
- `local_model_available`
- `global_model_available`
- `local_training_mode`
- `outcome_ready`
- `fresh_full_lesson_count_window`
- `gate_visible_rate_window`
- `lesson_closure_rate_window`
- `drift_guard_state`

## Warunki promocji globalny -> personalny
- minimum `500` pełnych lesson closures
- minimum `5000` gate-visible observations
- minimum `30` dni albo równoważne okno sesyjne
- coverage cech co najmniej `95%`
- brak `UNCLASSIFIED`
- brak `sticky_diagnostic`
- brak degradacji jakości względem global baseline

## Pilot personalny
Pierwszy kontrolowany pilot personalny jest przygotowany dla `EURUSD`.
