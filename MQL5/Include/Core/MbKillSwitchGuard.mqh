#ifndef MB_KILL_SWITCH_GUARD_INCLUDED
#define MB_KILL_SWITCH_GUARD_INCLUDED

#include "MbRuntimeTypes.mqh"
#include "MbStorage.mqh"

void MbKillSwitchEvaluate(const MbSymbolProfile &profile,MbRuntimeState &state,MbKillSwitchState &out)
  {
   MbKillSwitchStateReset(out);
   out.armed = profile.kill_switch_required;

   if(!profile.kill_switch_required)
      return;

   datetime now_ts = TimeCurrent();
   if(state.last_kill_switch_check > 0 && (now_ts - state.last_kill_switch_check) < 2)
     {
      out.token_present = state.kill_switch_cached_present;
      out.halt = state.kill_switch_cached_halt;
      out.reason_code = (out.halt ? "KILL_SWITCH_TOKEN_BLOCKED" : "OK");
      return;
     }

   string token_path = MbKeyFilePath(profile.symbol,profile.kill_switch_token_name);
   ResetLastError();
   int h = FileOpen(token_path, FILE_COMMON | FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
     {
      out.halt = true;
      out.reason_code = "KILL_SWITCH_TOKEN_MISSING";
      return;
     }

   string raw = FileReadString(h);
   FileClose(h);
   datetime ts = (datetime)StringToInteger(raw);
   out.token_present = (ts > 0);
   if(!out.token_present)
     {
      out.halt = true;
      out.reason_code = "KILL_SWITCH_TOKEN_INVALID";
      return;
     }

   if((TimeCurrent() - ts) > profile.kill_switch_max_age_sec)
     {
      out.halt = true;
      out.reason_code = "KILL_SWITCH_TOKEN_STALE";
     }

   state.last_kill_switch_check = now_ts;
   state.kill_switch_cached_present = out.token_present;
   state.kill_switch_cached_halt = out.halt;
  }

#endif
