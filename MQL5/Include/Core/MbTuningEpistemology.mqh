#ifndef MB_TUNING_EPISTEMOLOGY_INCLUDED
#define MB_TUNING_EPISTEMOLOGY_INCLUDED

#include "MbExecutionCommon.mqh"
#include "MbTuningStorage.mqh"
#include "MbTuningGuardMatrix.mqh"
#include "MbCandidateArbitration.mqh"

bool MbIsPaperConversionBlockedReason(const string raw_reason_code)
  {
   return (StringFind(raw_reason_code,"PAPER_CONVERSION_BLOCKED",0) == 0);
  }

bool MbIsForefieldDirtyReason(const string raw_reason_code)
  {
   return (
      StringFind(raw_reason_code,"FOREFIELD_DIRTY",0) == 0 ||
      raw_reason_code == "DATASET_NOISY" ||
      raw_reason_code == "CANDIDATES_NOISY"
   );
  }

bool MbIsExpectedPaperMarketClosure(const MbMarketSnapshot &market)
  {
   // In laptop/paper research we still want the bots and tuning loop alive
   // when the broker market is closed. A stale tick after a normal weekend
   // close is not the same thing as execution infrastructure being broken.
   return (
      market.paper_runtime_override_active &&
      market.terminal_connected &&
      !market.term_trade_allowed &&
      !market.raw_trade_permissions_ok &&
      market.tick_age_ms >= 15000
   );
  }

void MbResolveTrustThresholds(
   const string symbol,
   double &out_min_conversion_ratio,
   int &out_min_conversion_candidates,
   double &out_max_dirty_ratio
)
  {
   string family = "";
   MbResolveTuningGuardFamily(symbol,family);

   out_min_conversion_ratio = 0.08;
   out_min_conversion_candidates = 10;
   out_max_dirty_ratio = 0.42;

   if(family == "FX_MAIN")
     {
      out_min_conversion_ratio = 0.06;
      out_min_conversion_candidates = 8;
      out_max_dirty_ratio = 0.46;
      return;
     }
   if(family == "FX_ASIA")
     {
      out_min_conversion_ratio = 0.04;
      out_min_conversion_candidates = 6;
      out_max_dirty_ratio = 0.47;
      return;
     }
   if(family == "FX_CROSS")
     {
      out_min_conversion_ratio = 0.05;
      out_min_conversion_candidates = 10;
      out_max_dirty_ratio = 0.44;
      return;
     }
   if(family == "METALS_SPOT_PM")
     {
      out_min_conversion_ratio = 0.05;
      out_min_conversion_candidates = 8;
      out_max_dirty_ratio = 0.46;
      return;
     }
   if(family == "METALS_FUTURES")
     {
      out_min_conversion_ratio = 0.03;
      out_min_conversion_candidates = 6;
      out_max_dirty_ratio = 0.50;
      return;
     }
   if(family == "INDEX_EU" || family == "INDEX_US")
     {
      out_min_conversion_ratio = 0.05;
      out_min_conversion_candidates = 6;
      out_max_dirty_ratio = 0.40;
      return;
     }
  }

string MbResolvePaperConversionBlockedReasonCode(
   const int candidate_risk_block_rows,
   const int decision_risk_contract_block_rows,
   const int decision_portfolio_heat_block_rows,
   const int decision_rate_guard_block_rows,
   const double conversion_ratio,
   const double min_conversion_ratio
)
  {
   int risk_pressure = MathMax(candidate_risk_block_rows,decision_risk_contract_block_rows);
   if(decision_portfolio_heat_block_rows > 0 &&
      decision_portfolio_heat_block_rows >= MathMax(3,risk_pressure))
      return "PAPER_CONVERSION_BLOCKED_BY_PORTFOLIO_HEAT";

   if(decision_rate_guard_block_rows > 0 &&
      decision_rate_guard_block_rows >= MathMax(3,risk_pressure))
      return "PAPER_CONVERSION_BLOCKED_BY_RATE_GUARD";

   if(risk_pressure > 0)
      return "PAPER_CONVERSION_BLOCKED_BY_RISK_CONTRACT";

   if(conversion_ratio < min_conversion_ratio)
      return "PAPER_CONVERSION_BLOCKED_BY_LOW_RATIO";

   return "PAPER_CONVERSION_BLOCKED_BY_UNKNOWN";
  }

string MbResolveForefieldDirtyReasonCode(
   const int total_rows,
   const int none_unknown_rows,
   const int candidate_rows,
   const int candidate_invalid_rows,
   const int candidate_dirty_rows,
   const int candidate_dirty_candle_rows,
   const int candidate_dirty_renko_rows,
   const int candidate_dirty_hybrid_rows,
   const int candidate_dirty_spread_rows,
   const double dirty_ratio,
   const double max_dirty_ratio
)
  {
   if(total_rows > 0 && none_unknown_rows > (total_rows / 3))
      return "FOREFIELD_DIRTY_BY_OBSERVATION_GAPS";

   if(candidate_rows > 0 && candidate_invalid_rows > (candidate_rows / 3))
      return "FOREFIELD_DIRTY_BY_CANDIDATE_INVALID";

   if(candidate_dirty_spread_rows > 0 &&
      (
         candidate_dirty_spread_rows >= candidate_dirty_hybrid_rows &&
         candidate_dirty_spread_rows >= candidate_dirty_candle_rows &&
         candidate_dirty_spread_rows >= candidate_dirty_renko_rows
      ))
      return "FOREFIELD_DIRTY_BY_SPREAD_DISTORTION";

   if(candidate_dirty_rows > 0 &&
      dirty_ratio >= max_dirty_ratio &&
      candidate_dirty_spread_rows >= MathMax(3,candidate_dirty_rows / 4))
      return "FOREFIELD_DIRTY_BY_SPREAD_DISTORTION";

   if(candidate_dirty_hybrid_rows > 0 &&
      candidate_dirty_hybrid_rows >= candidate_dirty_candle_rows &&
      candidate_dirty_hybrid_rows >= candidate_dirty_renko_rows)
      return "FOREFIELD_DIRTY_BY_LOW_CONFIDENCE_HYBRID";

   if(candidate_dirty_candle_rows > 0 &&
      candidate_dirty_candle_rows >= candidate_dirty_renko_rows)
      return "FOREFIELD_DIRTY_BY_LOW_CONFIDENCE_CANDLE";

   if(candidate_dirty_renko_rows > 0)
      return "FOREFIELD_DIRTY_BY_LOW_CONFIDENCE_RENKO";

   if(candidate_dirty_rows > 0 && dirty_ratio >= max_dirty_ratio)
      return "FOREFIELD_DIRTY_BY_DIRTY_RATIO";

   return "FOREFIELD_DIRTY_BY_UNKNOWN";
  }

void MbNormalizeReasonTriple(const string raw_reason_code,MbReasonTriple &out)
  {
   out.domain = "MODE";
   out.reason_class = "STATUS";
   out.reason_code = raw_reason_code;

   if(raw_reason_code == "" || raw_reason_code == "UNASSESSED")
      return;

   if(
      raw_reason_code == "TRUSTED" ||
      raw_reason_code == "LOW_SAMPLE" ||
      raw_reason_code == "OBSERVATIONS_MISSING" ||
      raw_reason_code == "BUCKETS_EMPTY" ||
      MbIsForefieldDirtyReason(raw_reason_code)
   )
     {
      out.domain = "DATA";
      out.reason_class = "TRUST";
      return;
     }

   if(MbIsPaperConversionBlockedReason(raw_reason_code))
     {
      out.domain = "RISK";
      out.reason_class = "CONTRACT";
      return;
     }

   if(raw_reason_code == "CENTRAL_STATE_STALE")
     {
      out.domain = "CENTRAL";
      out.reason_class = "STALENESS";
      return;
     }

   if(
      raw_reason_code == "PORTFOLIO_HEAT_BLOCK" ||
      raw_reason_code == "FREEZE_FAMILY" ||
      raw_reason_code == "FREEZE_FLEET" ||
      raw_reason_code == "ARBITRATION_GROUP_UNKNOWN"
   )
     {
      out.domain = "CENTRAL";
      out.reason_class = "GATE";
      return;
     }

   if(
      raw_reason_code == "INFRASTRUCTURE_WEAK" ||
      raw_reason_code == "TERMINAL_DISCONNECTED" ||
      raw_reason_code == "PING_TOO_HIGH"
   )
     {
      out.domain = "INFRA";
      out.reason_class = "HEALTH";
      return;
     }

   if(
      raw_reason_code == "BROKER_PRICE_RATE_LIMIT" ||
      raw_reason_code == "BROKER_ORDER_RATE_LIMIT" ||
      raw_reason_code == "TICK_STALE" ||
      raw_reason_code == "RETRY_SPIKE" ||
      raw_reason_code == "SLIPPAGE_SPIKE" ||
      raw_reason_code == "EXECUTION_PRESSURE_HIGH"
   )
     {
      out.domain = "EXECUTION";
      out.reason_class = "DEGRADATION";
      return;
     }

   if(StringFind(raw_reason_code,"SPREAD_",0) == 0 || raw_reason_code == "NON_REPRESENTATIVE_COST")
     {
      out.domain = "COST";
      out.reason_class = "PRESSURE";
      return;
     }

   if(
      raw_reason_code == "FILTER_BREAKOUT_CANDLE" ||
      raw_reason_code == "FILTER_BREAKOUT_RENKO" ||
      raw_reason_code == "FILTER_TREND_CANDLE" ||
      raw_reason_code == "FILTER_RANGE_CANDLE" ||
      raw_reason_code == "FILTER_RANGE_RENKO" ||
      raw_reason_code == "FILTER_REJECTION_SUPPORT" ||
      raw_reason_code == "FLOOR_RANGE_CONFIDENCE" ||
      raw_reason_code == "REBALANCE"
   )
     {
      out.domain = "SIGNAL";
      out.reason_class = "ADAPTATION";
      return;
     }
  }

void MbEvaluateExecutionQualityState(
   const MbRuntimeState &state,
   const MbMarketSnapshot &market,
   MbExecutionQualityState &out
)
  {
   out.state = "GOOD";
   out.reason_code = "EXECUTION_HEALTHY";
   out.ping_ms = market.terminal_ping_last_ms;
   out.tick_age_ms = market.tick_age_ms;
   out.slippage_proxy = state.execution_pressure;
   out.retry_proxy = (double)state.exec_error_streak;
   out.execution_pressure = state.execution_pressure;

   if(!market.terminal_connected)
     {
      out.state = "BAD";
      out.reason_code = "TERMINAL_DISCONNECTED";
      return;
     }

   if(MbIsExpectedPaperMarketClosure(market))
     {
      out.state = "GOOD";
      out.reason_code = "MARKET_CLOSED_EXPECTED";
      return;
     }

   if(market.tick_age_ms >= 15000)
     {
      out.state = "BAD";
      out.reason_code = "TICK_STALE";
      return;
     }

   if(state.exec_error_streak >= 3)
     {
      out.state = "BAD";
      out.reason_code = "RETRY_SPIKE";
      return;
     }

   if(state.execution_pressure >= 0.85)
     {
      out.state = "BAD";
      out.reason_code = "EXECUTION_PRESSURE_HIGH";
      return;
     }

   if(market.terminal_ping_last_ms >= 90)
     {
      out.state = "BAD";
      out.reason_code = "PING_TOO_HIGH";
      return;
     }

   if(
      market.tick_age_ms >= 5000 ||
      state.exec_error_streak >= 1 ||
      state.execution_pressure >= 0.60 ||
      market.terminal_ping_last_ms >= 45 ||
      state.spread_anomaly_streak >= 4
   )
     {
      out.state = "CAUTION";
      if(state.exec_error_streak >= 1)
         out.reason_code = "RETRY_SPIKE";
      else if(market.tick_age_ms >= 5000)
         out.reason_code = "TICK_STALE";
      else if(market.terminal_ping_last_ms >= 45)
         out.reason_code = "PING_ELEVATED";
      else if(state.spread_anomaly_streak >= 4)
         out.reason_code = "RATE_LIMIT_PRESSURE";
      else
         out.reason_code = "EXECUTION_PRESSURE_HIGH";
     }
  }

void MbEvaluateCostPressureState(
   const string symbol,
   const MbRuntimeState &state,
   const MbMarketSnapshot &market,
   MbCostPressureState &out
)
  {
   string family = "";
   MbResolveTuningGuardFamily(symbol,family);

   double typical_move_points = 40.0;
   double time_stop_points = 16.0;
   double mfe_points = 28.0;
   double mae_points = 18.0;
   MbResolveCostBenchmarks(family,typical_move_points,time_stop_points,mfe_points,mae_points);

   out.state = "LOW";
   out.reason_code = "COST_ACCEPTABLE";
   double effective_spread_points = market.spread_points;
   // Strategy Tester can end a run on an artificially wide last quote. For the FX
   // families this was poisoning cost classification far more than the rest of the run.
   bool fx_family = (family == "FX_MAIN" || family == "FX_ASIA" || family == "FX_CROSS");
   if(MbIsStrategyTesterRuntime() && fx_family && effective_spread_points > (time_stop_points * 2.0))
      effective_spread_points = time_stop_points;

   out.spread_now = effective_spread_points;
   out.spread_vs_typical_move = effective_spread_points / MathMax(1.0,typical_move_points);
   out.spread_vs_time_stop = effective_spread_points / MathMax(1.0,time_stop_points);
   out.spread_vs_mfe = effective_spread_points / MathMax(1.0,mfe_points);
   out.spread_vs_mae = effective_spread_points / MathMax(1.0,mae_points);

   if(MbIsExpectedPaperMarketClosure(market))
     {
      out.state = "LOW";
      out.reason_code = "MARKET_CLOSED_EXPECTED";
      return;
     }

   double worst_ratio = MathMax(
      MathMax(out.spread_vs_typical_move,out.spread_vs_time_stop),
      MathMax(out.spread_vs_mfe,out.spread_vs_mae)
   );

   bool structurally_expensive = (family == "METALS_FUTURES");
   double bad_spread_non_representative_ratio = 0.80;
   if(fx_family)
      bad_spread_non_representative_ratio = 1.05;

   bool paper_not_representative = (structurally_expensive && worst_ratio >= 0.90);
   if(MbCanonicalSymbol(symbol) == "COPPER-US" && worst_ratio >= 0.75)
      paper_not_representative = true;

   if(state.spread_regime == "BAD" && worst_ratio >= bad_spread_non_representative_ratio)
      paper_not_representative = true;

   if(
      paper_not_representative &&
      MbIsStrategyTesterRuntime() &&
      fx_family &&
      state.spread_regime == "BAD" &&
      out.spread_vs_typical_move < 0.95
   )
      paper_not_representative = false;

   if(paper_not_representative)
     {
      out.state = "NON_REPRESENTATIVE";
      out.reason_code = "NON_REPRESENTATIVE_COST";
      return;
     }

   if(worst_ratio >= 0.75 || state.spread_regime == "BAD")
     {
      out.state = "HIGH";
      out.reason_code = "SPREAD_TOO_WIDE";
      return;
     }

   if(worst_ratio >= 0.45 || state.spread_regime == "WIDE")
     {
      out.state = "MEDIUM";
      out.reason_code = "SPREAD_ELEVATED";
      return;
     }

   if(state.execution_regime == "CAUTION")
     {
      out.state = "MEDIUM";
      out.reason_code = "COST_NEEDS_CAUTION";
     }
  }

datetime MbReadCandidateArbitrationTs(const string arbitration_group)
  {
   if(StringLen(arbitration_group) <= 0)
      return 0;

   int h = FileOpen(MbCandidateArbitrationStatePath(arbitration_group),FILE_COMMON | FILE_READ | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return 0;

   datetime ts = 0;
   while(!FileIsEnding(h))
     {
      string key = FileReadString(h);
      string value = FileReadString(h);
      if(key == "ts")
        {
         ts = (datetime)StringToInteger(value);
         break;
        }
     }
   FileClose(h);
   return ts;
  }

void MbEvaluateCentralStateStaleness(
   const string symbol,
   const datetime now,
   bool &out_stale,
   int &out_stale_seconds
)
  {
   out_stale = false;
   out_stale_seconds = 0;

   // In isolated Strategy Tester runs we do not have a representative family,
   // coordinator and arbiter refresh cadence. Treating this as a real central
   // failure poisons local diagnostics for single-agent research.
   if(MbIsStrategyTesterRuntime())
      return;

   string family = "";
   MbResolveTuningGuardFamily(symbol,family);

   MbTuningFamilyPolicy family_policy;
   MbTuningFamilyPolicyReset(family_policy);
   MbTuningCoordinatorState coordinator_state;
   MbTuningCoordinatorStateReset(coordinator_state);

   datetime last_family_eval = 0;
   if(StringLen(family) > 0 && MbLoadTuningFamilyPolicy(family,family_policy))
      last_family_eval = MathMax(family_policy.last_eval_at,family_policy.last_action_at);

   datetime last_coordinator_eval = 0;
   if(MbLoadTuningCoordinatorState(coordinator_state))
      last_coordinator_eval = MathMax(coordinator_state.last_eval_at,coordinator_state.last_action_at);

   string arbitration_group = MbResolveCandidateArbitrationGroup(family);
   datetime last_arbiter_eval = MbReadCandidateArbitrationTs(arbitration_group);

   datetime freshest = MathMax(last_family_eval,MathMax(last_coordinator_eval,last_arbiter_eval));
   if(freshest <= 0)
     {
      out_stale = true;
      out_stale_seconds = 86400;
      return;
     }

   out_stale_seconds = (int)(now - freshest);
   out_stale = (out_stale_seconds > 3600);
  }

void MbResolveTrustStateFromReport(
   const string symbol,
   const string raw_reason_code,
   const bool trusted,
   const int learning_sample_count,
   const int closed_lessons_count,
   const int candidate_rows,
   const int candidate_risk_block_rows,
   const int candidate_score_gate_rows,
   const int candidate_dirty_rows,
   const int paper_open_rows,
   const double recent_conversion_ratio,
   const int stale_seconds,
   MbTrustState &out
)
  {
   MbResolveTrustThresholds(symbol,out.min_conversion_ratio,out.min_conversion_candidates,out.max_dirty_ratio);
   out.state = "UNASSESSED";
   out.reason_code = raw_reason_code;
   out.sample_count = learning_sample_count;
   out.closed_lessons_count = closed_lessons_count;
   out.conversion_ratio = (candidate_score_gate_rows > 0 ? (double)paper_open_rows / (double)candidate_score_gate_rows : 0.0);
    out.recent_conversion_ratio = recent_conversion_ratio;
   out.dirty_ratio = (candidate_score_gate_rows > 0 ? (double)candidate_dirty_rows / (double)candidate_score_gate_rows : 0.0);
   out.blocked_ratio = (candidate_rows > 0 ? (double)candidate_risk_block_rows / (double)candidate_rows : 0.0);
   out.stale_seconds = stale_seconds;

   if(raw_reason_code == "CENTRAL_STATE_STALE")
     {
      out.state = "CENTRAL_STATE_STALE";
      return;
     }
   if(raw_reason_code == "INFRASTRUCTURE_WEAK")
     {
      out.state = "INFRASTRUCTURE_WEAK";
      return;
     }
   if(raw_reason_code == "OBSERVATIONS_MISSING")
     {
      out.state = "OBSERVATIONS_MISSING";
      return;
     }
   if(raw_reason_code == "LOW_SAMPLE")
     {
      out.state = "LOW_SAMPLE";
      return;
     }
   if(MbIsPaperConversionBlockedReason(raw_reason_code))
     {
      out.state = "PAPER_CONVERSION_BLOCKED";
      return;
     }
   if(MbIsForefieldDirtyReason(raw_reason_code))
     {
      out.state = "FOREFIELD_DIRTY";
      return;
     }
   if(trusted)
     {
      out.state = "TRUSTED";
      return;
     }
   out.state = "LOW_SAMPLE";
  }

void MbResolveTuningAdaptationContract(const string symbol,MbTuningAdaptationContract &out)
  {
   MbTuningAdaptationContractReset(out);

   string family = "";
   MbResolveTuningGuardFamily(symbol,family);

   if(family == "FX_ASIA")
     {
      out.tax_step_max = 0.025;
      out.cap_step_max = 0.04;
      out.floor_step_max = 0.05;
      out.min_closed_lessons = 5;
      return;
     }

   if(family == "FX_CROSS")
     {
      out.tax_step_max = 0.02;
      out.boost_step_max = 0.02;
      out.cap_step_max = 0.04;
      out.floor_step_max = 0.05;
      out.min_closed_lessons = 6;
      out.max_changes_per_window = 2;
      return;
     }

   if(family == "METALS_SPOT_PM" || family == "METALS_FUTURES")
     {
      out.tax_step_max = 0.02;
      out.boost_step_max = 0.02;
      out.cap_step_max = 0.04;
      out.floor_step_max = 0.04;
      out.min_closed_lessons = 7;
      out.min_clean_reviews = 3;
      out.max_changes_per_window = 2;
      return;
     }

   if(family == "INDEX_EU" || family == "INDEX_US")
     {
      out.tax_step_max = 0.025;
      out.cap_step_max = 0.04;
      out.floor_step_max = 0.04;
      out.min_closed_lessons = 6;
      out.max_changes_per_window = 2;
      return;
     }
  }

void MbBuildRuntimeEpistemicSnapshot(
   const string symbol,
   const MbRuntimeState &state,
   const MbMarketSnapshot &market,
   const MbTuningLocalPolicy &policy,
   const string raw_reason_code,
   MbReasonTriple &out_reason,
   MbExecutionQualityState &out_execution_quality,
   MbCostPressureState &out_cost_pressure
)
  {
   MbNormalizeReasonTriple(raw_reason_code,out_reason);
   MbEvaluateExecutionQualityState(state,market,out_execution_quality);
   MbEvaluateCostPressureState(symbol,state,market,out_cost_pressure);
  }

#endif
