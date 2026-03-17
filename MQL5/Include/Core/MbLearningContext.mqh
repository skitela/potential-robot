#ifndef MB_LEARNING_CONTEXT_INCLUDED
#define MB_LEARNING_CONTEXT_INCLUDED

#include "MbRuntimeTypes.mqh"
#include "MbStorage.mqh"

void MbEnsureLearningBucketSummaryHeader(const int h)
  {
   if(h == INVALID_HANDLE || FileSize(h) > 0)
      return;

   FileWrite(
      h,
      "setup_type",
      "market_regime",
      "samples",
      "wins",
      "losses",
      "pnl_sum",
      "avg_pnl"
   );
  }

void MbUpdateLearningBucketSummary(
   const string symbol,
   const string setup_type,
   const string market_regime,
   const double pnl
)
  {
   string observations_path = MbLogFilePath(symbol,"learning_observations_v2.csv");
   string path = MbLogFilePath(symbol,"learning_bucket_summary_v1.csv");
   string setups[];
   string regimes[];
   int samples_list[];
   int wins_list[];
   int losses_list[];
   double pnl_sums[];

   if(FileIsExist(observations_path,FILE_COMMON))
     {
      int hr = FileOpen(observations_path,FILE_COMMON | FILE_READ | FILE_CSV | FILE_ANSI);
      if(hr != INVALID_HANDLE)
        {
         while(!FileIsEnding(hr))
           {
            string c1 = FileReadString(hr);
            if(FileIsEnding(hr) && c1 == "")
               break;
            string c2 = FileReadString(hr);
            string c3 = FileReadString(hr);
            string c4 = FileReadString(hr);
            string c5 = FileReadString(hr);
            string c6 = FileReadString(hr);
            string c7 = FileReadString(hr);
            string c8 = FileReadString(hr);
            string c9 = FileReadString(hr);
            string c10 = FileReadString(hr);
            string c11 = FileReadString(hr);
            string c12 = FileReadString(hr);
            string c13 = FileReadString(hr);
            string c14 = FileReadString(hr);
            string c15 = FileReadString(hr);
            string c16 = FileReadString(hr);
            string c17 = FileReadString(hr);
            string c18 = FileReadString(hr);
            string c19 = FileReadString(hr);
            string c20 = FileReadString(hr);

            if(c1 == "" || c1 == "schema_version")
               continue;

            string row_setup = (c4 == "" ? "NONE" : c4);
            string row_regime = (c5 == "" ? "UNKNOWN" : c5);
            if(row_setup == "NONE" || row_regime == "UNKNOWN")
               continue;
            double row_pnl = StringToDouble(c19);
            int idx = -1;
            for(int i = 0; i < ArraySize(setups); ++i)
              {
               if(setups[i] == row_setup && regimes[i] == row_regime)
                 {
                  idx = i;
                  break;
                 }
              }

            if(idx < 0)
              {
               idx = ArraySize(setups);
               ArrayResize(setups,idx + 1);
               ArrayResize(regimes,idx + 1);
               ArrayResize(samples_list,idx + 1);
               ArrayResize(wins_list,idx + 1);
               ArrayResize(losses_list,idx + 1);
               ArrayResize(pnl_sums,idx + 1);
               setups[idx] = row_setup;
               regimes[idx] = row_regime;
               samples_list[idx] = 0;
               wins_list[idx] = 0;
               losses_list[idx] = 0;
               pnl_sums[idx] = 0.0;
              }

            samples_list[idx] += 1;
            if(row_pnl >= 0.0)
               wins_list[idx]++;
            else
               losses_list[idx]++;
            pnl_sums[idx] += row_pnl;
          }
         FileClose(hr);
        }
     }

   int hw = FileOpen(path,FILE_COMMON | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(hw == INVALID_HANDLE)
      return;

   MbEnsureLearningBucketSummaryHeader(hw);
   for(int i = 0; i < ArraySize(setups); ++i)
     {
      double avg_pnl = (samples_list[i] > 0 ? pnl_sums[i] / (double)samples_list[i] : 0.0);
      FileWrite(
         hw,
         setups[i],
         regimes[i],
         samples_list[i],
         wins_list[i],
         losses_list[i],
         DoubleToString(pnl_sums[i],2),
         DoubleToString(avg_pnl,4)
      );
     }
   FileClose(hw);
  }

void MbEnsureLearningObservationHeader(const int h,const bool with_schema_version)
  {
   if(h == INVALID_HANDLE || FileSize(h) > 0)
      return;

   if(with_schema_version)
     {
      FileWrite(
         h,
         "schema_version",
         "ts",
         "symbol",
         "setup_type",
         "market_regime",
         "spread_regime",
         "execution_regime",
         "confidence_bucket",
         "confidence_score",
         "candle_bias",
         "candle_quality_grade",
         "candle_score",
         "renko_bias",
         "renko_quality_grade",
         "renko_score",
         "renko_run_length",
         "renko_reversal_flag",
         "side",
         "pnl",
         "close_reason"
      );
      return;
     }

   FileWrite(
      h,
      "ts",
      "symbol",
      "setup_type",
      "market_regime",
      "spread_regime",
      "execution_regime",
      "confidence_bucket",
      "confidence_score",
      "candle_bias",
      "candle_quality_grade",
      "candle_score",
      "renko_bias",
      "renko_quality_grade",
      "renko_score",
      "renko_run_length",
      "renko_reversal_flag",
      "side",
      "pnl",
      "close_reason"
   );
  }

void MbWriteLearningObservationRecord(
   const int h,
   const bool with_schema_version,
   const datetime ts,
   const string symbol,
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
   if(with_schema_version)
     {
      FileWrite(
         h,
         "2.0",
         (long)ts,
         MbCanonicalSymbol(symbol),
         setup_type,
         market_regime,
         spread_regime,
         execution_regime,
         confidence_bucket,
         DoubleToString(confidence_score,4),
         candle_bias,
         candle_quality_grade,
         DoubleToString(candle_score,4),
         renko_bias,
         renko_quality_grade,
         DoubleToString(renko_score,4),
         renko_run_length,
         (renko_reversal_flag ? 1 : 0),
         (int)side,
         DoubleToString(pnl,2),
         close_reason
      );
      return;
     }

   FileWrite(
      h,
      (long)ts,
      MbCanonicalSymbol(symbol),
      setup_type,
      market_regime,
      spread_regime,
      execution_regime,
      confidence_bucket,
      DoubleToString(confidence_score,4),
      candle_bias,
      candle_quality_grade,
      DoubleToString(candle_score,4),
      renko_bias,
      renko_quality_grade,
      DoubleToString(renko_score,4),
      renko_run_length,
      (renko_reversal_flag ? 1 : 0),
      (int)side,
      DoubleToString(pnl,2),
      close_reason
   );
  }

void MbAppendLearningObservation(
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
   int h = FileOpen(MbLogFilePath(symbol,"learning_observations.csv"), FILE_COMMON | FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;
   MbEnsureLearningObservationHeader(h,false);
   FileSeek(h,0,SEEK_END);
   MbWriteLearningObservationRecord(
      h,
      false,
      ts,
      symbol,
      setup_type,
      market_regime,
      spread_regime,
      execution_regime,
      confidence_bucket,
      confidence_score,
      candle_bias,
      candle_quality_grade,
      candle_score,
      renko_bias,
      renko_quality_grade,
      renko_score,
      renko_run_length,
      renko_reversal_flag,
      side,
      pnl,
      close_reason
   );
   FileClose(h);
  }

void MbAppendLearningObservationV2(
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
   int h = FileOpen(MbLogFilePath(symbol,"learning_observations_v2.csv"), FILE_COMMON | FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;
   MbEnsureLearningObservationHeader(h,true);
   FileSeek(h,0,SEEK_END);
   MbWriteLearningObservationRecord(
      h,
      true,
      ts,
      symbol,
      setup_type,
      market_regime,
      spread_regime,
      execution_regime,
      confidence_bucket,
      confidence_score,
      candle_bias,
      candle_quality_grade,
      candle_score,
      renko_bias,
      renko_quality_grade,
      renko_score,
      renko_run_length,
      renko_reversal_flag,
      side,
      pnl,
      close_reason
   );
   FileClose(h);

   MbUpdateLearningBucketSummary(
      symbol,
      setup_type,
      market_regime,
      pnl
   );
  }

bool MbAppendHistoricalLearningObservation(
   const string symbol,
   const ulong magic,
   const ulong deal_ticket,
   const MbRuntimeState &state,
   const string close_reason
)
  {
   if(deal_ticket == 0)
      return false;
   if(!HistoryDealSelect(deal_ticket))
      return false;
   if((ulong)HistoryDealGetInteger(deal_ticket,DEAL_MAGIC) != magic)
      return false;
   if(HistoryDealGetString(deal_ticket,DEAL_SYMBOL) != symbol)
      return false;
   if((int)HistoryDealGetInteger(deal_ticket,DEAL_ENTRY) != DEAL_ENTRY_OUT)
      return false;

   double pnl = HistoryDealGetDouble(deal_ticket,DEAL_PROFIT)
      + HistoryDealGetDouble(deal_ticket,DEAL_SWAP)
      + HistoryDealGetDouble(deal_ticket,DEAL_COMMISSION);
   datetime deal_time = (datetime)HistoryDealGetInteger(deal_ticket,DEAL_TIME);

   MbAppendLearningObservation(
      symbol,
      deal_time,
      state.last_setup_type,
      state.market_regime,
      state.spread_regime,
      state.execution_regime,
      state.confidence_bucket,
      state.signal_confidence,
      state.candle_bias,
      state.candle_quality_grade,
      state.candle_score,
      state.renko_bias,
      state.renko_quality_grade,
      state.renko_score,
      state.renko_run_length,
      state.renko_reversal_flag,
      MB_SIGNAL_NONE,
      pnl,
      close_reason
   );
   return true;
  }

#endif
