#ifndef MB_TUNING_TYPES_INCLUDED
#define MB_TUNING_TYPES_INCLUDED

#include "MbRuntimeTypes.mqh"

struct MbReasonTriple
  {
   string domain;
   string reason_class;
   string reason_code;
  };

struct MbTrustState
  {
   string state;
   string reason_code;
   double conversion_ratio;
   double recent_conversion_ratio;
   double dirty_ratio;
   double blocked_ratio;
   double min_conversion_ratio;
   double max_dirty_ratio;
   int stale_seconds;
   int min_conversion_candidates;
   int sample_count;
   int closed_lessons_count;
  };

struct MbExecutionQualityState
  {
   string state;
   string reason_code;
   long ping_ms;
   long tick_age_ms;
   double slippage_proxy;
   double retry_proxy;
   double execution_pressure;
  };

struct MbCostPressureState
  {
   string state;
   string reason_code;
   double spread_now;
   double spread_vs_typical_move;
   double spread_vs_time_stop;
   double spread_vs_mfe;
   double spread_vs_mae;
  };

struct MbTuningAdaptationContract
  {
   double tax_step_max;
   double boost_step_max;
   double cap_step_max;
   double floor_step_max;
   int min_closed_lessons;
   int min_clean_reviews;
   int cooldown_after_change_sec;
   int max_changes_per_window;
   int change_window_sec;
   bool requires_trusted_state;
   bool requires_execution_not_bad;
   bool forbid_when_cost_non_representative;
  };

struct MbTuningLocalPolicy
  {
   bool enabled;
   bool trusted_data;
   bool require_aux_support_for_trend;
   bool require_support_for_rejection;
   bool require_non_poor_renko_for_breakout;
   bool require_non_poor_candle_for_breakout;
   bool require_non_poor_candle_for_trend;
   bool require_non_poor_candle_for_range;
   bool require_non_poor_renko_for_range;
   int revision;
   int min_bucket_samples;
   int cooldown_sec;
   int last_learning_sample_count;
   int last_observation_rows;
   int last_bucket_rows;
   int last_candidate_rows;
   int last_candidate_risk_block_rows;
   int last_candidate_score_gate_rows;
   int last_candidate_dirty_rows;
   int last_paper_open_rows;
   int last_logged_learning_sample_count;
   int last_logged_observation_rows;
   int last_logged_bucket_rows;
   int last_logged_candidate_rows;
   int last_logged_candidate_risk_block_rows;
   int last_logged_candidate_score_gate_rows;
   int last_logged_candidate_dirty_rows;
   int last_logged_paper_open_rows;
   bool last_logged_trusted;
   datetime last_eval_at;
   datetime last_action_at;
   datetime cooldown_until;
   datetime last_deckhand_log_at;
   double breakout_global_tax;
   double breakout_chaos_tax;
   double breakout_range_tax;
   double breakout_conflict_tax;
   double trend_breakout_tax;
   double trend_chaos_tax;
   double trend_caution_tax;
   double trend_no_aux_tax;
   double range_chaos_tax;
   double range_trend_tax;
   double range_confidence_floor;
   double index_opening_impulse_tax;
   double index_noon_transition_tax;
   double rejection_range_boost;
   double confidence_cap;
   double risk_cap;
   string trust_reason;
   string trust_reason_domain;
   string trust_reason_class;
   string last_logged_reason_code;
   string last_logged_reason_domain;
   string last_logged_reason_class;
   string last_action_code;
   string last_action_detail;
   string last_trust_state;
   string last_execution_quality_state;
   string last_cost_pressure_state;
   int reason_streak;
   int action_streak;
   int blocked_cycles;
   int trusted_cycles;
   datetime adaptation_window_started_at;
   int adaptation_changes_in_window;
   string last_focus_setup_type;
   string last_focus_market_regime;
   string last_hypothesis_code;
   string last_hypothesis_detail;
   string last_counterfactual_code;
   string last_counterfactual_detail;
   bool experiment_active;
   int experiment_revision;
   int experiment_review_count;
   datetime experiment_started_at;
   int experiment_baseline_samples;
   int experiment_baseline_wins;
   int experiment_baseline_losses;
   int experiment_baseline_paper_open_rows;
   double experiment_baseline_realized_pnl_lifetime;
   string experiment_baseline_trust_state;
   string experiment_baseline_execution_quality_state;
   string experiment_baseline_cost_pressure_state;
   string experiment_action_code;
   string experiment_focus_setup_type;
   string experiment_focus_market_regime;
   string experiment_cause_domain;
   string experiment_cause_class;
   string experiment_cause_code;
   string experiment_last_review_domain;
   string experiment_last_review_class;
   string experiment_last_review_code;
   string experiment_failure_domain;
   string experiment_failure_class;
   string experiment_failure_code;
   string experiment_status;
   datetime last_failed_at;
   datetime avoid_repeat_until;
   string last_failed_action_code;
   string last_failed_focus_setup_type;
   string last_failed_focus_market_regime;
   string last_failed_cause_domain;
   string last_failed_cause_class;
   string last_failed_cause_code;
  };

struct MbTuningDeckhandReport
  {
   bool trusted;
   bool rebuilt_bucket_summary;
   int total_rows;
   int observation_rows;
   int invalid_rows;
   int none_unknown_rows;
   int bucket_rows;
   int candidate_rows;
   int candidate_invalid_rows;
   int candidate_risk_block_rows;
   int candidate_score_gate_rows;
   int candidate_dirty_rows;
   int candidate_dirty_candle_rows;
   int candidate_dirty_renko_rows;
   int candidate_dirty_hybrid_rows;
   int candidate_dirty_spread_rows;
   int paper_open_rows;
   int decision_risk_contract_block_rows;
   int decision_portfolio_heat_block_rows;
   int decision_rate_guard_block_rows;
   double execution_pressure;
   int exec_error_streak;
   int spread_anomaly_streak;
   MbReasonTriple normalized_reason;
   MbTrustState trust_state;
   MbExecutionQualityState execution_quality;
   MbCostPressureState cost_pressure;
   string reason_code;
   datetime serviced_at;
  };

struct MbTuningBucketStats
  {
   string setup_type;
   string market_regime;
   int samples;
   int wins;
   int losses;
   double pnl_sum;
   double avg_pnl;
  };

struct MbTuningSymbolSnapshot
  {
   string symbol;
   string family;
   bool runtime_present;
   bool local_policy_present;
   bool local_policy_trusted;
   int learning_sample_count;
   int learning_win_count;
   int learning_loss_count;
   int loss_streak;
   bool paper_mode_active;
   double adaptive_risk_scale;
   double learning_bias;
   double realized_pnl_day;
   double equity_anchor_day;
   double daily_loss_pct;
   string market_regime;
   string spread_regime;
   string execution_regime;
   string last_setup_type;
   double confidence_cap;
   double risk_cap;
   double breakout_tax;
   double trend_tax;
   double rejection_boost;
   string trust_reason;
  };

struct MbTuningFamilyPolicy
  {
   bool enabled;
   bool trusted_data;
   bool freeze_new_changes;
   int revision;
   int symbol_count;
   int trusted_symbol_count;
   int degraded_symbol_count;
   int chaos_symbol_count;
   int bad_spread_symbol_count;
   int min_family_samples;
   int cooldown_sec;
   int last_total_samples;
   bool paper_mode_active;
   double aggregate_realized_pnl_day;
   double aggregate_equity_anchor_day;
   double family_daily_loss_pct;
   datetime last_eval_at;
   datetime last_action_at;
   datetime cooldown_until;
   double dominant_confidence_cap;
   double dominant_risk_cap;
   double breakout_family_tax;
   double trend_family_tax;
   double rejection_range_boost;
   string trust_reason;
   string last_action_code;
   string last_action_detail;
  };

struct MbTuningCoordinatorState
  {
   bool enabled;
   bool trusted_data;
   bool freeze_new_changes;
   int revision;
   int family_count;
   int trusted_family_count;
   int degraded_family_count;
   int max_local_changes_per_cycle;
   int cooldown_sec;
   bool paper_mode_active;
   double aggregate_realized_pnl_day;
   double aggregate_equity_anchor_day;
   double fleet_daily_loss_pct;
   datetime last_eval_at;
   datetime last_action_at;
   datetime cooldown_until;
   double global_confidence_cap;
   double global_risk_cap;
   string trust_reason;
   string last_action_code;
   string last_action_detail;
  };

void MbTuningLocalPolicyReset(MbTuningLocalPolicy &policy)
  {
   policy.enabled = true;
   policy.trusted_data = false;
   policy.require_aux_support_for_trend = false;
   policy.require_support_for_rejection = false;
   policy.require_non_poor_renko_for_breakout = false;
   policy.require_non_poor_candle_for_breakout = false;
   policy.require_non_poor_candle_for_trend = false;
   policy.require_non_poor_candle_for_range = false;
   policy.require_non_poor_renko_for_range = false;
   policy.revision = 0;
   policy.min_bucket_samples = 6;
   policy.cooldown_sec = 900;
   policy.last_learning_sample_count = 0;
   policy.last_observation_rows = 0;
   policy.last_bucket_rows = 0;
   policy.last_candidate_rows = 0;
   policy.last_candidate_risk_block_rows = 0;
   policy.last_candidate_score_gate_rows = 0;
   policy.last_candidate_dirty_rows = 0;
   policy.last_paper_open_rows = 0;
   policy.last_logged_learning_sample_count = 0;
   policy.last_logged_observation_rows = 0;
   policy.last_logged_bucket_rows = 0;
   policy.last_logged_candidate_rows = 0;
   policy.last_logged_candidate_risk_block_rows = 0;
   policy.last_logged_candidate_score_gate_rows = 0;
   policy.last_logged_candidate_dirty_rows = 0;
   policy.last_logged_paper_open_rows = 0;
   policy.last_logged_trusted = false;
   policy.last_eval_at = 0;
   policy.last_action_at = 0;
   policy.cooldown_until = 0;
   policy.last_deckhand_log_at = 0;
   policy.breakout_global_tax = 0.0;
   policy.breakout_chaos_tax = 0.0;
   policy.breakout_range_tax = 0.0;
   policy.breakout_conflict_tax = 0.0;
   policy.trend_breakout_tax = 0.0;
   policy.trend_chaos_tax = 0.0;
   policy.trend_caution_tax = 0.0;
   policy.trend_no_aux_tax = 0.0;
   policy.range_chaos_tax = 0.0;
   policy.range_trend_tax = 0.0;
   policy.range_confidence_floor = 0.0;
   policy.index_opening_impulse_tax = 0.0;
   policy.index_noon_transition_tax = 0.0;
   policy.rejection_range_boost = 0.0;
   policy.confidence_cap = 1.0;
   policy.risk_cap = 1.0;
   policy.trust_reason = "UNASSESSED";
   policy.trust_reason_domain = "DATA";
   policy.trust_reason_class = "TRUST";
   policy.last_logged_reason_code = "UNASSESSED";
   policy.last_logged_reason_domain = "DATA";
   policy.last_logged_reason_class = "TRUST";
   policy.last_action_code = "NONE";
   policy.last_action_detail = "";
   policy.last_trust_state = "UNASSESSED";
   policy.last_execution_quality_state = "UNASSESSED";
   policy.last_cost_pressure_state = "UNASSESSED";
   policy.reason_streak = 0;
   policy.action_streak = 0;
   policy.blocked_cycles = 0;
   policy.trusted_cycles = 0;
   policy.adaptation_window_started_at = 0;
   policy.adaptation_changes_in_window = 0;
   policy.last_focus_setup_type = "NONE";
   policy.last_focus_market_regime = "UNKNOWN";
   policy.last_hypothesis_code = "UNASSESSED";
   policy.last_hypothesis_detail = "";
   policy.last_counterfactual_code = "UNASSESSED";
   policy.last_counterfactual_detail = "";
   policy.experiment_active = false;
   policy.experiment_revision = 0;
   policy.experiment_review_count = 0;
   policy.experiment_started_at = 0;
   policy.experiment_baseline_samples = 0;
   policy.experiment_baseline_wins = 0;
   policy.experiment_baseline_losses = 0;
   policy.experiment_baseline_paper_open_rows = 0;
   policy.experiment_baseline_realized_pnl_lifetime = 0.0;
   policy.experiment_baseline_trust_state = "UNASSESSED";
   policy.experiment_baseline_execution_quality_state = "UNASSESSED";
   policy.experiment_baseline_cost_pressure_state = "UNASSESSED";
   policy.experiment_action_code = "NONE";
   policy.experiment_focus_setup_type = "NONE";
   policy.experiment_focus_market_regime = "UNKNOWN";
   policy.experiment_cause_domain = "MODE";
   policy.experiment_cause_class = "UNKNOWN";
   policy.experiment_cause_code = "UNASSESSED";
   policy.experiment_last_review_domain = "MODE";
   policy.experiment_last_review_class = "OBSERVATION";
   policy.experiment_last_review_code = "EXPERIMENT_IDLE";
   policy.experiment_failure_domain = "MODE";
   policy.experiment_failure_class = "NONE";
   policy.experiment_failure_code = "NONE";
   policy.experiment_status = "IDLE";
   policy.last_failed_at = 0;
   policy.avoid_repeat_until = 0;
   policy.last_failed_action_code = "NONE";
   policy.last_failed_focus_setup_type = "NONE";
   policy.last_failed_focus_market_regime = "UNKNOWN";
   policy.last_failed_cause_domain = "MODE";
   policy.last_failed_cause_class = "UNKNOWN";
   policy.last_failed_cause_code = "UNASSESSED";
  }

void MbTuningDeckhandReportReset(MbTuningDeckhandReport &report)
  {
   report.trusted = false;
   report.rebuilt_bucket_summary = false;
   report.total_rows = 0;
   report.observation_rows = 0;
   report.invalid_rows = 0;
   report.none_unknown_rows = 0;
   report.bucket_rows = 0;
   report.candidate_rows = 0;
   report.candidate_invalid_rows = 0;
   report.candidate_risk_block_rows = 0;
   report.candidate_score_gate_rows = 0;
   report.candidate_dirty_rows = 0;
   report.candidate_dirty_candle_rows = 0;
   report.candidate_dirty_renko_rows = 0;
   report.candidate_dirty_hybrid_rows = 0;
   report.candidate_dirty_spread_rows = 0;
   report.paper_open_rows = 0;
   report.decision_risk_contract_block_rows = 0;
   report.decision_portfolio_heat_block_rows = 0;
   report.decision_rate_guard_block_rows = 0;
   report.execution_pressure = 0.0;
   report.exec_error_streak = 0;
   report.spread_anomaly_streak = 0;
   report.normalized_reason.domain = "DATA";
   report.normalized_reason.reason_class = "TRUST";
   report.normalized_reason.reason_code = "UNASSESSED";
   report.trust_state.state = "UNASSESSED";
   report.trust_state.reason_code = "UNASSESSED";
   report.trust_state.conversion_ratio = 0.0;
   report.trust_state.recent_conversion_ratio = 0.0;
   report.trust_state.dirty_ratio = 0.0;
   report.trust_state.blocked_ratio = 0.0;
   report.trust_state.min_conversion_ratio = 0.0;
   report.trust_state.max_dirty_ratio = 0.0;
   report.trust_state.stale_seconds = 0;
   report.trust_state.min_conversion_candidates = 0;
   report.trust_state.sample_count = 0;
   report.trust_state.closed_lessons_count = 0;
   report.execution_quality.state = "UNASSESSED";
   report.execution_quality.reason_code = "UNASSESSED";
   report.execution_quality.ping_ms = 0;
   report.execution_quality.tick_age_ms = 0;
   report.execution_quality.slippage_proxy = 0.0;
   report.execution_quality.retry_proxy = 0.0;
   report.execution_quality.execution_pressure = 0.0;
   report.cost_pressure.state = "UNASSESSED";
   report.cost_pressure.reason_code = "UNASSESSED";
   report.cost_pressure.spread_now = 0.0;
   report.cost_pressure.spread_vs_typical_move = 0.0;
   report.cost_pressure.spread_vs_time_stop = 0.0;
   report.cost_pressure.spread_vs_mfe = 0.0;
   report.cost_pressure.spread_vs_mae = 0.0;
   report.reason_code = "UNASSESSED";
   report.serviced_at = 0;
  }

void MbTuningAdaptationContractReset(MbTuningAdaptationContract &contract)
  {
   contract.tax_step_max = 0.03;
   contract.boost_step_max = 0.03;
   contract.cap_step_max = 0.05;
   contract.floor_step_max = 0.06;
   contract.min_closed_lessons = 6;
   contract.min_clean_reviews = 2;
   contract.cooldown_after_change_sec = 900;
   contract.max_changes_per_window = 3;
   contract.change_window_sec = 21600;
   contract.requires_trusted_state = true;
   contract.requires_execution_not_bad = true;
   contract.forbid_when_cost_non_representative = true;
  }

void MbTuningBucketStatsReset(MbTuningBucketStats &stats)
  {
   stats.setup_type = "";
   stats.market_regime = "";
   stats.samples = 0;
   stats.wins = 0;
   stats.losses = 0;
   stats.pnl_sum = 0.0;
   stats.avg_pnl = 0.0;
  }

void MbTuningSymbolSnapshotReset(MbTuningSymbolSnapshot &snapshot)
  {
   snapshot.symbol = "";
   snapshot.family = "";
   snapshot.runtime_present = false;
   snapshot.local_policy_present = false;
   snapshot.local_policy_trusted = false;
   snapshot.learning_sample_count = 0;
   snapshot.learning_win_count = 0;
   snapshot.learning_loss_count = 0;
   snapshot.loss_streak = 0;
   snapshot.paper_mode_active = false;
   snapshot.adaptive_risk_scale = 1.0;
   snapshot.learning_bias = 0.0;
   snapshot.realized_pnl_day = 0.0;
   snapshot.equity_anchor_day = 0.0;
   snapshot.daily_loss_pct = 0.0;
   snapshot.market_regime = "UNKNOWN";
   snapshot.spread_regime = "UNKNOWN";
   snapshot.execution_regime = "UNKNOWN";
   snapshot.last_setup_type = "NONE";
   snapshot.confidence_cap = 1.0;
   snapshot.risk_cap = 1.0;
   snapshot.breakout_tax = 0.0;
   snapshot.trend_tax = 0.0;
   snapshot.rejection_boost = 0.0;
   snapshot.trust_reason = "UNASSESSED";
  }

void MbTuningFamilyPolicyReset(MbTuningFamilyPolicy &policy)
  {
   policy.enabled = true;
   policy.trusted_data = false;
   policy.freeze_new_changes = false;
   policy.revision = 0;
   policy.symbol_count = 0;
   policy.trusted_symbol_count = 0;
   policy.degraded_symbol_count = 0;
   policy.chaos_symbol_count = 0;
   policy.bad_spread_symbol_count = 0;
   policy.min_family_samples = 18;
   policy.cooldown_sec = 1800;
   policy.last_total_samples = 0;
   policy.paper_mode_active = false;
   policy.aggregate_realized_pnl_day = 0.0;
   policy.aggregate_equity_anchor_day = 0.0;
   policy.family_daily_loss_pct = 0.0;
   policy.last_eval_at = 0;
   policy.last_action_at = 0;
   policy.cooldown_until = 0;
   policy.dominant_confidence_cap = 1.0;
   policy.dominant_risk_cap = 1.0;
   policy.breakout_family_tax = 0.0;
   policy.trend_family_tax = 0.0;
   policy.rejection_range_boost = 0.0;
   policy.trust_reason = "UNASSESSED";
   policy.last_action_code = "NONE";
   policy.last_action_detail = "";
  }

void MbTuningCoordinatorStateReset(MbTuningCoordinatorState &state)
  {
   state.enabled = true;
   state.trusted_data = false;
   state.freeze_new_changes = false;
   state.revision = 0;
   state.family_count = 0;
   state.trusted_family_count = 0;
   state.degraded_family_count = 0;
   state.max_local_changes_per_cycle = 1;
   state.cooldown_sec = 1800;
   state.paper_mode_active = false;
   state.aggregate_realized_pnl_day = 0.0;
   state.aggregate_equity_anchor_day = 0.0;
   state.fleet_daily_loss_pct = 0.0;
   state.last_eval_at = 0;
   state.last_action_at = 0;
   state.cooldown_until = 0;
   state.global_confidence_cap = 1.0;
   state.global_risk_cap = 1.0;
   state.trust_reason = "UNASSESSED";
   state.last_action_code = "NONE";
   state.last_action_detail = "";
  }

#endif
