#ifndef MB_EXECUTION_PING_CONTRACT_INCLUDED
#define MB_EXECUTION_PING_CONTRACT_INCLUDED

#include "MbRuntimeTypes.mqh"
#include "MbStoragePaths.mqh"

struct MbExecutionPingContract
  {
   bool present;
   bool enabled;
   int revision;
   int refresh_interval_sec;
   double paper_operational_ping_ms;
   double live_operational_ping_ms;
  };

void MbExecutionPingContractReset(MbExecutionPingContract &contract)
  {
   contract.present = false;
   contract.enabled = false;
   contract.revision = 0;
   contract.refresh_interval_sec = 300;
   contract.paper_operational_ping_ms = 0.0;
   contract.live_operational_ping_ms = 0.0;
  }

string MbExecutionPingContractPath()
  {
   return MbGlobalStateDir() + "\\execution_ping_contract.csv";
  }

bool MbReadExecutionPingContract(MbExecutionPingContract &out)
  {
   MbExecutionPingContractReset(out);

   int h = FileOpen(MbExecutionPingContractPath(),FILE_COMMON | FILE_READ | FILE_CSV | FILE_ANSI);
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
      else if(key == "paper_operational_ping_ms")
         out.paper_operational_ping_ms = StringToDouble(value);
      else if(key == "live_operational_ping_ms")
         out.live_operational_ping_ms = StringToDouble(value);
     }
   FileClose(h);

   if(out.refresh_interval_sec < 60)
      out.refresh_interval_sec = 60;
   return true;
  }

double MbResolveManualExecutionPingMs(const bool paper_mode,const MbExecutionPingContract &contract)
  {
   if(!contract.present || !contract.enabled)
      return 0.0;

   return (paper_mode ? contract.paper_operational_ping_ms : contract.live_operational_ping_ms);
  }

void MbRefreshOperationalExecutionPing(const bool paper_mode,MbMarketSnapshot &snapshot)
  {
   static MbExecutionPingContract cached_contract;
   static bool cached_initialized = false;
   static datetime last_refresh = 0;

   bool should_refresh = (!cached_initialized);
   if(!should_refresh)
     {
      int refresh_interval_sec = (cached_contract.refresh_interval_sec >= 60 ? cached_contract.refresh_interval_sec : 300);
      should_refresh = (last_refresh <= 0 || (TimeCurrent() - last_refresh) >= refresh_interval_sec);
     }

   if(should_refresh)
     {
      MbExecutionPingContract current_contract;
      if(MbReadExecutionPingContract(current_contract))
         cached_contract = current_contract;
      else
         MbExecutionPingContractReset(cached_contract);
      cached_initialized = true;
      last_refresh = TimeCurrent();
     }

   snapshot.execution_ping_contract_present = cached_contract.present;
   snapshot.execution_ping_contract_enabled = (cached_contract.present && cached_contract.enabled);

   double resolved_ping_ms = MbResolveManualExecutionPingMs(paper_mode,cached_contract);
   if(resolved_ping_ms > 0.0)
      snapshot.operational_ping_ms = resolved_ping_ms;
   else
      snapshot.operational_ping_ms = 0.0;
  }

#endif
