#ifndef MB_ONNX_PILOT_OBSERVATION_INCLUDED
#define MB_ONNX_PILOT_OBSERVATION_INCLUDED

#include "MbStorage.mqh"
#include "MbStatusPlane.mqh"

struct MbOnnxObservationResult
  {
   bool available;
   bool teacher_available;
   bool teacher_used;
   bool run_ok;
   double teacher_score;
   double symbol_score;
   long latency_us;
   string reason_code;
  };

bool   g_mb_onnx_obs_enabled = false;
bool   g_mb_onnx_obs_symbol_ready = false;
bool   g_mb_onnx_obs_teacher_ready = false;
bool   g_mb_onnx_obs_teacher_feature_enabled = false;
long   g_mb_onnx_obs_symbol_handle = INVALID_HANDLE;
long   g_mb_onnx_obs_teacher_handle = INVALID_HANDLE;
string g_mb_onnx_obs_symbol = "";
string g_mb_onnx_obs_log_path = "";
string g_mb_onnx_obs_state_path = "";
string g_mb_onnx_obs_symbol_feature_names[];
string g_mb_onnx_obs_symbol_map_names[];
string g_mb_onnx_obs_symbol_map_payloads[];
string g_mb_onnx_obs_teacher_feature_names[];
string g_mb_onnx_obs_teacher_map_names[];
string g_mb_onnx_obs_teacher_map_payloads[];

string MbOnnxObservationEscapeJson(const string value)
  {
   string out = value;
   StringReplace(out,"\\","\\\\");
   StringReplace(out,"\"","\\\"");
   return out;
  }

void MbOnnxObservationResetResult(MbOnnxObservationResult &result)
  {
   result.available = false;
   result.teacher_available = false;
   result.teacher_used = false;
   result.run_ok = false;
   result.teacher_score = 0.0;
   result.symbol_score = 0.0;
   result.latency_us = 0;
   result.reason_code = "ONNX_NOT_READY";
  }

void MbOnnxObservationResetRuntime()
  {
   if(g_mb_onnx_obs_symbol_handle != INVALID_HANDLE)
     {
      OnnxRelease(g_mb_onnx_obs_symbol_handle);
      g_mb_onnx_obs_symbol_handle = INVALID_HANDLE;
     }
   if(g_mb_onnx_obs_teacher_handle != INVALID_HANDLE)
     {
      OnnxRelease(g_mb_onnx_obs_teacher_handle);
      g_mb_onnx_obs_teacher_handle = INVALID_HANDLE;
     }
   g_mb_onnx_obs_enabled = false;
   g_mb_onnx_obs_symbol_ready = false;
   g_mb_onnx_obs_teacher_ready = false;
   g_mb_onnx_obs_teacher_feature_enabled = false;
   g_mb_onnx_obs_symbol = "";
   g_mb_onnx_obs_log_path = "";
   g_mb_onnx_obs_state_path = "";
   ArrayResize(g_mb_onnx_obs_symbol_feature_names,0);
   ArrayResize(g_mb_onnx_obs_symbol_map_names,0);
   ArrayResize(g_mb_onnx_obs_symbol_map_payloads,0);
   ArrayResize(g_mb_onnx_obs_teacher_feature_names,0);
   ArrayResize(g_mb_onnx_obs_teacher_map_names,0);
   ArrayResize(g_mb_onnx_obs_teacher_map_payloads,0);
  }

void MbOnnxObservationEnsureCsvHeader(const string rel_path)
  {
   if(StringLen(rel_path) <= 0 || FileIsExist(rel_path,FILE_COMMON))
      return;

   int handle = FileOpen(rel_path,FILE_COMMON | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return;

   FileWrite(
      handle,
      "ts",
      "symbol",
      "stage",
      "available",
      "teacher_available",
      "teacher_used",
      "teacher_score",
      "symbol_score",
      "latency_us",
      "reason_code",
      "signal_valid",
      "setup_type",
      "market_regime",
      "spread_regime",
      "confidence_bucket",
      "score",
      "confidence_score",
      "spread_points"
   );
   FileClose(handle);
  }

void MbOnnxObservationWriteLatest(
   const string symbol,
   const MbSignalDecision &signal,
   const double spread_points,
   const MbOnnxObservationResult &result
)
  {
   if(StringLen(g_mb_onnx_obs_state_path) <= 0)
      return;

   int handle = FileOpen(g_mb_onnx_obs_state_path,FILE_COMMON | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return;

   string payload = StringFormat(
      "{\"schema_version\":\"1.0\",\"symbol\":\"%s\",\"available\":%s,\"teacher_available\":%s,\"teacher_used\":%s,\"run_ok\":%s,\"teacher_score\":%.6f,\"symbol_score\":%.6f,\"latency_us\":%I64d,\"reason_code\":\"%s\",\"signal_valid\":%s,\"setup_type\":\"%s\",\"market_regime\":\"%s\",\"spread_regime\":\"%s\",\"confidence_bucket\":\"%s\",\"score\":%.6f,\"confidence_score\":%.6f,\"spread_points\":%.2f,\"generated_at_utc\":%I64d}",
      MbOnnxObservationEscapeJson(symbol),
      MbJsonBool(result.available),
      MbJsonBool(result.teacher_available),
      MbJsonBool(result.teacher_used),
      MbJsonBool(result.run_ok),
      result.teacher_score,
      result.symbol_score,
      result.latency_us,
      MbOnnxObservationEscapeJson(result.reason_code),
      MbJsonBool(signal.valid),
      MbOnnxObservationEscapeJson(signal.setup_type),
      MbOnnxObservationEscapeJson(signal.market_regime),
      MbOnnxObservationEscapeJson(signal.spread_regime),
      MbOnnxObservationEscapeJson(signal.confidence_bucket),
      signal.score,
      signal.confidence_score,
      spread_points,
      (long)TimeCurrent()
   );

   FileWriteString(handle,payload);
   FileClose(handle);
  }

void MbOnnxObservationAppendLog(
   const datetime ts,
   const string symbol,
   const string stage,
   const MbSignalDecision &signal,
   const double spread_points,
   const MbOnnxObservationResult &result
)
  {
   if(StringLen(g_mb_onnx_obs_log_path) <= 0)
      return;

   int handle = FileOpen(g_mb_onnx_obs_log_path,FILE_COMMON | FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return;

   FileSeek(handle,0,SEEK_END);
   FileWrite(
      handle,
      (long)ts,
      MbCanonicalSymbol(symbol),
      stage,
      (result.available ? 1 : 0),
      (result.teacher_available ? 1 : 0),
      (result.teacher_used ? 1 : 0),
      DoubleToString(result.teacher_score,6),
      DoubleToString(result.symbol_score,6),
      result.latency_us,
      result.reason_code,
      (signal.valid ? 1 : 0),
      signal.setup_type,
      signal.market_regime,
      signal.spread_regime,
      signal.confidence_bucket,
      DoubleToString(signal.score,6),
      DoubleToString(signal.confidence_score,6),
      DoubleToString(spread_points,2)
   );
   FileClose(handle);
  }

bool MbOnnxObservationLoadContract(
   const string contract_rel_path,
   string &feature_names[],
   string &map_names[],
   string &map_payloads[],
   bool &teacher_feature_enabled
)
  {
   ArrayResize(feature_names,0);
   ArrayResize(map_names,0);
   ArrayResize(map_payloads,0);
   teacher_feature_enabled = false;

   int handle = FileOpen(contract_rel_path,FILE_COMMON | FILE_READ | FILE_CSV | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;

   while(!FileIsEnding(handle))
     {
      string row_type = FileReadString(handle);
      string row_key = FileReadString(handle);
      string row_value = FileReadString(handle);
      if(row_type == "type" && row_key == "key")
         continue;

      if(row_type == "meta" && row_key == "teacher_feature_enabled")
        {
         teacher_feature_enabled = (StringToInteger(row_value) != 0);
         continue;
        }

      if(row_type == "list" && row_key == "feature_names")
        {
         if(StringLen(row_value) <= 0)
            continue;
         StringSplit(row_value,'|',feature_names);
         continue;
        }

      if(row_type == "map")
        {
         int next = ArraySize(map_names);
         ArrayResize(map_names,next + 1);
         ArrayResize(map_payloads,next + 1);
         map_names[next] = row_key;
         map_payloads[next] = row_value;
        }
     }

   FileClose(handle);
   return (ArraySize(feature_names) > 0);
  }

int MbOnnxObservationMapLookup(
   const string feature_name,
   const string raw_value,
   const string &map_names[],
   const string &map_payloads[]
)
  {
   string normalized_value = raw_value;
   if(StringLen(normalized_value) <= 0)
      normalized_value = "UNKNOWN";

   for(int i = 0; i < ArraySize(map_names); ++i)
     {
      if(map_names[i] != feature_name)
         continue;

      string pairs[];
      int pair_count = StringSplit(map_payloads[i],'|',pairs);
      int unknown_value = -1;
      for(int p = 0; p < pair_count; ++p)
        {
         string parts[];
         if(StringSplit(pairs[p],'=',parts) < 2)
            continue;
         string key = parts[0];
         int value = (int)StringToInteger(parts[1]);
         if(key == "UNKNOWN")
            unknown_value = value;
         if(key == normalized_value)
            return value;
        }
      return unknown_value;
     }
   return -1;
  }

float MbOnnxObservationResolveFeatureValue(
   const string feature_name,
   const string symbol,
   const MbSignalDecision &signal,
   const double spread_points,
   const double teacher_score,
   const string &map_names[],
   const string &map_payloads[]
)
  {
   if(feature_name == "symbol")
      return (float)MbOnnxObservationMapLookup(feature_name,MbCanonicalSymbol(symbol),map_names,map_payloads);
   if(feature_name == "setup_type")
      return (float)MbOnnxObservationMapLookup(feature_name,signal.setup_type,map_names,map_payloads);
   if(feature_name == "market_regime")
      return (float)MbOnnxObservationMapLookup(feature_name,signal.market_regime,map_names,map_payloads);
   if(feature_name == "spread_regime")
      return (float)MbOnnxObservationMapLookup(feature_name,signal.spread_regime,map_names,map_payloads);
   if(feature_name == "confidence_bucket")
      return (float)MbOnnxObservationMapLookup(feature_name,signal.confidence_bucket,map_names,map_payloads);
   if(feature_name == "candle_bias")
      return (float)MbOnnxObservationMapLookup(feature_name,signal.candle_bias,map_names,map_payloads);
   if(feature_name == "candle_quality_grade")
      return (float)MbOnnxObservationMapLookup(feature_name,signal.candle_quality_grade,map_names,map_payloads);
   if(feature_name == "renko_bias")
      return (float)MbOnnxObservationMapLookup(feature_name,signal.renko_bias,map_names,map_payloads);
   if(feature_name == "renko_quality_grade")
      return (float)MbOnnxObservationMapLookup(feature_name,signal.renko_quality_grade,map_names,map_payloads);
   if(feature_name == "score")
      return (float)signal.score;
   if(feature_name == "confidence_score")
      return (float)signal.confidence_score;
   if(feature_name == "candle_score")
      return (float)signal.candle_score;
   if(feature_name == "renko_score")
      return (float)signal.renko_score;
   if(feature_name == "spread_points")
      return (float)spread_points;
   if(feature_name == "qdm_spread_mean")
      return 0.0f;
   if(feature_name == "qdm_spread_max")
      return 0.0f;
   if(feature_name == "qdm_mid_range_1m")
      return 0.0f;
   if(feature_name == "qdm_mid_return_1m")
      return 0.0f;
   if(feature_name == "teacher_global_score")
      return (float)teacher_score;
   if(feature_name == "renko_run_length")
      return (float)signal.renko_run_length;
   if(feature_name == "renko_reversal_flag")
      return (float)(signal.renko_reversal_flag ? 1 : 0);
   if(feature_name == "qdm_tick_count")
      return 0.0f;
   if(feature_name == "qdm_data_present")
      return 0.0f;
   return 0.0f;
  }

bool MbOnnxObservationPrepareSession(
   const string model_rel_path,
   const int feature_count,
   long &handle
)
  {
   if(StringLen(model_rel_path) <= 0 || feature_count <= 0)
      return false;

   handle = OnnxCreate(model_rel_path,ONNX_COMMON_FOLDER);
   if(handle == INVALID_HANDLE)
      return false;

   ulong input_shape[2];
   input_shape[0] = 1;
   input_shape[1] = (ulong)feature_count;
   if(!OnnxSetInputShape(handle,0,input_shape))
     {
      OnnxRelease(handle);
      handle = INVALID_HANDLE;
      return false;
     }

   ulong label_shape[1];
   label_shape[0] = 1;
   if(!OnnxSetOutputShape(handle,0,label_shape))
     {
      OnnxRelease(handle);
      handle = INVALID_HANDLE;
      return false;
     }

   ulong probability_shape[2];
   probability_shape[0] = 1;
   probability_shape[1] = 2;
   if(!OnnxSetOutputShape(handle,1,probability_shape))
     {
      OnnxRelease(handle);
      handle = INVALID_HANDLE;
      return false;
     }

   return true;
  }

bool MbOnnxObservationRunModel(
   const long handle,
   const string symbol,
   const MbSignalDecision &signal,
   const double spread_points,
   const double teacher_score,
   const string &feature_names[],
   const string &map_names[],
   const string &map_payloads[],
   double &out_score
)
  {
   int feature_count = ArraySize(feature_names);
   if(handle == INVALID_HANDLE || feature_count <= 0)
      return false;

   matrixf input_matrix(1,feature_count);
   for(int i = 0; i < feature_count; ++i)
      input_matrix[0][i] = MbOnnxObservationResolveFeatureValue(feature_names[i],symbol,signal,spread_points,teacher_score,map_names,map_payloads);

   vectorf output_label(1);
   matrixf output_probabilities(1,2);
   if(!OnnxRun(handle,0,input_matrix,output_label,output_probabilities))
      return false;

   out_score = (double)output_probabilities[0][1];
   return true;
  }

bool MbOnnxObservationInit(
   const string symbol,
   const bool enabled,
   const string log_rel_path,
   const string state_rel_path
)
  {
   MbOnnxObservationResetRuntime();
   g_mb_onnx_obs_enabled = enabled;
   g_mb_onnx_obs_symbol = MbCanonicalSymbol(symbol);
   g_mb_onnx_obs_log_path = log_rel_path;
   g_mb_onnx_obs_state_path = state_rel_path;
   MbOnnxObservationEnsureCsvHeader(g_mb_onnx_obs_log_path);

   if(!enabled)
      return false;

   string teacher_contract = MbKeyFilePath("_GLOBAL","paper_gate_acceptor_runtime_contract_latest.csv");
   string teacher_model = MbKeyFilePath("_GLOBAL","paper_gate_acceptor_runtime_latest.onnx");
   bool ignored_teacher_feature = false;
   if(
      MbOnnxObservationLoadContract(
         teacher_contract,
         g_mb_onnx_obs_teacher_feature_names,
         g_mb_onnx_obs_teacher_map_names,
         g_mb_onnx_obs_teacher_map_payloads,
         ignored_teacher_feature
      ) &&
      MbOnnxObservationPrepareSession(
         teacher_model,
         ArraySize(g_mb_onnx_obs_teacher_feature_names),
         g_mb_onnx_obs_teacher_handle
      )
   )
      g_mb_onnx_obs_teacher_ready = true;

   string symbol_contract = MbKeyFilePath(g_mb_onnx_obs_symbol,"paper_gate_acceptor_runtime_contract_latest.csv");
   string symbol_model = MbKeyFilePath(g_mb_onnx_obs_symbol,"paper_gate_acceptor_runtime_latest.onnx");
   if(
      MbOnnxObservationLoadContract(
         symbol_contract,
         g_mb_onnx_obs_symbol_feature_names,
         g_mb_onnx_obs_symbol_map_names,
         g_mb_onnx_obs_symbol_map_payloads,
         g_mb_onnx_obs_teacher_feature_enabled
      ) &&
      MbOnnxObservationPrepareSession(
         symbol_model,
         ArraySize(g_mb_onnx_obs_symbol_feature_names),
         g_mb_onnx_obs_symbol_handle
      )
   )
      g_mb_onnx_obs_symbol_ready = true;

   return (g_mb_onnx_obs_symbol_ready && (!g_mb_onnx_obs_teacher_feature_enabled || g_mb_onnx_obs_teacher_ready));
  }

void MbOnnxObservationShutdown()
  {
   MbOnnxObservationResetRuntime();
  }

bool MbOnnxObservationEvaluate(
   const datetime ts,
   const string stage,
   const string symbol,
   const MbSignalDecision &signal,
   const double spread_points,
   MbOnnxObservationResult &result
)
  {
   MbOnnxObservationResetResult(result);

   if(!g_mb_onnx_obs_enabled)
     {
      result.reason_code = "ONNX_DISABLED";
      return false;
     }

   if(!g_mb_onnx_obs_symbol_ready)
     {
      result.reason_code = "ONNX_SYMBOL_MODEL_NOT_READY";
      MbOnnxObservationWriteLatest(symbol,signal,spread_points,result);
      MbOnnxObservationAppendLog(ts,symbol,stage,signal,spread_points,result);
      return false;
     }

   ulong started_us = GetMicrosecondCount();
   result.available = true;
   result.teacher_available = g_mb_onnx_obs_teacher_ready;

   if(g_mb_onnx_obs_teacher_feature_enabled)
     {
      if(!g_mb_onnx_obs_teacher_ready)
        {
         result.reason_code = "ONNX_GLOBAL_TEACHER_NOT_READY";
         result.latency_us = (long)(GetMicrosecondCount() - started_us);
         MbOnnxObservationWriteLatest(symbol,signal,spread_points,result);
         MbOnnxObservationAppendLog(ts,symbol,stage,signal,spread_points,result);
         return false;
        }

      if(!MbOnnxObservationRunModel(
            g_mb_onnx_obs_teacher_handle,
            symbol,
            signal,
            spread_points,
            0.0,
            g_mb_onnx_obs_teacher_feature_names,
            g_mb_onnx_obs_teacher_map_names,
            g_mb_onnx_obs_teacher_map_payloads,
            result.teacher_score
         ))
        {
         result.reason_code = "ONNX_GLOBAL_RUN_FAILED";
         result.latency_us = (long)(GetMicrosecondCount() - started_us);
         MbOnnxObservationWriteLatest(symbol,signal,spread_points,result);
         MbOnnxObservationAppendLog(ts,symbol,stage,signal,spread_points,result);
         return false;
        }
      result.teacher_used = true;
     }

   if(!MbOnnxObservationRunModel(
         g_mb_onnx_obs_symbol_handle,
         symbol,
         signal,
         spread_points,
         result.teacher_score,
         g_mb_onnx_obs_symbol_feature_names,
         g_mb_onnx_obs_symbol_map_names,
         g_mb_onnx_obs_symbol_map_payloads,
         result.symbol_score
      ))
     {
      result.reason_code = "ONNX_SYMBOL_RUN_FAILED";
      result.latency_us = (long)(GetMicrosecondCount() - started_us);
      MbOnnxObservationWriteLatest(symbol,signal,spread_points,result);
      MbOnnxObservationAppendLog(ts,symbol,stage,signal,spread_points,result);
      return false;
     }

   result.run_ok = true;
   result.reason_code = "ONNX_OBSERVATION_OK";
   result.latency_us = (long)(GetMicrosecondCount() - started_us);
   MbOnnxObservationWriteLatest(symbol,signal,spread_points,result);
   MbOnnxObservationAppendLog(ts,symbol,stage,signal,spread_points,result);
   return true;
  }

#endif
