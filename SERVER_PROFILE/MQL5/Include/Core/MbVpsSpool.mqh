#ifndef MB_VPS_SPOOL_INCLUDED
#define MB_VPS_SPOOL_INCLUDED

#include "MbStorage.mqh"

int g_mb_vps_spool_bucket_minutes = 1;

bool MbVpsSpoolEnabled()
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION) != 0)
      return false;
   if(MbHasStrategyTesterSandbox())
      return false;
   return true;
  }

string MbVpsSpoolRootDir()
  {
   return MbRootPath() + "\\spool";
  }

datetime MbVpsSpoolBucketStart(const datetime ts)
  {
   int bucket_minutes = MathMax(1,g_mb_vps_spool_bucket_minutes);
   long bucket_seconds = (long)bucket_minutes * 60;
   if(bucket_seconds <= 0)
      bucket_seconds = 60;
   return (datetime)((long)ts - ((long)ts % bucket_seconds));
  }

string MbVpsSpoolUtcToken(const datetime ts)
  {
   MqlDateTime parts;
   TimeToStruct(ts,parts);
   return StringFormat("%04d%02d%02dT%02d%02d%02dZ",parts.year,parts.mon,parts.day,parts.hour,parts.min,parts.sec);
  }

string MbVpsSpoolDayToken(const datetime ts)
  {
   MqlDateTime parts;
   TimeToStruct(ts,parts);
   return StringFormat("%04d%02d%02d",parts.year,parts.mon,parts.day);
  }

string MbVpsSpoolHourToken(const datetime ts)
  {
   MqlDateTime parts;
   TimeToStruct(ts,parts);
   return StringFormat("%02d",parts.hour);
  }

string MbVpsSpoolStreamDir(const string stream,const datetime ts)
  {
   return MbVpsSpoolRootDir() + "\\" + stream + "\\" + MbVpsSpoolDayToken(ts) + "\\" + MbVpsSpoolHourToken(ts);
  }

string MbVpsSpoolChunkBase(const string stream,const string symbol,const datetime ts)
  {
   return MbVpsSpoolStreamDir(stream,ts) + "\\" + MbCanonicalSymbol(symbol) + "__" + MbVpsSpoolUtcToken(ts);
  }

string MbVpsSpoolDataPath(const string stream,const string symbol,const datetime ts)
  {
   return MbVpsSpoolChunkBase(stream,symbol,ts) + ".tsv";
  }

string MbVpsSpoolManifestPath(const string stream,const string symbol,const datetime ts)
  {
   return MbVpsSpoolDataPath(stream,symbol,ts) + ".manifest.json";
  }

string MbVpsSpoolReadyPath(const string stream,const string symbol,const datetime ts)
  {
   return MbVpsSpoolDataPath(stream,symbol,ts) + ".ready";
  }

void MbVpsSpoolEnsureDirs(const string stream,const datetime ts)
  {
   MbEnsureDir(MbRootPath());
   MbEnsureDir(MbVpsSpoolRootDir());
   MbEnsureDir(MbVpsSpoolRootDir() + "\\" + stream);
   MbEnsureDir(MbVpsSpoolRootDir() + "\\" + stream + "\\" + MbVpsSpoolDayToken(ts));
   MbEnsureDir(MbVpsSpoolStreamDir(stream,ts));
  }

string MbVpsSpoolSanitizeField(const string value)
  {
   string out = value;
   StringReplace(out,"\t"," ");
   StringReplace(out,"\r"," ");
   StringReplace(out,"\n"," ");
   return out;
  }

string MbVpsSpoolJoinFields(const string &fields[])
  {
   string line = "";
   for(int i = 0; i < ArraySize(fields); ++i)
     {
      if(i > 0)
         line += "\t";
      line += MbVpsSpoolSanitizeField(fields[i]);
     }
   return line;
  }

void MbVpsSpoolEnsureHeader(const string rel_path,const string &header_fields[])
  {
   int handle = FileOpen(rel_path,FILE_COMMON | FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return;

   if(FileSize(handle) <= 0)
     {
      string header_line = MbVpsSpoolJoinFields(header_fields) + "\r\n";
      FileWriteString(handle,header_line);
     }
   FileClose(handle);
  }

bool MbVpsSpoolAppendLine(const string stream,const string symbol,const datetime bucket_start,const string &header_fields[],const string &row_fields[])
  {
   if(!MbVpsSpoolEnabled())
      return false;

   MbVpsSpoolEnsureDirs(stream,bucket_start);
   string rel_path = MbVpsSpoolDataPath(stream,symbol,bucket_start);
   MbVpsSpoolEnsureHeader(rel_path,header_fields);

   int handle = FileOpen(rel_path,FILE_COMMON | FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
     {
      PrintFormat("MB_VPS_SPOOL_APPEND_FAILED stream=%s symbol=%s path=%s err=%d",stream,MbCanonicalSymbol(symbol),rel_path,GetLastError());
      return false;
     }

   FileSeek(handle,0,SEEK_END);
   FileWriteString(handle,MbVpsSpoolJoinFields(row_fields) + "\r\n");
   FileClose(handle);
   return true;
  }

int MbVpsSpoolCountDataRows(const string rel_path)
  {
   int handle = FileOpen(rel_path,FILE_COMMON | FILE_READ | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return 0;

   int rows = 0;
   bool header_skipped = false;
   while(!FileIsEnding(handle))
     {
      string line = FileReadString(handle);
      if(StringLen(line) <= 0)
         continue;
      if(!header_skipped)
        {
         header_skipped = true;
         continue;
        }
      rows++;
     }
   FileClose(handle);
   return rows;
  }

void MbVpsSpoolWriteManifest(const string stream,const string symbol,const datetime bucket_start)
  {
   if(!MbVpsSpoolEnabled())
      return;

   string data_path = MbVpsSpoolDataPath(stream,symbol,bucket_start);
   int row_count = MbVpsSpoolCountDataRows(data_path);
   string manifest_path = MbVpsSpoolManifestPath(stream,symbol,bucket_start);
   int handle = FileOpen(manifest_path,FILE_COMMON | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return;

   string payload = StringFormat(
      "{\"schema_version\":\"1.0\",\"transport_version\":\"tsv_raw_v1\",\"stream\":\"%s\",\"symbol\":\"%s\",\"bucket_start_utc\":%I64d,\"bucket_end_utc\":%I64d,\"bucket_minutes\":%d,\"row_count\":%d,\"data_path\":\"%s\",\"ready_path\":\"%s\",\"generated_at_utc\":%I64d}",
      MbVpsSpoolSanitizeField(stream),
      MbVpsSpoolSanitizeField(MbCanonicalSymbol(symbol)),
      (long)bucket_start,
      (long)(bucket_start + MathMax(1,g_mb_vps_spool_bucket_minutes) * 60),
      MathMax(1,g_mb_vps_spool_bucket_minutes),
      row_count,
      MbVpsSpoolSanitizeField(data_path),
      MbVpsSpoolSanitizeField(MbVpsSpoolReadyPath(stream,symbol,bucket_start)),
      (long)TimeCurrent()
   );

   FileWriteString(handle,payload);
   FileClose(handle);
  }

void MbVpsSpoolTouchReady(const string stream,const string symbol,const datetime bucket_start)
  {
   string ready_path = MbVpsSpoolReadyPath(stream,symbol,bucket_start);
   int handle = FileOpen(ready_path,FILE_COMMON | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return;
   FileClose(handle);
  }

void MbVpsSpoolAppendOnnx(
   const datetime ts,
   const string symbol,
   const string stage,
   const string runtime_channel,
   const bool available,
   const bool teacher_available,
   const bool teacher_used,
   const double teacher_score,
   const double symbol_score,
   const long latency_us,
   const string reason_code,
   const MbSignalDecision &signal,
   const double spread_points
)
  {
   datetime bucket_start = MbVpsSpoolBucketStart(ts);
   string header_fields[];
   ArrayResize(header_fields,19);
   header_fields[0] = "ts";
   header_fields[1] = "symbol";
   header_fields[2] = "stage";
   header_fields[3] = "runtime_channel";
   header_fields[4] = "available";
   header_fields[5] = "teacher_available";
   header_fields[6] = "teacher_used";
   header_fields[7] = "teacher_score";
   header_fields[8] = "symbol_score";
   header_fields[9] = "latency_us";
   header_fields[10] = "reason_code";
   header_fields[11] = "signal_valid";
   header_fields[12] = "setup_type";
   header_fields[13] = "market_regime";
   header_fields[14] = "spread_regime";
   header_fields[15] = "confidence_bucket";
   header_fields[16] = "score";
   header_fields[17] = "confidence_score";
   header_fields[18] = "spread_points";

   string row_fields[];
   ArrayResize(row_fields,19);
   row_fields[0] = (string)((long)ts);
   row_fields[1] = MbCanonicalSymbol(symbol);
   row_fields[2] = stage;
   row_fields[3] = runtime_channel;
   row_fields[4] = (available ? "1" : "0");
   row_fields[5] = (teacher_available ? "1" : "0");
   row_fields[6] = (teacher_used ? "1" : "0");
   row_fields[7] = DoubleToString(teacher_score,6);
   row_fields[8] = DoubleToString(symbol_score,6);
   row_fields[9] = (string)latency_us;
   row_fields[10] = reason_code;
   row_fields[11] = (signal.valid ? "1" : "0");
   row_fields[12] = signal.setup_type;
   row_fields[13] = signal.market_regime;
   row_fields[14] = signal.spread_regime;
   row_fields[15] = signal.confidence_bucket;
   row_fields[16] = DoubleToString(signal.score,6);
   row_fields[17] = DoubleToString(signal.confidence_score,6);
   row_fields[18] = DoubleToString(spread_points,2);

   if(MbVpsSpoolAppendLine("onnx_observations",symbol,bucket_start,header_fields,row_fields))
     {
      MbVpsSpoolWriteManifest("onnx_observations",symbol,bucket_start);
      MbVpsSpoolTouchReady("onnx_observations",symbol,bucket_start);
     }
  }

void MbVpsSpoolAppendCandidate(
   const datetime ts,
   const string symbol,
   const string stage,
   const bool accepted,
   const string reason_code,
   const string setup_type,
   const string side,
   const double score,
   const double confidence_score,
   const double risk_multiplier,
   const double lots,
   const string market_regime,
   const string spread_regime,
   const string execution_regime,
   const string confidence_bucket,
   const string candle_bias,
   const string candle_quality_grade,
   const double candle_score,
   const string renko_bias,
   const string renko_quality_grade,
   const double renko_score,
   const int renko_run_length,
   const bool renko_reversal_flag,
   const double spread_points
)
  {
   datetime bucket_start = MbVpsSpoolBucketStart(ts);
   string header_fields[];
   ArrayResize(header_fields,24);
   header_fields[0] = "ts";
   header_fields[1] = "symbol";
   header_fields[2] = "stage";
   header_fields[3] = "accepted";
   header_fields[4] = "reason_code";
   header_fields[5] = "setup_type";
   header_fields[6] = "side";
   header_fields[7] = "score";
   header_fields[8] = "confidence_score";
   header_fields[9] = "risk_multiplier";
   header_fields[10] = "lots";
   header_fields[11] = "market_regime";
   header_fields[12] = "spread_regime";
   header_fields[13] = "execution_regime";
   header_fields[14] = "confidence_bucket";
   header_fields[15] = "candle_bias";
   header_fields[16] = "candle_quality_grade";
   header_fields[17] = "candle_score";
   header_fields[18] = "renko_bias";
   header_fields[19] = "renko_quality_grade";
   header_fields[20] = "renko_score";
   header_fields[21] = "renko_run_length";
   header_fields[22] = "renko_reversal_flag";
   header_fields[23] = "spread_points";

   string row_fields[];
   ArrayResize(row_fields,24);
   row_fields[0] = (string)((long)ts);
   row_fields[1] = MbCanonicalSymbol(symbol);
   row_fields[2] = stage;
   row_fields[3] = (accepted ? "1" : "0");
   row_fields[4] = reason_code;
   row_fields[5] = setup_type;
   row_fields[6] = side;
   row_fields[7] = DoubleToString(score,6);
   row_fields[8] = DoubleToString(confidence_score,6);
   row_fields[9] = DoubleToString(risk_multiplier,6);
   row_fields[10] = DoubleToString(lots,4);
   row_fields[11] = market_regime;
   row_fields[12] = spread_regime;
   row_fields[13] = execution_regime;
   row_fields[14] = confidence_bucket;
   row_fields[15] = candle_bias;
   row_fields[16] = candle_quality_grade;
   row_fields[17] = DoubleToString(candle_score,6);
   row_fields[18] = renko_bias;
   row_fields[19] = renko_quality_grade;
   row_fields[20] = DoubleToString(renko_score,6);
   row_fields[21] = (string)renko_run_length;
   row_fields[22] = (renko_reversal_flag ? "1" : "0");
   row_fields[23] = DoubleToString(spread_points,2);

   if(MbVpsSpoolAppendLine("candidate_signals",symbol,bucket_start,header_fields,row_fields))
     {
      MbVpsSpoolWriteManifest("candidate_signals",symbol,bucket_start);
      MbVpsSpoolTouchReady("candidate_signals",symbol,bucket_start);
     }
  }

void MbVpsSpoolAppendLearningV2(
   const string symbol,
   const datetime ts,
   const string setup_type,
   const string market_regime,
   const string spread_regime,
   const string execution_regime,
   const string confidence_bucket,
   const double confidence_score,
   const string candle_bias,
   const string candle_quality_grade,
   const double candle_score,
   const string renko_bias,
   const string renko_quality_grade,
   const double renko_score,
   const int renko_run_length,
   const bool renko_reversal_flag,
   const MbSignalSide side,
   const double pnl,
   const string close_reason
)
  {
   datetime bucket_start = MbVpsSpoolBucketStart(ts);
   string header_fields[];
   ArrayResize(header_fields,20);
   header_fields[0] = "schema_version";
   header_fields[1] = "ts";
   header_fields[2] = "symbol";
   header_fields[3] = "setup_type";
   header_fields[4] = "market_regime";
   header_fields[5] = "spread_regime";
   header_fields[6] = "execution_regime";
   header_fields[7] = "confidence_bucket";
   header_fields[8] = "confidence_score";
   header_fields[9] = "candle_bias";
   header_fields[10] = "candle_quality_grade";
   header_fields[11] = "candle_score";
   header_fields[12] = "renko_bias";
   header_fields[13] = "renko_quality_grade";
   header_fields[14] = "renko_score";
   header_fields[15] = "renko_run_length";
   header_fields[16] = "renko_reversal_flag";
   header_fields[17] = "side";
   header_fields[18] = "pnl";
   header_fields[19] = "close_reason";

   string row_fields[];
   ArrayResize(row_fields,20);
   row_fields[0] = "2.0";
   row_fields[1] = (string)((long)ts);
   row_fields[2] = MbCanonicalSymbol(symbol);
   row_fields[3] = setup_type;
   row_fields[4] = market_regime;
   row_fields[5] = spread_regime;
   row_fields[6] = execution_regime;
   row_fields[7] = confidence_bucket;
   row_fields[8] = DoubleToString(confidence_score,4);
   row_fields[9] = candle_bias;
   row_fields[10] = candle_quality_grade;
   row_fields[11] = DoubleToString(candle_score,4);
   row_fields[12] = renko_bias;
   row_fields[13] = renko_quality_grade;
   row_fields[14] = DoubleToString(renko_score,4);
   row_fields[15] = (string)renko_run_length;
   row_fields[16] = (renko_reversal_flag ? "1" : "0");
   row_fields[17] = (string)((int)side);
   row_fields[18] = DoubleToString(pnl,2);
   row_fields[19] = close_reason;

   if(MbVpsSpoolAppendLine("learning_observations_v2",symbol,bucket_start,header_fields,row_fields))
     {
      MbVpsSpoolWriteManifest("learning_observations_v2",symbol,bucket_start);
      MbVpsSpoolTouchReady("learning_observations_v2",symbol,bucket_start);
     }
  }

#endif
