#ifndef MB_CANDIDATE_SIGNAL_JOURNAL_INCLUDED
#define MB_CANDIDATE_SIGNAL_JOURNAL_INCLUDED

#include "MbRuntimeTypes.mqh"
#include "MbStorage.mqh"

struct MbCandidateSignalRecord
  {
   datetime ts;
   string symbol;
   string stage;
   bool accepted;
   string reason_code;
   string setup_type;
   MbSignalSide side;
   double score;
   double confidence_score;
   double risk_multiplier;
   double lots;
   string market_regime;
   string spread_regime;
   string execution_regime;
   string confidence_bucket;
   string candle_bias;
   string candle_quality_grade;
   double candle_score;
   string renko_bias;
   string renko_quality_grade;
   double renko_score;
   int renko_run_length;
   bool renko_reversal_flag;
   double spread_points;
  };

MbCandidateSignalRecord g_mb_candidate_queue[];
string g_mb_candidate_queue_path = "";

string MbCandidateSignalSideName(const MbSignalSide side)
  {
   if(side == MB_SIGNAL_BUY)
      return "BUY";
   if(side == MB_SIGNAL_SELL)
      return "SELL";
   return "NONE";
  }

void MbEnsureCandidateSignalHeader(const int h)
  {
   if(h == INVALID_HANDLE || FileSize(h) > 0)
      return;

   FileWrite(
      h,
      "ts",
      "symbol",
      "stage",
      "accepted",
      "reason_code",
      "setup_type",
      "side",
      "score",
      "confidence_score",
      "risk_multiplier",
      "lots",
      "market_regime",
      "spread_regime",
      "execution_regime",
      "confidence_bucket",
      "candle_bias",
      "candle_quality_grade",
      "candle_score",
      "renko_bias",
      "renko_quality_grade",
      "renko_score",
      "renko_run_length",
      "renko_reversal_flag",
      "spread_points"
   );
  }

void MbWriteCandidateSignalRecord(const int h,const MbCandidateSignalRecord &record)
  {
   FileWrite(
      h,
      (long)record.ts,
      MbCanonicalSymbol(record.symbol),
      record.stage,
      (record.accepted ? 1 : 0),
      record.reason_code,
      record.setup_type,
      MbCandidateSignalSideName(record.side),
      DoubleToString(record.score,6),
      DoubleToString(record.confidence_score,6),
      DoubleToString(record.risk_multiplier,6),
      DoubleToString(record.lots,4),
      record.market_regime,
      record.spread_regime,
      record.execution_regime,
      record.confidence_bucket,
      record.candle_bias,
      record.candle_quality_grade,
      DoubleToString(record.candle_score,6),
      record.renko_bias,
      record.renko_quality_grade,
      DoubleToString(record.renko_score,6),
      record.renko_run_length,
      (record.renko_reversal_flag ? 1 : 0),
      DoubleToString(record.spread_points,2)
   );
  }

void MbCandidateSignalJournalInit(const string rel_path)
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION) != 0)
     {
      g_mb_candidate_queue_path = "";
      ArrayResize(g_mb_candidate_queue,0);
      return;
     }

   g_mb_candidate_queue_path = rel_path;
   ArrayResize(g_mb_candidate_queue,0);

   if(StringLen(rel_path) <= 0 || FileIsExist(rel_path,FILE_COMMON))
      return;

   int h = FileOpen(rel_path,FILE_COMMON | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;
   MbEnsureCandidateSignalHeader(h);
   FileClose(h);
  }

void MbCandidateSignalJournalFlush()
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION) != 0)
     {
      ArrayResize(g_mb_candidate_queue,0);
      return;
     }

   int queued = ArraySize(g_mb_candidate_queue);
   if(queued <= 0 || StringLen(g_mb_candidate_queue_path) <= 0)
      return;

   int h = FileOpen(g_mb_candidate_queue_path,FILE_COMMON | FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;

   MbEnsureCandidateSignalHeader(h);
   FileSeek(h,0,SEEK_END);
   for(int i = 0; i < queued; ++i)
      MbWriteCandidateSignalRecord(h,g_mb_candidate_queue[i]);
   FileClose(h);
   ArrayResize(g_mb_candidate_queue,0);
  }

void MbAppendCandidateSignal(
   const string rel_path,
   const datetime ts,
   const string symbol,
   const string stage,
   const bool accepted,
   const string reason_code,
   const MbSignalDecision &signal,
   const double spread_points,
   const double lots
)
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION) != 0)
      return;

   MbCandidateSignalRecord record;
   record.ts = ts;
   record.symbol = symbol;
   record.stage = stage;
   record.accepted = accepted;
   record.reason_code = reason_code;
   record.setup_type = (signal.setup_type == "" ? "NONE" : signal.setup_type);
   record.side = signal.side;
   record.score = signal.score;
   record.confidence_score = signal.confidence_score;
   record.risk_multiplier = signal.risk_multiplier;
   record.lots = lots;
   record.market_regime = signal.market_regime;
   record.spread_regime = signal.spread_regime;
   record.execution_regime = signal.execution_regime;
   record.confidence_bucket = signal.confidence_bucket;
   record.candle_bias = signal.candle_bias;
   record.candle_quality_grade = signal.candle_quality_grade;
   record.candle_score = signal.candle_score;
   record.renko_bias = signal.renko_bias;
   record.renko_quality_grade = signal.renko_quality_grade;
   record.renko_score = signal.renko_score;
   record.renko_run_length = signal.renko_run_length;
   record.renko_reversal_flag = signal.renko_reversal_flag;
   record.spread_points = spread_points;

   if(StringLen(g_mb_candidate_queue_path) > 0 && rel_path == g_mb_candidate_queue_path)
     {
      int next = ArraySize(g_mb_candidate_queue);
      ArrayResize(g_mb_candidate_queue,next + 1);
      g_mb_candidate_queue[next] = record;
      if(ArraySize(g_mb_candidate_queue) >= 64)
         MbCandidateSignalJournalFlush();
      return;
     }

   int h = FileOpen(rel_path,FILE_COMMON | FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;

   MbEnsureCandidateSignalHeader(h);
   FileSeek(h,0,SEEK_END);
   MbWriteCandidateSignalRecord(h,record);
   FileClose(h);
  }

#endif
