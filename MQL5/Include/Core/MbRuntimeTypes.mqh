#ifndef MB_RUNTIME_TYPES_INCLUDED
#define MB_RUNTIME_TYPES_INCLUDED

enum MbRuntimeMode
  {
   MB_MODE_BLOCKED = 0,
   MB_MODE_CAUTION = 1,
   MB_MODE_READY = 2,
   MB_MODE_CLOSE_ONLY = 3
  };

enum MbSignalSide
  {
   MB_SIGNAL_NONE = 0,
   MB_SIGNAL_BUY = 1,
   MB_SIGNAL_SELL = -1
  };

struct MbRuntimeState
  {
   string symbol;
   ulong magic;
   datetime started_at;
   datetime last_tick_at;
   datetime last_timer_at;
   datetime last_heartbeat_at;
   datetime last_state_save_at;
   datetime last_trade_attempt;
   datetime last_kill_switch_check;
   datetime last_core_contract_check;
   ulong last_closed_deal_ticket;
   datetime price_budget_sec_anchor;
   datetime price_budget_min_anchor;
   datetime order_budget_sec_anchor;
   datetime order_budget_min_anchor;
   datetime cooldown_until;
   datetime day_anchor;
   datetime session_anchor;
   long ticks_seen;
   long timer_cycles;
   int price_requests_sec;
   int price_requests_min;
   int order_requests_sec;
   int order_requests_min;
   int loss_streak;
   int exec_error_streak;
   int spread_anomaly_streak;
   int learning_sample_count;
   int learning_win_count;
   int learning_loss_count;
   double realized_pnl_lifetime;
   double realized_pnl_day;
   double realized_pnl_session;
   double capital_core_anchor;
   double equity_anchor_day;
   double equity_anchor_session;
   double effective_profit_buffer;
   double effective_risk_base;
   double effective_loss_allowance_multiplier;
   double coordinator_risk_cap;
   double execution_pressure;
   double learning_bias;
   double learning_confidence;
   double adaptive_risk_scale;
   double signal_confidence;
   double signal_risk_multiplier;
   double candle_score;
   double renko_score;
   int renko_run_length;
   bool renko_reversal_flag;
   bool paper_mode_active;
   bool trade_rights;
   bool paper_rights;
   bool observation_rights;
   bool kill_switch_cached_halt;
   bool kill_switch_cached_present;
   bool capital_core_contract_present;
   bool capital_core_contract_enabled;
   bool caution_mode;
   bool close_only;
   bool force_flatten;
   bool halt;
   string allowed_direction;
   string market_regime;
   string spread_regime;
   string execution_regime;
   string confidence_bucket;
   string last_setup_type;
   string candle_bias;
   string candle_quality_grade;
   string renko_bias;
   string renko_quality_grade;
   MbRuntimeMode mode;
  };

struct MbSymbolProfile
  {
   string symbol;
   ENUM_TIMEFRAMES trade_tf;
   double max_spread_points;
   double caution_spread_points;
   int deviation_points;
   double quotes_tolerance_pct;
   int max_tick_age_sec;
   double min_margin_free_pct;
   double hard_daily_loss_pct;
   double hard_session_loss_pct;
   int min_seconds_between_entries;
   string session_profile;
   int trade_window_start_hour;
   int trade_window_end_hour;
   bool friday_cutoff_enabled;
   int friday_cutoff_hour;
   bool kill_switch_required;
   string kill_switch_token_name;
   int kill_switch_max_age_sec;
   int max_price_requests_per_sec;
   int max_price_requests_per_min;
   int price_requests_eco_threshold_pct;
   int max_market_orders_per_sec;
   int max_market_orders_per_min;
   int market_orders_eco_threshold_pct;
  };

struct MbSignalDecision
  {
   bool valid;
   MbSignalSide side;
   double score;
   double confidence_score;
   double risk_multiplier;
   double candle_score;
   double renko_score;
   int renko_run_length;
   bool renko_reversal_flag;
   string market_regime;
   string spread_regime;
   string execution_regime;
   string confidence_bucket;
   string setup_type;
   string candle_bias;
   string candle_quality_grade;
   string renko_bias;
   string renko_quality_grade;
   string reason_code;
  };

struct MbExecutionCheck
  {
   bool allowed;
   ENUM_ORDER_TYPE_FILLING filling;
   long order_check_retcode;
   double margin_required;
   double expected_move_points;
   double modeled_slippage_points;
   double modeled_commission_points;
   double safety_margin_points;
   double modeled_total_cost_points;
   double benchmark_typical_move_points;
   double benchmark_time_stop_points;
   double benchmark_mfe_points;
   double benchmark_mae_points;
   string reason;
   string diag;
  };

struct MbExecutionResult
  {
   bool ok;
   long retcode;
   string retcode_name;
   string reason;
   int retries_used;
   double executed_price;
   double slippage_points;
   long order_send_ms;
  };

struct MbMarketSnapshot
  {
   bool valid;
   bool terminal_connected;
   bool term_trade_allowed;
   bool mql_trade_allowed;
   bool account_trade_allowed;
   bool raw_trade_permissions_ok;
   bool trade_permissions_ok;
   bool paper_runtime_override_active;
   long account_trade_mode;
   long symbol_trade_mode;
   int stops_level;
   int freeze_level;
   double margin_free;
   double equity;
   double bid;
   double ask;
   double spread_points;
   long terminal_ping_last_us;
   long terminal_ping_last_ms;
   long tick_time_msc;
   long tick_age_ms;
   double tick_value;
   double tick_size;
   double vol_step;
   double vol_min;
   double vol_max;
   string diag;
   datetime refreshed_at;
  };

struct MbLatencyProfile
  {
   long sample_count;
   long local_latency_us_sum;
   long local_latency_us_max;
   long order_send_ms_sum;
   long order_send_ms_max;
   long last_local_latency_us;
   long last_order_send_ms;
   long execution_attempt_count;
   long execution_ok_count;
   long execution_retry_sum;
   double execution_slippage_sum;
   double execution_slippage_max;
   datetime window_started_at;
  };

struct MbExecutionSummary
  {
   long latency_samples;
   long local_latency_us_avg;
   long local_latency_us_max;
   long order_send_ms_avg;
   long order_send_ms_max;
   long last_local_latency_us;
   long last_order_send_ms;
   long execution_attempt_count;
   long execution_ok_count;
   long execution_retry_avg_milli;
   long execution_slippage_points_avg_milli;
   long execution_slippage_points_max_milli;
  };

struct MbRuntimeControlState
  {
   bool halt;
   bool close_only;
   bool paper_only;
   bool force_flatten;
   bool trade_rights;
   bool paper_rights;
   bool observation_rights;
   double risk_cap;
   string requested_mode;
   string reason_code;
   string allowed_direction;
  };

struct MbKillSwitchState
  {
   bool armed;
   bool token_present;
   bool halt;
   string reason_code;
  };

struct MbRateGuardState
  {
   bool allowed;
   bool caution_mode;
   bool halt;
   string reason_code;
  };

string MbNormalizeAllowedDirection(const string raw_allowed_direction)
  {
   string normalized = raw_allowed_direction;
   StringToUpper(normalized);

   if(normalized == "BUY" || normalized == "LONG")
      return "BUY_ONLY";
   if(normalized == "SELL" || normalized == "SHORT")
      return "SELL_ONLY";
   if(normalized == "NONE" || normalized == "BLOCKED")
      return "NONE";
   if(normalized == "FLAT" || normalized == "FLAT_ONLY" || normalized == "CLOSE_ONLY")
      return "FLAT_ONLY";
   if(normalized == "BUY_ONLY" || normalized == "SELL_ONLY" || normalized == "BOTH")
      return normalized;

   return "BOTH";
  }

string MbResolveAllowedDirectionForState(const MbRuntimeState &state)
  {
   if(state.halt)
      return "NONE";
   if(state.close_only)
      return "FLAT_ONLY";
   return MbNormalizeAllowedDirection(state.allowed_direction);
  }

string MbResolveAllowedDirectionForControl(const MbRuntimeControlState &state)
  {
   if(state.halt)
      return "NONE";
   if(state.close_only)
      return "FLAT_ONLY";
   return MbNormalizeAllowedDirection(state.allowed_direction);
  }

void MbRuntimeReset(MbRuntimeState &state)
  {
   state.symbol = "";
   state.magic = 0;
   state.started_at = TimeCurrent();
   state.last_tick_at = 0;
   state.last_timer_at = 0;
   state.last_heartbeat_at = 0;
   state.last_state_save_at = 0;
   state.last_trade_attempt = 0;
   state.last_kill_switch_check = 0;
   state.last_core_contract_check = 0;
   state.last_closed_deal_ticket = 0;
   state.price_budget_sec_anchor = 0;
   state.price_budget_min_anchor = 0;
   state.order_budget_sec_anchor = 0;
   state.order_budget_min_anchor = 0;
   state.cooldown_until = 0;
   state.day_anchor = 0;
   state.session_anchor = 0;
   state.ticks_seen = 0;
   state.timer_cycles = 0;
   state.price_requests_sec = 0;
   state.price_requests_min = 0;
   state.order_requests_sec = 0;
   state.order_requests_min = 0;
   state.loss_streak = 0;
   state.exec_error_streak = 0;
   state.spread_anomaly_streak = 0;
   state.learning_sample_count = 0;
   state.learning_win_count = 0;
   state.learning_loss_count = 0;
   state.realized_pnl_lifetime = 0.0;
   state.realized_pnl_day = 0.0;
   state.realized_pnl_session = 0.0;
   state.capital_core_anchor = 0.0;
   state.equity_anchor_day = 0.0;
   state.equity_anchor_session = 0.0;
   state.effective_profit_buffer = 0.0;
   state.effective_risk_base = 0.0;
   state.effective_loss_allowance_multiplier = 1.0;
   state.coordinator_risk_cap = 1.0;
   state.execution_pressure = 0.0;
   state.learning_bias = 0.0;
   state.learning_confidence = 0.0;
   state.adaptive_risk_scale = 1.0;
   state.signal_confidence = 0.0;
   state.signal_risk_multiplier = 1.0;
   state.candle_score = 0.0;
   state.renko_score = 0.0;
   state.renko_run_length = 0;
   state.renko_reversal_flag = false;
   state.paper_mode_active = false;
   state.trade_rights = true;
   state.paper_rights = false;
   state.observation_rights = true;
   state.kill_switch_cached_halt = false;
   state.kill_switch_cached_present = false;
   state.capital_core_contract_present = false;
   state.capital_core_contract_enabled = false;
   state.caution_mode = false;
   state.close_only = false;
   state.force_flatten = false;
   state.halt = false;
   state.allowed_direction = "BOTH";
   state.market_regime = "UNKNOWN";
   state.spread_regime = "UNKNOWN";
   state.execution_regime = "UNKNOWN";
   state.confidence_bucket = "LOW";
   state.last_setup_type = "NONE";
   state.candle_bias = "NONE";
   state.candle_quality_grade = "UNKNOWN";
   state.renko_bias = "NONE";
   state.renko_quality_grade = "UNKNOWN";
   state.mode = MB_MODE_READY;
  }

void MbSymbolProfileReset(MbSymbolProfile &profile)
  {
   profile.symbol = "";
   profile.trade_tf = PERIOD_M5;
   profile.max_spread_points = 0.0;
   profile.caution_spread_points = 0.0;
   profile.deviation_points = 20;
   profile.quotes_tolerance_pct = 0.10;
   profile.max_tick_age_sec = 5;
   profile.min_margin_free_pct = 120.0;
   profile.hard_daily_loss_pct = 2.0;
   profile.hard_session_loss_pct = 1.0;
   profile.min_seconds_between_entries = 60;
   profile.session_profile = "UNSPECIFIED";
   profile.trade_window_start_hour = 0;
   profile.trade_window_end_hour = 23;
   profile.friday_cutoff_enabled = true;
   profile.friday_cutoff_hour = 16;
   profile.kill_switch_required = false;
   profile.kill_switch_token_name = "";
   profile.kill_switch_max_age_sec = 120;
   profile.max_price_requests_per_sec = 8;
   profile.max_price_requests_per_min = 120;
   profile.price_requests_eco_threshold_pct = 80;
   profile.max_market_orders_per_sec = 2;
   profile.max_market_orders_per_min = 12;
   profile.market_orders_eco_threshold_pct = 80;
  }

void MbSignalDecisionReset(MbSignalDecision &decision)
  {
   decision.valid = false;
   decision.side = MB_SIGNAL_NONE;
   decision.score = 0.0;
   decision.confidence_score = 0.0;
   decision.risk_multiplier = 1.0;
   decision.candle_score = 0.0;
   decision.renko_score = 0.0;
   decision.renko_run_length = 0;
   decision.renko_reversal_flag = false;
   decision.market_regime = "UNKNOWN";
   decision.spread_regime = "UNKNOWN";
   decision.execution_regime = "UNKNOWN";
   decision.confidence_bucket = "LOW";
   decision.setup_type = "NONE";
   decision.candle_bias = "NONE";
   decision.candle_quality_grade = "UNKNOWN";
   decision.renko_bias = "NONE";
   decision.renko_quality_grade = "UNKNOWN";
   decision.reason_code = "NONE";
  }

void MbExecutionCheckReset(MbExecutionCheck &check)
  {
   check.allowed = false;
   check.filling = ORDER_FILLING_RETURN;
   check.order_check_retcode = 0;
   check.margin_required = 0.0;
   check.expected_move_points = 0.0;
   check.modeled_slippage_points = 0.0;
   check.modeled_commission_points = 0.0;
   check.safety_margin_points = 0.0;
   check.modeled_total_cost_points = 0.0;
   check.benchmark_typical_move_points = 0.0;
   check.benchmark_time_stop_points = 0.0;
   check.benchmark_mfe_points = 0.0;
   check.benchmark_mae_points = 0.0;
   check.reason = "UNKNOWN";
   check.diag = "";
  }

void MbExecutionResultReset(MbExecutionResult &result)
  {
   result.ok = false;
   result.retcode = 0;
   result.retcode_name = "NOT_SENT";
   result.reason = "NOT_SENT";
   result.retries_used = 0;
   result.executed_price = 0.0;
   result.slippage_points = 0.0;
   result.order_send_ms = 0;
  }

void MbMarketSnapshotReset(MbMarketSnapshot &snapshot)
  {
   snapshot.valid = false;
   snapshot.terminal_connected = false;
   snapshot.term_trade_allowed = false;
   snapshot.mql_trade_allowed = false;
   snapshot.account_trade_allowed = false;
   snapshot.raw_trade_permissions_ok = false;
   snapshot.trade_permissions_ok = false;
   snapshot.paper_runtime_override_active = false;
   snapshot.account_trade_mode = 0;
   snapshot.symbol_trade_mode = 0;
   snapshot.stops_level = 0;
   snapshot.freeze_level = 0;
   snapshot.margin_free = 0.0;
   snapshot.equity = 0.0;
   snapshot.bid = 0.0;
   snapshot.ask = 0.0;
   snapshot.spread_points = 0.0;
   snapshot.terminal_ping_last_us = 0;
   snapshot.terminal_ping_last_ms = 0;
   snapshot.tick_time_msc = 0;
   snapshot.tick_age_ms = 0;
   snapshot.tick_value = 0.0;
   snapshot.tick_size = 0.0;
   snapshot.vol_step = 0.0;
   snapshot.vol_min = 0.0;
   snapshot.vol_max = 0.0;
   snapshot.diag = "";
   snapshot.refreshed_at = 0;
  }

void MbLatencyProfileReset(MbLatencyProfile &profile)
  {
   profile.sample_count = 0;
   profile.local_latency_us_sum = 0;
   profile.local_latency_us_max = 0;
   profile.order_send_ms_sum = 0;
   profile.order_send_ms_max = 0;
   profile.last_local_latency_us = 0;
   profile.last_order_send_ms = 0;
   profile.execution_attempt_count = 0;
   profile.execution_ok_count = 0;
   profile.execution_retry_sum = 0;
   profile.execution_slippage_sum = 0.0;
   profile.execution_slippage_max = 0.0;
   profile.window_started_at = TimeCurrent();
  }

void MbRuntimeControlStateReset(MbRuntimeControlState &state)
  {
   state.halt = false;
   state.close_only = false;
   state.paper_only = false;
   state.force_flatten = false;
   state.trade_rights = true;
   state.paper_rights = false;
   state.observation_rights = true;
   state.risk_cap = 1.0;
   state.requested_mode = "RUN";
   state.reason_code = "OK";
   state.allowed_direction = "BOTH";
  }

void MbKillSwitchStateReset(MbKillSwitchState &state)
  {
   state.armed = false;
   state.token_present = false;
   state.halt = false;
   state.reason_code = "OK";
  }

void MbRateGuardStateReset(MbRateGuardState &state)
  {
   state.allowed = true;
   state.caution_mode = false;
   state.halt = false;
   state.reason_code = "OK";
  }

#endif
