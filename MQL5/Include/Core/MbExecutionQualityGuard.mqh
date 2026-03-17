#ifndef MB_EXECUTION_QUALITY_GUARD_INCLUDED
#define MB_EXECUTION_QUALITY_GUARD_INCLUDED

#include "MbRuntimeTypes.mqh"
#include "MbLatencyProfile.mqh"

MbGuardVerdict MbEvaluateExecutionQualityGuard(
   const MbSymbolProfile &profile,
   MbRuntimeState &state,
   const MbLatencyProfile &latency,
   string &reason_code
)
  {
   reason_code = "OK";
   if(latency.execution_attempt_count < 3)
      return MB_GUARD_OK;

   double ok_ratio = MbLatencyExecutionOkRatio(latency);
   double avg_retries = MbLatencyExecutionAvgRetries(latency);
   double avg_slippage = MbLatencyExecutionAvgSlippagePoints(latency);

   double caution_ok_ratio = 0.60;
   double block_ok_ratio = 0.34;
   double caution_slippage = 2.0;
   double block_slippage = 3.5;
   double caution_retries = 0.35;
   double block_retries = 0.80;

   if(profile.session_profile == "FX_ASIA")
     {
      caution_ok_ratio = 0.55;
      block_ok_ratio = 0.30;
      caution_slippage = 2.2;
      block_slippage = 3.8;
     }
   else if(profile.session_profile == "FX_CROSS")
     {
      caution_ok_ratio = 0.58;
      block_ok_ratio = 0.32;
      caution_slippage = 2.4;
      block_slippage = 4.2;
     }
   else if(profile.session_profile == "METALS_SPOT_PM")
     {
      caution_ok_ratio = 0.52;
      block_ok_ratio = 0.28;
      caution_slippage = 3.0;
      block_slippage = 5.0;
      caution_retries = 0.45;
      block_retries = 0.95;
     }
   else if(profile.session_profile == "METALS_FUTURES")
     {
      caution_ok_ratio = 0.50;
      block_ok_ratio = 0.27;
      caution_slippage = 3.2;
      block_slippage = 5.4;
      caution_retries = 0.50;
      block_retries = 1.05;
     }

   if(ok_ratio < block_ok_ratio || avg_slippage >= block_slippage || avg_retries >= block_retries)
     {
      reason_code = "EXEC_QUALITY_BLOCK";
      return MB_GUARD_BLOCK;
     }

   if(ok_ratio < caution_ok_ratio || avg_slippage >= caution_slippage || avg_retries >= caution_retries)
     {
      reason_code = "EXEC_QUALITY_CAUTION";
      state.caution_mode = true;
     }

   return MB_GUARD_OK;
  }

#endif
