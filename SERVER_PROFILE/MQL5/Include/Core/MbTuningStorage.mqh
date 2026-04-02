#ifndef MB_TUNING_STORAGE_INCLUDED
#define MB_TUNING_STORAGE_INCLUDED

#include "MbStorage.mqh"
#include "MbTuningTypes.mqh"

void MbEnsureTuningActionHeader(const int h)
  {
   if(h == INVALID_HANDLE || FileSize(h) > 0)
      return;

   FileWrite(
      h,
      "ts",
      "symbol",
      "revision",
      "action_code",
      "action_detail",
      "trusted_data",
      "trust_reason",
      "trust_reason_domain",
      "trust_reason_class",
      "trust_state",
      "execution_quality_state",
      "cost_pressure_state",
      "confidence_cap",
      "risk_cap",
      "breakout_global_tax",
      "breakout_chaos_tax",
      "breakout_range_tax",
      "trend_breakout_tax",
      "trend_chaos_tax",
      "rejection_range_boost",
      "range_chaos_tax",
      "range_trend_tax",
      "range_confidence_floor",
      "index_opening_impulse_tax",
      "index_noon_transition_tax",
      "require_aux_support_for_trend",
      "require_support_for_rejection",
      "require_non_poor_renko_for_breakout",
      "require_non_poor_candle_for_breakout",
      "require_non_poor_candle_for_range",
      "require_non_poor_renko_for_range",
      "require_non_poor_candle_for_trend"
   );
  }

string MbTuningReasoningLogPath(const string symbol)
  {
   return MbLogFilePath(symbol,"tuning_reasoning.csv");
  }

string MbTuningExperimentLogPath(const string symbol)
  {
   return MbLogFilePath(symbol,"tuning_experiments.csv");
  }

string MbTuningStablePolicyPath(const string symbol)
  {
   return MbStateFilePath(symbol,"tuning_policy_stable.csv");
  }

void MbEnsureTuningReasoningHeader(const int h)
  {
   if(h == INVALID_HANDLE || FileSize(h) > 0)
      return;

   FileWrite(
      h,
      "ts",
      "symbol",
      "phase",
      "trusted_data",
      "trust_reason",
      "trust_reason_domain",
      "trust_reason_class",
      "trust_state",
      "execution_quality_state",
      "execution_quality_reason_code",
      "cost_pressure_state",
      "cost_pressure_reason_code",
      "reason_streak",
      "blocked_cycles",
      "trusted_cycles",
      "focus_setup_type",
      "focus_market_regime",
      "hypothesis_code",
      "hypothesis_detail",
      "counterfactual_code",
      "counterfactual_detail",
      "action_code",
      "action_detail",
      "candidate_rows",
      "candidate_risk_block_rows",
      "candidate_score_gate_rows",
      "candidate_dirty_rows",
      "candidate_dirty_candle_rows",
      "candidate_dirty_renko_rows",
      "candidate_dirty_hybrid_rows",
      "candidate_dirty_spread_rows",
      "paper_open_rows",
      "conversion_ratio",
      "recent_conversion_ratio",
      "min_conversion_ratio",
      "min_conversion_candidates",
      "dirty_ratio",
      "max_dirty_ratio",
      "blocked_ratio",
      "decision_risk_contract_block_rows",
      "decision_portfolio_heat_block_rows",
      "decision_rate_guard_block_rows",
      "central_stale_seconds",
      "execution_pressure",
      "exec_error_streak",
      "spread_anomaly_streak"
   );
  }

void MbEnsureTuningExperimentHeader(const int h)
  {
   if(h == INVALID_HANDLE || FileSize(h) > 0)
      return;

   FileWrite(
      h,
      "ts",
      "symbol",
      "phase",
      "experiment_status",
      "experiment_revision",
      "experiment_action_code",
      "experiment_focus_setup_type",
      "experiment_focus_market_regime",
      "baseline_samples",
      "current_samples",
      "delta_samples",
      "baseline_wins",
      "current_wins",
      "delta_wins",
      "baseline_losses",
      "current_losses",
      "delta_losses",
      "baseline_paper_open_rows",
      "current_paper_open_rows",
      "delta_paper_open_rows",
      "baseline_realized_pnl_lifetime",
      "current_realized_pnl_lifetime",
      "delta_realized_pnl_lifetime",
      "baseline_trust_state",
      "baseline_execution_quality_state",
      "baseline_cost_pressure_state",
      "experiment_cause_domain",
      "experiment_cause_class",
      "experiment_cause_code",
      "review_reason_domain",
      "review_reason_class",
      "review_reason_code",
      "failure_reason_domain",
      "failure_reason_class",
      "failure_reason_code",
      "trust_reason",
      "trust_reason_domain",
      "trust_reason_class",
      "trust_state",
      "execution_quality_state",
      "execution_quality_reason_code",
      "cost_pressure_state",
      "cost_pressure_reason_code",
      "report_reason_code",
      "report_reason_domain",
      "report_reason_class",
      "last_action_code",
      "last_action_detail",
      "detail"
   );
  }

void MbAppendTuningReasoningEvent(
   const string symbol,
   const string phase,
   const MbTuningLocalPolicy &policy,
   const MbTuningDeckhandReport &report
)
  {
   string path = MbTuningReasoningLogPath(symbol);
   int h = FileOpen(path,FILE_COMMON | FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;

   MbEnsureTuningReasoningHeader(h);
   FileSeek(h,0,SEEK_END);
   FileWrite(
      h,
      (long)TimeCurrent(),
      MbCanonicalSymbol(symbol),
      phase,
      (policy.trusted_data ? 1 : 0),
      policy.trust_reason,
      policy.trust_reason_domain,
      policy.trust_reason_class,
      policy.last_trust_state,
      report.execution_quality.state,
      report.execution_quality.reason_code,
      report.cost_pressure.state,
      report.cost_pressure.reason_code,
      policy.reason_streak,
      policy.blocked_cycles,
      policy.trusted_cycles,
      policy.last_focus_setup_type,
      policy.last_focus_market_regime,
      policy.last_hypothesis_code,
      policy.last_hypothesis_detail,
      policy.last_counterfactual_code,
      policy.last_counterfactual_detail,
      policy.last_action_code,
      policy.last_action_detail,
      report.candidate_rows,
      report.candidate_risk_block_rows,
      report.candidate_score_gate_rows,
      report.candidate_dirty_rows,
      report.candidate_dirty_candle_rows,
      report.candidate_dirty_renko_rows,
      report.candidate_dirty_hybrid_rows,
      report.candidate_dirty_spread_rows,
      report.paper_open_rows,
      DoubleToString(report.trust_state.conversion_ratio,4),
      DoubleToString(report.trust_state.recent_conversion_ratio,4),
      DoubleToString(report.trust_state.min_conversion_ratio,4),
      report.trust_state.min_conversion_candidates,
      DoubleToString(report.trust_state.dirty_ratio,4),
      DoubleToString(report.trust_state.max_dirty_ratio,4),
      DoubleToString(report.trust_state.blocked_ratio,4),
      report.decision_risk_contract_block_rows,
      report.decision_portfolio_heat_block_rows,
      report.decision_rate_guard_block_rows,
      report.trust_state.stale_seconds,
      DoubleToString(report.execution_pressure,4),
      report.exec_error_streak,
      report.spread_anomaly_streak
   );
   FileClose(h);
  }

void MbAppendTuningExperimentEvent(
   const string symbol,
   const string phase,
   const MbTuningLocalPolicy &policy,
   const MbRuntimeState &state,
   const MbTuningDeckhandReport &report,
   const string detail
)
  {
   string path = MbTuningExperimentLogPath(symbol);
   int h = FileOpen(path,FILE_COMMON | FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;

   MbEnsureTuningExperimentHeader(h);
   FileSeek(h,0,SEEK_END);

   int delta_samples = state.learning_sample_count - policy.experiment_baseline_samples;
   int delta_wins = state.learning_win_count - policy.experiment_baseline_wins;
   int delta_losses = state.learning_loss_count - policy.experiment_baseline_losses;
   int delta_paper_open_rows = report.paper_open_rows - policy.experiment_baseline_paper_open_rows;
   double delta_realized_pnl_lifetime = state.realized_pnl_lifetime - policy.experiment_baseline_realized_pnl_lifetime;

   FileWrite(
      h,
      (long)TimeCurrent(),
      MbCanonicalSymbol(symbol),
      phase,
      policy.experiment_status,
      policy.experiment_revision,
      policy.experiment_action_code,
      policy.experiment_focus_setup_type,
      policy.experiment_focus_market_regime,
      policy.experiment_baseline_samples,
      state.learning_sample_count,
      delta_samples,
      policy.experiment_baseline_wins,
      state.learning_win_count,
      delta_wins,
      policy.experiment_baseline_losses,
      state.learning_loss_count,
      delta_losses,
      policy.experiment_baseline_paper_open_rows,
      report.paper_open_rows,
      delta_paper_open_rows,
      DoubleToString(policy.experiment_baseline_realized_pnl_lifetime,2),
      DoubleToString(state.realized_pnl_lifetime,2),
      DoubleToString(delta_realized_pnl_lifetime,2),
      policy.experiment_baseline_trust_state,
      policy.experiment_baseline_execution_quality_state,
      policy.experiment_baseline_cost_pressure_state,
      policy.experiment_cause_domain,
      policy.experiment_cause_class,
      policy.experiment_cause_code,
      policy.experiment_last_review_domain,
      policy.experiment_last_review_class,
      policy.experiment_last_review_code,
      policy.experiment_failure_domain,
      policy.experiment_failure_class,
      policy.experiment_failure_code,
      policy.trust_reason,
      policy.trust_reason_domain,
      policy.trust_reason_class,
      policy.last_trust_state,
      report.execution_quality.state,
      report.execution_quality.reason_code,
      report.cost_pressure.state,
      report.cost_pressure.reason_code,
      report.reason_code,
      report.normalized_reason.domain,
      report.normalized_reason.reason_class,
      policy.last_action_code,
      policy.last_action_detail,
      detail
   );
   FileClose(h);
  }

void MbAppendTuningActionEvent(
   const string path,
   const string symbol,
   const MbTuningLocalPolicy &policy,
   const MbTuningDeckhandReport &report
)
  {
   int h = FileOpen(path,FILE_COMMON | FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;
   MbEnsureTuningActionHeader(h);
   FileSeek(h,0,SEEK_END);
   FileWrite(
      h,
      (long)TimeCurrent(),
      MbCanonicalSymbol(symbol),
      policy.revision,
      policy.last_action_code,
      policy.last_action_detail,
      (policy.trusted_data ? 1 : 0),
      policy.trust_reason,
      policy.trust_reason_domain,
      policy.trust_reason_class,
      policy.last_trust_state,
      report.execution_quality.state,
      report.cost_pressure.state,
      DoubleToString(policy.confidence_cap,4),
      DoubleToString(policy.risk_cap,4),
      DoubleToString(policy.breakout_global_tax,4),
      DoubleToString(policy.breakout_chaos_tax,4),
      DoubleToString(policy.breakout_range_tax,4),
      DoubleToString(policy.trend_breakout_tax,4),
      DoubleToString(policy.trend_chaos_tax,4),
      DoubleToString(policy.rejection_range_boost,4),
      DoubleToString(policy.range_chaos_tax,4),
      DoubleToString(policy.range_trend_tax,4),
      DoubleToString(policy.range_confidence_floor,4),
      DoubleToString(policy.index_opening_impulse_tax,4),
      DoubleToString(policy.index_noon_transition_tax,4),
      (policy.require_aux_support_for_trend ? 1 : 0),
      (policy.require_support_for_rejection ? 1 : 0),
      (policy.require_non_poor_renko_for_breakout ? 1 : 0),
      (policy.require_non_poor_candle_for_breakout ? 1 : 0),
      (policy.require_non_poor_candle_for_range ? 1 : 0),
      (policy.require_non_poor_renko_for_range ? 1 : 0),
      (policy.require_non_poor_candle_for_trend ? 1 : 0)
   );
   FileClose(h);
  }

void MbEnsureTuningDeckhandHeader(const int h)
  {
   if(h == INVALID_HANDLE || FileSize(h) > 0)
      return;

   FileWrite(
      h,
      "ts",
      "symbol",
      "trusted",
      "rebuilt_bucket_summary",
      "total_rows",
      "observation_rows",
      "invalid_rows",
      "none_unknown_rows",
      "bucket_rows",
      "candidate_rows",
      "candidate_invalid_rows",
      "candidate_risk_block_rows",
      "candidate_score_gate_rows",
      "candidate_dirty_rows",
      "candidate_dirty_candle_rows",
      "candidate_dirty_renko_rows",
      "candidate_dirty_hybrid_rows",
      "candidate_dirty_spread_rows",
      "paper_open_rows",
      "reason_code",
      "reason_domain",
      "reason_class",
      "trust_state",
      "conversion_ratio",
      "recent_conversion_ratio",
      "min_conversion_ratio",
      "min_conversion_candidates",
      "dirty_ratio",
      "max_dirty_ratio",
      "blocked_ratio",
      "decision_risk_contract_block_rows",
      "decision_portfolio_heat_block_rows",
      "decision_rate_guard_block_rows",
      "central_stale_seconds",
      "execution_quality_state",
      "execution_quality_reason_code",
      "execution_quality_ping_ms",
      "execution_quality_tick_age_ms",
      "cost_pressure_state",
      "cost_pressure_reason_code",
      "spread_now",
      "spread_vs_typical_move",
      "spread_vs_time_stop",
      "spread_vs_mfe",
      "spread_vs_mae"
   );
  }

void MbAppendTuningDeckhandEvent(
   const string path,
   const string symbol,
   const MbTuningDeckhandReport &report
)
  {
   int h = FileOpen(path,FILE_COMMON | FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;
   MbEnsureTuningDeckhandHeader(h);
   FileSeek(h,0,SEEK_END);
   FileWrite(
      h,
      (long)report.serviced_at,
      MbCanonicalSymbol(symbol),
      (report.trusted ? 1 : 0),
      (report.rebuilt_bucket_summary ? 1 : 0),
      report.total_rows,
      report.observation_rows,
      report.invalid_rows,
      report.none_unknown_rows,
      report.bucket_rows,
      report.candidate_rows,
      report.candidate_invalid_rows,
      report.candidate_risk_block_rows,
      report.candidate_score_gate_rows,
      report.candidate_dirty_rows,
      report.candidate_dirty_candle_rows,
      report.candidate_dirty_renko_rows,
      report.candidate_dirty_hybrid_rows,
      report.candidate_dirty_spread_rows,
      report.paper_open_rows,
      report.reason_code,
      report.normalized_reason.domain,
      report.normalized_reason.reason_class,
      report.trust_state.state,
      DoubleToString(report.trust_state.conversion_ratio,4),
      DoubleToString(report.trust_state.recent_conversion_ratio,4),
      DoubleToString(report.trust_state.min_conversion_ratio,4),
      report.trust_state.min_conversion_candidates,
      DoubleToString(report.trust_state.dirty_ratio,4),
      DoubleToString(report.trust_state.max_dirty_ratio,4),
      DoubleToString(report.trust_state.blocked_ratio,4),
      report.decision_risk_contract_block_rows,
      report.decision_portfolio_heat_block_rows,
      report.decision_rate_guard_block_rows,
      report.trust_state.stale_seconds,
      report.execution_quality.state,
      report.execution_quality.reason_code,
      report.execution_quality.ping_ms,
      report.execution_quality.tick_age_ms,
      report.cost_pressure.state,
      report.cost_pressure.reason_code,
      DoubleToString(report.cost_pressure.spread_now,2),
      DoubleToString(report.cost_pressure.spread_vs_typical_move,4),
      DoubleToString(report.cost_pressure.spread_vs_time_stop,4),
      DoubleToString(report.cost_pressure.spread_vs_mfe,4),
      DoubleToString(report.cost_pressure.spread_vs_mae,4)
   );
   FileClose(h);
  }

bool MbSaveTuningLocalPolicyToPath(const string path,const MbTuningLocalPolicy &policy)
  {
   int h = FileOpen(path, FILE_COMMON | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;

   FileWrite(h,"enabled",(policy.enabled ? 1 : 0));
   FileWrite(h,"trusted_data",(policy.trusted_data ? 1 : 0));
   FileWrite(h,"require_aux_support_for_trend",(policy.require_aux_support_for_trend ? 1 : 0));
   FileWrite(h,"require_support_for_rejection",(policy.require_support_for_rejection ? 1 : 0));
   FileWrite(h,"require_non_poor_renko_for_breakout",(policy.require_non_poor_renko_for_breakout ? 1 : 0));
   FileWrite(h,"require_non_poor_candle_for_breakout",(policy.require_non_poor_candle_for_breakout ? 1 : 0));
   FileWrite(h,"require_non_poor_candle_for_trend",(policy.require_non_poor_candle_for_trend ? 1 : 0));
   FileWrite(h,"require_non_poor_candle_for_range",(policy.require_non_poor_candle_for_range ? 1 : 0));
   FileWrite(h,"require_non_poor_renko_for_range",(policy.require_non_poor_renko_for_range ? 1 : 0));
   FileWrite(h,"revision",policy.revision);
   FileWrite(h,"min_bucket_samples",policy.min_bucket_samples);
   FileWrite(h,"cooldown_sec",policy.cooldown_sec);
   FileWrite(h,"last_learning_sample_count",policy.last_learning_sample_count);
   FileWrite(h,"last_observation_rows",policy.last_observation_rows);
   FileWrite(h,"last_bucket_rows",policy.last_bucket_rows);
   FileWrite(h,"last_candidate_rows",policy.last_candidate_rows);
   FileWrite(h,"last_candidate_risk_block_rows",policy.last_candidate_risk_block_rows);
   FileWrite(h,"last_candidate_score_gate_rows",policy.last_candidate_score_gate_rows);
   FileWrite(h,"last_candidate_dirty_rows",policy.last_candidate_dirty_rows);
   FileWrite(h,"last_paper_open_rows",policy.last_paper_open_rows);
   FileWrite(h,"last_logged_learning_sample_count",policy.last_logged_learning_sample_count);
   FileWrite(h,"last_logged_observation_rows",policy.last_logged_observation_rows);
   FileWrite(h,"last_logged_bucket_rows",policy.last_logged_bucket_rows);
   FileWrite(h,"last_logged_candidate_rows",policy.last_logged_candidate_rows);
   FileWrite(h,"last_logged_candidate_risk_block_rows",policy.last_logged_candidate_risk_block_rows);
   FileWrite(h,"last_logged_candidate_score_gate_rows",policy.last_logged_candidate_score_gate_rows);
   FileWrite(h,"last_logged_candidate_dirty_rows",policy.last_logged_candidate_dirty_rows);
   FileWrite(h,"last_logged_paper_open_rows",policy.last_logged_paper_open_rows);
   FileWrite(h,"last_logged_trusted",(policy.last_logged_trusted ? 1 : 0));
   FileWrite(h,"last_eval_at",(long)policy.last_eval_at);
   FileWrite(h,"last_action_at",(long)policy.last_action_at);
   FileWrite(h,"cooldown_until",(long)policy.cooldown_until);
   FileWrite(h,"last_deckhand_log_at",(long)policy.last_deckhand_log_at);
   FileWrite(h,"breakout_global_tax",DoubleToString(policy.breakout_global_tax,6));
   FileWrite(h,"breakout_chaos_tax",DoubleToString(policy.breakout_chaos_tax,6));
   FileWrite(h,"breakout_range_tax",DoubleToString(policy.breakout_range_tax,6));
   FileWrite(h,"breakout_conflict_tax",DoubleToString(policy.breakout_conflict_tax,6));
   FileWrite(h,"trend_breakout_tax",DoubleToString(policy.trend_breakout_tax,6));
   FileWrite(h,"trend_chaos_tax",DoubleToString(policy.trend_chaos_tax,6));
   FileWrite(h,"trend_caution_tax",DoubleToString(policy.trend_caution_tax,6));
   FileWrite(h,"trend_no_aux_tax",DoubleToString(policy.trend_no_aux_tax,6));
   FileWrite(h,"range_chaos_tax",DoubleToString(policy.range_chaos_tax,6));
   FileWrite(h,"range_trend_tax",DoubleToString(policy.range_trend_tax,6));
   FileWrite(h,"range_confidence_floor",DoubleToString(policy.range_confidence_floor,6));
   FileWrite(h,"index_opening_impulse_tax",DoubleToString(policy.index_opening_impulse_tax,6));
   FileWrite(h,"index_noon_transition_tax",DoubleToString(policy.index_noon_transition_tax,6));
   FileWrite(h,"rejection_range_boost",DoubleToString(policy.rejection_range_boost,6));
   FileWrite(h,"confidence_cap",DoubleToString(policy.confidence_cap,6));
   FileWrite(h,"risk_cap",DoubleToString(policy.risk_cap,6));
   FileWrite(h,"trust_reason",policy.trust_reason);
   FileWrite(h,"trust_reason_domain",policy.trust_reason_domain);
   FileWrite(h,"trust_reason_class",policy.trust_reason_class);
   FileWrite(h,"last_logged_reason_code",policy.last_logged_reason_code);
   FileWrite(h,"last_logged_reason_domain",policy.last_logged_reason_domain);
   FileWrite(h,"last_logged_reason_class",policy.last_logged_reason_class);
   FileWrite(h,"last_action_code",policy.last_action_code);
   FileWrite(h,"last_action_detail",policy.last_action_detail);
   FileWrite(h,"last_trust_state",policy.last_trust_state);
   FileWrite(h,"last_execution_quality_state",policy.last_execution_quality_state);
   FileWrite(h,"last_cost_pressure_state",policy.last_cost_pressure_state);
   FileWrite(h,"reason_streak",policy.reason_streak);
   FileWrite(h,"action_streak",policy.action_streak);
   FileWrite(h,"blocked_cycles",policy.blocked_cycles);
   FileWrite(h,"trusted_cycles",policy.trusted_cycles);
   FileWrite(h,"adaptation_window_started_at",(long)policy.adaptation_window_started_at);
   FileWrite(h,"adaptation_changes_in_window",policy.adaptation_changes_in_window);
   FileWrite(h,"last_focus_setup_type",policy.last_focus_setup_type);
   FileWrite(h,"last_focus_market_regime",policy.last_focus_market_regime);
   FileWrite(h,"last_hypothesis_code",policy.last_hypothesis_code);
   FileWrite(h,"last_hypothesis_detail",policy.last_hypothesis_detail);
   FileWrite(h,"last_counterfactual_code",policy.last_counterfactual_code);
   FileWrite(h,"last_counterfactual_detail",policy.last_counterfactual_detail);
   FileWrite(h,"experiment_active",(policy.experiment_active ? 1 : 0));
   FileWrite(h,"experiment_revision",policy.experiment_revision);
   FileWrite(h,"experiment_review_count",policy.experiment_review_count);
   FileWrite(h,"experiment_started_at",(long)policy.experiment_started_at);
   FileWrite(h,"experiment_baseline_samples",policy.experiment_baseline_samples);
   FileWrite(h,"experiment_baseline_wins",policy.experiment_baseline_wins);
   FileWrite(h,"experiment_baseline_losses",policy.experiment_baseline_losses);
   FileWrite(h,"experiment_baseline_paper_open_rows",policy.experiment_baseline_paper_open_rows);
   FileWrite(h,"experiment_baseline_realized_pnl_lifetime",DoubleToString(policy.experiment_baseline_realized_pnl_lifetime,6));
   FileWrite(h,"experiment_baseline_trust_state",policy.experiment_baseline_trust_state);
   FileWrite(h,"experiment_baseline_execution_quality_state",policy.experiment_baseline_execution_quality_state);
   FileWrite(h,"experiment_baseline_cost_pressure_state",policy.experiment_baseline_cost_pressure_state);
   FileWrite(h,"experiment_action_code",policy.experiment_action_code);
   FileWrite(h,"experiment_focus_setup_type",policy.experiment_focus_setup_type);
   FileWrite(h,"experiment_focus_market_regime",policy.experiment_focus_market_regime);
   FileWrite(h,"experiment_cause_domain",policy.experiment_cause_domain);
   FileWrite(h,"experiment_cause_class",policy.experiment_cause_class);
   FileWrite(h,"experiment_cause_code",policy.experiment_cause_code);
   FileWrite(h,"experiment_last_review_domain",policy.experiment_last_review_domain);
   FileWrite(h,"experiment_last_review_class",policy.experiment_last_review_class);
   FileWrite(h,"experiment_last_review_code",policy.experiment_last_review_code);
   FileWrite(h,"experiment_failure_domain",policy.experiment_failure_domain);
   FileWrite(h,"experiment_failure_class",policy.experiment_failure_class);
   FileWrite(h,"experiment_failure_code",policy.experiment_failure_code);
   FileWrite(h,"experiment_status",policy.experiment_status);
   FileWrite(h,"last_failed_at",(long)policy.last_failed_at);
   FileWrite(h,"avoid_repeat_until",(long)policy.avoid_repeat_until);
   FileWrite(h,"last_failed_action_code",policy.last_failed_action_code);
   FileWrite(h,"last_failed_focus_setup_type",policy.last_failed_focus_setup_type);
   FileWrite(h,"last_failed_focus_market_regime",policy.last_failed_focus_market_regime);
   FileWrite(h,"last_failed_cause_domain",policy.last_failed_cause_domain);
   FileWrite(h,"last_failed_cause_class",policy.last_failed_cause_class);
   FileWrite(h,"last_failed_cause_code",policy.last_failed_cause_code);
   FileClose(h);
   return true;
  }

bool MbSaveTuningLocalPolicy(const string symbol,const MbTuningLocalPolicy &policy)
  {
   return MbSaveTuningLocalPolicyToPath(MbStateFilePath(symbol,"tuning_policy.csv"),policy);
  }

bool MbSaveEffectiveTuningLocalPolicy(const string symbol,const MbTuningLocalPolicy &policy)
  {
   return MbSaveTuningLocalPolicyToPath(MbStateFilePath(symbol,"tuning_policy_effective.csv"),policy);
  }

bool MbLoadTuningLocalPolicyFromPath(const string path,MbTuningLocalPolicy &policy)
  {
   int h = FileOpen(path, FILE_COMMON | FILE_READ | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;

   while(!FileIsEnding(h))
     {
      string key = FileReadString(h);
      string value = FileReadString(h);
      if(key == "enabled") policy.enabled = (StringToInteger(value) != 0);
      else if(key == "trusted_data") policy.trusted_data = (StringToInteger(value) != 0);
      else if(key == "require_aux_support_for_trend") policy.require_aux_support_for_trend = (StringToInteger(value) != 0);
      else if(key == "require_support_for_rejection") policy.require_support_for_rejection = (StringToInteger(value) != 0);
      else if(key == "require_non_poor_renko_for_breakout") policy.require_non_poor_renko_for_breakout = (StringToInteger(value) != 0);
      else if(key == "require_non_poor_candle_for_breakout") policy.require_non_poor_candle_for_breakout = (StringToInteger(value) != 0);
      else if(key == "require_non_poor_candle_for_trend") policy.require_non_poor_candle_for_trend = (StringToInteger(value) != 0);
      else if(key == "require_non_poor_candle_for_range") policy.require_non_poor_candle_for_range = (StringToInteger(value) != 0);
      else if(key == "require_non_poor_renko_for_range") policy.require_non_poor_renko_for_range = (StringToInteger(value) != 0);
      else if(key == "revision") policy.revision = (int)StringToInteger(value);
      else if(key == "min_bucket_samples") policy.min_bucket_samples = (int)StringToInteger(value);
      else if(key == "cooldown_sec") policy.cooldown_sec = (int)StringToInteger(value);
      else if(key == "last_learning_sample_count") policy.last_learning_sample_count = (int)StringToInteger(value);
      else if(key == "last_observation_rows") policy.last_observation_rows = (int)StringToInteger(value);
      else if(key == "last_bucket_rows") policy.last_bucket_rows = (int)StringToInteger(value);
      else if(key == "last_candidate_rows") policy.last_candidate_rows = (int)StringToInteger(value);
      else if(key == "last_candidate_risk_block_rows") policy.last_candidate_risk_block_rows = (int)StringToInteger(value);
      else if(key == "last_candidate_score_gate_rows") policy.last_candidate_score_gate_rows = (int)StringToInteger(value);
      else if(key == "last_candidate_dirty_rows") policy.last_candidate_dirty_rows = (int)StringToInteger(value);
      else if(key == "last_paper_open_rows") policy.last_paper_open_rows = (int)StringToInteger(value);
      else if(key == "last_logged_learning_sample_count") policy.last_logged_learning_sample_count = (int)StringToInteger(value);
      else if(key == "last_logged_observation_rows") policy.last_logged_observation_rows = (int)StringToInteger(value);
      else if(key == "last_logged_bucket_rows") policy.last_logged_bucket_rows = (int)StringToInteger(value);
      else if(key == "last_logged_candidate_rows") policy.last_logged_candidate_rows = (int)StringToInteger(value);
      else if(key == "last_logged_candidate_risk_block_rows") policy.last_logged_candidate_risk_block_rows = (int)StringToInteger(value);
      else if(key == "last_logged_candidate_score_gate_rows") policy.last_logged_candidate_score_gate_rows = (int)StringToInteger(value);
      else if(key == "last_logged_candidate_dirty_rows") policy.last_logged_candidate_dirty_rows = (int)StringToInteger(value);
      else if(key == "last_logged_paper_open_rows") policy.last_logged_paper_open_rows = (int)StringToInteger(value);
      else if(key == "last_logged_trusted") policy.last_logged_trusted = (StringToInteger(value) != 0);
      else if(key == "last_eval_at") policy.last_eval_at = (datetime)StringToInteger(value);
      else if(key == "last_action_at") policy.last_action_at = (datetime)StringToInteger(value);
      else if(key == "cooldown_until") policy.cooldown_until = (datetime)StringToInteger(value);
      else if(key == "last_deckhand_log_at") policy.last_deckhand_log_at = (datetime)StringToInteger(value);
      else if(key == "breakout_global_tax") policy.breakout_global_tax = StringToDouble(value);
      else if(key == "breakout_chaos_tax") policy.breakout_chaos_tax = StringToDouble(value);
      else if(key == "breakout_range_tax") policy.breakout_range_tax = StringToDouble(value);
      else if(key == "breakout_conflict_tax") policy.breakout_conflict_tax = StringToDouble(value);
      else if(key == "trend_breakout_tax") policy.trend_breakout_tax = StringToDouble(value);
      else if(key == "trend_chaos_tax") policy.trend_chaos_tax = StringToDouble(value);
      else if(key == "trend_caution_tax") policy.trend_caution_tax = StringToDouble(value);
      else if(key == "trend_no_aux_tax") policy.trend_no_aux_tax = StringToDouble(value);
      else if(key == "range_chaos_tax") policy.range_chaos_tax = StringToDouble(value);
      else if(key == "range_trend_tax") policy.range_trend_tax = StringToDouble(value);
      else if(key == "range_confidence_floor") policy.range_confidence_floor = StringToDouble(value);
      else if(key == "index_opening_impulse_tax") policy.index_opening_impulse_tax = StringToDouble(value);
      else if(key == "index_noon_transition_tax") policy.index_noon_transition_tax = StringToDouble(value);
      else if(key == "rejection_range_boost") policy.rejection_range_boost = StringToDouble(value);
      else if(key == "confidence_cap") policy.confidence_cap = StringToDouble(value);
      else if(key == "risk_cap") policy.risk_cap = StringToDouble(value);
      else if(key == "trust_reason") policy.trust_reason = value;
      else if(key == "trust_reason_domain") policy.trust_reason_domain = value;
      else if(key == "trust_reason_class") policy.trust_reason_class = value;
      else if(key == "last_logged_reason_code") policy.last_logged_reason_code = value;
      else if(key == "last_logged_reason_domain") policy.last_logged_reason_domain = value;
      else if(key == "last_logged_reason_class") policy.last_logged_reason_class = value;
      else if(key == "last_action_code") policy.last_action_code = value;
      else if(key == "last_action_detail") policy.last_action_detail = value;
      else if(key == "last_trust_state") policy.last_trust_state = value;
      else if(key == "last_execution_quality_state") policy.last_execution_quality_state = value;
      else if(key == "last_cost_pressure_state") policy.last_cost_pressure_state = value;
      else if(key == "reason_streak") policy.reason_streak = (int)StringToInteger(value);
      else if(key == "action_streak") policy.action_streak = (int)StringToInteger(value);
      else if(key == "blocked_cycles") policy.blocked_cycles = (int)StringToInteger(value);
      else if(key == "trusted_cycles") policy.trusted_cycles = (int)StringToInteger(value);
      else if(key == "adaptation_window_started_at") policy.adaptation_window_started_at = (datetime)StringToInteger(value);
      else if(key == "adaptation_changes_in_window") policy.adaptation_changes_in_window = (int)StringToInteger(value);
      else if(key == "last_focus_setup_type") policy.last_focus_setup_type = value;
      else if(key == "last_focus_market_regime") policy.last_focus_market_regime = value;
      else if(key == "last_hypothesis_code") policy.last_hypothesis_code = value;
      else if(key == "last_hypothesis_detail") policy.last_hypothesis_detail = value;
      else if(key == "last_counterfactual_code") policy.last_counterfactual_code = value;
      else if(key == "last_counterfactual_detail") policy.last_counterfactual_detail = value;
      else if(key == "experiment_active") policy.experiment_active = (StringToInteger(value) != 0);
      else if(key == "experiment_revision") policy.experiment_revision = (int)StringToInteger(value);
      else if(key == "experiment_review_count") policy.experiment_review_count = (int)StringToInteger(value);
      else if(key == "experiment_started_at") policy.experiment_started_at = (datetime)StringToInteger(value);
      else if(key == "experiment_baseline_samples") policy.experiment_baseline_samples = (int)StringToInteger(value);
      else if(key == "experiment_baseline_wins") policy.experiment_baseline_wins = (int)StringToInteger(value);
      else if(key == "experiment_baseline_losses") policy.experiment_baseline_losses = (int)StringToInteger(value);
      else if(key == "experiment_baseline_paper_open_rows") policy.experiment_baseline_paper_open_rows = (int)StringToInteger(value);
      else if(key == "experiment_baseline_realized_pnl_lifetime") policy.experiment_baseline_realized_pnl_lifetime = StringToDouble(value);
      else if(key == "experiment_baseline_trust_state") policy.experiment_baseline_trust_state = value;
      else if(key == "experiment_baseline_execution_quality_state") policy.experiment_baseline_execution_quality_state = value;
      else if(key == "experiment_baseline_cost_pressure_state") policy.experiment_baseline_cost_pressure_state = value;
      else if(key == "experiment_action_code") policy.experiment_action_code = value;
      else if(key == "experiment_focus_setup_type") policy.experiment_focus_setup_type = value;
      else if(key == "experiment_focus_market_regime") policy.experiment_focus_market_regime = value;
      else if(key == "experiment_cause_domain") policy.experiment_cause_domain = value;
      else if(key == "experiment_cause_class") policy.experiment_cause_class = value;
      else if(key == "experiment_cause_code") policy.experiment_cause_code = value;
      else if(key == "experiment_last_review_domain") policy.experiment_last_review_domain = value;
      else if(key == "experiment_last_review_class") policy.experiment_last_review_class = value;
      else if(key == "experiment_last_review_code") policy.experiment_last_review_code = value;
      else if(key == "experiment_failure_domain") policy.experiment_failure_domain = value;
      else if(key == "experiment_failure_class") policy.experiment_failure_class = value;
      else if(key == "experiment_failure_code") policy.experiment_failure_code = value;
      else if(key == "experiment_status") policy.experiment_status = value;
      else if(key == "last_failed_at") policy.last_failed_at = (datetime)StringToInteger(value);
      else if(key == "avoid_repeat_until") policy.avoid_repeat_until = (datetime)StringToInteger(value);
      else if(key == "last_failed_action_code") policy.last_failed_action_code = value;
      else if(key == "last_failed_focus_setup_type") policy.last_failed_focus_setup_type = value;
      else if(key == "last_failed_focus_market_regime") policy.last_failed_focus_market_regime = value;
      else if(key == "last_failed_cause_domain") policy.last_failed_cause_domain = value;
      else if(key == "last_failed_cause_class") policy.last_failed_cause_class = value;
      else if(key == "last_failed_cause_code") policy.last_failed_cause_code = value;
     }

   FileClose(h);
   return true;
  }

bool MbLoadTuningLocalPolicy(const string symbol,MbTuningLocalPolicy &policy)
  {
   return MbLoadTuningLocalPolicyFromPath(MbStateFilePath(symbol,"tuning_policy.csv"),policy);
  }

bool MbSaveStableTuningLocalPolicy(const string symbol,const MbTuningLocalPolicy &policy)
  {
   return MbSaveTuningLocalPolicyToPath(MbTuningStablePolicyPath(symbol),policy);
  }

bool MbLoadStableTuningLocalPolicy(const string symbol,MbTuningLocalPolicy &policy)
  {
   return MbLoadTuningLocalPolicyFromPath(MbTuningStablePolicyPath(symbol),policy);
  }

string MbTuningFamilyStateDir(const string family)
  {
   return MbRootPath() + "\\state\\_families\\" + family;
  }

string MbTuningFamilyLogDir(const string family)
  {
   return MbRootPath() + "\\logs\\_families\\" + family;
  }

string MbTuningCoordinatorStateDir()
  {
   return MbRootPath() + "\\state\\_coordinator";
  }

string MbTuningCoordinatorLogDir()
  {
   return MbRootPath() + "\\logs\\_coordinator";
  }

string MbTuningFamilyPolicyPath(const string family)
  {
   return MbTuningFamilyStateDir(family) + "\\tuning_family_policy.csv";
  }

string MbTuningFamilyActionLogPath(const string family)
  {
   return MbTuningFamilyLogDir(family) + "\\tuning_family_actions.csv";
  }

string MbTuningCoordinatorStatePath()
  {
   return MbTuningCoordinatorStateDir() + "\\tuning_coordinator_state.csv";
  }

string MbTuningCoordinatorActionLogPath()
  {
   return MbTuningCoordinatorLogDir() + "\\tuning_coordinator_actions.csv";
  }

bool MbEnsureTuningFamilyStorage(const string family)
  {
   bool ok = true;
   ok = MbEnsureDir(MbRootPath()) && ok;
   ok = MbEnsureDir(MbRootPath() + "\\state") && ok;
   ok = MbEnsureDir(MbRootPath() + "\\logs") && ok;
   ok = MbEnsureDir(MbRootPath() + "\\state\\_families") && ok;
   ok = MbEnsureDir(MbRootPath() + "\\logs\\_families") && ok;
   ok = MbEnsureDir(MbTuningFamilyStateDir(family)) && ok;
   ok = MbEnsureDir(MbTuningFamilyLogDir(family)) && ok;
   return ok;
  }

bool MbEnsureTuningCoordinatorStorage()
  {
   bool ok = true;
   ok = MbEnsureDir(MbRootPath()) && ok;
   ok = MbEnsureDir(MbRootPath() + "\\state") && ok;
   ok = MbEnsureDir(MbRootPath() + "\\logs") && ok;
   ok = MbEnsureDir(MbTuningCoordinatorStateDir()) && ok;
   ok = MbEnsureDir(MbTuningCoordinatorLogDir()) && ok;
   return ok;
  }

void MbEnsureTuningFamilyActionHeader(const int h)
  {
   if(h == INVALID_HANDLE || FileSize(h) > 0)
      return;

   FileWrite(
      h,
      "ts",
      "family",
      "revision",
      "action_code",
      "action_detail",
      "trusted_data",
      "trust_reason",
      "symbol_count",
      "trusted_symbol_count",
      "degraded_symbol_count",
      "chaos_symbol_count",
      "bad_spread_symbol_count",
      "paper_mode_active",
      "aggregate_realized_pnl_day",
      "aggregate_equity_anchor_day",
      "family_daily_loss_pct",
      "dominant_confidence_cap",
      "dominant_risk_cap",
      "breakout_family_tax",
      "trend_family_tax",
      "rejection_range_boost",
      "freeze_new_changes"
   );
  }

void MbAppendTuningFamilyActionEvent(const string family,const MbTuningFamilyPolicy &policy)
  {
   if(!MbEnsureTuningFamilyStorage(family))
      return;

   int h = FileOpen(MbTuningFamilyActionLogPath(family),FILE_COMMON | FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;

   MbEnsureTuningFamilyActionHeader(h);
   FileSeek(h,0,SEEK_END);
   FileWrite(
      h,
      (long)TimeCurrent(),
      family,
      policy.revision,
      policy.last_action_code,
      policy.last_action_detail,
      (policy.trusted_data ? 1 : 0),
      policy.trust_reason,
      policy.symbol_count,
      policy.trusted_symbol_count,
      policy.degraded_symbol_count,
      policy.chaos_symbol_count,
      policy.bad_spread_symbol_count,
      (policy.paper_mode_active ? 1 : 0),
      DoubleToString(policy.aggregate_realized_pnl_day,2),
      DoubleToString(policy.aggregate_equity_anchor_day,2),
      DoubleToString(policy.family_daily_loss_pct,4),
      DoubleToString(policy.dominant_confidence_cap,4),
      DoubleToString(policy.dominant_risk_cap,4),
      DoubleToString(policy.breakout_family_tax,4),
      DoubleToString(policy.trend_family_tax,4),
      DoubleToString(policy.rejection_range_boost,4),
      (policy.freeze_new_changes ? 1 : 0)
   );
   FileClose(h);
  }

bool MbSaveTuningFamilyPolicy(const string family,const MbTuningFamilyPolicy &policy)
  {
   if(!MbEnsureTuningFamilyStorage(family))
      return false;

   int h = FileOpen(MbTuningFamilyPolicyPath(family),FILE_COMMON | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;

   FileWrite(h,"enabled",(policy.enabled ? 1 : 0));
   FileWrite(h,"trusted_data",(policy.trusted_data ? 1 : 0));
   FileWrite(h,"freeze_new_changes",(policy.freeze_new_changes ? 1 : 0));
   FileWrite(h,"revision",policy.revision);
   FileWrite(h,"symbol_count",policy.symbol_count);
   FileWrite(h,"trusted_symbol_count",policy.trusted_symbol_count);
   FileWrite(h,"degraded_symbol_count",policy.degraded_symbol_count);
   FileWrite(h,"chaos_symbol_count",policy.chaos_symbol_count);
   FileWrite(h,"bad_spread_symbol_count",policy.bad_spread_symbol_count);
   FileWrite(h,"min_family_samples",policy.min_family_samples);
   FileWrite(h,"cooldown_sec",policy.cooldown_sec);
   FileWrite(h,"last_total_samples",policy.last_total_samples);
   FileWrite(h,"paper_mode_active",(policy.paper_mode_active ? 1 : 0));
   FileWrite(h,"aggregate_realized_pnl_day",DoubleToString(policy.aggregate_realized_pnl_day,2));
   FileWrite(h,"aggregate_equity_anchor_day",DoubleToString(policy.aggregate_equity_anchor_day,2));
   FileWrite(h,"family_daily_loss_pct",DoubleToString(policy.family_daily_loss_pct,6));
   FileWrite(h,"last_eval_at",(long)policy.last_eval_at);
   FileWrite(h,"last_action_at",(long)policy.last_action_at);
   FileWrite(h,"cooldown_until",(long)policy.cooldown_until);
   FileWrite(h,"dominant_confidence_cap",DoubleToString(policy.dominant_confidence_cap,6));
   FileWrite(h,"dominant_risk_cap",DoubleToString(policy.dominant_risk_cap,6));
   FileWrite(h,"breakout_family_tax",DoubleToString(policy.breakout_family_tax,6));
   FileWrite(h,"trend_family_tax",DoubleToString(policy.trend_family_tax,6));
   FileWrite(h,"rejection_range_boost",DoubleToString(policy.rejection_range_boost,6));
   FileWrite(h,"trust_reason",policy.trust_reason);
   FileWrite(h,"last_action_code",policy.last_action_code);
   FileWrite(h,"last_action_detail",policy.last_action_detail);
   FileClose(h);
   return true;
  }

bool MbLoadTuningFamilyPolicy(const string family,MbTuningFamilyPolicy &policy)
  {
   int h = FileOpen(MbTuningFamilyPolicyPath(family),FILE_COMMON | FILE_READ | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;

   while(!FileIsEnding(h))
     {
      string key = FileReadString(h);
      string value = FileReadString(h);
      if(key == "enabled") policy.enabled = (StringToInteger(value) != 0);
      else if(key == "trusted_data") policy.trusted_data = (StringToInteger(value) != 0);
      else if(key == "freeze_new_changes") policy.freeze_new_changes = (StringToInteger(value) != 0);
      else if(key == "revision") policy.revision = (int)StringToInteger(value);
      else if(key == "symbol_count") policy.symbol_count = (int)StringToInteger(value);
      else if(key == "trusted_symbol_count") policy.trusted_symbol_count = (int)StringToInteger(value);
      else if(key == "degraded_symbol_count") policy.degraded_symbol_count = (int)StringToInteger(value);
      else if(key == "chaos_symbol_count") policy.chaos_symbol_count = (int)StringToInteger(value);
      else if(key == "bad_spread_symbol_count") policy.bad_spread_symbol_count = (int)StringToInteger(value);
      else if(key == "min_family_samples") policy.min_family_samples = (int)StringToInteger(value);
      else if(key == "cooldown_sec") policy.cooldown_sec = (int)StringToInteger(value);
      else if(key == "last_total_samples") policy.last_total_samples = (int)StringToInteger(value);
      else if(key == "paper_mode_active") policy.paper_mode_active = (StringToInteger(value) != 0);
      else if(key == "aggregate_realized_pnl_day") policy.aggregate_realized_pnl_day = StringToDouble(value);
      else if(key == "aggregate_equity_anchor_day") policy.aggregate_equity_anchor_day = StringToDouble(value);
      else if(key == "family_daily_loss_pct") policy.family_daily_loss_pct = StringToDouble(value);
      else if(key == "last_eval_at") policy.last_eval_at = (datetime)StringToInteger(value);
      else if(key == "last_action_at") policy.last_action_at = (datetime)StringToInteger(value);
      else if(key == "cooldown_until") policy.cooldown_until = (datetime)StringToInteger(value);
      else if(key == "dominant_confidence_cap") policy.dominant_confidence_cap = StringToDouble(value);
      else if(key == "dominant_risk_cap") policy.dominant_risk_cap = StringToDouble(value);
      else if(key == "breakout_family_tax") policy.breakout_family_tax = StringToDouble(value);
      else if(key == "trend_family_tax") policy.trend_family_tax = StringToDouble(value);
      else if(key == "rejection_range_boost") policy.rejection_range_boost = StringToDouble(value);
      else if(key == "trust_reason") policy.trust_reason = value;
      else if(key == "last_action_code") policy.last_action_code = value;
      else if(key == "last_action_detail") policy.last_action_detail = value;
     }

   FileClose(h);
   return true;
  }

void MbEnsureTuningCoordinatorActionHeader(const int h)
  {
   if(h == INVALID_HANDLE || FileSize(h) > 0)
      return;

   FileWrite(
      h,
      "ts",
      "revision",
      "action_code",
      "action_detail",
      "trusted_data",
      "trust_reason",
      "family_count",
      "trusted_family_count",
      "degraded_family_count",
      "paper_mode_active",
      "aggregate_realized_pnl_day",
      "aggregate_equity_anchor_day",
      "fleet_daily_loss_pct",
      "global_confidence_cap",
      "global_risk_cap",
      "max_local_changes_per_cycle",
      "freeze_new_changes"
   );
  }

void MbAppendTuningCoordinatorActionEvent(const MbTuningCoordinatorState &state)
  {
   if(!MbEnsureTuningCoordinatorStorage())
      return;

   int h = FileOpen(MbTuningCoordinatorActionLogPath(),FILE_COMMON | FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;

   MbEnsureTuningCoordinatorActionHeader(h);
   FileSeek(h,0,SEEK_END);
   FileWrite(
      h,
      (long)TimeCurrent(),
      state.revision,
      state.last_action_code,
      state.last_action_detail,
      (state.trusted_data ? 1 : 0),
      state.trust_reason,
      state.family_count,
      state.trusted_family_count,
      state.degraded_family_count,
      (state.paper_mode_active ? 1 : 0),
      DoubleToString(state.aggregate_realized_pnl_day,2),
      DoubleToString(state.aggregate_equity_anchor_day,2),
      DoubleToString(state.fleet_daily_loss_pct,4),
      DoubleToString(state.global_confidence_cap,4),
      DoubleToString(state.global_risk_cap,4),
      state.max_local_changes_per_cycle,
      (state.freeze_new_changes ? 1 : 0)
   );
   FileClose(h);
  }

bool MbSaveTuningCoordinatorState(const MbTuningCoordinatorState &state)
  {
   if(!MbEnsureTuningCoordinatorStorage())
      return false;

   int h = FileOpen(MbTuningCoordinatorStatePath(),FILE_COMMON | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;

   FileWrite(h,"enabled",(state.enabled ? 1 : 0));
   FileWrite(h,"trusted_data",(state.trusted_data ? 1 : 0));
   FileWrite(h,"freeze_new_changes",(state.freeze_new_changes ? 1 : 0));
   FileWrite(h,"revision",state.revision);
   FileWrite(h,"family_count",state.family_count);
   FileWrite(h,"trusted_family_count",state.trusted_family_count);
   FileWrite(h,"degraded_family_count",state.degraded_family_count);
   FileWrite(h,"max_local_changes_per_cycle",state.max_local_changes_per_cycle);
   FileWrite(h,"cooldown_sec",state.cooldown_sec);
   FileWrite(h,"paper_mode_active",(state.paper_mode_active ? 1 : 0));
   FileWrite(h,"aggregate_realized_pnl_day",DoubleToString(state.aggregate_realized_pnl_day,2));
   FileWrite(h,"aggregate_equity_anchor_day",DoubleToString(state.aggregate_equity_anchor_day,2));
   FileWrite(h,"fleet_daily_loss_pct",DoubleToString(state.fleet_daily_loss_pct,6));
   FileWrite(h,"last_eval_at",(long)state.last_eval_at);
   FileWrite(h,"last_action_at",(long)state.last_action_at);
   FileWrite(h,"cooldown_until",(long)state.cooldown_until);
   FileWrite(h,"global_confidence_cap",DoubleToString(state.global_confidence_cap,6));
   FileWrite(h,"global_risk_cap",DoubleToString(state.global_risk_cap,6));
   FileWrite(h,"trust_reason",state.trust_reason);
   FileWrite(h,"last_action_code",state.last_action_code);
   FileWrite(h,"last_action_detail",state.last_action_detail);
   FileClose(h);
   return true;
  }

bool MbLoadTuningCoordinatorState(MbTuningCoordinatorState &state)
  {
   int h = FileOpen(MbTuningCoordinatorStatePath(),FILE_COMMON | FILE_READ | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;

   while(!FileIsEnding(h))
     {
      string key = FileReadString(h);
      string value = FileReadString(h);
      if(key == "enabled") state.enabled = (StringToInteger(value) != 0);
      else if(key == "trusted_data") state.trusted_data = (StringToInteger(value) != 0);
      else if(key == "freeze_new_changes") state.freeze_new_changes = (StringToInteger(value) != 0);
      else if(key == "revision") state.revision = (int)StringToInteger(value);
      else if(key == "family_count") state.family_count = (int)StringToInteger(value);
      else if(key == "trusted_family_count") state.trusted_family_count = (int)StringToInteger(value);
      else if(key == "degraded_family_count") state.degraded_family_count = (int)StringToInteger(value);
      else if(key == "max_local_changes_per_cycle") state.max_local_changes_per_cycle = (int)StringToInteger(value);
      else if(key == "cooldown_sec") state.cooldown_sec = (int)StringToInteger(value);
      else if(key == "paper_mode_active") state.paper_mode_active = (StringToInteger(value) != 0);
      else if(key == "aggregate_realized_pnl_day") state.aggregate_realized_pnl_day = StringToDouble(value);
      else if(key == "aggregate_equity_anchor_day") state.aggregate_equity_anchor_day = StringToDouble(value);
      else if(key == "fleet_daily_loss_pct") state.fleet_daily_loss_pct = StringToDouble(value);
      else if(key == "last_eval_at") state.last_eval_at = (datetime)StringToInteger(value);
      else if(key == "last_action_at") state.last_action_at = (datetime)StringToInteger(value);
      else if(key == "cooldown_until") state.cooldown_until = (datetime)StringToInteger(value);
      else if(key == "global_confidence_cap") state.global_confidence_cap = StringToDouble(value);
      else if(key == "global_risk_cap") state.global_risk_cap = StringToDouble(value);
      else if(key == "trust_reason") state.trust_reason = value;
      else if(key == "last_action_code") state.last_action_code = value;
      else if(key == "last_action_detail") state.last_action_detail = value;
     }

   FileClose(h);
   return true;
  }

#endif
