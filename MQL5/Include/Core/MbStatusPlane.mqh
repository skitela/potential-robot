#ifndef MB_STATUS_PLANE_INCLUDED
#define MB_STATUS_PLANE_INCLUDED

#include "MbRuntimeTypes.mqh"
#include "MbStorage.mqh"

string MbJsonBool(const bool value)
  {
   return (value ? "true" : "false");
  }

string MbRuntimeModeLabel(const MbRuntimeMode mode)
  {
   switch(mode)
     {
      case MB_MODE_BLOCKED: return "BLOCKED";
      case MB_MODE_CAUTION: return "CAUTION";
      case MB_MODE_READY: return "READY";
      case MB_MODE_CLOSE_ONLY: return "CLOSE_ONLY";
     }
   return "UNKNOWN";
  }

string MbRuntimeModeLabelForState(const MbRuntimeState &state)
  {
   if(state.halt)
      return "BLOCKED";
   if(state.paper_mode_active)
      return "PAPER_ONLY";
   if(state.close_only)
      return "CLOSE_ONLY";
   if(state.caution_mode)
      return "CAUTION";
   return MbRuntimeModeLabel(state.mode);
  }

int MbCooldownLeftSec(const MbRuntimeState &state)
  {
   if(state.cooldown_until <= 0 || TimeCurrent() >= state.cooldown_until)
      return 0;
   return (int)(state.cooldown_until - TimeCurrent());
  }

int MbIncidentPressure(const MbRuntimeState &state)
  {
   return state.loss_streak + state.exec_error_streak + state.spread_anomaly_streak;
  }

bool MbFlushHeartbeat(MbRuntimeState &state)
  {
   int h = FileOpen(MbStateFilePath(state.symbol,"heartbeat.txt"), FILE_COMMON | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;
   state.last_heartbeat_at = TimeCurrent();
   FileWriteString(h,IntegerToString((int)state.last_heartbeat_at));
   FileClose(h);
   return true;
  }

bool MbFlushRuntimeStatus(const MbRuntimeState &state,const string reason_code)
  {
   int h = FileOpen(MbStateFilePath(state.symbol,"runtime_status.json"), FILE_COMMON | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;
   string payload = StringFormat(
      "{\"schema_version\":\"1.2\",\"symbol\":\"%s\",\"runtime_mode\":\"%s\",\"caution_mode\":%s,\"close_only\":%s,\"halt\":%s,\"force_flatten\":%s,\"trade_rights\":%s,\"paper_rights\":%s,\"observation_rights\":%s,\"allowed_direction\":\"%s\",\"cooldown_left_sec\":%d,\"incident_pressure\":%d,\"ticks_seen\":%I64d,\"timer_cycles\":%I64d,\"execution_pressure\":%.4f,\"reason_code\":\"%s\",\"heartbeat_utc\":%I64d}",
      state.symbol,
      MbRuntimeModeLabelForState(state),
      MbJsonBool(state.caution_mode),
      MbJsonBool(state.close_only),
      MbJsonBool(state.halt),
      MbJsonBool(state.force_flatten),
      MbJsonBool(state.trade_rights),
      MbJsonBool(state.paper_rights),
      MbJsonBool(state.observation_rights),
      MbResolveAllowedDirectionForState(state),
      MbCooldownLeftSec(state),
      MbIncidentPressure(state),
      state.ticks_seen,
      state.timer_cycles,
      state.execution_pressure,
      reason_code,
      (long)TimeCurrent()
   );
   FileWriteString(h,payload);
   FileClose(h);
   return true;
  }

#endif
