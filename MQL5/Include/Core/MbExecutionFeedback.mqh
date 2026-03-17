#ifndef MB_EXECUTION_FEEDBACK_INCLUDED
#define MB_EXECUTION_FEEDBACK_INCLUDED

#include "MbRuntimeTypes.mqh"
#include "MbExecutionTelemetry.mqh"
#include "MbIncidentJournal.mqh"

double MbExecutionPressureClamp(const double value)
  {
   return MathMax(0.0,MathMin(1.0,value));
  }

void MbUpdateExecutionPressure(
   const MbMarketSnapshot &snapshot,
   MbRuntimeState &state,
   const long local_latency_us,
   const MbExecutionResult &exec_result
)
  {
   double pressure = state.execution_pressure * 0.92;
   pressure += MathMin(0.18,snapshot.spread_points / MathMax(1.0,snapshot.spread_points + 1.0) * 0.10);
   pressure += MathMin(0.15,MathMax(0.0,exec_result.order_send_ms) / 100.0);
   pressure += MathMin(0.12,MathMax(0.0,local_latency_us) / 15000.0 * 0.10);
   pressure += MathMin(0.20,MathMax(0.0,exec_result.slippage_points) / 10.0 * 0.12);
   if(!exec_result.ok)
      pressure += 0.25;
   if(exec_result.retries_used > 0)
      pressure += MathMin(0.12,0.06 * exec_result.retries_used);
   if(exec_result.ok && exec_result.retcode == 10009 && exec_result.slippage_points <= 1.0 && exec_result.order_send_ms <= 20)
      pressure -= 0.08;
   state.execution_pressure = MbExecutionPressureClamp(pressure);
  }

void MbFinalizeExecutionAttempt(
   const string telemetry_rel_path,
   const string incidents_rel_path,
   const MbMarketSnapshot &snapshot,
   MbRuntimeState &state,
   const long local_latency_us,
   const string action_name,
   MbExecutionResult &exec_result
)
  {
   MbUpdateExecutionPressure(snapshot,state,local_latency_us,exec_result);
   state.last_trade_attempt = TimeCurrent();

   if(!exec_result.ok)
     {
      state.exec_error_streak++;
      MbIncidentNoteRetcode(incidents_rel_path,state.symbol,"order_send",exec_result.retcode,exec_result.retcode_name,exec_result.retries_used + 1);
     }
   else
     {
      state.exec_error_streak = 0;
     }

   MbAppendExecutionTelemetry(
      telemetry_rel_path,
      TimeCurrent(),
      state.symbol,
      action_name,
      local_latency_us,
      exec_result.order_send_ms,
      snapshot.spread_points,
      exec_result.slippage_points,
      exec_result.retcode
   );
  }

#endif
