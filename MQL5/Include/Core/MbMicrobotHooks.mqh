#ifndef MB_MICROBOT_HOOKS_INCLUDED
#define MB_MICROBOT_HOOKS_INCLUDED

#include "MbSupervisorSnapshot.mqh"
#include "MbOnnxPilotObservation.mqh"

struct MbMicrobotHookState
  {
   string runtime_channel;
   string last_stage;
   string last_reason_code;
   string gate_reason_code;
   bool gate_allowed;
   double teacher_score;
   double student_score;
  };

void MbMicrobotHooksReset(MbMicrobotHookState &state)
  {
   state.runtime_channel = "PAPER";
   state.last_stage = "BOOTSTRAP";
   state.last_reason_code = "INITIALIZING";
   state.gate_reason_code = "UNASSESSED";
   state.gate_allowed = false;
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
  }

void MbMicrobotHooksRecordStage(
   MbMicrobotHookState &state,
   const bool paper_mode_active,
   const string stage,
   const string reason_code
)
  {
   state.runtime_channel = MbMicrobotHooksResolveRuntimeChannel(paper_mode_active);
   state.last_stage = stage;
   state.last_reason_code = reason_code;
  }

void MbMicrobotHooksRecordObservation(
   MbMicrobotHookState &state,
   const bool paper_mode_active,
   const MbOnnxObservationResult &result
)
  {
   state.runtime_channel = MbMicrobotHooksResolveRuntimeChannel(paper_mode_active);
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
   state.gate_allowed = gate_allowed;
   state.gate_reason_code = gate_reason_code;
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
   return MbSupervisorSnapshotWrite(
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
  }

#endif
