#ifndef MB_DECISION_JOURNAL_INCLUDED
#define MB_DECISION_JOURNAL_INCLUDED

#include "MbExecutionCommon.mqh"
#include "MbRuntimeLogRotation.mqh"

struct MbDecisionEventRecord
  {
   datetime ts;
   string symbol;
   string phase;
   string verdict;
   string reason;
   double spread_points;
   double score;
   double lots;
   long retcode;
  };

MbDecisionEventRecord g_mb_decision_queue[];
string g_mb_decision_queue_path = "";

void MbEnsureDecisionHeader(const int h)
  {
   if(h == INVALID_HANDLE || FileSize(h) > 0)
      return;
   FileWrite(h,"ts","symbol","phase","verdict","reason","spread_points","score","lots","retcode","retcode_name");
  }

void MbWriteDecisionEventRecord(const int h,const MbDecisionEventRecord &record)
  {
   FileWrite(
      h,
      (long)record.ts,
      record.symbol,
      record.phase,
      record.verdict,
      record.reason,
      DoubleToString(record.spread_points,2),
      DoubleToString(record.score,6),
      DoubleToString(record.lots,4),
      (long)record.retcode,
      MbClassifyRetcode(record.retcode)
   );
  }

void MbDecisionJournalInit(const string rel_path)
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION) != 0)
     {
      g_mb_decision_queue_path = "";
      ArrayResize(g_mb_decision_queue,0);
      return;
     }

   g_mb_decision_queue_path = rel_path;
   ArrayResize(g_mb_decision_queue,0);
  }

void MbDecisionJournalFlush()
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION) != 0)
     {
      ArrayResize(g_mb_decision_queue,0);
      return;
     }

   int queued = ArraySize(g_mb_decision_queue);
   if(queued <= 0 || StringLen(g_mb_decision_queue_path) <= 0)
      return;

   MbRotateRuntimeLogIfOversized(g_mb_decision_queue_path);
   int h = FileOpen(g_mb_decision_queue_path, FILE_COMMON | FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;
   MbEnsureDecisionHeader(h);
   FileSeek(h,0,SEEK_END);
   for(int i = 0; i < queued; ++i)
      MbWriteDecisionEventRecord(h,g_mb_decision_queue[i]);
   FileClose(h);
   ArrayResize(g_mb_decision_queue,0);
  }

void MbAppendDecisionEvent(
   const string rel_path,
   const datetime ts,
   const string symbol,
   const string phase,
   const string verdict,
   const string reason,
   const double spread_points,
   const double score,
   const double lots,
   const long retcode
)
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION) != 0)
      return;

   MbDecisionEventRecord record;
   record.ts = ts;
   record.symbol = symbol;
   record.phase = phase;
   record.verdict = verdict;
   record.reason = reason;
   record.spread_points = spread_points;
   record.score = score;
   record.lots = lots;
   record.retcode = retcode;

   if(StringLen(g_mb_decision_queue_path) > 0 && rel_path == g_mb_decision_queue_path)
     {
      int next = ArraySize(g_mb_decision_queue);
      ArrayResize(g_mb_decision_queue,next + 1);
      g_mb_decision_queue[next] = record;
      if(ArraySize(g_mb_decision_queue) >= 32)
         MbDecisionJournalFlush();
      return;
     }

   MbRotateRuntimeLogIfOversized(rel_path);
   int h = FileOpen(rel_path, FILE_COMMON | FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;
   MbEnsureDecisionHeader(h);
   FileSeek(h,0,SEEK_END);
   MbWriteDecisionEventRecord(h,record);
   FileClose(h);
  }

#endif
