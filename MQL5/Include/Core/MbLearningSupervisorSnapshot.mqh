#ifndef MB_LEARNING_SUPERVISOR_SNAPSHOT_INCLUDED
#define MB_LEARNING_SUPERVISOR_SNAPSHOT_INCLUDED

#include "MbStatusPlane.mqh"
#include "MbStorage.mqh"
#include "MbPaperTrading.mqh"
#include "MbMlRuntimeBridge.mqh"

string MbLearningSupervisorSnapshotEscapeJson(const string value)
  {
   string out = value;
   StringReplace(out,"\\","\\\\");
   StringReplace(out,"\"","\\\"");
   return out;
  }

string MbLearningSupervisorSnapshotPath(const string symbol)
  {
   return MbStateFilePath(symbol,"learning_supervisor_snapshot_latest.json");
  }

bool MbLearningSupervisorSnapshotWrite(
   const string symbol,
   const string runtime_channel,
   const string last_stage,
   const string last_reason_code,
   const string last_scan_source,
   const string last_setup_type,
   const bool paper_mode_active,
   const bool runtime_heartbeat_alive,
   const bool gate_visible,
   const bool paper_open_visible,
   const bool paper_close_visible,
   const bool lesson_write_visible,
   const bool knowledge_write_visible,
   const MbPaperPositionState &paper_position,
   const MbRuntimeState &runtime_state,
   const MbMarketSnapshot &market,
   const MbLatencyProfile &latency,
   const MbMlRuntimeBridgeState &ml_bridge,
   const double teacher_score,
   const double student_score
)
  {
   string canonical_symbol = MbCanonicalSymbol(symbol);
   string path = MbLearningSupervisorSnapshotPath(canonical_symbol);
   MbEnsureDir(MbSymbolStateDir(canonical_symbol));

   int handle = FileOpen(path,FILE_COMMON | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;

   double local_latency_us_avg = (latency.sample_count > 0 ? (double)latency.local_latency_us_sum / (double)latency.sample_count : 0.0);
   string payload = StringFormat(
      "{\"schema_version\":\"1.0\",\"symbol\":\"%s\",\"generated_at_utc\":%I64d,\"runtime_channel\":\"%s\",\"runtime_heartbeat_alive\":%s,\"paper_mode_active\":%s,\"last_stage\":\"%s\",\"last_reason_code\":\"%s\",\"last_scan_source\":\"%s\",\"setup_type\":\"%s\",\"gate_visible\":%s,\"paper_open_visible\":%s,\"paper_close_visible\":%s,\"lesson_write_visible\":%s,\"knowledge_write_visible\":%s,\"paper_position_open\":%s,\"teacher_score\":%.6f,\"student_score\":%.6f,\"contract_present\":%s,\"local_model_available\":%s,\"global_model_available\":%s,\"outcome_ready\":%s,\"local_training_mode\":\"%s\",\"runtime_scope\":\"%s\",\"market_session_open\":%s,\"spread_points\":%.4f,\"terminal_ping_ms\":%I64d,\"local_latency_us_avg\":%.2f}",
      MbLearningSupervisorSnapshotEscapeJson(canonical_symbol),
      (long)TimeCurrent(),
      MbLearningSupervisorSnapshotEscapeJson(runtime_channel),
      MbJsonBool(runtime_heartbeat_alive),
      MbJsonBool(paper_mode_active),
      MbLearningSupervisorSnapshotEscapeJson(last_stage),
      MbLearningSupervisorSnapshotEscapeJson(last_reason_code),
      MbLearningSupervisorSnapshotEscapeJson(last_scan_source),
      MbLearningSupervisorSnapshotEscapeJson(last_setup_type),
      MbJsonBool(gate_visible),
      MbJsonBool(paper_open_visible),
      MbJsonBool(paper_close_visible),
      MbJsonBool(lesson_write_visible),
      MbJsonBool(knowledge_write_visible),
      MbJsonBool(MbPaperHasOpenPosition(paper_position)),
      teacher_score,
      student_score,
      MbJsonBool(MbMlRuntimeBridgeContractPresent(ml_bridge)),
      MbJsonBool(MbMlRuntimeBridgeLocalModelAvailable(ml_bridge)),
      MbJsonBool(MbMlRuntimeBridgeGlobalModelAvailable(ml_bridge)),
      MbJsonBool(MbMlRuntimeBridgeOutcomeReady(ml_bridge)),
      MbLearningSupervisorSnapshotEscapeJson(MbMlRuntimeBridgeLocalTrainingMode(ml_bridge)),
      MbLearningSupervisorSnapshotEscapeJson(MbMlRuntimeBridgeRuntimeScope(ml_bridge)),
      MbJsonBool(market.trade_permissions_ok),
      market.spread_points,
      market.terminal_ping_last_ms,
      local_latency_us_avg
   );

   FileWriteString(handle,payload);
   FileClose(handle);
   return true;
  }

#endif
