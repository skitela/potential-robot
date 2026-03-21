#ifndef MB_TESTER_TELEMETRY_INCLUDED
#define MB_TESTER_TELEMETRY_INCLUDED

#include "MbRuntimeTypes.mqh"
#include "MbStorage.mqh"
#include "MbStatusPlane.mqh"
#include "MbLatencyProfile.mqh"
#include "MbTuningEpistemology.mqh"
#include "MbTuningTypes.mqh"
#include "MbTesterOptimizationInputs.mqh"

string MbTesterTelemetryEscapeJson(const string value)
  {
   string out = value;
   StringReplace(out,"\\","\\\\");
   StringReplace(out,"\"","\\\"");
   return out;
  }

string MbTesterTelemetryResolveSymbol(const string preferred_symbol)
  {
   string resolved = MbCanonicalSymbol(preferred_symbol);
   if(StringLen(resolved) > 0)
      return resolved;

   string chart_symbol = MbCanonicalSymbol(Symbol());
   if(StringLen(chart_symbol) > 0)
      return chart_symbol;

   return "UNKNOWN";
  }

double MbTesterTelemetryClamp(const double value,const double min_value,const double max_value)
  {
   return MathMax(min_value,MathMin(max_value,value));
  }

ulong g_mb_tester_telemetry_processed_passes[];
bool g_mb_tester_telemetry_filter_ready = false;

double MbTesterTelemetryPayloadValue(const double &payload[],const int index,const double default_value = 0.0)
  {
   if(index < 0 || index >= ArraySize(payload))
      return default_value;
   return payload[index];
  }

bool MbTesterTelemetryHasProcessedPass(const ulong pass)
  {
   for(int i = 0; i < ArraySize(g_mb_tester_telemetry_processed_passes); ++i)
     {
      if(g_mb_tester_telemetry_processed_passes[i] == pass)
         return true;
     }
   return false;
  }

void MbTesterTelemetryMarkProcessedPass(const ulong pass)
  {
   if(pass == 0 || MbTesterTelemetryHasProcessedPass(pass))
      return;

   int next = ArraySize(g_mb_tester_telemetry_processed_passes);
   ArrayResize(g_mb_tester_telemetry_processed_passes,next + 1);
   g_mb_tester_telemetry_processed_passes[next] = pass;
  }

string MbTesterTelemetryInputsJson(const string &inputs[],const uint input_count)
  {
   string json = "[";
   for(uint i = 0; i < input_count; ++i)
     {
      if(i > 0)
         json += ",";
      json += "\"" + MbTesterTelemetryEscapeJson(inputs[(int)i]) + "\"";
     }
   json += "]";
   return json;
  }

double MbTesterTelemetryWinRate(const MbRuntimeState &state)
  {
   if(state.learning_sample_count <= 0)
      return 0.0;
   return ((double)state.learning_win_count / (double)state.learning_sample_count);
  }

double MbTesterTelemetryTrustPenalty(const MbTuningLocalPolicy &policy)
  {
   string trust_state = policy.last_trust_state;
   StringToUpper(trust_state);

   if(trust_state == "FOREFIELD_DIRTY" || trust_state == "DIRTY_FOREGROUND")
      return 0.55;
   if(trust_state == "PAPER_CONVERSION_BLOCKED")
      return 0.45;
   if(trust_state == "LOW_SAMPLE")
      return 0.35;
   if(!policy.trusted_data)
      return 0.25;

   return 0.0;
  }

double MbTesterTelemetryCostPenalty(const MbCostPressureState &cost_pressure)
  {
   string state = cost_pressure.state;
   StringToUpper(state);

   if(state == "NON_REPRESENTATIVE")
      return 0.45;
   if(state == "HIGH")
      return 0.25;
   if(state == "MEDIUM")
      return 0.10;

   return 0.0;
  }

double MbTesterTelemetryExecutionPenalty(const MbRuntimeState &state,const MbExecutionSummary &summary)
  {
   double exec_ok_ratio = 1.0;
   if(summary.execution_attempt_count > 0)
      exec_ok_ratio = ((double)summary.execution_ok_count / (double)summary.execution_attempt_count);

   double avg_retries = (summary.execution_retry_avg_milli / 1000.0);
   double pressure_penalty = MbTesterTelemetryClamp(state.execution_pressure,0.0,1.0) * 0.25;
   double retries_penalty = MathMin(0.15,avg_retries * 0.05);
   double fail_penalty = MathMin(0.25,(1.0 - exec_ok_ratio) * 0.40);

   return (pressure_penalty + retries_penalty + fail_penalty);
  }

double MbTesterTelemetryLatencyPenalty(const MbExecutionSummary &summary)
  {
   if(summary.latency_samples <= 0)
      return 0.0;

   double latency_penalty = ((double)summary.local_latency_us_avg / 250000.0);
   return MathMin(0.10,MathMax(0.0,latency_penalty));
  }

double MbTesterTelemetrySampleBonus(const MbRuntimeState &state)
  {
   return MathMin(0.30,(double)state.learning_sample_count * 0.015);
  }

double MbTesterTelemetryWinRateBonus(const MbRuntimeState &state)
  {
   if(state.learning_sample_count <= 0)
      return 0.0;

   double centered = MbTesterTelemetryWinRate(state) - 0.50;
   return MbTesterTelemetryClamp(centered * 0.50,-0.25,0.25);
  }

void MbTesterTelemetryEnsureCsvHeader(const int handle)
  {
   if(handle == INVALID_HANDLE || FileSize(handle) > 0)
      return;

   FileWrite(
      handle,
      "ts",
      "symbol",
      "magic",
      "policy_revision",
      "experiment_status",
      "runtime_mode",
      "custom_score",
      "realized_pnl_lifetime",
      "learning_sample_count",
      "learning_win_count",
      "learning_loss_count",
      "win_rate",
      "trust_state",
      "trust_reason",
      "trust_penalty",
      "cost_pressure_state",
      "cost_pressure_reason_code",
      "cost_penalty",
      "execution_quality_state",
      "execution_quality_reason_code",
      "execution_penalty",
      "latency_penalty",
      "execution_ok_ratio",
      "avg_retries",
      "avg_slippage_points",
      "signal_confidence",
      "learning_bias",
      "confidence_cap",
      "risk_cap"
   );
  }

bool MbTesterTelemetryWriteLatest(
   const MbSymbolProfile &profile,
   const MbRuntimeState &state,
   const MbMarketSnapshot &snapshot,
   const MbTuningLocalPolicy &policy,
   const MbLatencyProfile &latency,
   const MbReasonTriple &normalized_reason,
   const MbExecutionQualityState &execution_quality,
   const MbCostPressureState &cost_pressure,
   const MbExecutionSummary &summary,
   const double custom_score,
   const double trust_penalty,
   const double cost_penalty,
   const double execution_penalty,
   const double latency_penalty
)
  {
   int handle = FileOpen(MbStateFilePath(profile.symbol,"tester_telemetry_latest.json"), FILE_COMMON | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;

   double exec_ok_ratio = 1.0;
   double avg_retries = 0.0;
   double avg_slippage = 0.0;
   if(summary.execution_attempt_count > 0)
     {
      exec_ok_ratio = ((double)summary.execution_ok_count / (double)summary.execution_attempt_count);
      avg_retries = (summary.execution_retry_avg_milli / 1000.0);
      avg_slippage = (summary.execution_slippage_points_avg_milli / 1000.0);
     }

   string payload = StringFormat(
      "{\"schema_version\":\"1.3\",\"symbol\":\"%s\",\"magic\":%I64d,\"runtime_mode\":\"%s\",\"session_profile\":\"%s\",\"custom_score\":%.6f,\"realized_pnl_lifetime\":%.6f,\"learning_sample_count\":%d,\"learning_win_count\":%d,\"learning_loss_count\":%d,\"win_rate\":%.6f,\"trust_state\":\"%s\",\"trust_reason\":\"%s\",\"trust_reason_domain\":\"%s\",\"trust_reason_class\":\"%s\",\"trust_penalty\":%.6f,\"cost_pressure_state\":\"%s\",\"cost_pressure_reason_code\":\"%s\",\"cost_penalty\":%.6f,\"execution_quality_state\":\"%s\",\"execution_quality_reason_code\":\"%s\",\"execution_penalty\":%.6f,\"latency_penalty\":%.6f,\"execution_ok_ratio\":%.6f,\"avg_retries\":%.6f,\"avg_slippage_points\":%.6f,\"latency_samples\":%I64d,\"local_latency_us_avg\":%I64d,\"signal_confidence\":%.6f,\"learning_bias\":%.6f,\"policy_revision\":%d,\"policy_action_code\":\"%s\",\"experiment_status\":\"%s\",\"confidence_cap\":%.6f,\"risk_cap\":%.6f,\"force_flatten\":%s,\"trade_rights\":%s,\"paper_rights\":%s,\"observation_rights\":%s,\"allowed_direction\":\"%s\",\"paper_runtime_override_active\":%s,\"terminal_ping_ms\":%I64d,\"spread_points\":%.2f,\"generated_at_utc\":%I64d}",
      MbTesterTelemetryEscapeJson(profile.symbol),
      (long)state.magic,
      MbRuntimeModeLabelForState(state),
      MbTesterTelemetryEscapeJson(profile.session_profile),
      custom_score,
      state.realized_pnl_lifetime,
      state.learning_sample_count,
      state.learning_win_count,
      state.learning_loss_count,
      MbTesterTelemetryWinRate(state),
      MbTesterTelemetryEscapeJson(policy.last_trust_state),
      MbTesterTelemetryEscapeJson(policy.trust_reason),
      MbTesterTelemetryEscapeJson(normalized_reason.domain),
      MbTesterTelemetryEscapeJson(normalized_reason.reason_class),
      trust_penalty,
      MbTesterTelemetryEscapeJson(cost_pressure.state),
      MbTesterTelemetryEscapeJson(cost_pressure.reason_code),
      cost_penalty,
      MbTesterTelemetryEscapeJson(execution_quality.state),
      MbTesterTelemetryEscapeJson(execution_quality.reason_code),
      execution_penalty,
      latency_penalty,
      exec_ok_ratio,
      avg_retries,
      avg_slippage,
      summary.latency_samples,
      summary.local_latency_us_avg,
      state.signal_confidence,
      state.learning_bias,
      policy.revision,
      MbTesterTelemetryEscapeJson(policy.last_action_code),
      MbTesterTelemetryEscapeJson(policy.experiment_status),
      policy.confidence_cap,
      policy.risk_cap,
      MbJsonBool(state.force_flatten),
      MbJsonBool(state.trade_rights),
      MbJsonBool(state.paper_rights),
      MbJsonBool(state.observation_rights),
      MbTesterTelemetryEscapeJson(MbResolveAllowedDirectionForState(state)),
      MbJsonBool(snapshot.paper_runtime_override_active),
      snapshot.terminal_ping_last_ms,
      snapshot.spread_points,
      (long)TimeTradeServer()
   );

   FileWriteString(handle,payload);
   FileClose(handle);
   return true;
  }

bool MbTesterTelemetryAppendPassSummary(
   const MbSymbolProfile &profile,
   const MbRuntimeState &state,
   const MbTuningLocalPolicy &policy,
   const MbExecutionQualityState &execution_quality,
   const MbCostPressureState &cost_pressure,
   const MbExecutionSummary &summary,
   const double custom_score,
   const double trust_penalty,
   const double cost_penalty,
   const double execution_penalty,
   const double latency_penalty
)
  {
   int handle = FileOpen(MbLogFilePath(profile.symbol,"tester_pass_summary.csv"), FILE_COMMON | FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;

   MbTesterTelemetryEnsureCsvHeader(handle);
   FileSeek(handle,0,SEEK_END);

   double exec_ok_ratio = 1.0;
   double avg_retries = 0.0;
   double avg_slippage = 0.0;
   if(summary.execution_attempt_count > 0)
     {
      exec_ok_ratio = ((double)summary.execution_ok_count / (double)summary.execution_attempt_count);
      avg_retries = (summary.execution_retry_avg_milli / 1000.0);
      avg_slippage = (summary.execution_slippage_points_avg_milli / 1000.0);
     }

   FileWrite(
      handle,
      (long)TimeCurrent(),
      MbCanonicalSymbol(profile.symbol),
      (long)state.magic,
      policy.revision,
      policy.experiment_status,
      MbRuntimeModeLabelForState(state),
      DoubleToString(custom_score,6),
      DoubleToString(state.realized_pnl_lifetime,6),
      state.learning_sample_count,
      state.learning_win_count,
      state.learning_loss_count,
      DoubleToString(MbTesterTelemetryWinRate(state),6),
      policy.last_trust_state,
      policy.trust_reason,
      DoubleToString(trust_penalty,6),
      cost_pressure.state,
      cost_pressure.reason_code,
      DoubleToString(cost_penalty,6),
      execution_quality.state,
      execution_quality.reason_code,
      DoubleToString(execution_penalty,6),
      DoubleToString(latency_penalty,6),
      DoubleToString(exec_ok_ratio,6),
      DoubleToString(avg_retries,6),
      DoubleToString(avg_slippage,6),
      DoubleToString(state.signal_confidence,6),
      DoubleToString(state.learning_bias,6),
      DoubleToString(policy.confidence_cap,6),
      DoubleToString(policy.risk_cap,6)
   );

   FileClose(handle);
   return true;
  }

bool MbTesterTelemetryWriteOptimizationLatest(
   const string symbol,
   const long magic,
   const ulong pass,
   const string frame_name,
   const double frame_value,
   const double &payload[],
   const string &inputs[],
   const uint input_count
)
  {
   int handle = FileOpen(MbStateFilePath(symbol,"tester_telemetry_latest.json"), FILE_COMMON | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;

   string output = StringFormat(
      "{\"schema_version\":\"1.3\",\"symbol\":\"%s\",\"magic\":%I64d,\"runtime_mode\":\"OPTIMIZATION_PASS\",\"custom_score\":%.6f,\"realized_pnl_lifetime\":%.6f,\"learning_sample_count\":%d,\"win_rate\":%.6f,\"trust_penalty\":%.6f,\"cost_penalty\":%.6f,\"execution_penalty\":%.6f,\"latency_penalty\":%.6f,\"policy_revision\":%d,\"confidence_cap\":%.6f,\"risk_cap\":%.6f,\"execution_ok_ratio\":%.6f,\"experiment_status\":\"OPTIMIZATION_PASS\",\"frame_name\":\"%s\",\"frame_pass\":%I64u,\"force_flatten\":false,\"trade_rights\":false,\"paper_rights\":true,\"observation_rights\":true,\"allowed_direction\":\"BOTH\",\"optimization_inputs_count\":%u,\"optimization_inputs\":%s,\"generated_at_utc\":%I64d}",
      MbTesterTelemetryEscapeJson(symbol),
      magic,
      frame_value,
      MbTesterTelemetryPayloadValue(payload,1),
      (int)MbTesterTelemetryPayloadValue(payload,2),
      MbTesterTelemetryPayloadValue(payload,3),
      MbTesterTelemetryPayloadValue(payload,4),
      MbTesterTelemetryPayloadValue(payload,5),
      MbTesterTelemetryPayloadValue(payload,6),
      MbTesterTelemetryPayloadValue(payload,7),
      (int)MbTesterTelemetryPayloadValue(payload,8),
      MbTesterTelemetryPayloadValue(payload,9),
      MbTesterTelemetryPayloadValue(payload,10),
      MbTesterTelemetryPayloadValue(payload,11,1.0),
      MbTesterTelemetryEscapeJson(frame_name),
      pass,
      input_count,
      MbTesterTelemetryInputsJson(inputs,input_count),
      (long)TimeTradeServer()
   );

   FileWriteString(handle,output);
   FileClose(handle);
   return true;
  }

bool MbTesterTelemetryAppendOptimizationPass(
   const string symbol,
   const long magic,
   const ulong pass,
   const string frame_name,
   const long frame_id,
   const double frame_value,
   const double &payload[],
   const string &inputs[],
   const uint input_count
)
  {
   int handle = FileOpen(MbRunFilePath(symbol,"tester_optimization_passes.jsonl"), FILE_COMMON | FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;

   FileSeek(handle,0,SEEK_END);
   string output = StringFormat(
      "{\"schema_version\":\"1.1\",\"symbol\":\"%s\",\"magic\":%I64d,\"frame_name\":\"%s\",\"frame_id\":%I64d,\"frame_pass\":%I64u,\"custom_score\":%.6f,\"realized_pnl_lifetime\":%.6f,\"learning_sample_count\":%d,\"win_rate\":%.6f,\"trust_penalty\":%.6f,\"cost_penalty\":%.6f,\"execution_penalty\":%.6f,\"latency_penalty\":%.6f,\"policy_revision\":%d,\"confidence_cap\":%.6f,\"risk_cap\":%.6f,\"execution_ok_ratio\":%.6f,\"force_flatten\":false,\"allowed_direction\":\"BOTH\",\"optimization_inputs_count\":%u,\"optimization_inputs\":%s,\"generated_at_utc\":%I64d}",
      MbTesterTelemetryEscapeJson(symbol),
      magic,
      MbTesterTelemetryEscapeJson(frame_name),
      frame_id,
      pass,
      frame_value,
      MbTesterTelemetryPayloadValue(payload,1),
      (int)MbTesterTelemetryPayloadValue(payload,2),
      MbTesterTelemetryPayloadValue(payload,3),
      MbTesterTelemetryPayloadValue(payload,4),
      MbTesterTelemetryPayloadValue(payload,5),
      MbTesterTelemetryPayloadValue(payload,6),
      MbTesterTelemetryPayloadValue(payload,7),
      (int)MbTesterTelemetryPayloadValue(payload,8),
      MbTesterTelemetryPayloadValue(payload,9),
      MbTesterTelemetryPayloadValue(payload,10),
      MbTesterTelemetryPayloadValue(payload,11,1.0),
      input_count,
      MbTesterTelemetryInputsJson(inputs,input_count),
      (long)TimeTradeServer()
   );

   FileWriteString(handle,output + "\n");
   FileClose(handle);
   return true;
  }

bool MbTesterTelemetryConfigureOptimizationFilter(const long magic,const bool force_reset = false)
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION) == 0)
      return false;

   if(force_reset || !g_mb_tester_telemetry_filter_ready)
      g_mb_tester_telemetry_filter_ready = FrameFilter("MICROBOT_PASS_V1",magic);
   return g_mb_tester_telemetry_filter_ready;
  }

void MbTesterTelemetryCollectOptimizationPasses(const string symbol,const long magic,const bool force_reset_filter = false)
  {
   if(!MbIsStrategyTesterRuntime() || MQLInfoInteger(MQL_OPTIMIZATION) == 0)
      return;

   string resolved_symbol = MbTesterTelemetryResolveSymbol(symbol);
   if(!MbStorageInit(resolved_symbol))
      return;

   if(!MbTesterTelemetryConfigureOptimizationFilter(magic,force_reset_filter))
      return;

   ulong pass = 0;
   string name = "";
   long id = 0;
   double value = 0.0;
   double payload[];
   while(FrameNext(pass,name,id,value,payload))
     {
      if(MbTesterTelemetryHasProcessedPass(pass))
         continue;

      string inputs[];
      uint input_count = 0;
      FrameInputs(pass,inputs,input_count);
      MbTesterTelemetryAppendOptimizationPass(resolved_symbol,magic,pass,name,id,value,payload,inputs,input_count);
      MbTesterTelemetryWriteOptimizationLatest(resolved_symbol,magic,pass,name,value,payload,inputs,input_count);
      MbTesterTelemetryMarkProcessedPass(pass);
     }
  }

bool MbTesterTelemetryWriteSessionMarker(const string symbol,const string stage,const long magic)
  {
   string resolved_symbol = MbTesterTelemetryResolveSymbol(symbol);
   if(!MbStorageInit(resolved_symbol))
      return false;

   int handle = FileOpen(MbRunFilePath(resolved_symbol,"tester_telemetry_session.json"), FILE_COMMON | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;

   string payload = StringFormat(
      "{\"schema_version\":\"1.0\",\"symbol\":\"%s\",\"magic\":%I64d,\"stage\":\"%s\",\"optimization_active\":%s,\"tester_active\":%s,\"generated_at_utc\":%I64d}",
      MbTesterTelemetryEscapeJson(resolved_symbol),
      magic,
      MbTesterTelemetryEscapeJson(stage),
      MbJsonBool(MQLInfoInteger(MQL_OPTIMIZATION) != 0),
      MbJsonBool(MbIsStrategyTesterRuntime()),
      (long)TimeTradeServer()
   );
   FileWriteString(handle,payload);
   FileClose(handle);
   return true;
  }

bool MbTesterTelemetryFinalizeSingleRun(
   const MbSymbolProfile &profile,
   const MbRuntimeState &state,
   const MbMarketSnapshot &snapshot,
   const MbTuningLocalPolicy &policy,
   const MbLatencyProfile &latency
)
  {
   if((!MbIsStrategyTesterRuntime() && !MbHasStrategyTesterSandbox()) || MQLInfoInteger(MQL_OPTIMIZATION) != 0)
      return false;

   MbExecutionSummary summary;
   MbBuildExecutionSummary(latency,summary);

   MbReasonTriple normalized_reason;
   MbExecutionQualityState execution_quality;
   MbCostPressureState cost_pressure;
   MbBuildRuntimeEpistemicSnapshot(profile.symbol,state,snapshot,policy,"TESTER_FINALIZE",normalized_reason,execution_quality,cost_pressure);

   double trust_penalty = MbTesterTelemetryTrustPenalty(policy);
   double cost_penalty = MbTesterTelemetryCostPenalty(cost_pressure);
   double execution_penalty = MbTesterTelemetryExecutionPenalty(state,summary);
   double latency_penalty = MbTesterTelemetryLatencyPenalty(summary);
   double sample_bonus = MbTesterTelemetrySampleBonus(state);
   double win_rate_bonus = MbTesterTelemetryWinRateBonus(state);

   double custom_score =
      state.realized_pnl_lifetime +
      sample_bonus +
      win_rate_bonus -
      trust_penalty -
      cost_penalty -
      execution_penalty -
      latency_penalty;

   MbTesterTelemetryWriteLatest(profile,state,snapshot,policy,latency,normalized_reason,execution_quality,cost_pressure,summary,custom_score,trust_penalty,cost_penalty,execution_penalty,latency_penalty);
   MbTesterTelemetryAppendPassSummary(profile,state,policy,execution_quality,cost_pressure,summary,custom_score,trust_penalty,cost_penalty,execution_penalty,latency_penalty);
   MbTesterTelemetryWriteSessionMarker(profile.symbol,"tester_single_run_finalize",(long)state.magic);
   return true;
  }

int MbTesterTelemetryOnInit(const string symbol,const long magic)
  {
   if(!MbIsStrategyTesterRuntime())
      return INIT_SUCCEEDED;

   ArrayResize(g_mb_tester_telemetry_processed_passes,0);
   g_mb_tester_telemetry_filter_ready = false;
   if(MQLInfoInteger(MQL_OPTIMIZATION) != 0)
     {
      MbConfigureCommonOptimizationRanges();
      MbTesterTelemetryConfigureOptimizationFilter(magic,true);
     }
   MbTesterTelemetryWriteSessionMarker(symbol,"tester_init",magic);
   return INIT_SUCCEEDED;
  }

double MbTesterTelemetryOnTester(
   const MbSymbolProfile &profile,
   const MbRuntimeState &state,
   const MbMarketSnapshot &snapshot,
   const MbTuningLocalPolicy &policy,
   const MbLatencyProfile &latency
)
  {
   MbExecutionSummary summary;
   MbBuildExecutionSummary(latency,summary);

   MbReasonTriple normalized_reason;
   MbExecutionQualityState execution_quality;
   MbCostPressureState cost_pressure;
   MbBuildRuntimeEpistemicSnapshot(profile.symbol,state,snapshot,policy,"TESTER_EVAL",normalized_reason,execution_quality,cost_pressure);

   double trust_penalty = MbTesterTelemetryTrustPenalty(policy);
   double cost_penalty = MbTesterTelemetryCostPenalty(cost_pressure);
   double execution_penalty = MbTesterTelemetryExecutionPenalty(state,summary);
   double latency_penalty = MbTesterTelemetryLatencyPenalty(summary);
   double sample_bonus = MbTesterTelemetrySampleBonus(state);
   double win_rate_bonus = MbTesterTelemetryWinRateBonus(state);

   double custom_score =
      state.realized_pnl_lifetime +
      sample_bonus +
      win_rate_bonus -
      trust_penalty -
      cost_penalty -
      execution_penalty -
      latency_penalty;

   if(MQLInfoInteger(MQL_OPTIMIZATION) != 0)
     {
      double payload[];
      ArrayResize(payload,12);
      payload[0] = custom_score;
      payload[1] = state.realized_pnl_lifetime;
      payload[2] = (double)state.learning_sample_count;
      payload[3] = MbTesterTelemetryWinRate(state);
      payload[4] = trust_penalty;
      payload[5] = cost_penalty;
      payload[6] = execution_penalty;
      payload[7] = latency_penalty;
      payload[8] = (double)policy.revision;
      payload[9] = policy.confidence_cap;
      payload[10] = policy.risk_cap;
      payload[11] = (summary.execution_attempt_count > 0 ? (double)summary.execution_ok_count / (double)summary.execution_attempt_count : 1.0);
      FrameAdd("MICROBOT_PASS_V1",(long)state.magic,custom_score,payload);
     }
   else
     {
      MbTesterTelemetryWriteLatest(profile,state,snapshot,policy,latency,normalized_reason,execution_quality,cost_pressure,summary,custom_score,trust_penalty,cost_penalty,execution_penalty,latency_penalty);
      MbTesterTelemetryAppendPassSummary(profile,state,policy,execution_quality,cost_pressure,summary,custom_score,trust_penalty,cost_penalty,execution_penalty,latency_penalty);
     }

   return custom_score;
  }

void MbTesterTelemetryOnPass(const string symbol,const long magic)
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION) == 0)
      return;

   MbTesterTelemetryCollectOptimizationPasses(symbol,magic,false);
   MbTesterTelemetryWriteSessionMarker(symbol,"tester_pass",magic);
  }

void MbTesterTelemetryOnDeinit(const string symbol,const long magic)
  {
   if(!MbIsStrategyTesterRuntime())
      return;

   if(MQLInfoInteger(MQL_OPTIMIZATION) != 0)
      MbTesterTelemetryCollectOptimizationPasses(symbol,magic,true);
   MbTesterTelemetryWriteSessionMarker(symbol,"tester_deinit",magic);
  }

#endif
