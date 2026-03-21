#ifndef MB_EXECUTION_SUMMARY_PLANE_INCLUDED
#define MB_EXECUTION_SUMMARY_PLANE_INCLUDED

#include "MbRuntimeTypes.mqh"
#include "MbStorage.mqh"
#include "MbStatusPlane.mqh"
#include "MbLatencyProfile.mqh"
#include "MbTuningEpistemology.mqh"

void MbFlushExecutionSummary(
   const MbSymbolProfile &profile,
   const MbRuntimeState &state,
   const MbMarketSnapshot &snapshot,
   const MbTuningLocalPolicy &policy,
   const MbLatencyProfile &latency,
   const string reason_code
)
  {
   MbExecutionSummary summary;
   MbBuildExecutionSummary(latency,summary);
   MbReasonTriple normalized_reason;
   MbExecutionQualityState execution_quality;
   MbCostPressureState cost_pressure;
   MbBuildRuntimeEpistemicSnapshot(profile.symbol,state,snapshot,policy,reason_code,normalized_reason,execution_quality,cost_pressure);

   int h = FileOpen(MbStateFilePath(profile.symbol,"execution_summary.json"), FILE_COMMON | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;
   string payload = StringFormat(
      "{\"schema_version\":\"1.2\",\"symbol\":\"%s\",\"runtime_mode\":\"%s\",\"session_profile\":\"%s\",\"reason_code\":\"%s\",\"reason_domain\":\"%s\",\"reason_class\":\"%s\",\"trust_state\":\"%s\",\"trust_reason\":\"%s\",\"execution_quality_state\":\"%s\",\"execution_quality_reason_code\":\"%s\",\"cost_pressure_state\":\"%s\",\"cost_pressure_reason_code\":\"%s\",\"cooldown_left_sec\":%d,\"incident_pressure\":%d,\"execution_pressure\":%.4f,\"learning_bias\":%.4f,\"learning_confidence\":%.4f,\"learning_sample_count\":%d,\"learning_win_count\":%d,\"learning_loss_count\":%d,\"adaptive_risk_scale\":%.4f,\"coordinator_risk_cap\":%.4f,\"signal_confidence\":%.4f,\"signal_risk_multiplier\":%.4f,\"trade_rights\":%s,\"paper_rights\":%s,\"observation_rights\":%s,\"market_regime\":\"%s\",\"spread_regime\":\"%s\",\"execution_regime\":\"%s\",\"confidence_bucket\":\"%s\",\"last_setup_type\":\"%s\",\"candle_bias\":\"%s\",\"candle_quality_grade\":\"%s\",\"candle_score\":%.4f,\"renko_bias\":\"%s\",\"renko_quality_grade\":\"%s\",\"renko_score\":%.4f,\"renko_run_length\":%d,\"renko_reversal_flag\":%s",
      profile.symbol,
      MbRuntimeModeLabelForState(state),
      profile.session_profile,
      reason_code,
      normalized_reason.domain,
      normalized_reason.reason_class,
      policy.last_trust_state,
      policy.trust_reason,
      execution_quality.state,
      execution_quality.reason_code,
      cost_pressure.state,
      cost_pressure.reason_code,
      MbCooldownLeftSec(state),
      MbIncidentPressure(state),
      state.execution_pressure,
      state.learning_bias,
      state.learning_confidence,
      state.learning_sample_count,
      state.learning_win_count,
      state.learning_loss_count,
      state.adaptive_risk_scale,
      state.coordinator_risk_cap,
      state.signal_confidence,
      state.signal_risk_multiplier,
      MbJsonBool(state.trade_rights),
      MbJsonBool(state.paper_rights),
      MbJsonBool(state.observation_rights),
      state.market_regime,
      state.spread_regime,
      state.execution_regime,
      state.confidence_bucket,
      state.last_setup_type,
      state.candle_bias,
      state.candle_quality_grade,
      state.candle_score,
      state.renko_bias,
      state.renko_quality_grade,
      state.renko_score,
      state.renko_run_length,
      (state.renko_reversal_flag ? "true" : "false")
   );
   payload += StringFormat(
      ",\"latency_samples\":%I64d,\"local_latency_us_avg\":%I64d,\"local_latency_us_max\":%I64d,\"order_send_ms_avg\":%I64d,\"order_send_ms_max\":%I64d,\"last_local_latency_us\":%I64d,\"last_order_send_ms\":%I64d,\"execution_attempt_count\":%I64d,\"execution_ok_count\":%I64d,\"execution_retry_avg\":%.3f,\"execution_slippage_points_avg\":%.3f,\"execution_slippage_points_max\":%.3f,\"spread_points\":%.2f,\"tick_age_ms\":%I64d,\"terminal_connected\":%s,\"terminal_ping_ms\":%I64d,\"cache_valid\":%s,\"trade_permissions_ok\":%s,\"raw_trade_permissions_ok\":%s,\"paper_runtime_override_active\":%s,\"term_trade_allowed\":%s,\"mql_trade_allowed\":%s,\"account_trade_allowed\":%s",
      summary.latency_samples,
      summary.local_latency_us_avg,
      summary.local_latency_us_max,
      summary.order_send_ms_avg,
      summary.order_send_ms_max,
      summary.last_local_latency_us,
      summary.last_order_send_ms,
      summary.execution_attempt_count,
      summary.execution_ok_count,
      (summary.execution_retry_avg_milli / 1000.0),
      (summary.execution_slippage_points_avg_milli / 1000.0),
      (summary.execution_slippage_points_max_milli / 1000.0),
      snapshot.spread_points,
      snapshot.tick_age_ms,
      MbJsonBool(snapshot.terminal_connected),
      snapshot.terminal_ping_last_ms,
      MbJsonBool(snapshot.valid),
      MbJsonBool(snapshot.trade_permissions_ok),
      MbJsonBool(snapshot.raw_trade_permissions_ok),
      MbJsonBool(snapshot.paper_runtime_override_active),
      MbJsonBool(snapshot.term_trade_allowed),
      MbJsonBool(snapshot.mql_trade_allowed),
      MbJsonBool(snapshot.account_trade_allowed)
   );
   payload += StringFormat(
      ",\"loss_streak\":%d,\"exec_error_streak\":%d,\"spread_anomaly_streak\":%d,\"cost_spread_vs_typical_move\":%.4f,\"cost_spread_vs_time_stop\":%.4f,\"cost_spread_vs_mfe\":%.4f,\"cost_spread_vs_mae\":%.4f}",
      state.loss_streak,
      state.exec_error_streak,
      state.spread_anomaly_streak,
      cost_pressure.spread_vs_typical_move,
      cost_pressure.spread_vs_time_stop,
      cost_pressure.spread_vs_mfe,
      cost_pressure.spread_vs_mae
   );
   FileWriteString(h,payload);
   FileClose(h);
  }

#endif
