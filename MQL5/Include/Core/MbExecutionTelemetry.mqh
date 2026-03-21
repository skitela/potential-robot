#ifndef MB_EXECUTION_TELEMETRY_INCLUDED
#define MB_EXECUTION_TELEMETRY_INCLUDED

#include "MbExecutionCommon.mqh"

struct MbExecutionTelemetryRecord
  {
   datetime ts;
   string symbol;
   string action_name;
   long local_latency_us;
   long order_send_ms;
   double spread_points;
   double slippage_points;
   long retcode;
  };

MbExecutionTelemetryRecord g_mb_execution_telemetry_queue[];
string g_mb_execution_telemetry_queue_path = "";

void MbEnsureExecutionTelemetryHeader(const int h)
  {
   if(h == INVALID_HANDLE || FileSize(h) > 0)
      return;
   FileWrite(h,"ts","symbol","action_name","local_latency_us","order_send_ms","spread_points","slippage_points","retcode","retcode_name");
  }

void MbWriteExecutionTelemetryRecord(const int h,const MbExecutionTelemetryRecord &record)
  {
   FileWrite(
      h,
      (long)record.ts,
      record.symbol,
      record.action_name,
      (long)record.local_latency_us,
      (long)record.order_send_ms,
      DoubleToString(record.spread_points,2),
      DoubleToString(record.slippage_points,2),
      (long)record.retcode,
      MbClassifyRetcode(record.retcode)
   );
  }

void MbExecutionTelemetryInit(const string rel_path)
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION) != 0)
     {
      g_mb_execution_telemetry_queue_path = "";
      ArrayResize(g_mb_execution_telemetry_queue,0);
      return;
     }

   g_mb_execution_telemetry_queue_path = rel_path;
   ArrayResize(g_mb_execution_telemetry_queue,0);
  }

void MbExecutionTelemetryFlush()
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION) != 0)
     {
      ArrayResize(g_mb_execution_telemetry_queue,0);
      return;
     }

   int queued = ArraySize(g_mb_execution_telemetry_queue);
   if(queued <= 0 || StringLen(g_mb_execution_telemetry_queue_path) <= 0)
      return;

   int h = FileOpen(g_mb_execution_telemetry_queue_path, FILE_COMMON | FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;
   MbEnsureExecutionTelemetryHeader(h);
   FileSeek(h,0,SEEK_END);
   for(int i = 0; i < queued; ++i)
      MbWriteExecutionTelemetryRecord(h,g_mb_execution_telemetry_queue[i]);
   FileClose(h);
   ArrayResize(g_mb_execution_telemetry_queue,0);
  }

void MbAppendExecutionTelemetry(
   const string rel_path,
   const datetime ts,
   const string symbol,
   const string action_name,
   const long local_latency_us,
   const long order_send_ms,
   const double spread_points,
   const double slippage_points,
   const long retcode
)
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION) != 0)
      return;

   MbExecutionTelemetryRecord record;
   record.ts = ts;
   record.symbol = symbol;
   record.action_name = action_name;
   record.local_latency_us = local_latency_us;
   record.order_send_ms = order_send_ms;
   record.spread_points = spread_points;
   record.slippage_points = slippage_points;
   record.retcode = retcode;

   if(StringLen(g_mb_execution_telemetry_queue_path) > 0 && rel_path == g_mb_execution_telemetry_queue_path)
     {
      int next = ArraySize(g_mb_execution_telemetry_queue);
      ArrayResize(g_mb_execution_telemetry_queue,next + 1);
      g_mb_execution_telemetry_queue[next] = record;
      if(ArraySize(g_mb_execution_telemetry_queue) >= 32)
         MbExecutionTelemetryFlush();
      return;
     }

   int h = FileOpen(rel_path, FILE_COMMON | FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;
   MbEnsureExecutionTelemetryHeader(h);
   FileSeek(h,0,SEEK_END);
   MbWriteExecutionTelemetryRecord(h,record);
   FileClose(h);
  }

#endif
