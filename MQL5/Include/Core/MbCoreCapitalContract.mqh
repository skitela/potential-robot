#ifndef MB_CORE_CAPITAL_CONTRACT_INCLUDED
#define MB_CORE_CAPITAL_CONTRACT_INCLUDED

#include "MbRuntimeTypes.mqh"
#include "MbStoragePaths.mqh"

struct MbCoreCapitalContract
  {
   bool present;
   bool enabled;
   int revision;
   int refresh_interval_sec;
   double paper_core_capital;
   double live_core_capital;
  };

void MbCoreCapitalContractReset(MbCoreCapitalContract &contract)
  {
   contract.present = false;
   contract.enabled = false;
   contract.revision = 0;
   contract.refresh_interval_sec = 60;
   contract.paper_core_capital = 0.0;
   contract.live_core_capital = 0.0;
  }

string MbCoreCapitalContractPath()
  {
   return MbGlobalStateDir() + "\\core_capital_contract.csv";
  }

bool MbReadCoreCapitalContract(MbCoreCapitalContract &out)
  {
   MbCoreCapitalContractReset(out);

   int h = FileOpen(MbCoreCapitalContractPath(),FILE_COMMON | FILE_READ | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;

   out.present = true;
   while(!FileIsEnding(h))
     {
      string key = FileReadString(h);
      string value = FileReadString(h);
      if(key == "enabled")
         out.enabled = (StringToInteger(value) != 0);
      else if(key == "revision")
         out.revision = (int)StringToInteger(value);
      else if(key == "refresh_interval_sec")
         out.refresh_interval_sec = (int)StringToInteger(value);
      else if(key == "paper_core_capital")
         out.paper_core_capital = StringToDouble(value);
      else if(key == "live_core_capital")
         out.live_core_capital = StringToDouble(value);
     }
   FileClose(h);

   if(out.refresh_interval_sec < 15)
      out.refresh_interval_sec = 15;
   return true;
  }

double MbResolveManualCoreCapital(const bool paper_mode,const MbCoreCapitalContract &contract)
  {
   if(!contract.present || !contract.enabled)
      return 0.0;

   return (paper_mode ? contract.paper_core_capital : contract.live_core_capital);
  }

void MbRefreshManualCoreCapital(const bool paper_mode,const MbMarketSnapshot &snapshot,MbRuntimeState &state)
  {
   if(snapshot.equity <= 0.0)
      return;

   bool should_refresh = (state.last_core_contract_check <= 0);
   static MbCoreCapitalContract cached_contract;
   static bool cached_initialized = false;

   if(!cached_initialized)
     {
      MbCoreCapitalContractReset(cached_contract);
      cached_initialized = true;
      should_refresh = true;
     }

   int refresh_interval_sec = 60;
   if(cached_contract.refresh_interval_sec >= 15)
      refresh_interval_sec = cached_contract.refresh_interval_sec;
   if(!should_refresh && state.last_core_contract_check > 0)
      should_refresh = ((TimeCurrent() - state.last_core_contract_check) >= refresh_interval_sec);

   if(should_refresh)
     {
      MbCoreCapitalContract current_contract;
      if(MbReadCoreCapitalContract(current_contract))
         cached_contract = current_contract;
      else
         MbCoreCapitalContractReset(cached_contract);
      state.last_core_contract_check = TimeCurrent();
     }

   state.capital_core_contract_present = cached_contract.present;
   state.capital_core_contract_enabled = (cached_contract.present && cached_contract.enabled);

   double manual_core = MbResolveManualCoreCapital(paper_mode,cached_contract);
   if(manual_core > 0.0)
     {
      state.capital_core_anchor = manual_core;
      return;
     }

   if(state.capital_core_anchor <= 0.0)
      state.capital_core_anchor = snapshot.equity;
  }

#endif
