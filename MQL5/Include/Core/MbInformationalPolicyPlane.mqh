#ifndef MB_INFORMATIONAL_POLICY_PLANE_INCLUDED
#define MB_INFORMATIONAL_POLICY_PLANE_INCLUDED

#include "MbRuntimeTypes.mqh"
#include "MbStorage.mqh"
#include "MbStatusPlane.mqh"
#include "MbTuningEpistemology.mqh"

string MbBuildInformationalPolicyPayload(
   const MbSymbolProfile &profile,
   const MbRuntimeState &state,
   const MbMarketSnapshot &snapshot,
   const MbTuningLocalPolicy &policy,
   const string verdict_light,
   const string reason_code
)
  {
   MbReasonTriple normalized_reason;
   MbExecutionQualityState execution_quality;
   MbCostPressureState cost_pressure;
   MbBuildRuntimeEpistemicSnapshot(profile.symbol,state,snapshot,policy,reason_code,normalized_reason,execution_quality,cost_pressure);

   return StringFormat(
      "{\"schema_version\":\"1.1\",\"symbol\":\"%s\",\"session_profile\":\"%s\",\"runtime_mode\":\"%s\",\"caution_mode\":%s,\"close_only\":%s,\"halt\":%s,\"cooldown_left_sec\":%d,\"incident_pressure\":%d,\"execution_pressure\":%.4f,\"learning_bias\":%.4f,\"learning_confidence\":%.4f,\"learning_sample_count\":%d,\"adaptive_risk_scale\":%.4f,\"coordinator_risk_cap\":%.4f,\"signal_confidence\":%.4f,\"signal_risk_multiplier\":%.4f,\"market_regime\":\"%s\",\"spread_regime\":\"%s\",\"execution_regime\":\"%s\",\"confidence_bucket\":\"%s\",\"last_setup_type\":\"%s\",\"candle_bias\":\"%s\",\"candle_quality_grade\":\"%s\",\"candle_score\":%.4f,\"renko_bias\":\"%s\",\"renko_quality_grade\":\"%s\",\"renko_score\":%.4f,\"renko_run_length\":%d,\"renko_reversal_flag\":%s,\"spread_points\":%.2f,\"tick_age_ms\":%I64d,\"terminal_connected\":%s,\"terminal_ping_ms\":%I64d,\"ticks_seen\":%I64d,\"timer_cycles\":%I64d,\"trade_permissions_ok\":%s,\"raw_trade_permissions_ok\":%s,\"paper_runtime_override_active\":%s,\"term_trade_allowed\":%s,\"mql_trade_allowed\":%s,\"account_trade_allowed\":%s,\"verdict_light\":\"%s\",\"reason_code\":\"%s\",\"reason_domain\":\"%s\",\"reason_class\":\"%s\",\"trust_state\":\"%s\",\"trust_reason\":\"%s\",\"execution_quality_state\":\"%s\",\"execution_quality_reason_code\":\"%s\",\"cost_pressure_state\":\"%s\",\"cost_pressure_reason_code\":\"%s\"}",
      profile.symbol,
      profile.session_profile,
      MbRuntimeModeLabel(state.mode),
      MbJsonBool(state.caution_mode),
      MbJsonBool(state.close_only),
      MbJsonBool(state.halt),
      MbCooldownLeftSec(state),
      MbIncidentPressure(state),
      state.execution_pressure,
      state.learning_bias,
      state.learning_confidence,
      state.learning_sample_count,
      state.adaptive_risk_scale,
      state.coordinator_risk_cap,
      state.signal_confidence,
      state.signal_risk_multiplier,
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
      (state.renko_reversal_flag ? "true" : "false"),
      snapshot.spread_points,
      snapshot.tick_age_ms,
      MbJsonBool(snapshot.terminal_connected),
      snapshot.terminal_ping_last_ms,
      state.ticks_seen,
      state.timer_cycles,
      MbJsonBool(snapshot.trade_permissions_ok),
      MbJsonBool(snapshot.raw_trade_permissions_ok),
      MbJsonBool(snapshot.paper_runtime_override_active),
      MbJsonBool(snapshot.term_trade_allowed),
      MbJsonBool(snapshot.mql_trade_allowed),
      MbJsonBool(snapshot.account_trade_allowed),
      verdict_light,
      reason_code,
      normalized_reason.domain,
      normalized_reason.reason_class,
      policy.last_trust_state,
      policy.trust_reason,
      execution_quality.state,
      execution_quality.reason_code,
      cost_pressure.state,
      cost_pressure.reason_code
   );
  }

void MbFlushInformationalPolicy(
   const MbSymbolProfile &profile,
   const MbRuntimeState &state,
   const MbMarketSnapshot &snapshot,
   const MbTuningLocalPolicy &policy,
   const string verdict_light,
   const string reason_code
)
  {
   int h = FileOpen(MbStateFilePath(profile.symbol,"informational_policy.json"), FILE_COMMON | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;
   FileWriteString(h,MbBuildInformationalPolicyPayload(profile,state,snapshot,policy,verdict_light,reason_code));
   FileClose(h);
  }

#endif
