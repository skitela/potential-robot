#ifndef MB_SUPERVISOR_SNAPSHOT_INCLUDED
#define MB_SUPERVISOR_SNAPSHOT_INCLUDED

#include "MbStatusPlane.mqh"
#include "MbStorage.mqh"
#include "MbPaperTrading.mqh"
#include "MbMlRuntimeBridge.mqh"
#include "MbRuntimeStatusSchema.mqh"

string MbSupervisorSnapshotEscapeJson(const string value)
  {
   string out = value;
   StringReplace(out,"\\","\\\\");
   StringReplace(out,"\"","\\\"");
   return out;
  }

string MbSupervisorSnapshotPath(const string symbol)
  {
   return MbStateFilePath(symbol,"supervisor_snapshot_latest.json");
  }

bool MbSupervisorSnapshotWrite(
   const string symbol,
   const string runtime_channel,
   const string last_stage,
   const string last_reason_code,
   const bool paper_mode_active,
   const MbPaperPositionState &paper_position,
   const MbRuntimeState &runtime_state,
   const MbMarketSnapshot &market,
   const MbLatencyProfile &latency,
   const MbMlRuntimeBridgeState &ml_bridge,
   const double teacher_score,
   const double student_score,
   const bool gate_allowed,
   const string gate_reason_code
)
  {
   string canonical_symbol = MbCanonicalSymbol(symbol);
   string path = MbSupervisorSnapshotPath(canonical_symbol);
   MbEnsureDir(MbSymbolStateDir(canonical_symbol));

   int handle = FileOpen(path,FILE_COMMON | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;

   double local_latency_us_avg = (latency.sample_count > 0 ? (double)latency.local_latency_us_sum / (double)latency.sample_count : 0.0);
   string status_code = MbResolveRuntimeStatus(
      last_stage,
      last_reason_code,
      MbMlRuntimeBridgeContractPresent(ml_bridge),
      MbMlRuntimeBridgeLocalModelAvailable(ml_bridge),
      MbPaperHasOpenPosition(paper_position)
   );

   string payload = StringFormat(
      "{\"schema_version\":\"1.0\",\"symbol\":\"%s\",\"generated_at_utc\":%I64d,\"runtime_channel\":\"%s\",\"status_code\":\"%s\",\"last_stage\":\"%s\",\"last_reason_code\":\"%s\",\"paper_mode_active\":%s,\"paper_position_open\":%s,\"teacher_score\":%.6f,\"student_score\":%.6f,\"gate_allowed\":%s,\"gate_reason_code\":\"%s\",\"contract_present\":%s,\"local_model_available\":%s,\"global_model_available\":%s,\"outcome_ready\":%s,\"local_training_mode\":\"%s\",\"runtime_scope\":\"%s\",\"terminal_ping_ms\":%I64d,\"local_latency_us_avg\":%.2f,\"spread_points\":%.4f,\"signal_confidence\":%.6f,\"last_setup_type\":\"%s\"}",
      MbSupervisorSnapshotEscapeJson(canonical_symbol),
      (long)TimeCurrent(),
      MbSupervisorSnapshotEscapeJson(runtime_channel),
      MbSupervisorSnapshotEscapeJson(status_code),
      MbSupervisorSnapshotEscapeJson(last_stage),
      MbSupervisorSnapshotEscapeJson(last_reason_code),
      MbJsonBool(paper_mode_active),
      MbJsonBool(MbPaperHasOpenPosition(paper_position)),
      teacher_score,
      student_score,
      MbJsonBool(gate_allowed),
      MbSupervisorSnapshotEscapeJson(gate_reason_code),
      MbJsonBool(MbMlRuntimeBridgeContractPresent(ml_bridge)),
      MbJsonBool(MbMlRuntimeBridgeLocalModelAvailable(ml_bridge)),
      MbJsonBool(MbMlRuntimeBridgeGlobalModelAvailable(ml_bridge)),
      MbJsonBool(MbMlRuntimeBridgeOutcomeReady(ml_bridge)),
      MbSupervisorSnapshotEscapeJson(MbMlRuntimeBridgeLocalTrainingMode(ml_bridge)),
      MbSupervisorSnapshotEscapeJson(MbMlRuntimeBridgeRuntimeScope(ml_bridge)),
      market.terminal_ping_last_ms,
      local_latency_us_avg,
      market.spread_points,
      runtime_state.signal_confidence,
      MbSupervisorSnapshotEscapeJson(runtime_state.last_setup_type)
   );

   FileWriteString(handle,payload);
   FileClose(handle);
   return true;
  }

#endif
