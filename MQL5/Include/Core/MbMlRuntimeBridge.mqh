#ifndef MB_ML_RUNTIME_BRIDGE_INCLUDED
#define MB_ML_RUNTIME_BRIDGE_INCLUDED

#include "MbExecutionSnapshot.mqh"
#include "MbBrokerNetLedger.mqh"
#include "MbMlFeatureContract.mqh"
#include "MbStudentDecisionGate.mqh"
#include "MbStorage.mqh"
#include "MbPaperTrading.mqh"
#include "MbOnnxPilotObservation.mqh"

struct MbMlRuntimeBridgeContract
  {
   bool present;
   bool enabled;
   bool student_gate_enabled;
   bool teacher_required;
   bool outcome_ready;
   bool local_model_available;
   bool global_model_available;
   bool paper_live_enabled;
   string local_training_mode;
   string runtime_scope;
   string paper_live_bucket;
   string universe_version;
   string plan_hash;
   MbDecisionThresholds thresholds;
  };

struct MbMlRuntimeBridgeState
  {
   bool enabled;
   bool student_gate_enabled;
   string symbol;
   string snapshot_state_path;
   string feature_contract_state_path;
   string ledger_log_path;
   string student_gate_state_path;
   string contract_path;
   datetime last_contract_refresh_at;
   datetime last_feature_contract_write_at;
   MbMlRuntimeBridgeContract contract;
  };

string MbMlRuntimeBridgeEscapeJson(const string value)
  {
   string out = value;
   StringReplace(out,"\\","\\\\");
   StringReplace(out,"\"","\\\"");
   return out;
  }

void MbMlRuntimeBridgeResetContract(MbMlRuntimeBridgeContract &contract)
  {
   contract.present = false;
   contract.enabled = false;
   contract.student_gate_enabled = false;
   contract.teacher_required = true;
   contract.outcome_ready = false;
   contract.local_model_available = false;
   contract.global_model_available = false;
    contract.paper_live_enabled = false;
   contract.local_training_mode = "FALLBACK_ONLY";
   contract.runtime_scope = "LAPTOP_ONLY";
   contract.paper_live_bucket = "GLOBAL_TEACHER_ONLY";
   contract.universe_version = "";
   contract.plan_hash = "";
   MbSetDefaultDecisionThresholds(contract.thresholds);
  }

void MbMlRuntimeBridgeReset(MbMlRuntimeBridgeState &state)
  {
   state.enabled = false;
   state.student_gate_enabled = false;
   state.symbol = "";
   state.snapshot_state_path = "";
   state.feature_contract_state_path = "";
   state.ledger_log_path = "";
   state.student_gate_state_path = "";
   state.contract_path = "";
   state.last_contract_refresh_at = 0;
   state.last_feature_contract_write_at = 0;
   MbMlRuntimeBridgeResetContract(state.contract);
  }

bool MbMlRuntimeBridgeReadBool(const string value)
  {
   string normalized = value;
   StringToUpper(normalized);
   return (normalized == "1" || normalized == "TRUE" || normalized == "YES" || normalized == "ON");
  }

bool MbMlRuntimeBridgeLoadContract(MbMlRuntimeBridgeState &state)
  {
   MbMlRuntimeBridgeResetContract(state.contract);
   if(StringLen(state.contract_path) <= 0 || !FileIsExist(state.contract_path,FILE_COMMON))
      return false;

   int handle = FileOpen(state.contract_path,FILE_COMMON | FILE_READ | FILE_CSV | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;

   while(!FileIsEnding(handle))
     {
      string key = FileReadString(handle);
      string value = FileReadString(handle);
      if(key == "")
         continue;

      if(key == "enabled")
         state.contract.enabled = MbMlRuntimeBridgeReadBool(value);
      else if(key == "student_gate_enabled")
         state.contract.student_gate_enabled = MbMlRuntimeBridgeReadBool(value);
      else if(key == "teacher_required")
         state.contract.teacher_required = MbMlRuntimeBridgeReadBool(value);
      else if(key == "outcome_ready")
         state.contract.outcome_ready = MbMlRuntimeBridgeReadBool(value);
      else if(key == "local_model_available")
         state.contract.local_model_available = MbMlRuntimeBridgeReadBool(value);
      else if(key == "global_model_available")
         state.contract.global_model_available = MbMlRuntimeBridgeReadBool(value);
      else if(key == "paper_live_enabled")
         state.contract.paper_live_enabled = MbMlRuntimeBridgeReadBool(value);
      else if(key == "local_training_mode")
         state.contract.local_training_mode = value;
      else if(key == "runtime_scope")
         state.contract.runtime_scope = value;
      else if(key == "paper_live_bucket")
         state.contract.paper_live_bucket = value;
      else if(key == "universe_version")
         state.contract.universe_version = value;
      else if(key == "plan_hash")
         state.contract.plan_hash = value;
      else if(key == "min_gate_probability")
         state.contract.thresholds.min_gate_probability = StringToDouble(value);
      else if(key == "min_decision_score_pln")
         state.contract.thresholds.min_decision_score_pln = StringToDouble(value);
      else if(key == "max_spread_points")
         state.contract.thresholds.max_spread_points = StringToDouble(value);
      else if(key == "max_server_ping_ms")
         state.contract.thresholds.max_server_ping_ms = StringToDouble(value);
      else if(key == "max_server_latency_us_avg")
         state.contract.thresholds.max_server_latency_us_avg = StringToDouble(value);
     }

   FileClose(handle);
   state.contract.present = true;
   state.last_contract_refresh_at = TimeCurrent();
   return true;
  }

bool MbMlRuntimeBridgePaperLiveEnabled(const MbMlRuntimeBridgeState &state)
  {
   return state.contract.paper_live_enabled;
  }

string MbMlRuntimeBridgeRuntimeScope(const MbMlRuntimeBridgeState &state)
  {
   return state.contract.runtime_scope;
  }

string MbMlRuntimeBridgePaperLiveBucket(const MbMlRuntimeBridgeState &state)
  {
   return state.contract.paper_live_bucket;
  }

string MbMlRuntimeBridgeUniverseVersion(const MbMlRuntimeBridgeState &state)
  {
   return state.contract.universe_version;
  }

void MbMlRuntimeBridgeInit(
   MbMlRuntimeBridgeState &state,
   const string symbol,
   const bool enabled,
   const bool student_gate_enabled
)
  {
   MbMlRuntimeBridgeReset(state);
   state.enabled = enabled;
   state.student_gate_enabled = student_gate_enabled;
   state.symbol = MbCanonicalSymbol(symbol);
   state.snapshot_state_path = MbStateFilePath(state.symbol,"ml_execution_snapshot_latest.json");
   state.feature_contract_state_path = MbStateFilePath(state.symbol,"ml_feature_contract_latest.json");
   state.ledger_log_path = MbLogFilePath(state.symbol,"broker_net_ledger_runtime.csv");
   state.student_gate_state_path = MbStateFilePath(state.symbol,"student_gate_latest.json");
   state.contract_path = MbStateFilePath(state.symbol,"student_gate_contract.csv");
   MbStorageInit(state.symbol);
   MbMlRuntimeBridgeLoadContract(state);
  }

void MbMlRuntimeBridgeShutdown(MbMlRuntimeBridgeState &state)
  {
   MbMlRuntimeBridgeReset(state);
  }

void MbMlRuntimeBridgeEnsureLedgerHeader(const string rel_path)
  {
   if(StringLen(rel_path) <= 0 || FileIsExist(rel_path,FILE_COMMON))
      return;

   int handle = FileOpen(rel_path,FILE_COMMON | FILE_WRITE | FILE_CSV | FILE_ANSI,',');
   if(handle == INVALID_HANDLE)
      return;

   FileWrite(
      handle,
      "symbol_alias",
      "ts",
      "side",
      "lots",
      "entry_price",
      "exit_price",
      "spread_points_entry",
      "spread_points_exit",
      "slippage_points",
      "gross_pln",
      "spread_cost_pln",
      "slippage_cost_pln",
      "commission_pln",
      "swap_pln",
      "extra_fee_pln",
      "net_pln"
   );
   FileClose(handle);
  }

void MbMlRuntimeBridgeBuildExecutionSnapshot(
   const MbSymbolProfile &profile,
   const MbMarketSnapshot &market,
   const MbLatencyProfile &latency,
   MbExecutionSnapshot &snapshot
)
  {
   snapshot.symbol_alias = MbCanonicalSymbol(profile.symbol);
   snapshot.broker_symbol = profile.symbol;
   snapshot.spread_points = market.spread_points;
   snapshot.tick_size = market.tick_size;
   snapshot.tick_value = market.tick_value;
   snapshot.terminal_ping_ms = (double)market.terminal_ping_last_ms;
   snapshot.local_latency_us_avg = (latency.sample_count > 0 ? (double)latency.local_latency_us_sum / (double)latency.sample_count : 0.0);
   snapshot.local_latency_us_max = (double)latency.local_latency_us_max;
   snapshot.runtime_latency_us = (double)latency.last_local_latency_us;
   snapshot.ts_server = TimeCurrent();
   snapshot.broker_session_open = market.trade_permissions_ok;
   snapshot.server_ping_contract_enabled = market.execution_ping_contract_enabled;
  }

void MbMlRuntimeBridgeWriteExecutionSnapshot(
   MbMlRuntimeBridgeState &state,
   const MbSymbolProfile &profile,
   const MbMarketSnapshot &market,
   const MbLatencyProfile &latency
)
  {
   if(!state.enabled || StringLen(state.snapshot_state_path) <= 0)
      return;

   MbExecutionSnapshot snapshot;
   MbMlRuntimeBridgeBuildExecutionSnapshot(profile,market,latency,snapshot);

   int handle = FileOpen(state.snapshot_state_path,FILE_COMMON | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return;

   string payload = StringFormat(
      "{\"schema_version\":\"1.0\",\"symbol_alias\":\"%s\",\"broker_symbol\":\"%s\",\"spread_points\":%.6f,\"tick_size\":%.8f,\"tick_value\":%.8f,\"terminal_ping_ms\":%.2f,\"local_latency_us_avg\":%.2f,\"local_latency_us_max\":%.2f,\"runtime_latency_us\":%.2f,\"ts_server_utc\":%I64d,\"broker_session_open\":%s,\"server_ping_contract_enabled\":%s}",
      MbMlRuntimeBridgeEscapeJson(snapshot.symbol_alias),
      MbMlRuntimeBridgeEscapeJson(snapshot.broker_symbol),
      snapshot.spread_points,
      snapshot.tick_size,
      snapshot.tick_value,
      snapshot.terminal_ping_ms,
      snapshot.local_latency_us_avg,
      snapshot.local_latency_us_max,
      snapshot.runtime_latency_us,
      (long)snapshot.ts_server,
      (snapshot.broker_session_open ? "true" : "false"),
      (snapshot.server_ping_contract_enabled ? "true" : "false")
   );
   FileWriteString(handle,payload);
   FileClose(handle);
  }

void MbMlRuntimeBridgeWriteFeatureContract(MbMlRuntimeBridgeState &state)
  {
   if(!state.enabled || StringLen(state.feature_contract_state_path) <= 0)
      return;

   if(state.last_feature_contract_write_at > 0 && (TimeCurrent() - state.last_feature_contract_write_at) < 300 && FileIsExist(state.feature_contract_state_path,FILE_COMMON))
      return;

   string global_names[];
   string local_names[];
   MbFillGlobalFeatureNames(global_names);
   MbFillLocalFeatureNames(local_names);

   int handle = FileOpen(state.feature_contract_state_path,FILE_COMMON | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return;

   string payload = "{\"schema_version\":\"1.0\",\"global_features\":[";
   for(int i = 0; i < ArraySize(global_names); ++i)
     {
      if(i > 0)
         payload += ",";
      payload += "\"" + MbMlRuntimeBridgeEscapeJson(global_names[i]) + "\"";
     }
   payload += "],\"local_features\":[";
   for(int j = 0; j < ArraySize(local_names); ++j)
     {
      if(j > 0)
         payload += ",";
      payload += "\"" + MbMlRuntimeBridgeEscapeJson(local_names[j]) + "\"";
     }
   payload += "]}";

   FileWriteString(handle,payload);
   FileClose(handle);
   state.last_feature_contract_write_at = TimeCurrent();
  }

void MbMlRuntimeBridgeFlushSnapshot(
   MbMlRuntimeBridgeState &state,
   const MbSymbolProfile &profile,
   const MbMarketSnapshot &market,
   const MbLatencyProfile &latency
)
  {
   if(!state.enabled)
      return;
   MbMlRuntimeBridgeWriteExecutionSnapshot(state,profile,market,latency);
   MbMlRuntimeBridgeWriteFeatureContract(state);
   if(state.last_contract_refresh_at <= 0 || (TimeCurrent() - state.last_contract_refresh_at) >= 60)
      MbMlRuntimeBridgeLoadContract(state);
  }

double MbMlRuntimeBridgeEstimateEdgePln(
   const MbMarketSnapshot &market,
   const MbSignalDecision &signal,
   const double lots
)
  {
   double base = MathMax(0.0,MathAbs(signal.score));
   double tick_value = (market.tick_value > 0.0 ? market.tick_value : 1.0);
   double qty = MathMax(lots,0.01);
   return base * tick_value * qty;
  }

void MbMlRuntimeBridgeWriteGateState(
   MbMlRuntimeBridgeState &state,
   const datetime now_ts,
   const string reason_code,
   const string local_training_mode,
   const bool outcome_ready,
   const bool gate_applied,
   const bool allowed,
   const double teacher_score,
   const double student_score,
   const double expected_edge_pln,
   const double decision_score_pln,
   const double spread_points,
   const double server_ping_ms,
   const double server_latency_us_avg
)
  {
   if(!state.enabled || StringLen(state.student_gate_state_path) <= 0)
      return;

   int handle = FileOpen(state.student_gate_state_path,FILE_COMMON | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return;

   string payload = StringFormat(
      "{\"schema_version\":\"1.0\",\"symbol\":\"%s\",\"generated_at_utc\":%I64d,\"reason_code\":\"%s\",\"local_training_mode\":\"%s\",\"outcome_ready\":%s,\"gate_applied\":%s,\"allowed\":%s,\"teacher_score\":%.6f,\"student_score\":%.6f,\"expected_edge_pln\":%.6f,\"decision_score_pln\":%.6f,\"spread_points\":%.6f,\"server_ping_ms\":%.6f,\"server_latency_us_avg\":%.6f}",
      MbMlRuntimeBridgeEscapeJson(state.symbol),
      (long)now_ts,
      MbMlRuntimeBridgeEscapeJson(reason_code),
      MbMlRuntimeBridgeEscapeJson(local_training_mode),
      (outcome_ready ? "true" : "false"),
      (gate_applied ? "true" : "false"),
      (allowed ? "true" : "false"),
      teacher_score,
      student_score,
      expected_edge_pln,
      decision_score_pln,
      spread_points,
      server_ping_ms,
      server_latency_us_avg
   );
   FileWriteString(handle,payload);
   FileClose(handle);
  }

bool MbMlRuntimeBridgeApplyStudentGate(
   MbMlRuntimeBridgeState &state,
   const datetime now_ts,
   const MbSymbolProfile &profile,
   const MbMarketSnapshot &market,
   const MbLatencyProfile &latency,
   const MbRuntimeState &runtime_state,
   MbSignalDecision &signal,
   const MbOnnxObservationResult &onnx_result,
   const double lots
)
  {
   MbMlRuntimeBridgeFlushSnapshot(state,profile,market,latency);

   double teacher_score = onnx_result.teacher_score;
   double student_score = onnx_result.symbol_score;
   double server_latency_us_avg = (latency.sample_count > 0 ? (double)latency.local_latency_us_sum / (double)latency.sample_count : 0.0);
   double server_ping_ms = (market.operational_ping_ms > 0.0 ? market.operational_ping_ms : (double)market.terminal_ping_last_ms);

   if(!state.enabled || !state.student_gate_enabled || !signal.valid)
     {
      MbMlRuntimeBridgeWriteGateState(state,now_ts,"BRIDGE_DISABLED",state.contract.local_training_mode,false,false,true,teacher_score,student_score,0.0,0.0,market.spread_points,server_ping_ms,server_latency_us_avg);
      return false;
     }

   if(!onnx_result.available)
     {
      MbMlRuntimeBridgeWriteGateState(state,now_ts,"ONNX_RESULT_UNAVAILABLE",state.contract.local_training_mode,false,false,true,teacher_score,student_score,0.0,0.0,market.spread_points,server_ping_ms,server_latency_us_avg);
      return false;
     }

   if(!state.contract.present || !state.contract.enabled)
     {
      MbMlRuntimeBridgeWriteGateState(state,now_ts,"CONTRACT_MISSING_OR_DISABLED",state.contract.local_training_mode,false,false,true,teacher_score,student_score,0.0,0.0,market.spread_points,server_ping_ms,server_latency_us_avg);
      return false;
     }

   if(state.contract.local_training_mode == "FALLBACK_ONLY" || !state.contract.local_model_available)
     {
      MbMlRuntimeBridgeWriteGateState(state,now_ts,"LOCAL_MODEL_INACTIVE",state.contract.local_training_mode,state.contract.outcome_ready,false,true,teacher_score,student_score,0.0,0.0,market.spread_points,server_ping_ms,server_latency_us_avg);
      return false;
     }

   if(state.contract.teacher_required && !onnx_result.teacher_available)
     {
      MbMlRuntimeBridgeWriteGateState(state,now_ts,"TEACHER_UNAVAILABLE",state.contract.local_training_mode,state.contract.outcome_ready,false,true,teacher_score,student_score,0.0,0.0,market.spread_points,server_ping_ms,server_latency_us_avg);
      return false;
     }

   double expected_edge_pln = MbMlRuntimeBridgeEstimateEdgePln(market,signal,lots);
   double decision_score_pln = MathMax(0.0,student_score) * expected_edge_pln;
   bool allowed = MbAllowStudentTrade(
      teacher_score,
      student_score,
      expected_edge_pln,
      decision_score_pln,
      market.spread_points,
      server_ping_ms,
      server_latency_us_avg,
      state.contract.outcome_ready,
      state.contract.thresholds
   );

   if(!allowed)
     {
      signal.valid = false;
      signal.reason_code = "ML_STUDENT_GATE_BLOCK";
     }

   MbMlRuntimeBridgeWriteGateState(
      state,
      now_ts,
      (allowed ? "ML_STUDENT_GATE_ALLOW" : "ML_STUDENT_GATE_BLOCK"),
      state.contract.local_training_mode,
      state.contract.outcome_ready,
      true,
      allowed,
      teacher_score,
      student_score,
      expected_edge_pln,
      decision_score_pln,
      market.spread_points,
      server_ping_ms,
      server_latency_us_avg
   );
   return !allowed;
  }

bool MbMlRuntimeBridgeAppendLedgerRow(
   MbMlRuntimeBridgeState &state,
   const MbBrokerNetLedgerRow &row
)
  {
   if(!state.enabled || StringLen(state.ledger_log_path) <= 0)
      return false;

   MbMlRuntimeBridgeEnsureLedgerHeader(state.ledger_log_path);
   int handle = FileOpen(state.ledger_log_path,FILE_COMMON | FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI,',');
   if(handle == INVALID_HANDLE)
      return false;

   FileSeek(handle,0,SEEK_END);
   FileWrite(
      handle,
      row.symbol_alias,
      row.ts,
      row.side,
      DoubleToString(row.lots,4),
      DoubleToString(row.entry_price,_Digits),
      DoubleToString(row.exit_price,_Digits),
      DoubleToString(row.spread_points_entry,4),
      DoubleToString(row.spread_points_exit,4),
      DoubleToString(row.slippage_points,4),
      DoubleToString(row.gross_pln,6),
      DoubleToString(row.spread_cost_pln,6),
      DoubleToString(row.slippage_cost_pln,6),
      DoubleToString(row.commission_pln,6),
      DoubleToString(row.swap_pln,6),
      DoubleToString(row.extra_fee_pln,6),
      DoubleToString(row.net_pln,6)
   );
   FileClose(handle);
   return true;
  }

bool MbMlRuntimeBridgeAppendPaperLedger(
   MbMlRuntimeBridgeState &state,
   const datetime now_ts,
   const string symbol,
   const MbPaperPositionState &closed_state,
   const MbMarketSnapshot &market,
   const double paper_pnl,
   const string close_reason
)
  {
   if(!state.enabled)
      return false;

   MbBrokerNetLedgerRow row;
   row.symbol_alias = MbCanonicalSymbol(symbol);
   row.ts = (long)now_ts;
   row.side = (closed_state.side == MB_SIGNAL_BUY ? "BUY" : (closed_state.side == MB_SIGNAL_SELL ? "SELL" : "NONE"));
   row.lots = closed_state.lots;
   row.entry_price = closed_state.entry_price;
   row.exit_price = closed_state.last_mark_price;
   row.spread_points_entry = closed_state.opened_spread_points;
   row.spread_points_exit = market.spread_points;
   row.slippage_points = closed_state.modeled_slippage_points;
   row.gross_pln = (MathIsValidNumber(closed_state.gross_pln) ? closed_state.gross_pln : paper_pnl);
   row.spread_cost_pln = (MathIsValidNumber(closed_state.spread_cost_pln) ? closed_state.spread_cost_pln : 0.0);
   row.slippage_cost_pln = (MathIsValidNumber(closed_state.slippage_cost_pln) ? closed_state.slippage_cost_pln : 0.0);
   row.commission_pln = (MathIsValidNumber(closed_state.commission_pln) ? closed_state.commission_pln : 0.0);
   row.swap_pln = (MathIsValidNumber(closed_state.swap_pln) ? closed_state.swap_pln : 0.0);
   row.extra_fee_pln = (MathIsValidNumber(closed_state.extra_fee_pln) ? closed_state.extra_fee_pln : 0.0);
   row.net_pln = (MathIsValidNumber(closed_state.net_pln) ? closed_state.net_pln : (row.gross_pln - row.slippage_cost_pln - row.commission_pln - row.swap_pln - row.extra_fee_pln));
   return MbMlRuntimeBridgeAppendLedgerRow(state,row);
  }

bool MbMlRuntimeBridgeAppendLiveDealLedger(
   MbMlRuntimeBridgeState &state,
   const string symbol,
   const ulong magic,
   const ulong deal_ticket
)
  {
   if(!state.enabled || deal_ticket == 0)
      return false;
   if(!HistoryDealSelect(deal_ticket))
      return false;
   if((ulong)HistoryDealGetInteger(deal_ticket,DEAL_MAGIC) != magic)
      return false;
   if(HistoryDealGetString(deal_ticket,DEAL_SYMBOL) != symbol)
      return false;
   if((int)HistoryDealGetInteger(deal_ticket,DEAL_ENTRY) != DEAL_ENTRY_OUT)
      return false;

   MbBrokerNetLedgerRow row;
   row.symbol_alias = MbCanonicalSymbol(symbol);
   row.ts = (long)HistoryDealGetInteger(deal_ticket,DEAL_TIME);
   row.side = "UNKNOWN";
   row.lots = HistoryDealGetDouble(deal_ticket,DEAL_VOLUME);
   row.entry_price = 0.0;
   row.exit_price = HistoryDealGetDouble(deal_ticket,DEAL_PRICE);
   row.spread_points_entry = 0.0;
   row.spread_points_exit = 0.0;
   row.slippage_points = 0.0;
   row.gross_pln = HistoryDealGetDouble(deal_ticket,DEAL_PROFIT);
   row.spread_cost_pln = 0.0;
   row.slippage_cost_pln = 0.0;
   row.commission_pln = HistoryDealGetDouble(deal_ticket,DEAL_COMMISSION);
   row.swap_pln = HistoryDealGetDouble(deal_ticket,DEAL_SWAP);
   row.extra_fee_pln = HistoryDealGetDouble(deal_ticket,DEAL_FEE);
   row.net_pln = row.gross_pln + row.commission_pln + row.swap_pln + row.extra_fee_pln;
   return MbMlRuntimeBridgeAppendLedgerRow(state,row);
  }

#endif
