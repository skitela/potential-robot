#ifndef MB_LATENCY_PROFILE_INCLUDED
#define MB_LATENCY_PROFILE_INCLUDED

#include "MbRuntimeTypes.mqh"

void MbLatencyProfileInit(MbLatencyProfile &profile)
  {
   MbLatencyProfileReset(profile);
  }

void MbLatencyProfileRecord(MbLatencyProfile &profile,const long local_latency_us,const long order_send_ms)
  {
   if(profile.window_started_at <= 0)
      profile.window_started_at = TimeCurrent();
   profile.sample_count++;
   profile.local_latency_us_sum += MathMax(0,local_latency_us);
   profile.local_latency_us_max = MathMax(profile.local_latency_us_max,local_latency_us);
   profile.order_send_ms_sum += MathMax(0,order_send_ms);
   profile.order_send_ms_max = MathMax(profile.order_send_ms_max,order_send_ms);
   profile.last_local_latency_us = local_latency_us;
   profile.last_order_send_ms = order_send_ms;
  }

void MbLatencyProfileRecordExecution(
   MbLatencyProfile &profile,
   const bool exec_ok,
   const int retries_used,
   const double slippage_points
)
  {
   if(profile.window_started_at <= 0)
      profile.window_started_at = TimeCurrent();
   profile.execution_attempt_count++;
   if(exec_ok)
      profile.execution_ok_count++;
   profile.execution_retry_sum += MathMax(0,retries_used);
   profile.execution_slippage_sum += MathMax(0.0,slippage_points);
   profile.execution_slippage_max = MathMax(profile.execution_slippage_max,MathMax(0.0,slippage_points));
  }

double MbLatencyExecutionOkRatio(const MbLatencyProfile &profile)
  {
   if(profile.execution_attempt_count <= 0)
      return 1.0;
   return ((double)profile.execution_ok_count / (double)profile.execution_attempt_count);
  }

double MbLatencyExecutionAvgRetries(const MbLatencyProfile &profile)
  {
   if(profile.execution_attempt_count <= 0)
      return 0.0;
   return ((double)profile.execution_retry_sum / (double)profile.execution_attempt_count);
  }

double MbLatencyExecutionAvgSlippagePoints(const MbLatencyProfile &profile)
  {
   if(profile.execution_attempt_count <= 0)
      return 0.0;
   return (profile.execution_slippage_sum / (double)profile.execution_attempt_count);
  }

void MbBuildExecutionSummary(const MbLatencyProfile &profile,MbExecutionSummary &out)
  {
   out.latency_samples = profile.sample_count;
   out.local_latency_us_avg = (profile.sample_count > 0 ? (profile.local_latency_us_sum / profile.sample_count) : 0);
   out.local_latency_us_max = profile.local_latency_us_max;
   out.order_send_ms_avg = (profile.sample_count > 0 ? (profile.order_send_ms_sum / profile.sample_count) : 0);
   out.order_send_ms_max = profile.order_send_ms_max;
   out.last_local_latency_us = profile.last_local_latency_us;
   out.last_order_send_ms = profile.last_order_send_ms;
   out.execution_attempt_count = profile.execution_attempt_count;
   out.execution_ok_count = profile.execution_ok_count;
   out.execution_retry_avg_milli = (profile.execution_attempt_count > 0 ? (long)MathRound((1000.0 * profile.execution_retry_sum) / profile.execution_attempt_count) : 0);
   out.execution_slippage_points_avg_milli = (profile.execution_attempt_count > 0 ? (long)MathRound((1000.0 * profile.execution_slippage_sum) / profile.execution_attempt_count) : 0);
   out.execution_slippage_points_max_milli = (long)MathRound(1000.0 * profile.execution_slippage_max);
  }

void MbLatencyProfileFlush(MbLatencyProfile &profile,const string rel_path)
  {
   if(profile.sample_count <= 0)
      return;
   int h = FileOpen(rel_path, FILE_COMMON | FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;
   FileSeek(h,0,SEEK_END);
   FileWrite(
      h,
      (long)TimeCurrent(),
      (long)profile.window_started_at,
      (long)profile.sample_count,
      (long)(profile.local_latency_us_sum / profile.sample_count),
      (long)profile.local_latency_us_max,
      (long)(profile.order_send_ms_sum / profile.sample_count),
      (long)profile.order_send_ms_max,
      (long)profile.last_local_latency_us,
      (long)profile.last_order_send_ms,
      (long)profile.execution_attempt_count,
      (long)profile.execution_ok_count,
      (long)profile.execution_retry_sum,
      DoubleToString(profile.execution_slippage_sum,3),
      DoubleToString(profile.execution_slippage_max,3)
   );
   FileClose(h);
   MbLatencyProfileInit(profile);
  }

#endif
