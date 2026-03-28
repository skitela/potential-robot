#ifndef MB_TUNING_DECKHAND_INCLUDED
#define MB_TUNING_DECKHAND_INCLUDED

#include "MbLearningContext.mqh"
#include "MbTuningEpistemology.mqh"

bool MbTuningDeckhandShouldJournal(
   const MbTuningLocalPolicy &policy,
   const MbTuningDeckhandReport &report,
   const int learning_sample_count
)
  {
   if(report.rebuilt_bucket_summary)
      return true;
   if(policy.last_logged_trusted != report.trusted)
      return true;
   if(policy.last_logged_reason_code != report.reason_code)
      return true;
   if(policy.last_logged_reason_domain != report.normalized_reason.domain)
      return true;
   if(policy.last_logged_reason_class != report.normalized_reason.reason_class)
      return true;
   if(policy.last_logged_learning_sample_count != learning_sample_count)
      return true;
   if(policy.last_logged_observation_rows != report.observation_rows)
      return true;
   if(policy.last_logged_bucket_rows != report.bucket_rows)
      return true;
   if(policy.last_logged_candidate_rows != report.candidate_rows)
      return true;
   if(policy.last_logged_candidate_risk_block_rows != report.candidate_risk_block_rows)
      return true;
   if(policy.last_logged_candidate_score_gate_rows != report.candidate_score_gate_rows)
      return true;
   if(policy.last_logged_candidate_dirty_rows != report.candidate_dirty_rows)
      return true;
   if(policy.last_logged_paper_open_rows != report.paper_open_rows)
      return true;
   return false;
  }

bool MbTuningDeckhandIsPoorGrade(const string grade)
  {
   return (grade == "" || grade == "POOR" || grade == "UNKNOWN");
  }

bool MbTuningDeckhandScanObservations(
   const string symbol,
   int &out_total_rows,
   int &out_valid_rows,
   int &out_invalid_rows,
   int &out_none_unknown_rows
)
  {
   out_total_rows = 0;
   out_valid_rows = 0;
   out_invalid_rows = 0;
   out_none_unknown_rows = 0;

   string path = MbLogFilePath(symbol,"learning_observations_v2.csv");
   int h = FileOpen(path,FILE_COMMON | FILE_READ | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;

   while(!FileIsEnding(h))
     {
      string c1 = FileReadString(h);
      if(FileIsEnding(h) && c1 == "")
         break;
      string c2 = FileReadString(h);
      string c3 = FileReadString(h);
      string c4 = FileReadString(h);
      string c5 = FileReadString(h);
      string c6 = FileReadString(h);
      string c7 = FileReadString(h);
      string c8 = FileReadString(h);
      string c9 = FileReadString(h);
      string c10 = FileReadString(h);
      string c11 = FileReadString(h);
      string c12 = FileReadString(h);
      string c13 = FileReadString(h);
      string c14 = FileReadString(h);
      string c15 = FileReadString(h);
      string c16 = FileReadString(h);
      string c17 = FileReadString(h);
      string c18 = FileReadString(h);
      string c19 = FileReadString(h);
      string c20 = FileReadString(h);

      if(c1 == "" || c1 == "schema_version")
         continue;

      out_total_rows++;
      string setup_type = (c4 == "" ? "NONE" : c4);
      string market_regime = (c5 == "" ? "UNKNOWN" : c5);

      if(setup_type == "NONE" || market_regime == "UNKNOWN")
        {
         out_none_unknown_rows++;
         out_invalid_rows++;
         continue;
        }

      if(c19 == "")
        {
         out_invalid_rows++;
         continue;
        }

      out_valid_rows++;
     }

   FileClose(h);
   return true;
  }

int MbTuningDeckhandCountBucketRows(const string symbol)
  {
   string path = MbLogFilePath(symbol,"learning_bucket_summary_v1.csv");
   int h = FileOpen(path,FILE_COMMON | FILE_READ | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return 0;

   int rows = 0;
   while(!FileIsEnding(h))
     {
      string c1 = FileReadString(h);
      if(FileIsEnding(h) && c1 == "")
         break;
      string c2 = FileReadString(h);
      string c3 = FileReadString(h);
      string c4 = FileReadString(h);
      string c5 = FileReadString(h);
      string c6 = FileReadString(h);
      string c7 = FileReadString(h);
      if(c1 == "" || c1 == "setup_type")
         continue;
      rows++;
     }

   FileClose(h);
  return rows;
  }

bool MbTuningDeckhandScanCandidates(
   const string symbol,
   int &out_total_rows,
   int &out_invalid_rows,
   int &out_risk_block_rows,
   int &out_score_gate_rows,
   int &out_dirty_rows,
   int &out_dirty_candle_rows,
   int &out_dirty_renko_rows,
   int &out_dirty_hybrid_rows,
   int &out_dirty_spread_rows
)
  {
   out_total_rows = 0;
   out_invalid_rows = 0;
   out_risk_block_rows = 0;
   out_score_gate_rows = 0;
   out_dirty_rows = 0;
   out_dirty_candle_rows = 0;
   out_dirty_renko_rows = 0;
   out_dirty_hybrid_rows = 0;
   out_dirty_spread_rows = 0;

   string path = MbLogFilePath(symbol,"candidate_signals.csv");
   int h = FileOpen(path,FILE_COMMON | FILE_READ | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;

   while(!FileIsEnding(h))
     {
      string c1 = FileReadString(h);
      if(FileIsEnding(h) && c1 == "")
         break;
      string c2 = FileReadString(h);
      string c3 = FileReadString(h);
      string c4 = FileReadString(h);
      string c5 = FileReadString(h);
      string c6 = FileReadString(h);
      string c7 = FileReadString(h);
      string c8 = FileReadString(h);
      string c9 = FileReadString(h);
      string c10 = FileReadString(h);
      string c11 = FileReadString(h);
      string c12 = FileReadString(h);
      string c13 = FileReadString(h);
      string c14 = FileReadString(h);
      string c15 = FileReadString(h);
      string c16 = FileReadString(h);
      string c17 = FileReadString(h);
      string c18 = FileReadString(h);
      string c19 = FileReadString(h);
      string c20 = FileReadString(h);
      string c21 = FileReadString(h);
      string c22 = FileReadString(h);
      string c23 = FileReadString(h);
      string c24 = FileReadString(h);

      if(c1 == "" || c1 == "ts")
         continue;

      out_total_rows++;
      if(c3 == "" || c5 == "" || c6 == "" || c6 == "NONE" || c8 == "")
         out_invalid_rows++;

      bool accepted = (c4 != "0");
      if(c3 == "SIZE_BLOCK" && c5 == "RISK_CONTRACT_BLOCK")
         out_risk_block_rows++;
      if(c3 == "EVALUATED" && accepted && c5 == "PAPER_SCORE_GATE")
        {
         out_score_gate_rows++;

         string canonical_symbol = MbCanonicalSymbol(symbol);
         string setup_type = c6;
         string market_regime = c12;
         double confidence_score = StringToDouble(c9);
         bool low_confidence = (c15 == "LOW" || confidence_score < 0.60);
         bool poor_candle = MbTuningDeckhandIsPoorGrade(c17);
         bool poor_renko = MbTuningDeckhandIsPoorGrade(c20);
         bool spread_dirty = (c13 == "BAD");
         bool dirty_by_quality = (low_confidence && (poor_candle || poor_renko));
         bool audusd_supported_range_candle = (
            canonical_symbol == "AUDUSD" &&
            setup_type == "SETUP_RANGE" &&
            poor_candle &&
            !poor_renko &&
            !spread_dirty
         );
         bool audusd_range_regime_relief = (
            canonical_symbol == "AUDUSD" &&
            setup_type == "SETUP_RANGE" &&
            market_regime == "RANGE" &&
            !spread_dirty
         );
         bool gbpusd_trend_breakout_relief = (
            canonical_symbol == "GBPUSD" &&
            setup_type == "SETUP_TREND" &&
            market_regime == "BREAKOUT" &&
            !spread_dirty &&
            !(poor_candle && poor_renko)
         );
         bool gbpusd_breakout_breakout_relief = (
            canonical_symbol == "GBPUSD" &&
            setup_type == "SETUP_BREAKOUT" &&
            market_regime == "BREAKOUT" &&
            c17 == "FAIR" &&
            !spread_dirty
         );
         if(
            dirty_by_quality &&
            (
               audusd_supported_range_candle ||
               audusd_range_regime_relief ||
               gbpusd_trend_breakout_relief ||
               gbpusd_breakout_breakout_relief
            )
         )
            dirty_by_quality = false;
         if(dirty_by_quality || spread_dirty)
           {
            out_dirty_rows++;
            if(spread_dirty)
               out_dirty_spread_rows++;
            if(dirty_by_quality)
              {
               if(poor_candle && poor_renko)
                  out_dirty_hybrid_rows++;
               else if(poor_candle)
                  out_dirty_candle_rows++;
               else
                  out_dirty_renko_rows++;
              }
           }
        }
     }

   FileClose(h);
   return true;
  }

bool MbTuningDeckhandScanDecisionEvents(
   const string symbol,
   int &out_paper_open_rows,
   int &out_risk_contract_block_rows,
   int &out_portfolio_heat_block_rows,
   int &out_rate_guard_block_rows
)
  {
   out_paper_open_rows = 0;
   out_risk_contract_block_rows = 0;
   out_portfolio_heat_block_rows = 0;
   out_rate_guard_block_rows = 0;

   string path = MbLogFilePath(symbol,"decision_events.csv");
   int h = FileOpen(path,FILE_COMMON | FILE_READ | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;

   while(!FileIsEnding(h))
     {
      string c1 = FileReadString(h);
      if(FileIsEnding(h) && c1 == "")
         break;
      string c2 = FileReadString(h);
      string c3 = FileReadString(h);
      string c4 = FileReadString(h);
      string c5 = FileReadString(h);
      string c6 = FileReadString(h);
      string c7 = FileReadString(h);
      string c8 = FileReadString(h);
      string c9 = FileReadString(h);
      string c10 = FileReadString(h);

      if(c1 == "" || c1 == "ts")
         continue;

      if(c3 == "PAPER_OPEN" && c4 == "OK" && c5 == "PAPER_POSITION_OPENED")
         out_paper_open_rows++;
      if(c4 == "SKIP" && c5 == "RISK_CONTRACT_BLOCK")
         out_risk_contract_block_rows++;
      if(c4 == "SKIP" && c5 == "PORTFOLIO_HEAT_BLOCK")
         out_portfolio_heat_block_rows++;
      if(c4 == "SKIP" && c5 == "BROKER_PRICE_RATE_LIMIT")
         out_rate_guard_block_rows++;
     }

   FileClose(h);
   return true;
  }

void MbRunTuningDeckhand(
   const string symbol,
   const MbRuntimeState &state,
   const MbMarketSnapshot &market,
   const string deckhand_log_path,
   MbTuningLocalPolicy &policy,
   MbTuningDeckhandReport &report
)
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION) != 0)
     {
      MbTuningDeckhandReportReset(report);
      report.serviced_at = TimeCurrent();
      report.reason_code = "OPTIMIZATION_RUNTIME";
      MbNormalizeReasonTriple(report.reason_code,report.normalized_reason);
      return;
     }

   MbTuningDeckhandReportReset(report);
   report.serviced_at = TimeCurrent();
   report.execution_pressure = state.execution_pressure;
   report.exec_error_streak = state.exec_error_streak;
   report.spread_anomaly_streak = state.spread_anomaly_streak;
   policy.last_eval_at = report.serviced_at;
   string previous_reason = policy.trust_reason;
   bool previous_trusted = policy.trusted_data;
   bool deckhand_log_missing = !FileIsExist(deckhand_log_path,FILE_COMMON);
   int previous_learning_sample_count = policy.last_learning_sample_count;
   int previous_observation_rows = policy.last_observation_rows;
   int previous_candidate_rows = policy.last_candidate_rows;
   int previous_candidate_risk_block_rows = policy.last_candidate_risk_block_rows;
   int previous_candidate_score_gate_rows = policy.last_candidate_score_gate_rows;
   int previous_candidate_dirty_rows = policy.last_candidate_dirty_rows;
   int previous_paper_open_rows = policy.last_paper_open_rows;

   if(!policy.enabled)
     {
      report.reason_code = "TUNING_DISABLED";
      MbNormalizeReasonTriple(report.reason_code,report.normalized_reason);
      MbResolveTrustStateFromReport(symbol,report.reason_code,false,state.learning_sample_count,0,0,0,0,0,0,0.0,0,report.trust_state);
      policy.trusted_data = false;
      policy.trust_reason = report.reason_code;
      policy.trust_reason_domain = report.normalized_reason.domain;
      policy.trust_reason_class = report.normalized_reason.reason_class;
      policy.last_trust_state = report.trust_state.state;
      policy.last_execution_quality_state = report.execution_quality.state;
      policy.last_cost_pressure_state = report.cost_pressure.state;
      if(deckhand_log_missing || MbTuningDeckhandShouldJournal(policy,report,state.learning_sample_count))
        {
         policy.last_logged_trusted = report.trusted;
         policy.last_logged_reason_code = report.reason_code;
         policy.last_logged_reason_domain = report.normalized_reason.domain;
         policy.last_logged_reason_class = report.normalized_reason.reason_class;
         policy.last_logged_learning_sample_count = state.learning_sample_count;
         policy.last_logged_observation_rows = report.observation_rows;
         policy.last_logged_bucket_rows = report.bucket_rows;
         policy.last_logged_candidate_rows = report.candidate_rows;
         policy.last_logged_candidate_risk_block_rows = report.candidate_risk_block_rows;
         policy.last_logged_candidate_score_gate_rows = report.candidate_score_gate_rows;
         policy.last_logged_candidate_dirty_rows = report.candidate_dirty_rows;
         policy.last_logged_paper_open_rows = report.paper_open_rows;
         policy.last_deckhand_log_at = report.serviced_at;
         MbAppendTuningDeckhandEvent(deckhand_log_path,symbol,report);
        }
      return;
     }

   int total_rows = 0;
   int valid_rows = 0;
   int invalid_rows = 0;
   int none_unknown_rows = 0;
   if(!MbTuningDeckhandScanObservations(symbol,total_rows,valid_rows,invalid_rows,none_unknown_rows))
     {
      report.reason_code = "OBSERVATIONS_MISSING";
      MbNormalizeReasonTriple(report.reason_code,report.normalized_reason);
      MbResolveTrustStateFromReport(symbol,report.reason_code,false,state.learning_sample_count,0,0,0,0,0,0,0.0,0,report.trust_state);
      policy.trusted_data = false;
      policy.trust_reason = report.reason_code;
      policy.trust_reason_domain = report.normalized_reason.domain;
      policy.trust_reason_class = report.normalized_reason.reason_class;
      policy.last_trust_state = report.trust_state.state;
      policy.last_execution_quality_state = report.execution_quality.state;
      policy.last_cost_pressure_state = report.cost_pressure.state;
      if(deckhand_log_missing || MbTuningDeckhandShouldJournal(policy,report,state.learning_sample_count))
        {
         policy.last_logged_trusted = report.trusted;
         policy.last_logged_reason_code = report.reason_code;
         policy.last_logged_reason_domain = report.normalized_reason.domain;
         policy.last_logged_reason_class = report.normalized_reason.reason_class;
         policy.last_logged_learning_sample_count = state.learning_sample_count;
         policy.last_logged_observation_rows = report.observation_rows;
         policy.last_logged_bucket_rows = report.bucket_rows;
         policy.last_logged_candidate_rows = report.candidate_rows;
         policy.last_logged_candidate_risk_block_rows = report.candidate_risk_block_rows;
         policy.last_logged_candidate_score_gate_rows = report.candidate_score_gate_rows;
         policy.last_logged_candidate_dirty_rows = report.candidate_dirty_rows;
         policy.last_logged_paper_open_rows = report.paper_open_rows;
         policy.last_deckhand_log_at = report.serviced_at;
         MbAppendTuningDeckhandEvent(deckhand_log_path,symbol,report);
        }
      return;
     }

   report.total_rows = total_rows;
   report.observation_rows = valid_rows;
   report.invalid_rows = invalid_rows;
   report.none_unknown_rows = none_unknown_rows;

   bool needs_rebuild = (
      valid_rows > 0 &&
      (
         policy.last_learning_sample_count != state.learning_sample_count ||
         !FileIsExist(MbLogFilePath(symbol,"learning_bucket_summary_v1.csv"),FILE_COMMON)
      )
   );

   if(needs_rebuild)
     {
      MbUpdateLearningBucketSummary(symbol,"","",0.0);
      report.rebuilt_bucket_summary = true;
     }

   report.bucket_rows = MbTuningDeckhandCountBucketRows(symbol);
   int candidate_rows = 0;
   int candidate_invalid_rows = 0;
   int candidate_risk_block_rows = 0;
   int candidate_score_gate_rows = 0;
   int candidate_dirty_rows = 0;
   int candidate_dirty_candle_rows = 0;
   int candidate_dirty_renko_rows = 0;
   int candidate_dirty_hybrid_rows = 0;
   int candidate_dirty_spread_rows = 0;
   if(MbTuningDeckhandScanCandidates(
      symbol,
      candidate_rows,
      candidate_invalid_rows,
      candidate_risk_block_rows,
      candidate_score_gate_rows,
      candidate_dirty_rows,
      candidate_dirty_candle_rows,
      candidate_dirty_renko_rows,
      candidate_dirty_hybrid_rows,
      candidate_dirty_spread_rows
   ))
     {
      report.candidate_rows = candidate_rows;
      report.candidate_invalid_rows = candidate_invalid_rows;
      report.candidate_risk_block_rows = candidate_risk_block_rows;
      report.candidate_score_gate_rows = candidate_score_gate_rows;
      report.candidate_dirty_rows = candidate_dirty_rows;
      report.candidate_dirty_candle_rows = candidate_dirty_candle_rows;
      report.candidate_dirty_renko_rows = candidate_dirty_renko_rows;
      report.candidate_dirty_hybrid_rows = candidate_dirty_hybrid_rows;
      report.candidate_dirty_spread_rows = candidate_dirty_spread_rows;
     }

   int paper_open_rows = 0;
   int decision_risk_contract_block_rows = 0;
   int decision_portfolio_heat_block_rows = 0;
   int decision_rate_guard_block_rows = 0;
   if(MbTuningDeckhandScanDecisionEvents(
      symbol,
      paper_open_rows,
      decision_risk_contract_block_rows,
      decision_portfolio_heat_block_rows,
      decision_rate_guard_block_rows
   ))
     {
      report.paper_open_rows = paper_open_rows;
      report.decision_risk_contract_block_rows = decision_risk_contract_block_rows;
      report.decision_portfolio_heat_block_rows = decision_portfolio_heat_block_rows;
      report.decision_rate_guard_block_rows = decision_rate_guard_block_rows;
     }

   int new_learning_sample_count = MathMax(0,state.learning_sample_count - previous_learning_sample_count);
   int new_observation_rows = MathMax(0,report.observation_rows - previous_observation_rows);
   int new_candidate_rows = MathMax(0,report.candidate_rows - previous_candidate_rows);
   int new_candidate_risk_block_rows = MathMax(0,report.candidate_risk_block_rows - previous_candidate_risk_block_rows);
   int new_candidate_score_gate_rows = MathMax(0,report.candidate_score_gate_rows - previous_candidate_score_gate_rows);
   int new_candidate_dirty_rows = MathMax(0,report.candidate_dirty_rows - previous_candidate_dirty_rows);
   int new_paper_open_rows = MathMax(0,report.paper_open_rows - previous_paper_open_rows);
   double recent_conversion_ratio = (new_candidate_score_gate_rows > 0 ? (double)new_paper_open_rows / (double)new_candidate_score_gate_rows : 0.0);
   double min_conversion_ratio = 0.0;
   int min_conversion_candidates = 0;
   double max_dirty_ratio = 0.0;
   MbResolveTrustThresholds(symbol,min_conversion_ratio,min_conversion_candidates,max_dirty_ratio);

   bool candidate_backlog = (new_candidate_rows >= MathMax(24,policy.min_bucket_samples * 4));
   bool learning_stalled = (new_learning_sample_count <= 0 && new_observation_rows <= 0);
   bool conversion_gate_active = (report.candidate_score_gate_rows >= min_conversion_candidates);
   double lifetime_conversion_ratio = (report.candidate_score_gate_rows > 0 ? (double)report.paper_open_rows / (double)report.candidate_score_gate_rows : 0.0);
   bool conversion_ratio_blocked = (
      conversion_gate_active &&
      lifetime_conversion_ratio < min_conversion_ratio &&
      (new_candidate_score_gate_rows <= 0 || recent_conversion_ratio < min_conversion_ratio)
   );
   bool paper_conversion_blocked = (
      conversion_ratio_blocked ||
      (
         candidate_backlog &&
         learning_stalled &&
         new_paper_open_rows <= 0 &&
         new_candidate_risk_block_rows >= MathMax(8,new_candidate_rows / 4)
      )
   );
   bool dirty_ratio_blocked = (
      report.candidate_score_gate_rows >= MathMax(6,min_conversion_candidates) &&
      report.candidate_dirty_rows > 0 &&
      ((double)report.candidate_dirty_rows / (double)MathMax(1,report.candidate_score_gate_rows)) >= max_dirty_ratio
   );
   bool forefield_dirty = (
      dirty_ratio_blocked ||
      (
         candidate_backlog &&
         learning_stalled &&
         new_paper_open_rows <= 0 &&
         new_candidate_score_gate_rows >= MathMax(8,new_candidate_rows / 5) &&
         new_candidate_dirty_rows >= MathMax(6,new_candidate_score_gate_rows / 3)
      )
   );
   MbEvaluateExecutionQualityState(state,market,report.execution_quality);
   MbEvaluateCostPressureState(symbol,state,market,report.cost_pressure);
   bool central_state_stale = false;
   int central_stale_seconds = 0;
   MbEvaluateCentralStateStaleness(symbol,report.serviced_at,central_state_stale,central_stale_seconds);
   bool infrastructure_weak = (
      state.halt ||
      report.execution_quality.state == "BAD" ||
      state.execution_pressure >= 0.72 ||
      state.exec_error_streak >= 2 ||
      state.spread_anomaly_streak >= 4
   );

   int min_rows = MathMax(3,policy.min_bucket_samples);
   if(report.observation_rows < min_rows)
      report.reason_code = "LOW_SAMPLE";
   else if(report.bucket_rows <= 0)
      report.reason_code = "BUCKETS_EMPTY";
   else if(report.total_rows > 0 && report.none_unknown_rows > (report.total_rows / 3))
      report.reason_code = "FOREFIELD_DIRTY_BY_OBSERVATION_GAPS";
   else if(report.candidate_rows > 0 && report.candidate_invalid_rows > (report.candidate_rows / 3))
      report.reason_code = "FOREFIELD_DIRTY_BY_CANDIDATE_INVALID";
   else if(central_state_stale)
      report.reason_code = "CENTRAL_STATE_STALE";
   else if(infrastructure_weak)
      report.reason_code = "INFRASTRUCTURE_WEAK";
   else if(paper_conversion_blocked)
      report.reason_code = MbResolvePaperConversionBlockedReasonCode(
         report.candidate_risk_block_rows,
         report.decision_risk_contract_block_rows,
         report.decision_portfolio_heat_block_rows,
         report.decision_rate_guard_block_rows,
         lifetime_conversion_ratio,
         min_conversion_ratio
      );
   else if(forefield_dirty)
      report.reason_code = MbResolveForefieldDirtyReasonCode(
         report.total_rows,
         report.none_unknown_rows,
         report.candidate_rows,
         report.candidate_invalid_rows,
         report.candidate_dirty_rows,
         report.candidate_dirty_candle_rows,
         report.candidate_dirty_renko_rows,
         report.candidate_dirty_hybrid_rows,
         report.candidate_dirty_spread_rows,
         (report.candidate_score_gate_rows > 0 ? (double)report.candidate_dirty_rows / (double)report.candidate_score_gate_rows : 0.0),
         max_dirty_ratio
      );
   else
      report.reason_code = "TRUSTED";

   MbNormalizeReasonTriple(report.reason_code,report.normalized_reason);
   MbResolveTrustStateFromReport(
      symbol,
      report.reason_code,
      (report.reason_code == "TRUSTED"),
      state.learning_sample_count,
      (state.learning_win_count + state.learning_loss_count),
      report.candidate_rows,
      report.candidate_risk_block_rows,
      report.candidate_score_gate_rows,
      report.candidate_dirty_rows,
      report.paper_open_rows,
      recent_conversion_ratio,
      central_stale_seconds,
      report.trust_state
   );
   report.trusted = (report.trust_state.state == "TRUSTED");
   bool should_journal = (deckhand_log_missing || MbTuningDeckhandShouldJournal(policy,report,state.learning_sample_count));
   policy.reason_streak = ((previous_reason == report.reason_code) ? (policy.reason_streak + 1) : 1);
   if(report.trusted)
     {
      policy.trusted_cycles = (previous_trusted ? (policy.trusted_cycles + 1) : 1);
      policy.blocked_cycles = 0;
     }
   else
     {
      policy.blocked_cycles = ((previous_trusted || previous_reason != report.reason_code) ? 1 : (policy.blocked_cycles + 1));
      policy.trusted_cycles = 0;
     }
   policy.trusted_data = report.trusted;
   policy.trust_reason = report.reason_code;
   policy.trust_reason_domain = report.normalized_reason.domain;
   policy.trust_reason_class = report.normalized_reason.reason_class;
   policy.last_trust_state = report.trust_state.state;
   policy.last_execution_quality_state = report.execution_quality.state;
   policy.last_cost_pressure_state = report.cost_pressure.state;
   if(MbIsPaperConversionBlockedReason(report.reason_code))
     {
      policy.last_hypothesis_code = "ODBLOKUJ_KONWERSJE_PAPER";
      policy.last_hypothesis_detail = StringFormat(
         "reason=%s;score_gate=%d;paper_open=%d;conversion=%.4f;recent_conversion=%.4f;min_conversion=%.4f;risk=%d;heat=%d;rate=%d",
         report.reason_code,
         report.candidate_score_gate_rows,
         report.paper_open_rows,
         report.trust_state.conversion_ratio,
         report.trust_state.recent_conversion_ratio,
         report.trust_state.min_conversion_ratio,
         report.decision_risk_contract_block_rows,
         report.decision_portfolio_heat_block_rows,
         report.decision_rate_guard_block_rows
      );
      policy.last_counterfactual_code = "GDYBY_NIE_ODBLOKOWAC";
      policy.last_counterfactual_detail = "agent dalej widzialby sygnaly, ale nie dostawalby reprezentatywnych lekcji papierowych";
     }
   else if(MbIsForefieldDirtyReason(report.reason_code))
     {
      policy.last_hypothesis_code = "OCZYSC_PRZEDPOLE";
      policy.last_hypothesis_detail = StringFormat(
         "reason=%s;score_gate=%d;dirty=%d;dirty_ratio=%.4f;max_dirty=%.4f;candle=%d;renko=%d;hybrid=%d;spread=%d",
         report.reason_code,
         report.candidate_score_gate_rows,
         report.candidate_dirty_rows,
         report.trust_state.dirty_ratio,
         report.trust_state.max_dirty_ratio,
         report.candidate_dirty_candle_rows,
         report.candidate_dirty_renko_rows,
         report.candidate_dirty_hybrid_rows,
         report.candidate_dirty_spread_rows
      );
      policy.last_counterfactual_code = "GDYBY_WEJSC_W_BRUD";
      policy.last_counterfactual_detail = "agent uczylby sie na slabym materiale i wracal do tych samych bledow";
     }
   else if(report.reason_code == "CENTRAL_STATE_STALE")
     {
      policy.last_hypothesis_code = "USTABILIZUJ_CENTRALE";
      policy.last_hypothesis_detail = StringFormat(
         "central_stale_seconds=%d;reason=%s",
         central_stale_seconds,
         report.reason_code
      );
      policy.last_counterfactual_code = "GDYBY_UFAC_STAREJ_CENTRALI";
      policy.last_counterfactual_detail = "agent przypisalby blokady lub zgody do nieaktualnego stanu centralnego";
     }
   else if(report.reason_code == "INFRASTRUCTURE_WEAK")
     {
      policy.last_hypothesis_code = "WSTRZYMAJ_STROJENIE_INFRA";
      policy.last_hypothesis_detail = StringFormat(
         "exec_quality=%s;exec_reason=%s;ping=%I64d;tick_age=%I64d",
         report.execution_quality.state,
         report.execution_quality.reason_code,
         report.execution_quality.ping_ms,
         report.execution_quality.tick_age_ms
      );
      policy.last_counterfactual_code = "GDYBY_STROIC_PRZY_SLABEJ_EGZEKUCJI";
      policy.last_counterfactual_detail = "agent obwinilby setup za problem wykonania albo lacza";
     }
   else if(report.reason_code == "LOW_SAMPLE" || report.reason_code == "OBSERVATIONS_MISSING" || report.reason_code == "BUCKETS_EMPTY")
     {
      policy.last_hypothesis_code = "ZBIERAJ_PROBKE";
      policy.last_hypothesis_detail = StringFormat(
         "observations=%d;buckets=%d",
         report.observation_rows,
         report.bucket_rows
      );
      policy.last_counterfactual_code = "GDYBY_STROIC_ZA_WCZESNIE";
      policy.last_counterfactual_detail = "agent moglby przeregulowac sie na zbyt malej probce";
     }
   else if(report.reason_code == "TRUSTED")
     {
      policy.last_hypothesis_code = "GOTOWY_DO_STROJENIA";
      policy.last_hypothesis_detail = StringFormat(
         "observations=%d;buckets=%d;paper_open=%d;conversion=%.4f",
         report.observation_rows,
         report.bucket_rows,
         report.paper_open_rows,
         report.trust_state.conversion_ratio
      );
      policy.last_counterfactual_code = "MATERIAL_CZYSTY";
      policy.last_counterfactual_detail = "mozna stroic na danych, ktore maja juz sensowny ksztalt";
     }

   policy.last_learning_sample_count = state.learning_sample_count;
   policy.last_observation_rows = report.observation_rows;
   policy.last_bucket_rows = report.bucket_rows;
   policy.last_candidate_rows = report.candidate_rows;
   policy.last_candidate_risk_block_rows = report.candidate_risk_block_rows;
   policy.last_candidate_score_gate_rows = report.candidate_score_gate_rows;
   policy.last_candidate_dirty_rows = report.candidate_dirty_rows;
   policy.last_paper_open_rows = report.paper_open_rows;
   if(should_journal)
     {
      policy.last_logged_trusted = report.trusted;
      policy.last_logged_reason_code = report.reason_code;
      policy.last_logged_reason_domain = report.normalized_reason.domain;
      policy.last_logged_reason_class = report.normalized_reason.reason_class;
      policy.last_logged_learning_sample_count = state.learning_sample_count;
      policy.last_logged_observation_rows = report.observation_rows;
      policy.last_logged_bucket_rows = report.bucket_rows;
      policy.last_logged_candidate_rows = report.candidate_rows;
      policy.last_logged_candidate_risk_block_rows = report.candidate_risk_block_rows;
      policy.last_logged_candidate_score_gate_rows = report.candidate_score_gate_rows;
      policy.last_logged_candidate_dirty_rows = report.candidate_dirty_rows;
      policy.last_logged_paper_open_rows = report.paper_open_rows;
      policy.last_deckhand_log_at = report.serviced_at;
      MbAppendTuningDeckhandEvent(deckhand_log_path,symbol,report);
      MbAppendTuningReasoningEvent(symbol,"DECKHAND",policy,report);
     }
  }

#endif
