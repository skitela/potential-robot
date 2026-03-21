#ifndef MB_RUNTIME_CONTROL_INCLUDED
#define MB_RUNTIME_CONTROL_INCLUDED

#include "MbRuntimeTypes.mqh"
#include "MbStorage.mqh"

string MbResolveDomainFromSessionProfile(const string session_profile)
  {
   if(session_profile == "FX_MAIN" || session_profile == "FX_ASIA" || session_profile == "FX_CROSS")
      return "FX";
   if(session_profile == "METALS_SPOT_PM" || session_profile == "METALS_FUTURES")
      return "METALS";
   if(session_profile == "INDEX_EU" || session_profile == "INDEX_US")
      return "INDICES";
   return "";
  }

string MbDomainRuntimeControlPath(const string domain)
  {
   if(StringLen(domain) <= 0)
      return "";
   return MbDomainStateDir(domain) + "\\runtime_control.csv";
  }

bool MbIsEffectivePaperRuntimeActive(
   const bool live_entries_enabled,
   const bool paper_collect_mode,
   const MbRuntimeControlState &control
)
  {
   return (!live_entries_enabled || paper_collect_mode || control.paper_only);
  }

void MbRecalculateRuntimeControlRights(MbRuntimeControlState &state)
  {
   if(state.halt)
     {
      state.trade_rights = false;
      state.paper_rights = false;
      state.observation_rights = false;
      return;
     }

   state.observation_rights = true;
   if(state.paper_only)
     {
      state.trade_rights = false;
      state.paper_rights = true;
      return;
     }

   if(state.close_only)
     {
      state.trade_rights = false;
      state.paper_rights = false;
      return;
     }

   state.trade_rights = true;
   state.paper_rights = false;
  }

void MbApplyRuntimeRights(
   MbRuntimeState &state,
   const bool trade_rights,
   const bool paper_rights,
   const bool observation_rights
)
  {
   state.trade_rights = trade_rights;
   state.paper_rights = paper_rights;
   state.observation_rights = observation_rights;
  }

void MbMergeRuntimeControl(MbRuntimeControlState &io_target,const MbRuntimeControlState &overlay)
  {
   io_target.risk_cap = MathMin(io_target.risk_cap,MathMax(0.0,overlay.risk_cap));
   io_target.force_flatten = (io_target.force_flatten || overlay.force_flatten);

   if(overlay.halt)
     {
      io_target.halt = true;
      io_target.paper_only = false;
      io_target.close_only = false;
      io_target.requested_mode = "HALT";
      io_target.reason_code = overlay.reason_code;
      MbRecalculateRuntimeControlRights(io_target);
      return;
     }

   if(overlay.paper_only && !io_target.halt)
     {
      io_target.paper_only = true;
      io_target.close_only = false;
      io_target.requested_mode = "PAPER_ONLY";
      io_target.reason_code = overlay.reason_code;
      MbRecalculateRuntimeControlRights(io_target);
      return;
     }

   if(overlay.close_only && !io_target.halt && !io_target.paper_only)
     {
      io_target.close_only = true;
      io_target.requested_mode = "CLOSE_ONLY";
      io_target.reason_code = overlay.reason_code;
     }

   MbRecalculateRuntimeControlRights(io_target);
  }

void MbReadRuntimeControlFile(const string path,MbRuntimeControlState &out)
  {
   MbRuntimeControlStateReset(out);
   int h = FileOpen(path, FILE_COMMON | FILE_READ | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;
   while(!FileIsEnding(h))
     {
      string key = FileReadString(h);
      string value = FileReadString(h);
      if(key == "requested_mode")
         out.requested_mode = value;
      else if(key == "reason_code")
         out.reason_code = value;
      else if(key == "risk_cap")
         out.risk_cap = StringToDouble(value);
      else if(key == "force_flatten")
         out.force_flatten = (StringToInteger(value) != 0);
     }
   FileClose(h);

   string mode = out.requested_mode;
   StringToUpper(mode);
   if(mode == "HALT")
      out.halt = true;
   else if(mode == "PAPER_ONLY")
      out.paper_only = true;
   else if(mode == "CLOSE_ONLY")
      out.close_only = true;

   MbRecalculateRuntimeControlRights(out);
  }

void MbReadRuntimeControl(const string symbol,MbRuntimeControlState &out)
  {
   MbReadRuntimeControlFile(MbStateFilePath(symbol,"runtime_control.csv"),out);
  }

void MbReadRuntimeControl(const string symbol,const string session_profile,MbRuntimeControlState &out)
  {
   MbReadRuntimeControl(symbol,out);

   string domain = MbResolveDomainFromSessionProfile(session_profile);
   if(StringLen(domain) <= 0)
      return;

   MbRuntimeControlState domain_control;
   MbReadRuntimeControlFile(MbDomainRuntimeControlPath(domain),domain_control);
   MbMergeRuntimeControl(out,domain_control);
  }

void MbApplyRuntimeControl(MbRuntimeState &state,const MbRuntimeControlState &control)
  {
   state.halt = control.halt;
   state.paper_mode_active = (control.paper_only && !control.halt);
   state.close_only = (control.close_only && !control.halt && !control.paper_only);
   state.force_flatten = control.force_flatten;
   state.coordinator_risk_cap = MathMax(0.0,MathMin(control.risk_cap,1.0));
   MbApplyRuntimeRights(state,control.trade_rights,control.paper_rights,control.observation_rights);

   if(state.paper_mode_active)
     {
      state.halt = false;
      state.close_only = false;
      state.caution_mode = false;
      state.mode = MB_MODE_READY;
      MbApplyRuntimeRights(state,false,true,true);
      return;
     }

   if(state.halt)
     {
      state.mode = MB_MODE_BLOCKED;
      MbApplyRuntimeRights(state,false,false,false);
      return;
     }

   if(state.close_only)
     {
      state.mode = MB_MODE_CLOSE_ONLY;
      MbApplyRuntimeRights(state,false,false,true);
      return;
     }

   state.mode = (state.caution_mode ? MB_MODE_CAUTION : MB_MODE_READY);
   MbApplyRuntimeRights(state,true,false,true);
  }

void MbNormalizePaperRuntimeState(MbRuntimeState &state,const bool paper_mode_active)
  {
   state.paper_mode_active = paper_mode_active;
   if(!paper_mode_active)
      return;

   state.halt = false;
   state.close_only = false;
   state.caution_mode = false;
   state.mode = MB_MODE_READY;
   MbApplyRuntimeRights(state,false,true,true);
  }

void MbRefreshPaperTradeRights(MbRuntimeState &state,const bool paper_mode_active)
  {
   if(!paper_mode_active)
      return;

   state.halt = false;
   state.close_only = false;
   state.mode = MB_MODE_READY;
   MbApplyRuntimeRights(state,false,true,true);
  }

void MbNormalizePaperRuntimeState(
   MbRuntimeState &state,
   MbMarketSnapshot &snapshot,
   const bool paper_mode_active
)
  {
   MbNormalizePaperRuntimeState(state,paper_mode_active);
   snapshot.paper_runtime_override_active = paper_mode_active;
   if(!paper_mode_active)
      return;
   snapshot.trade_permissions_ok = true;
  }

void MbApplyPaperRuntimeOverride(
   MbRuntimeState &state,
   MbMarketSnapshot &snapshot,
   MbKillSwitchState &kill_switch,
   const bool paper_mode_active
)
  {
   MbNormalizePaperRuntimeState(state,snapshot,paper_mode_active);
   if(!paper_mode_active)
      return;

   kill_switch.halt = false;
   kill_switch.reason_code = "PAPER_MODE_ACTIVE";
  }

#endif
