#ifndef MB_MICROBOT_HOOKS_INCLUDED
#define MB_MICROBOT_HOOKS_INCLUDED

#include "MbSupervisorSnapshot.mqh"
#include "MbLearningSupervisorSnapshot.mqh"
#include "MbOnnxPilotObservation.mqh"
#include "MbMlRuntimeBridge.mqh"
#include "MbTeacherKnowledgeSnapshot.mqh"

struct MbMicrobotHookState
  {
   string runtime_channel;
   string last_stage;
   string last_reason_code;
   string last_scan_source;
   string last_setup_type;
   string gate_reason_code;
   bool gate_allowed;
   bool gate_visible;
   bool paper_open_visible;
   bool paper_close_visible;
   bool lesson_write_visible;
   bool knowledge_write_visible;
   bool runtime_heartbeat_alive;
   double teacher_score;
   double student_score;
  };

void MbMicrobotHooksReset(MbMicrobotHookState &state)
  {
   state.runtime_channel = "PAPER";
   state.last_stage = "BOOTSTRAP";
   state.last_reason_code = "INITIALIZING";
   state.last_scan_source = "BOOTSTRAP";
   state.last_setup_type = "";
   state.gate_reason_code = "UNASSESSED";
   state.gate_allowed = false;
    state.gate_visible = false;
   state.paper_open_visible = false;
   state.paper_close_visible = false;
   state.lesson_write_visible = false;
   state.knowledge_write_visible = false;
   state.runtime_heartbeat_alive = false;
   state.teacher_score = 0.0;
   state.student_score = 0.0;
  }

string MbMicrobotHooksResolveRuntimeChannel(const bool paper_mode_active)
  {
   return (paper_mode_active ? "PAPER" : "LIVE");
  }

void MbMicrobotHooksInit(MbMicrobotHookState &state,const bool paper_mode_active)
  {
   MbMicrobotHooksReset(state);
   state.runtime_channel = MbMicrobotHooksResolveRuntimeChannel(paper_mode_active);
   state.runtime_heartbeat_alive = true;
  }

void MbMicrobotHooksResetAttemptState(MbMicrobotHookState &state)
  {
   state.gate_reason_code = "UNASSESSED";
   state.gate_allowed = false;
   state.gate_visible = false;
   state.paper_open_visible = false;
   state.paper_close_visible = false;
   state.lesson_write_visible = false;
   state.knowledge_write_visible = false;
  }

void MbMicrobotHooksRecordStage(
   MbMicrobotHookState &state,
   const bool paper_mode_active,
   const string stage,
   const string reason_code
)
  {
   state.runtime_channel = MbMicrobotHooksResolveRuntimeChannel(paper_mode_active);
   state.runtime_heartbeat_alive = true;
   state.last_stage = stage;
   state.last_reason_code = reason_code;
  }

void MbMicrobotHooksRecordScan(
   MbMicrobotHookState &state,
   const bool paper_mode_active,
   const string scan_source,
   const string setup_type,
   const string reason_code
)
  {
   state.runtime_channel = MbMicrobotHooksResolveRuntimeChannel(paper_mode_active);
   state.runtime_heartbeat_alive = true;
   MbMicrobotHooksResetAttemptState(state);
   state.last_stage = "SCAN";
   state.last_reason_code = reason_code;
   state.last_scan_source = scan_source;
   state.last_setup_type = setup_type;
  }

void MbMicrobotHooksRecordObservation(
   MbMicrobotHookState &state,
   const bool paper_mode_active,
   const MbOnnxObservationResult &result
)
  {
   state.runtime_channel = MbMicrobotHooksResolveRuntimeChannel(paper_mode_active);
   state.runtime_heartbeat_alive = true;
   state.teacher_score = result.teacher_score;
   state.student_score = result.symbol_score;
  }

void MbMicrobotHooksRecordGate(
   MbMicrobotHookState &state,
   const bool paper_mode_active,
   const bool gate_allowed,
   const string gate_reason_code
)
  {
   state.runtime_channel = MbMicrobotHooksResolveRuntimeChannel(paper_mode_active);
   state.runtime_heartbeat_alive = true;
   state.gate_allowed = gate_allowed;
   state.gate_reason_code = gate_reason_code;
   state.gate_visible = true;
  }

void MbMicrobotHooksMarkPaperOpen(
   MbMicrobotHookState &state,
   const bool paper_mode_active,
   const bool paper_opened,
   const string reason_code
)
  {
   state.runtime_channel = MbMicrobotHooksResolveRuntimeChannel(paper_mode_active);
   state.runtime_heartbeat_alive = true;
   state.paper_open_visible = paper_opened;
   state.last_stage = "PAPER_OPEN";
   state.last_reason_code = reason_code;
  }

void MbMicrobotHooksMarkPaperClose(
   MbMicrobotHookState &state,
   const bool paper_mode_active,
   const string reason_code
)
  {
   state.runtime_channel = MbMicrobotHooksResolveRuntimeChannel(paper_mode_active);
   state.runtime_heartbeat_alive = true;
   state.paper_close_visible = true;
   state.last_stage = "PAPER_CLOSE";
   state.last_reason_code = reason_code;
  }

void MbMicrobotHooksMarkOutcomeWrites(
   MbMicrobotHookState &state,
   const bool paper_mode_active,
   const bool lesson_written,
   const bool knowledge_written,
   const string reason_code
)
  {
   state.runtime_channel = MbMicrobotHooksResolveRuntimeChannel(paper_mode_active);
   state.runtime_heartbeat_alive = true;
   state.lesson_write_visible = lesson_written;
   state.knowledge_write_visible = knowledge_written;
   state.last_stage = (knowledge_written ? "KNOWLEDGE_WRITE" : (lesson_written ? "LESSON_WRITE" : "OUTCOME_PENDING"));
   state.last_reason_code = reason_code;
  }

bool MbMicrobotHooksWriteSnapshot(
   MbMicrobotHookState &state,
   const string symbol,
   const bool paper_mode_active,
   const MbPaperPositionState &paper_position,
   const MbRuntimeState &runtime_state,
   const MbMarketSnapshot &market,
   const MbLatencyProfile &latency,
   const MbMlRuntimeBridgeState &ml_bridge
)
  {
   bool supervisor_written = MbSupervisorSnapshotWrite(
      symbol,
      state.runtime_channel,
      state.last_stage,
      state.last_reason_code,
      paper_mode_active,
      paper_position,
      runtime_state,
      market,
      latency,
      ml_bridge,
      state.teacher_score,
      state.student_score,
      state.gate_allowed,
      state.gate_reason_code
   );
   bool learning_written = MbLearningSupervisorSnapshotWrite(
      symbol,
      state.runtime_channel,
      state.last_stage,
      state.last_reason_code,
      state.last_scan_source,
      state.last_setup_type,
      paper_mode_active,
      state.runtime_heartbeat_alive,
      state.gate_visible,
      state.paper_open_visible,
      state.paper_close_visible,
      state.lesson_write_visible,
      state.knowledge_write_visible,
      paper_position,
      runtime_state,
      market,
      latency,
      ml_bridge,
      state.teacher_score,
      state.student_score
   );
   double server_ping_ms = (market.operational_ping_ms > 0.0 ? market.operational_ping_ms : (double)market.terminal_ping_last_ms);
   double server_latency_us_avg = (latency.sample_count > 0 ? (double)latency.local_latency_us_sum / (double)latency.sample_count : 0.0);
   string teacher_id = (MbMlRuntimeBridgeTeacherPackagePresent(ml_bridge) ? MbMlRuntimeBridgeTeacherId(ml_bridge) : "GLOBAL_TEACHER_DEFAULT");
   string teacher_scope = (MbMlRuntimeBridgeTeacherPackagePresent(ml_bridge) ? MbMlRuntimeBridgeTeacherScope(ml_bridge) : "GLOBAL");
   string teacher_mode = MbMlRuntimeBridgeTeacherModeLabel(ml_bridge);
   bool teacher_snapshot_written = MbTeacherWriteKnowledgeSnapshot(
      MbMlRuntimeBridgeTeacherSnapshotPath(ml_bridge),
      symbol,
      teacher_id,
      teacher_scope,
      teacher_mode,
      MbMlRuntimeBridgeTeacherPackagePresent(ml_bridge),
      MbMlRuntimeBridgeTeacherPersonalAllowed(ml_bridge),
      state.gate_visible,
      state.lesson_write_visible,
      state.knowledge_write_visible,
      state.last_reason_code,
      MbMlRuntimeBridgeRuntimeScope(ml_bridge),
      MbMlRuntimeBridgeLocalTrainingMode(ml_bridge),
      state.teacher_score,
      state.student_score,
      market.spread_points,
      server_ping_ms,
      server_latency_us_avg
   );
   return (supervisor_written && learning_written && teacher_snapshot_written);
  }

#endif
