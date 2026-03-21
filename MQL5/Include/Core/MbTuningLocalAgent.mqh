#ifndef MB_TUNING_LOCAL_AGENT_INCLUDED
#define MB_TUNING_LOCAL_AGENT_INCLUDED

#include "MbTuningDeckhand.mqh"
#include "MbTuningGuardMatrix.mqh"
#include "MbForexDoctrineEURUSD.mqh"

double MbTuningClamp(const double value,const double lo,const double hi)
  {
   return MathMax(lo,MathMin(hi,value));
  }

double MbTuningClampStep(const double current,const double target,const double max_step)
  {
   if(max_step <= 0.0)
      return target;
   double delta = target - current;
   if(delta > max_step)
      return current + max_step;
   if(delta < (-max_step))
      return current - max_step;
   return target;
  }

void MbTuningSetReasonTriple(
   MbReasonTriple &out,
   const string domain,
   const string reason_class,
   const string reason_code
)
  {
   out.domain = domain;
   out.reason_class = reason_class;
   out.reason_code = reason_code;
  }

bool MbTuningLocalAlphaJudgeable(const MbTuningDeckhandReport &report)
  {
   return (
      report.trust_state.state == "TRUSTED" &&
      report.execution_quality.state != "BAD" &&
      report.cost_pressure.state != "NON_REPRESENTATIVE"
   );
  }

bool MbTuningExperimentBaselineJudgeable(const MbTuningLocalPolicy &policy)
  {
   return (
      policy.experiment_baseline_trust_state == "TRUSTED" &&
      policy.experiment_baseline_execution_quality_state != "BAD" &&
      policy.experiment_baseline_cost_pressure_state != "NON_REPRESENTATIVE"
   );
  }

void MbTuningResolveExperimentReviewReason(
   const MbTuningLocalPolicy &policy,
   const MbRuntimeState &state,
   const MbTuningDeckhandReport &report,
   MbReasonTriple &out
)
  {
   int delta_samples = state.learning_sample_count - policy.experiment_baseline_samples;
   int delta_wins = state.learning_win_count - policy.experiment_baseline_wins;
   int delta_losses = state.learning_loss_count - policy.experiment_baseline_losses;
  int delta_closed = delta_wins + delta_losses;
  int delta_paper_open_rows = report.paper_open_rows - policy.experiment_baseline_paper_open_rows;
  double delta_realized_pnl_lifetime = state.realized_pnl_lifetime - policy.experiment_baseline_realized_pnl_lifetime;
  int age_sec = (int)(TimeCurrent() - policy.experiment_started_at);
   string trust_reason_code = report.trust_state.reason_code;
   if(trust_reason_code == "")
      trust_reason_code = report.reason_code;
   bool baseline_judgeable = MbTuningExperimentBaselineJudgeable(policy);

   string paper_conversion_reason_code = report.reason_code;
   if(!MbIsPaperConversionBlockedReason(paper_conversion_reason_code))
      paper_conversion_reason_code = trust_reason_code;
   if(MbIsPaperConversionBlockedReason(paper_conversion_reason_code))
     {
      MbTuningSetReasonTriple(out,"RISK","CONTRACT",paper_conversion_reason_code);
      return;
     }

   string forefield_dirty_reason_code = report.reason_code;
   if(!MbIsForefieldDirtyReason(forefield_dirty_reason_code))
      forefield_dirty_reason_code = trust_reason_code;
   if(MbIsForefieldDirtyReason(forefield_dirty_reason_code))
     {
      MbTuningSetReasonTriple(out,"DATA","TRUST",forefield_dirty_reason_code);
      return;
     }

   if(report.trust_state.state != "TRUSTED")
     {
      if(report.trust_state.state == "CENTRAL_STATE_STALE" || trust_reason_code == "CENTRAL_STATE_STALE")
         MbTuningSetReasonTriple(out,"CENTRAL","STALENESS","CENTRAL_STATE_STALE");
      else if(report.trust_state.state == "INFRASTRUCTURE_WEAK" || trust_reason_code == "INFRASTRUCTURE_WEAK")
         MbTuningSetReasonTriple(out,"INFRA","HEALTH",(trust_reason_code == "" ? "INFRASTRUCTURE_WEAK" : trust_reason_code));
      else
         MbTuningSetReasonTriple(out,"DATA","TRUST",(trust_reason_code == "" ? "TRUST_STATE_BLOCKED" : trust_reason_code));
      return;
     }

   if(report.execution_quality.state == "BAD")
     {
      MbTuningSetReasonTriple(
         out,
         "EXECUTION",
         "DEGRADATION",
         (report.execution_quality.reason_code == "" ? "EXECUTION_QUALITY_BAD" : report.execution_quality.reason_code)
      );
      return;
     }

   if(report.cost_pressure.state == "NON_REPRESENTATIVE")
     {
      MbTuningSetReasonTriple(
         out,
         "COST",
         "PRESSURE",
         (report.cost_pressure.reason_code == "" ? "NON_REPRESENTATIVE_COST" : report.cost_pressure.reason_code)
      );
      return;
     }

   if(!baseline_judgeable &&
      (delta_closed > 0 || delta_paper_open_rows > 0 || delta_samples >= MathMax(2,policy.min_bucket_samples / 2)))
     {
      MbTuningSetReasonTriple(out,"MODE","OBSERVATION","EXPERIMENT_BASELINE_NOT_JUDGEABLE");
      return;
     }

   if(delta_closed >= 2 && delta_losses >= (delta_wins + 1) && delta_realized_pnl_lifetime <= -0.20)
     {
      MbTuningSetReasonTriple(out,"SIGNAL","NEGATIVE_OUTCOME","EXPERIMENT_NET_DEGRADED");
      return;
     }

   if(delta_paper_open_rows >= 2 && delta_losses >= delta_wins && delta_realized_pnl_lifetime <= -0.30)
     {
      MbTuningSetReasonTriple(out,"SIGNAL","NEGATIVE_OUTCOME","EXPERIMENT_CONVERSION_DEGRADED");
      return;
     }

   if(delta_closed > 0 && delta_realized_pnl_lifetime >= 0.20)
     {
      MbTuningSetReasonTriple(out,"SIGNAL","POSITIVE_OUTCOME","EXPERIMENT_NET_IMPROVED");
      return;
     }

   if(delta_closed >= 2 && delta_wins > delta_losses && delta_realized_pnl_lifetime >= -0.05)
     {
      MbTuningSetReasonTriple(out,"SIGNAL","POSITIVE_OUTCOME","EXPERIMENT_BALANCE_IMPROVED");
      return;
     }

   if(delta_paper_open_rows >= 2 && delta_losses <= 0 && delta_realized_pnl_lifetime >= -0.05)
     {
      MbTuningSetReasonTriple(out,"SIGNAL","POSITIVE_OUTCOME","EXPERIMENT_CONVERSION_IMPROVED");
      return;
     }

   if(age_sec >= MathMax(900,policy.cooldown_sec) &&
      delta_samples <= 0 &&
      delta_closed <= 0 &&
      delta_paper_open_rows <= 0)
     {
      MbTuningSetReasonTriple(out,"MODE","OBSERVATION","EXPERIMENT_NO_PROGRESS");
      return;
     }

   if(report.normalized_reason.reason_code != "" &&
      report.normalized_reason.reason_code != "TRUSTED" &&
      report.normalized_reason.reason_code != "UNASSESSED")
     {
      out = report.normalized_reason;
      return;
     }

   MbTuningSetReasonTriple(out,"MODE","OBSERVATION","EXPERIMENT_WAITING_CLEAN_EVIDENCE");
  }

void MbTuningApplyBoundedStep(const MbTuningLocalPolicy &current,MbTuningLocalPolicy &next,const MbTuningAdaptationContract &contract)
  {
   next.breakout_global_tax = MbTuningClampStep(current.breakout_global_tax,next.breakout_global_tax,contract.tax_step_max);
   next.breakout_chaos_tax = MbTuningClampStep(current.breakout_chaos_tax,next.breakout_chaos_tax,contract.tax_step_max);
   next.breakout_range_tax = MbTuningClampStep(current.breakout_range_tax,next.breakout_range_tax,contract.tax_step_max);
   next.breakout_conflict_tax = MbTuningClampStep(current.breakout_conflict_tax,next.breakout_conflict_tax,contract.tax_step_max);
   next.trend_breakout_tax = MbTuningClampStep(current.trend_breakout_tax,next.trend_breakout_tax,contract.tax_step_max);
   next.trend_chaos_tax = MbTuningClampStep(current.trend_chaos_tax,next.trend_chaos_tax,contract.tax_step_max);
   next.trend_caution_tax = MbTuningClampStep(current.trend_caution_tax,next.trend_caution_tax,contract.tax_step_max);
   next.trend_no_aux_tax = MbTuningClampStep(current.trend_no_aux_tax,next.trend_no_aux_tax,contract.tax_step_max);
   next.range_chaos_tax = MbTuningClampStep(current.range_chaos_tax,next.range_chaos_tax,contract.tax_step_max);
   next.range_trend_tax = MbTuningClampStep(current.range_trend_tax,next.range_trend_tax,contract.tax_step_max);
   next.range_confidence_floor = MbTuningClampStep(current.range_confidence_floor,next.range_confidence_floor,contract.floor_step_max);
   next.index_opening_impulse_tax = MbTuningClampStep(current.index_opening_impulse_tax,next.index_opening_impulse_tax,contract.tax_step_max);
   next.index_noon_transition_tax = MbTuningClampStep(current.index_noon_transition_tax,next.index_noon_transition_tax,contract.tax_step_max);
   next.rejection_range_boost = MbTuningClampStep(current.rejection_range_boost,next.rejection_range_boost,contract.boost_step_max);
   next.confidence_cap = MbTuningClampStep(current.confidence_cap,next.confidence_cap,contract.cap_step_max);
   next.risk_cap = MbTuningClampStep(current.risk_cap,next.risk_cap,contract.cap_step_max);
  }

void MbTuningRefreshAdaptationWindow(MbTuningLocalPolicy &policy,const MbTuningAdaptationContract &contract)
  {
   if(policy.adaptation_window_started_at <= 0 || (TimeCurrent() - policy.adaptation_window_started_at) >= contract.change_window_sec)
     {
      policy.adaptation_window_started_at = TimeCurrent();
      policy.adaptation_changes_in_window = 0;
     }
  }

double MbTuningPenaltyFromAvg(const double avg_pnl,const int samples,const int min_samples,const double factor,const double lo,const double hi)
  {
   if(samples < min_samples || avg_pnl >= -0.10)
      return 0.0;
   return MbTuningClamp((-avg_pnl) * factor,lo,hi);
  }

double MbTuningBoostFromAvg(const double avg_pnl,const int samples,const int min_samples,const double factor,const double lo,const double hi)
  {
   if(samples < min_samples || avg_pnl <= 0.10)
      return 0.0;
   return MbTuningClamp(avg_pnl * factor,lo,hi);
  }

bool MbTuningResolveFamily(const string symbol,string &out_family)
  {
   out_family = "";
   return MbResolveTuningGuardFamily(symbol,out_family);
  }

bool MbTuningIsIndexFamily(const string family)
  {
   return (family == "INDEX_EU" || family == "INDEX_US");
  }

int MbReadTuningBucketSummary(const string symbol,MbTuningBucketStats &out[])
  {
   ArrayResize(out,0);
   string path = MbLogFilePath(symbol,"learning_bucket_summary_v1.csv");
   int h = FileOpen(path,FILE_COMMON | FILE_READ | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return 0;

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

      int next = ArraySize(out);
      ArrayResize(out,next + 1);
      MbTuningBucketStatsReset(out[next]);
      out[next].setup_type = c1;
      out[next].market_regime = c2;
      out[next].samples = (int)StringToInteger(c3);
      out[next].wins = (int)StringToInteger(c4);
      out[next].losses = (int)StringToInteger(c5);
      out[next].pnl_sum = StringToDouble(c6);
      out[next].avg_pnl = StringToDouble(c7);
     }

   FileClose(h);
   return ArraySize(out);
  }

bool MbTuningPolicyChanged(const MbTuningLocalPolicy &lhs,const MbTuningLocalPolicy &rhs)
  {
   if(lhs.require_aux_support_for_trend != rhs.require_aux_support_for_trend)
      return true;
   if(lhs.require_support_for_rejection != rhs.require_support_for_rejection)
      return true;
   if(lhs.require_non_poor_renko_for_breakout != rhs.require_non_poor_renko_for_breakout)
      return true;
   if(lhs.require_non_poor_candle_for_breakout != rhs.require_non_poor_candle_for_breakout)
      return true;
   if(lhs.require_non_poor_candle_for_trend != rhs.require_non_poor_candle_for_trend)
      return true;
   if(lhs.require_non_poor_candle_for_range != rhs.require_non_poor_candle_for_range)
      return true;
   if(lhs.require_non_poor_renko_for_range != rhs.require_non_poor_renko_for_range)
      return true;
   if(MathAbs(lhs.breakout_global_tax - rhs.breakout_global_tax) > 0.0005)
      return true;
   if(MathAbs(lhs.breakout_chaos_tax - rhs.breakout_chaos_tax) > 0.0005)
      return true;
   if(MathAbs(lhs.breakout_range_tax - rhs.breakout_range_tax) > 0.0005)
      return true;
   if(MathAbs(lhs.breakout_conflict_tax - rhs.breakout_conflict_tax) > 0.0005)
      return true;
   if(MathAbs(lhs.trend_breakout_tax - rhs.trend_breakout_tax) > 0.0005)
      return true;
   if(MathAbs(lhs.trend_chaos_tax - rhs.trend_chaos_tax) > 0.0005)
      return true;
   if(MathAbs(lhs.trend_caution_tax - rhs.trend_caution_tax) > 0.0005)
      return true;
   if(MathAbs(lhs.trend_no_aux_tax - rhs.trend_no_aux_tax) > 0.0005)
      return true;
   if(MathAbs(lhs.range_chaos_tax - rhs.range_chaos_tax) > 0.0005)
      return true;
   if(MathAbs(lhs.range_trend_tax - rhs.range_trend_tax) > 0.0005)
      return true;
   if(MathAbs(lhs.range_confidence_floor - rhs.range_confidence_floor) > 0.0005)
      return true;
   if(MathAbs(lhs.index_opening_impulse_tax - rhs.index_opening_impulse_tax) > 0.0005)
      return true;
   if(MathAbs(lhs.index_noon_transition_tax - rhs.index_noon_transition_tax) > 0.0005)
      return true;
   if(MathAbs(lhs.rejection_range_boost - rhs.rejection_range_boost) > 0.0005)
      return true;
   if(MathAbs(lhs.confidence_cap - rhs.confidence_cap) > 0.0005)
      return true;
   if(MathAbs(lhs.risk_cap - rhs.risk_cap) > 0.0005)
      return true;
  return false;
  }

void MbTuningResolveDominantFocus(
   const MbTuningBucketStats &buckets[],
   const int min_samples,
   string &out_setup_type,
   string &out_market_regime,
   string &out_focus_detail
)
  {
   out_setup_type = "NONE";
   out_market_regime = "UNKNOWN";
   out_focus_detail = "no_focus";

   int best_index = -1;
   double best_priority = 0.0;
   bool best_negative = false;
   int min_focus_samples = MathMax(3,min_samples / 2);
   for(int i = 0; i < ArraySize(buckets); ++i)
     {
      MbTuningBucketStats row = buckets[i];
      if(row.samples < min_focus_samples)
         continue;

      bool negative = (row.avg_pnl < 0.0);
      double priority = MathAbs(row.avg_pnl) * (double)row.samples;
      if(best_index < 0)
        {
         best_index = i;
         best_priority = priority;
         best_negative = negative;
         continue;
        }

      if(negative && !best_negative)
        {
         best_index = i;
         best_priority = priority;
         best_negative = true;
         continue;
        }
      if(negative == best_negative && priority > best_priority)
        {
         best_index = i;
         best_priority = priority;
         best_negative = negative;
        }
     }

   if(best_index < 0)
      return;

   MbTuningBucketStats focus = buckets[best_index];
   out_setup_type = focus.setup_type;
   out_market_regime = focus.market_regime;
   out_focus_detail = StringFormat(
      "setup=%s;regime=%s;samples=%d;wins=%d;losses=%d;avg_pnl=%.2f",
      focus.setup_type,
      focus.market_regime,
      focus.samples,
      focus.wins,
      focus.losses,
      focus.avg_pnl
   );
  }

void MbTuningResolveThoughts(
   const MbTuningLocalPolicy &policy,
   const MbTuningDeckhandReport &report,
   const string focus_setup_type,
   const string focus_market_regime,
   const string focus_detail,
   string &out_hypothesis_code,
   string &out_hypothesis_detail,
   string &out_counterfactual_code,
   string &out_counterfactual_detail
)
  {
   out_hypothesis_code = "REBALANSUJ";
   out_hypothesis_detail = focus_detail;
   out_counterfactual_code = "BEZ_ZMIAN";
   out_counterfactual_detail = focus_detail;

   if(MbIsPaperConversionBlockedReason(report.reason_code))
     {
      out_hypothesis_code = "ODBLOKUJ_KONWERSJE_PAPER";
      out_hypothesis_detail = StringFormat(
         "%s;reason=%s;score_gate=%d;paper_open=%d;conversion=%.4f;recent_conversion=%.4f;min_conversion=%.4f",
         focus_detail,
         report.reason_code,
         report.candidate_score_gate_rows,
         report.paper_open_rows,
         report.trust_state.conversion_ratio,
         report.trust_state.recent_conversion_ratio,
         report.trust_state.min_conversion_ratio
      );
      out_counterfactual_code = "GDYBY_BRAK_ODBLOKOWANIA";
      out_counterfactual_detail = "agent dalej widzialby sygnaly, ale nie dostawalby lekcji papierowych";
      return;
     }

   if(MbIsForefieldDirtyReason(report.reason_code))
     {
      out_hypothesis_code = "OCZYSC_PRZEDPOLE";
      out_hypothesis_detail = StringFormat(
         "%s;reason=%s;score_gate=%d;dirty=%d;dirty_ratio=%.4f;max_dirty=%.4f;spread_dirty=%d",
         focus_detail,
         report.reason_code,
         report.candidate_score_gate_rows,
         report.candidate_dirty_rows,
         report.trust_state.dirty_ratio,
         report.trust_state.max_dirty_ratio,
         report.candidate_dirty_spread_rows
      );
      out_counterfactual_code = "GDYBY_WEJSC_BEZ_CZYSZCZENIA";
      out_counterfactual_detail = "agent uczylby sie na brudnych przypadkach i wzmacnial zly genotyp";
      return;
     }

   if(report.reason_code == "INFRASTRUCTURE_WEAK")
     {
      out_hypothesis_code = "USTABILIZUJ_INFRASTRUKTURE";
      out_hypothesis_detail = StringFormat(
         "%s;exec_pressure=%.2f;exec_errors=%d;spread_anomaly=%d",
         focus_detail,
         report.execution_pressure,
         report.exec_error_streak,
         report.spread_anomaly_streak
      );
      out_counterfactual_code = "GDYBY_STROIC_NA_SLABYM_LACZU";
      out_counterfactual_detail = "agent pomylilby problem infrastruktury z problemem strategii i stroilby zly obszar";
      return;
     }

   if(report.reason_code == "LOW_SAMPLE" || report.reason_code == "OBSERVATIONS_MISSING" || report.reason_code == "BUCKETS_EMPTY")
     {
      out_hypothesis_code = "ZBIERAJ_MATERIAL";
      out_hypothesis_detail = StringFormat("%s;observations=%d;buckets=%d",focus_detail,report.observation_rows,report.bucket_rows);
      out_counterfactual_code = "GDYBY_STROIC_ZA_WCZESNIE";
      out_counterfactual_detail = "agent nadpisalby polityke na zbyt malej probce";
      return;
     }

   if(policy.require_non_poor_candle_for_breakout || policy.require_non_poor_renko_for_breakout)
      out_hypothesis_code = "PODNIES_JAKOSC_BREAKOUT";
   else if(policy.require_non_poor_candle_for_trend)
      out_hypothesis_code = "PODNIES_JAKOSC_TREND";
   else if(policy.require_non_poor_candle_for_range || policy.require_non_poor_renko_for_range || policy.range_confidence_floor > 0.0)
      out_hypothesis_code = "PODNIES_JAKOSC_RANGE";
   else if(policy.breakout_chaos_tax > 0.0)
      out_hypothesis_code = "PRZYTLUM_BREAKOUT_CHAOS";
   else if(policy.breakout_range_tax > 0.0)
      out_hypothesis_code = "PRZYTLUM_BREAKOUT_RANGE";
   else if(policy.trend_chaos_tax > 0.0)
      out_hypothesis_code = "PRZYTLUM_TREND_CHAOS";
   else if(policy.trend_breakout_tax > 0.0)
      out_hypothesis_code = "PRZYTLUM_TREND_BREAKOUT";
   else if(policy.range_chaos_tax > 0.0)
      out_hypothesis_code = "PRZYTLUM_RANGE_CHAOS";
   else if(policy.range_trend_tax > 0.0)
      out_hypothesis_code = "PRZYTLUM_RANGE_TREND";
   else if(policy.rejection_range_boost > 0.0)
      out_hypothesis_code = "WZMOCNIJ_REJECTION_RANGE";
   else if(policy.require_support_for_rejection)
      out_hypothesis_code = "ZADAJ_WSPARCIA_REJECTION";

   out_hypothesis_detail = focus_detail;
   out_counterfactual_code = "GDYBY_ZOSTAWIC_BEZ_ZMIAN";
   out_counterfactual_detail = focus_detail;
  }

void MbTuningSummarizeAction(
   const MbTuningLocalPolicy &policy,
   string &out_code,
   string &out_detail
)
  {
   out_code = "REBALANCE";
   double strongest = policy.breakout_chaos_tax;

   if(policy.trend_breakout_tax > strongest)
     {
      strongest = policy.trend_breakout_tax;
      out_code = "DAMP_TREND_BREAKOUT";
     }
   if(policy.trend_chaos_tax > strongest)
     {
      strongest = policy.trend_chaos_tax;
      out_code = "DAMP_TREND_CHAOS";
     }
   if(policy.range_chaos_tax > strongest)
     {
      strongest = policy.range_chaos_tax;
      out_code = "DAMP_RANGE_CHAOS";
     }
   if(policy.range_trend_tax > strongest)
     {
      strongest = policy.range_trend_tax;
      out_code = "DAMP_RANGE_TREND";
     }
   if(policy.breakout_range_tax > strongest)
     {
      strongest = policy.breakout_range_tax;
      out_code = "DAMP_BREAKOUT_RANGE";
     }
   if(policy.breakout_chaos_tax > strongest)
     {
      strongest = policy.breakout_chaos_tax;
      out_code = "DAMP_BREAKOUT_CHAOS";
     }
   if(policy.rejection_range_boost >= strongest && policy.rejection_range_boost > 0.0)
      out_code = "BOOST_REJECTION_RANGE";
   if(policy.index_opening_impulse_tax > strongest)
      out_code = "DAMP_INDEX_OPEN";
   if(policy.index_noon_transition_tax > strongest)
      out_code = "DAMP_INDEX_TRANSITION";
   if(policy.require_non_poor_renko_for_breakout)
      out_code = "FILTER_BREAKOUT_RENKO";
   if(policy.require_non_poor_candle_for_breakout)
      out_code = "FILTER_BREAKOUT_CANDLE";
   if(policy.require_non_poor_candle_for_trend)
      out_code = "FILTER_TREND_CANDLE";
   if(policy.require_non_poor_candle_for_range)
      out_code = "FILTER_RANGE_CANDLE";
   if(policy.require_non_poor_renko_for_range)
      out_code = "FILTER_RANGE_RENKO";
   if(policy.require_support_for_rejection)
      out_code = "FILTER_REJECTION_SUPPORT";
   if(policy.range_confidence_floor > 0.0)
      out_code = "FLOOR_RANGE_CONFIDENCE";

   out_detail = StringFormat(
      "conf_cap=%.2f;risk_cap=%.2f;bg=%.2f;bc=%.2f;br=%.2f;tb=%.2f;tc=%.2f;rch=%.2f;rt=%.2f;floor=%.2f;idxo=%.2f;idxn=%.2f;rr=%.2f;aux=%s;rej=%s;breakout_renko=%s;breakout_candle=%s;range_candle=%s;range_renko=%s;trend_candle=%s",
      policy.confidence_cap,
      policy.risk_cap,
      policy.breakout_global_tax,
      policy.breakout_chaos_tax,
      policy.breakout_range_tax,
      policy.trend_breakout_tax,
      policy.trend_chaos_tax,
      policy.range_chaos_tax,
      policy.range_trend_tax,
      policy.range_confidence_floor,
      policy.index_opening_impulse_tax,
      policy.index_noon_transition_tax,
      policy.rejection_range_boost,
      (policy.require_aux_support_for_trend ? "1" : "0"),
      (policy.require_support_for_rejection ? "1" : "0"),
      (policy.require_non_poor_renko_for_breakout ? "1" : "0"),
      (policy.require_non_poor_candle_for_breakout ? "1" : "0"),
      (policy.require_non_poor_candle_for_range ? "1" : "0"),
      (policy.require_non_poor_renko_for_range ? "1" : "0"),
      (policy.require_non_poor_candle_for_trend ? "1" : "0")
   );
  }

bool MbTuningFailedPathMatches(
   const MbTuningLocalPolicy &policy,
   const string action_code,
   const string focus_setup_type,
   const string focus_market_regime,
   const string cause_domain,
   const string cause_class,
   const string cause_code
)
  {
   if(policy.last_failed_action_code != action_code)
      return false;
   if(policy.last_failed_focus_setup_type != focus_setup_type)
      return false;
   if(policy.last_failed_focus_market_regime != focus_market_regime)
      return false;
   if(policy.last_failed_cause_domain != cause_domain)
      return false;
   if(policy.last_failed_cause_class != cause_class)
      return false;
   if(policy.last_failed_cause_code != cause_code)
      return false;
   return true;
  }

bool MbTuningShouldAvoidRepeat(
   const MbTuningLocalPolicy &policy,
   const string action_code,
   const string focus_setup_type,
   const string focus_market_regime,
   const string cause_domain,
   const string cause_class,
   const string cause_code
)
  {
   if(policy.last_failed_at <= 0 || policy.avoid_repeat_until <= TimeCurrent())
      return false;
   return MbTuningFailedPathMatches(policy,action_code,focus_setup_type,focus_market_regime,cause_domain,cause_class,cause_code);
  }

bool MbBuildAlternativeExperiment(
   const string symbol,
   const MbTuningLocalPolicy &policy,
   MbTuningLocalPolicy &out_alternative
)
  {
   string canonical = MbCanonicalSymbol(symbol);

   if(
      canonical == "EURUSD" &&
      policy.last_failed_action_code == "FILTER_TREND_CANDLE" &&
      policy.last_failed_focus_setup_type == "SETUP_TREND" &&
      policy.last_failed_focus_market_regime == "BREAKOUT"
   )
     {
      out_alternative = policy;
      out_alternative.require_non_poor_candle_for_trend = false;
      out_alternative.require_non_poor_candle_for_breakout = true;
      out_alternative.require_non_poor_renko_for_breakout = false;
      out_alternative.trend_breakout_tax = MathMax(policy.trend_breakout_tax,0.12);
      out_alternative.breakout_global_tax = MathMax(policy.breakout_global_tax,0.08);
      out_alternative.last_focus_setup_type = "SETUP_BREAKOUT";
      out_alternative.last_focus_market_regime = "BREAKOUT";
      out_alternative.last_hypothesis_code = "SPRAWDZ_JAKOSC_BREAKOUT";
      out_alternative.last_hypothesis_detail = "po fiasku filtra trendu sprawdz breakout z lepsza swieca i lekkim podatkiem trend/breakout";
      out_alternative.last_counterfactual_code = "GDYBY_TKWIC_W_FIASKU";
      out_alternative.last_counterfactual_detail = "agent nie sprawdzilby alternatywnej drogi po swiezo obalonym filtrze trendu";
      return MbTuningPolicyChanged(policy,out_alternative);
     }

   if(
      canonical == "DE30" &&
      policy.last_failed_action_code == "FILTER_BREAKOUT_RENKO" &&
      policy.last_failed_focus_setup_type == "SETUP_BREAKOUT" &&
      policy.last_failed_focus_market_regime == "BREAKOUT"
   )
     {
      out_alternative = policy;
      out_alternative.require_non_poor_candle_for_range = true;
      out_alternative.require_non_poor_renko_for_range = true;
      out_alternative.range_chaos_tax = MathMax(policy.range_chaos_tax,0.12);
      out_alternative.breakout_global_tax = MathMax(policy.breakout_global_tax,0.10);
      out_alternative.confidence_cap = MathMin(policy.confidence_cap,0.74);
      out_alternative.risk_cap = MathMin(policy.risk_cap,0.64);
      out_alternative.last_focus_setup_type = "SETUP_RANGE";
      out_alternative.last_focus_market_regime = "CHAOS";
      out_alternative.last_hypothesis_code = "ODEJSCIE_OD_BREAKOUT_DE30";
      out_alternative.last_hypothesis_detail = "po fiasku breakoutu w chaosie sprawdz tylko selektywny range z dobra swieca, renko i ciasniejszym ryzykiem";
      out_alternative.last_counterfactual_code = "GDYBY_TKWIC_W_BREAKOUT_CHAOS";
      out_alternative.last_counterfactual_detail = "agent dalej wzmacnialby indeksowy breakout, ktory nie utrzymuje sie po wejsciu";
      return MbTuningPolicyChanged(policy,out_alternative);
     }

   if(
      canonical == "USDJPY" &&
      policy.last_failed_action_code == "FLOOR_RANGE_CONFIDENCE" &&
      policy.last_failed_focus_setup_type == "SETUP_BREAKOUT" &&
      policy.last_failed_focus_market_regime == "TREND"
   )
     {
      out_alternative = policy;
      out_alternative.require_non_poor_candle_for_range = true;
      out_alternative.require_non_poor_renko_for_range = true;
      out_alternative.range_confidence_floor = MathMax(policy.range_confidence_floor,0.74);
      out_alternative.range_trend_tax = MathMax(policy.range_trend_tax,0.14);
      out_alternative.breakout_global_tax = MathMax(policy.breakout_global_tax,0.08);
      out_alternative.last_focus_setup_type = "SETUP_RANGE";
      out_alternative.last_focus_market_regime = "RANGE";
      out_alternative.last_hypothesis_code = "ODSIEJ_SLABY_RANGE";
      out_alternative.last_hypothesis_detail = "po fiasku podlogi pewnosci sprawdz range tylko z czysta swieca, renko i wyzszym podatkiem trend/range";
      out_alternative.last_counterfactual_code = "GDYBY_TRWAC_W_PSEUDO_BREAKOUT";
      out_alternative.last_counterfactual_detail = "agent dalej uczylby sie na slabym mean reversion z trendowego tla";
      return MbTuningPolicyChanged(policy,out_alternative);
     }

   if(
      canonical == "GBPAUD" &&
      policy.last_failed_action_code == "FLOOR_RANGE_CONFIDENCE" &&
      policy.last_failed_focus_setup_type == "SETUP_BREAKOUT" &&
      policy.last_failed_focus_market_regime == "BREAKOUT"
   )
     {
      out_alternative = policy;
      out_alternative.require_non_poor_renko_for_breakout = true;
      out_alternative.breakout_chaos_tax = MathMax(policy.breakout_chaos_tax,0.08);
      out_alternative.confidence_cap = MathMin(policy.confidence_cap,0.72);
      out_alternative.last_focus_setup_type = "SETUP_BREAKOUT";
      out_alternative.last_focus_market_regime = "BREAKOUT";
      out_alternative.last_hypothesis_code = "ODSIEJ_BREAKOUT_RENKO";
      out_alternative.last_hypothesis_detail = "po jalowym eksperymencie sprawdz breakout tylko z czystym renko i ciasniejsza pewnoscia";
      out_alternative.last_counterfactual_code = "GDYBY_TRWAC_W_JALOWYM_BREAKOUT";
      out_alternative.last_counterfactual_detail = "agent dalej wisialby na breakoutach bez nowych lekcji";
      return MbTuningPolicyChanged(policy,out_alternative);
     }

   if(
      canonical == "USDCHF" &&
      policy.last_failed_action_code == "FILTER_TREND_CANDLE" &&
      policy.last_failed_focus_setup_type == "SETUP_BREAKOUT" &&
      policy.last_failed_focus_market_regime == "BREAKOUT"
   )
     {
      out_alternative = policy;
      out_alternative.require_non_poor_candle_for_breakout = true;
      out_alternative.require_non_poor_renko_for_breakout = true;
      out_alternative.breakout_conflict_tax = MathMax(policy.breakout_conflict_tax,0.08);
      out_alternative.trend_breakout_tax = MathMax(policy.trend_breakout_tax,0.14);
      out_alternative.last_focus_setup_type = "SETUP_BREAKOUT";
      out_alternative.last_focus_market_regime = "BREAKOUT";
      out_alternative.last_hypothesis_code = "DOKREC_BREAKOUT_USDCHF";
      out_alternative.last_hypothesis_detail = "po stracie breakoutu sprawdz wejscia tylko z dobra swieca, renko i wiekszym podatkiem konfliktu";
      out_alternative.last_counterfactual_code = "GDYBY_BRAC_BREAKOUT_ZA_LATWO";
      out_alternative.last_counterfactual_detail = "agent dalej wpuszczalby breakouty, ktore nie wytrzymuja spreadu i konfliktu tla";
      return MbTuningPolicyChanged(policy,out_alternative);
     }

   if(
      canonical == "USDCAD" &&
      policy.last_failed_action_code == "FILTER_REJECTION_SUPPORT" &&
      policy.last_failed_focus_setup_type == "SETUP_BREAKOUT" &&
      policy.last_failed_focus_market_regime == "TREND"
   )
     {
      out_alternative = policy;
      out_alternative.require_non_poor_candle_for_trend = true;
      out_alternative.require_non_poor_candle_for_breakout = true;
      out_alternative.require_non_poor_renko_for_breakout = true;
      out_alternative.breakout_conflict_tax = MathMax(policy.breakout_conflict_tax,0.14);
      out_alternative.trend_breakout_tax = MathMax(policy.trend_breakout_tax,0.16);
      out_alternative.confidence_cap = MathMin(policy.confidence_cap,0.73);
      out_alternative.risk_cap = MathMin(policy.risk_cap,0.72);
      out_alternative.last_focus_setup_type = "SETUP_PULLBACK";
      out_alternative.last_focus_market_regime = "TREND";
      out_alternative.last_hypothesis_code = "ODEJSCIE_OD_BREAKOUT_USDCAD";
      out_alternative.last_hypothesis_detail = "po fiasku breakout-trendu sprawdz tylko bardziej selektywny pullback trendowy z dobra swieca i breakout renko";
      out_alternative.last_counterfactual_code = "GDYBY_GONIC_BREAKOUT_USDCAD";
      out_alternative.last_counterfactual_detail = "agent dalej uczylby sie na breakoutach, ktore wchodza za pozno i gasna po wejsciu";
      return MbTuningPolicyChanged(policy,out_alternative);
     }

   if(
      canonical == "PLATIN" &&
      policy.last_failed_action_code == "REBALANCE" &&
      policy.last_failed_focus_setup_type == "SETUP_BREAKOUT" &&
      policy.last_failed_focus_market_regime == "BREAKOUT"
   )
     {
      out_alternative = policy;
      out_alternative.require_non_poor_candle_for_breakout = true;
      out_alternative.breakout_global_tax = MathMax(policy.breakout_global_tax,0.10);
      out_alternative.risk_cap = MathMin(policy.risk_cap,0.60);
      out_alternative.last_focus_setup_type = "SETUP_BREAKOUT";
      out_alternative.last_focus_market_regime = "BREAKOUT";
      out_alternative.last_hypothesis_code = "OCIAC_PLATIN_BREAKOUT";
      out_alternative.last_hypothesis_detail = "po jalowym rebalansie sprawdz breakout tylko z dobra swieca i ciasniejszym ryzykiem";
      out_alternative.last_counterfactual_code = "GDYBY_REBALANSOWAC_W_PUSTKE";
      out_alternative.last_counterfactual_detail = "agent dalej wisialby na zmianie bez nowych lekcji i bez realnej selekcji";
      return MbTuningPolicyChanged(policy,out_alternative);
     }

   if(
      canonical == "SILVER" &&
      policy.last_failed_action_code == "FILTER_TREND_CANDLE" &&
      policy.last_failed_focus_setup_type == "SETUP_TREND" &&
      policy.last_failed_focus_market_regime == "CHAOS"
   )
     {
      out_alternative = policy;
      out_alternative.require_non_poor_candle_for_range = true;
      out_alternative.require_non_poor_renko_for_range = true;
      out_alternative.require_support_for_rejection = true;
      out_alternative.range_chaos_tax = MathMax(policy.range_chaos_tax,0.10);
      out_alternative.risk_cap = MathMin(policy.risk_cap,0.66);
      out_alternative.last_focus_setup_type = "SETUP_REJECTION";
      out_alternative.last_focus_market_regime = "RANGE";
      out_alternative.last_hypothesis_code = "SILVER_ODEJSCIE_OD_TRENDU";
      out_alternative.last_hypothesis_detail = "po stratnym trendzie w chaosie sprawdz tylko odrzucenie lub range z dobra swieca, renko i wsparciem";
      out_alternative.last_counterfactual_code = "GDYBY_GONIC_TREND_SILVER";
      out_alternative.last_counterfactual_detail = "agent dalej uczylby sie na ruchach trendowych, ktore w srebrze gasna po wejsciu";
      return MbTuningPolicyChanged(policy,out_alternative);
     }

   return false;
  }

string MbTuningBuildExperimentDetail(
   const MbTuningLocalPolicy &policy,
   const MbRuntimeState &state,
   const MbTuningDeckhandReport &report,
   const MbReasonTriple &review_reason
)
  {
   int delta_samples = state.learning_sample_count - policy.experiment_baseline_samples;
   int delta_wins = state.learning_win_count - policy.experiment_baseline_wins;
   int delta_losses = state.learning_loss_count - policy.experiment_baseline_losses;
   int delta_paper_open_rows = report.paper_open_rows - policy.experiment_baseline_paper_open_rows;
   double delta_realized_pnl_lifetime = state.realized_pnl_lifetime - policy.experiment_baseline_realized_pnl_lifetime;

   return StringFormat(
      "akcja=%s;fokus=%s/%s;probki=+%d;wygrane=+%d;przegrane=+%d;paper_open=+%d;pnl=%.2f;trust=%s;exec=%s;cost=%s;review=%s/%s/%s;powod=%s",
      policy.experiment_action_code,
      policy.experiment_focus_setup_type,
      policy.experiment_focus_market_regime,
      delta_samples,
      delta_wins,
      delta_losses,
      delta_paper_open_rows,
      delta_realized_pnl_lifetime,
      report.trust_state.state,
      report.execution_quality.state,
      report.cost_pressure.state,
      review_reason.domain,
      review_reason.reason_class,
      review_reason.reason_code,
      report.reason_code
   );
  }

bool MbTuningExperimentHasEvidence(
   const MbTuningLocalPolicy &policy,
   const MbRuntimeState &state,
   const MbTuningDeckhandReport &report
)
  {
   int delta_samples = state.learning_sample_count - policy.experiment_baseline_samples;
   int delta_closed = (state.learning_win_count - policy.experiment_baseline_wins) + (state.learning_loss_count - policy.experiment_baseline_losses);
   int delta_paper_open_rows = report.paper_open_rows - policy.experiment_baseline_paper_open_rows;
   int age_sec = (int)(TimeCurrent() - policy.experiment_started_at);

   if(
      report.trust_state.state != "TRUSTED" ||
      report.execution_quality.state == "BAD" ||
      report.cost_pressure.state == "NON_REPRESENTATIVE"
   )
     {
      if(age_sec < MathMax(900,policy.cooldown_sec))
         return false;
     }

   if(delta_closed >= 2 || delta_paper_open_rows >= 2)
      return true;
   if(delta_samples >= MathMax(3,policy.min_bucket_samples / 2))
      return true;
   if(age_sec >= MathMax(900,policy.cooldown_sec) && (delta_samples > 0 || MbIsPaperConversionBlockedReason(report.reason_code)))
      return true;
   return false;
  }

bool MbTuningExperimentSucceeded(
   const MbTuningLocalPolicy &policy,
   const MbRuntimeState &state,
   const MbTuningDeckhandReport &report,
   const MbReasonTriple &review_reason
)
  {
   if(!MbTuningExperimentBaselineJudgeable(policy) || !MbTuningLocalAlphaJudgeable(report))
      return false;
   if(review_reason.domain != "SIGNAL" || review_reason.reason_class == "NEGATIVE_OUTCOME")
      return false;

   int delta_wins = state.learning_win_count - policy.experiment_baseline_wins;
   int delta_losses = state.learning_loss_count - policy.experiment_baseline_losses;
   int delta_closed = delta_wins + delta_losses;
   int delta_paper_open_rows = report.paper_open_rows - policy.experiment_baseline_paper_open_rows;
   double delta_realized_pnl_lifetime = state.realized_pnl_lifetime - policy.experiment_baseline_realized_pnl_lifetime;

   if(delta_closed > 0 && delta_realized_pnl_lifetime >= 0.20)
      return true;
   if(delta_closed >= 2 && delta_wins > delta_losses && delta_realized_pnl_lifetime >= -0.05)
      return true;
   if(delta_paper_open_rows >= 2 && delta_losses <= 0 && delta_realized_pnl_lifetime >= -0.05)
      return true;
   return false;
  }

bool MbTuningExperimentFailed(
   const MbTuningLocalPolicy &policy,
   const MbRuntimeState &state,
   const MbTuningDeckhandReport &report,
   MbReasonTriple &io_review_reason
)
  {
   int delta_wins = state.learning_win_count - policy.experiment_baseline_wins;
   int delta_losses = state.learning_loss_count - policy.experiment_baseline_losses;
   int delta_closed = delta_wins + delta_losses;
   int delta_paper_open_rows = report.paper_open_rows - policy.experiment_baseline_paper_open_rows;
   double delta_realized_pnl_lifetime = state.realized_pnl_lifetime - policy.experiment_baseline_realized_pnl_lifetime;
   int age_sec = (int)(TimeCurrent() - policy.experiment_started_at);

   if(io_review_reason.domain == "RISK" &&
      io_review_reason.reason_class == "CONTRACT" &&
      report.paper_open_rows <= policy.experiment_baseline_paper_open_rows &&
      (report.candidate_risk_block_rows > 0 ||
       report.decision_portfolio_heat_block_rows > 0 ||
       report.decision_rate_guard_block_rows > 0) &&
      age_sec >= MathMax(600,policy.cooldown_sec / 2))
      return true;

   if(!MbTuningExperimentBaselineJudgeable(policy) &&
      policy.experiment_review_count >= 4 &&
      age_sec >= MathMax(900,policy.cooldown_sec))
     {
      MbTuningSetReasonTriple(io_review_reason,"MODE","OBSERVATION","EXPERIMENT_BASELINE_NOT_JUDGEABLE");
      return true;
     }

   if(delta_closed >= 2 && delta_losses >= (delta_wins + 1) && delta_realized_pnl_lifetime <= -0.20)
     {
      MbTuningSetReasonTriple(io_review_reason,"SIGNAL","NEGATIVE_OUTCOME","EXPERIMENT_NET_DEGRADED");
      return true;
     }

   if(delta_paper_open_rows >= 2 && delta_losses >= delta_wins && delta_realized_pnl_lifetime <= -0.30)
     {
      MbTuningSetReasonTriple(io_review_reason,"SIGNAL","NEGATIVE_OUTCOME","EXPERIMENT_CONVERSION_DEGRADED");
      return true;
     }

   if(policy.experiment_review_count >= 4 &&
      delta_paper_open_rows <= 0 &&
      (io_review_reason.domain == "RISK" || io_review_reason.domain == "DATA"))
      return true;

   if((io_review_reason.domain == "EXECUTION" || io_review_reason.domain == "COST") &&
      policy.experiment_review_count >= 5 &&
      age_sec >= MathMax(1200,policy.cooldown_sec))
      return true;

   if((io_review_reason.domain == "INFRA" || io_review_reason.domain == "CENTRAL") &&
      policy.experiment_review_count >= 4 &&
      age_sec >= MathMax(900,policy.cooldown_sec))
      return true;

   if(policy.experiment_review_count >= 6 &&
      delta_closed <= 0 &&
      delta_paper_open_rows <= 0 &&
      age_sec >= MathMax(1200,policy.cooldown_sec))
     {
      if(io_review_reason.domain == "MODE")
         MbTuningSetReasonTriple(io_review_reason,"MODE","OBSERVATION","EXPERIMENT_NO_PROGRESS");
      return true;
     }

   return false;
  }

void MbTuningActivateExperiment(
   MbTuningLocalPolicy &policy,
   const MbRuntimeState &state,
   const MbTuningDeckhandReport &report
)
  {
   policy.experiment_active = true;
   policy.experiment_revision = policy.revision;
   policy.experiment_review_count = 0;
   policy.experiment_started_at = TimeCurrent();
   policy.experiment_baseline_samples = state.learning_sample_count;
   policy.experiment_baseline_wins = state.learning_win_count;
   policy.experiment_baseline_losses = state.learning_loss_count;
   policy.experiment_baseline_paper_open_rows = report.paper_open_rows;
   policy.experiment_baseline_realized_pnl_lifetime = state.realized_pnl_lifetime;
   policy.experiment_baseline_trust_state = report.trust_state.state;
   policy.experiment_baseline_execution_quality_state = report.execution_quality.state;
   policy.experiment_baseline_cost_pressure_state = report.cost_pressure.state;
   policy.experiment_action_code = policy.last_action_code;
   policy.experiment_focus_setup_type = policy.last_focus_setup_type;
   policy.experiment_focus_market_regime = policy.last_focus_market_regime;
   policy.experiment_cause_domain = report.normalized_reason.domain;
   policy.experiment_cause_class = report.normalized_reason.reason_class;
   policy.experiment_cause_code = report.normalized_reason.reason_code;
   if(policy.experiment_cause_code == "")
      policy.experiment_cause_code = report.reason_code;
   policy.experiment_last_review_domain = "MODE";
   policy.experiment_last_review_class = "OBSERVATION";
   policy.experiment_last_review_code = "EXPERIMENT_STARTED";
   policy.experiment_failure_domain = "MODE";
   policy.experiment_failure_class = "NONE";
   policy.experiment_failure_code = "NONE";
   policy.experiment_status = "PENDING";
  }

bool MbTuningHandleActiveExperiment(
   const string symbol,
   const MbRuntimeState &state,
   const string action_log_path,
   MbTuningLocalPolicy &policy,
   const MbTuningDeckhandReport &report,
   string &out_reason
)
  {
   if(!policy.experiment_active)
      return false;

   policy.experiment_review_count++;
   MbReasonTriple review_reason;
   MbTuningResolveExperimentReviewReason(policy,state,report,review_reason);
   policy.experiment_last_review_domain = review_reason.domain;
   policy.experiment_last_review_class = review_reason.reason_class;
   policy.experiment_last_review_code = review_reason.reason_code;
   string detail = MbTuningBuildExperimentDetail(policy,state,report,review_reason);

   if(!MbTuningExperimentHasEvidence(policy,state,report))
     {
      policy.experiment_status = "PENDING";
      policy.last_hypothesis_code = "CZEKAJ_NA_WYNIK";
      policy.last_hypothesis_detail = detail;
      policy.last_counterfactual_code = "GDYBY_ZMIENIAC_ZA_CZESTO";
      policy.last_counterfactual_detail = "agent nie odroznilby skutku poprzedniej zmiany od nowej";
      MbSaveTuningLocalPolicy(symbol,policy);
      MbAppendTuningExperimentEvent(symbol,"REVIEW_PENDING",policy,state,report,detail);
      MbAppendTuningReasoningEvent(symbol,"EXPERIMENT_PENDING",policy,report);
      out_reason = "EXPERIMENT_PENDING";
      return true;
     }

   if(MbTuningExperimentSucceeded(policy,state,report,review_reason))
     {
      policy.experiment_active = false;
      policy.experiment_status = "ACCEPTED";
      policy.experiment_failure_domain = "MODE";
      policy.experiment_failure_class = "NONE";
      policy.experiment_failure_code = "NONE";
      policy.last_hypothesis_code = "UTRZYMAJ_SKUTECZNA_ZMIANE";
      policy.last_hypothesis_detail = detail;
      policy.last_counterfactual_code = "GDYBY_COFNAC_ZA_WCZESNIE";
      policy.last_counterfactual_detail = "agent oddalby zmiane, ktora poprawila material uczenia";
      MbSaveStableTuningLocalPolicy(symbol,policy);
      MbSaveTuningLocalPolicy(symbol,policy);
      MbAppendTuningExperimentEvent(symbol,"ACCEPT",policy,state,report,detail);
      MbAppendTuningReasoningEvent(symbol,"EXPERIMENT_ACCEPT",policy,report);
      out_reason = "EXPERIMENT_ACCEPTED";
      return true;
     }

   MbReasonTriple failure_reason = review_reason;
   bool failed = MbTuningExperimentFailed(policy,state,report,failure_reason);
   bool baseline_judgeable = MbTuningExperimentBaselineJudgeable(policy);
   if(!failed && policy.experiment_review_count >= 4)
     {
      int delta_wins = state.learning_win_count - policy.experiment_baseline_wins;
      int delta_losses = state.learning_loss_count - policy.experiment_baseline_losses;
      double delta_realized_pnl_lifetime = state.realized_pnl_lifetime - policy.experiment_baseline_realized_pnl_lifetime;
      if(delta_wins >= delta_losses && delta_realized_pnl_lifetime >= -0.10)
         failed = false;
      else
        {
         if(MbTuningLocalAlphaJudgeable(report) && baseline_judgeable)
            MbTuningSetReasonTriple(failure_reason,"SIGNAL","NEGATIVE_OUTCOME","EXPERIMENT_REVIEW_BALANCE_NEGATIVE");
         else if(!baseline_judgeable)
            MbTuningSetReasonTriple(failure_reason,"MODE","OBSERVATION","EXPERIMENT_BASELINE_NOT_JUDGEABLE");
         else if(failure_reason.domain == "MODE")
            MbTuningSetReasonTriple(failure_reason,"MODE","OBSERVATION","EXPERIMENT_REVIEW_INCONCLUSIVE");
         failed = true;
        }
     }

   if(!failed)
     {
      policy.experiment_status = "PENDING";
      policy.last_hypothesis_code = "DAJ_ZMIANIE_ODDECH";
      policy.last_hypothesis_detail = detail;
      policy.last_counterfactual_code = "GDYBY_ROZSTRZYGAC_ZA_SZYBKO";
      policy.last_counterfactual_detail = "agent ocenilby zmiane na zbyt malej probce";
      MbSaveTuningLocalPolicy(symbol,policy);
      MbAppendTuningExperimentEvent(symbol,"REVIEW_CONTINUE",policy,state,report,detail);
      MbAppendTuningReasoningEvent(symbol,"EXPERIMENT_CONTINUE",policy,report);
      out_reason = "EXPERIMENT_CONTINUE";
      return true;
     }

   policy.experiment_failure_domain = failure_reason.domain;
   policy.experiment_failure_class = failure_reason.reason_class;
   policy.experiment_failure_code = failure_reason.reason_code;

   MbTuningLocalPolicy restored = policy;
   if(!MbLoadStableTuningLocalPolicy(symbol,restored))
      restored = policy;

   restored.last_eval_at = TimeCurrent();
   restored.last_action_at = TimeCurrent();
   restored.cooldown_until = TimeCurrent() + MathMax(300,policy.cooldown_sec);
   restored.revision = MathMax(restored.revision,policy.revision) + 1;
   restored.last_action_code = "ROLLBACK";
   restored.last_action_detail = detail;
   restored.last_focus_setup_type = policy.experiment_focus_setup_type;
   restored.last_focus_market_regime = policy.experiment_focus_market_regime;
   restored.last_hypothesis_code = "COFNIJ_I_SZUKAJ_NOWEJ_DROGI";
   restored.last_hypothesis_detail = detail;
   restored.last_counterfactual_code = "GDYBY_TKWIC_W_FIASKU";
   restored.last_counterfactual_detail = "agent wzmacnialby sciezke, ktora pogarsza wynik";
   restored.reason_streak = policy.reason_streak;
   restored.blocked_cycles = policy.blocked_cycles;
   restored.trusted_cycles = policy.trusted_cycles;
   restored.last_failed_at = TimeCurrent();
   restored.avoid_repeat_until = TimeCurrent() + MathMax(1800,policy.cooldown_sec * 4);
   restored.last_failed_action_code = policy.experiment_action_code;
   restored.last_failed_focus_setup_type = policy.experiment_focus_setup_type;
   restored.last_failed_focus_market_regime = policy.experiment_focus_market_regime;
   restored.last_failed_cause_domain = policy.experiment_failure_domain;
   restored.last_failed_cause_class = policy.experiment_failure_class;
   restored.last_failed_cause_code = policy.experiment_failure_code;
   restored.experiment_active = false;
   restored.experiment_status = "ROLLED_BACK";
   restored.experiment_revision = policy.experiment_revision;
   restored.experiment_review_count = policy.experiment_review_count;
   restored.experiment_started_at = policy.experiment_started_at;
   restored.experiment_baseline_samples = policy.experiment_baseline_samples;
   restored.experiment_baseline_wins = policy.experiment_baseline_wins;
   restored.experiment_baseline_losses = policy.experiment_baseline_losses;
   restored.experiment_baseline_paper_open_rows = policy.experiment_baseline_paper_open_rows;
   restored.experiment_baseline_realized_pnl_lifetime = policy.experiment_baseline_realized_pnl_lifetime;
   restored.experiment_baseline_trust_state = policy.experiment_baseline_trust_state;
   restored.experiment_baseline_execution_quality_state = policy.experiment_baseline_execution_quality_state;
   restored.experiment_baseline_cost_pressure_state = policy.experiment_baseline_cost_pressure_state;
   restored.experiment_action_code = policy.experiment_action_code;
   restored.experiment_focus_setup_type = policy.experiment_focus_setup_type;
   restored.experiment_focus_market_regime = policy.experiment_focus_market_regime;
   restored.experiment_cause_domain = policy.experiment_cause_domain;
   restored.experiment_cause_class = policy.experiment_cause_class;
   restored.experiment_cause_code = policy.experiment_cause_code;
   restored.experiment_last_review_domain = policy.experiment_last_review_domain;
   restored.experiment_last_review_class = policy.experiment_last_review_class;
   restored.experiment_last_review_code = policy.experiment_last_review_code;
   restored.experiment_failure_domain = policy.experiment_failure_domain;
   restored.experiment_failure_class = policy.experiment_failure_class;
   restored.experiment_failure_code = policy.experiment_failure_code;

   policy = restored;
   MbSaveTuningLocalPolicy(symbol,policy);
   MbAppendTuningActionEvent(action_log_path,symbol,policy,report);
   MbAppendTuningExperimentEvent(symbol,"ROLLBACK",policy,state,report,detail);
   MbAppendTuningReasoningEvent(symbol,"EXPERIMENT_ROLLBACK",policy,report);
   out_reason = "EXPERIMENT_ROLLBACK";
   return true;
  }

bool MbRunLocalTuningAgent(
   const string symbol,
   const MbRuntimeState &state,
   const string action_log_path,
   MbTuningLocalPolicy &policy,
   const MbTuningDeckhandReport &report,
   string &out_reason
)
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION) != 0)
     {
      out_reason = "OPTIMIZATION_RUNTIME";
      return false;
     }

   out_reason = "NO_CHANGE";
   policy.last_eval_at = TimeCurrent();
   policy.trusted_data = report.trusted;
   policy.trust_reason = report.reason_code;
   policy.trust_reason_domain = report.normalized_reason.domain;
   policy.trust_reason_class = report.normalized_reason.reason_class;
   policy.last_trust_state = report.trust_state.state;
   policy.last_execution_quality_state = report.execution_quality.state;
   policy.last_cost_pressure_state = report.cost_pressure.state;

   MbTuningAdaptationContract contract;
   MbResolveTuningAdaptationContract(symbol,contract);
   MbTuningRefreshAdaptationWindow(policy,contract);

   if(MbTuningHandleActiveExperiment(symbol,state,action_log_path,policy,report,out_reason))
      return false;

   if(!policy.enabled)
     {
      out_reason = "TUNING_DISABLED";
      return false;
     }

   if(!report.trusted)
     {
      out_reason = report.reason_code;
      return false;
     }

   if(contract.requires_execution_not_bad && report.execution_quality.state == "BAD")
     {
      policy.last_hypothesis_code = "WSTRZYMAJ_STROJENIE_EGZEKUCJA";
      policy.last_hypothesis_detail = StringFormat(
         "execution_quality=%s;reason=%s",
         report.execution_quality.state,
         report.execution_quality.reason_code
      );
      policy.last_counterfactual_code = "GDYBY_STROIC_MIMO_ZLEJ_EGZEKUCJI";
      policy.last_counterfactual_detail = "agent stroilby sygnal na podstawie skazonej lekcji wykonawczej";
      MbSaveTuningLocalPolicy(symbol,policy);
      MbAppendTuningReasoningEvent(symbol,"LOCAL_AGENT",policy,report);
      out_reason = report.execution_quality.reason_code;
      return false;
     }

   if(contract.forbid_when_cost_non_representative && report.cost_pressure.state == "NON_REPRESENTATIVE")
     {
      policy.last_hypothesis_code = "WSTRZYMAJ_STROJENIE_KOSZT";
      policy.last_hypothesis_detail = StringFormat(
         "cost_pressure=%s;reason=%s",
         report.cost_pressure.state,
         report.cost_pressure.reason_code
      );
      policy.last_counterfactual_code = "GDYBY_STROIC_NIEREPREZENTATYWNY_KOSZT";
      policy.last_counterfactual_detail = "agent uznalby koszt strukturalny za problem lokalnej alfy";
      MbSaveTuningLocalPolicy(symbol,policy);
      MbAppendTuningReasoningEvent(symbol,"LOCAL_AGENT",policy,report);
      out_reason = report.cost_pressure.reason_code;
      return false;
     }

   if(state.learning_win_count + state.learning_loss_count < contract.min_closed_lessons)
     {
      policy.last_hypothesis_code = "CZEKAJ_NA_ZAMKNIETE_LEKCJE";
      policy.last_hypothesis_detail = StringFormat(
         "closed_lessons=%d;required=%d",
         state.learning_win_count + state.learning_loss_count,
         contract.min_closed_lessons
      );
      policy.last_counterfactual_code = "GDYBY_ZMIENIAC_ZA_WCZESNIE";
      policy.last_counterfactual_detail = "agent ruszalby parametry bez wystarczajacej liczby domknietych lekcji";
      MbSaveTuningLocalPolicy(symbol,policy);
      MbAppendTuningReasoningEvent(symbol,"LOCAL_AGENT",policy,report);
      out_reason = "MIN_CLOSED_LESSONS";
      return false;
     }

   if(policy.trusted_cycles < contract.min_clean_reviews)
     {
      policy.last_hypothesis_code = "CZEKAJ_NA_CZYSTE_PRZEGLADY";
      policy.last_hypothesis_detail = StringFormat(
         "trusted_cycles=%d;required=%d",
         policy.trusted_cycles,
         contract.min_clean_reviews
      );
      policy.last_counterfactual_code = "GDYBY_RUSZAC_ZA_SZYBKO";
      policy.last_counterfactual_detail = "agent zmienialby polityke zanim potwierdzi sie czystosc materialu";
      MbSaveTuningLocalPolicy(symbol,policy);
      MbAppendTuningReasoningEvent(symbol,"LOCAL_AGENT",policy,report);
      out_reason = "MIN_CLEAN_REVIEWS";
      return false;
     }

   if(state.learning_sample_count < policy.min_bucket_samples)
     {
      out_reason = "LOW_SAMPLE";
      return false;
     }

   if(policy.cooldown_until > 0 && TimeCurrent() < policy.cooldown_until)
     {
      out_reason = "COOLDOWN";
      return false;
     }

   if(policy.adaptation_changes_in_window >= contract.max_changes_per_window)
     {
      policy.last_hypothesis_code = "LIMIT_ZMIAN_W_OKNIE";
      policy.last_hypothesis_detail = StringFormat(
         "changes_in_window=%d;limit=%d;window_sec=%d",
         policy.adaptation_changes_in_window,
         contract.max_changes_per_window,
         contract.change_window_sec
      );
      policy.last_counterfactual_code = "GDYBY_ZMIENIAC_ZA_CZESTO";
      policy.last_counterfactual_detail = "agent zgubilby mozliwosc przypisania skutku do pojedynczej zmiany";
      MbSaveTuningLocalPolicy(symbol,policy);
      MbAppendTuningReasoningEvent(symbol,"LOCAL_AGENT",policy,report);
      out_reason = "ADAPTATION_WINDOW_LIMIT";
      return false;
     }

   MbTuningBucketStats buckets[];
   if(MbReadTuningBucketSummary(symbol,buckets) <= 0)
     {
      policy.last_focus_setup_type = "NONE";
      policy.last_focus_market_regime = "UNKNOWN";
      policy.last_hypothesis_code = "BUCKETS_MISSING";
      policy.last_hypothesis_detail = "brak bucketow do strojenia";
      policy.last_counterfactual_code = "GDYBY_STROIC_BEZ_BUCKETOW";
      policy.last_counterfactual_detail = "agent stroilby w ciemno bez podsumowania lekcji";
      MbSaveTuningLocalPolicy(symbol,policy);
      MbAppendTuningReasoningEvent(symbol,"LOCAL_AGENT",policy,report);
      out_reason = "BUCKETS_MISSING";
      return false;
     }

   MbTuningLocalPolicy next = policy;
   next.breakout_global_tax = 0.0;
   next.breakout_chaos_tax = 0.0;
   next.breakout_range_tax = 0.0;
   next.breakout_conflict_tax = 0.0;
   next.trend_breakout_tax = 0.0;
   next.trend_chaos_tax = 0.0;
   next.trend_caution_tax = 0.0;
   next.trend_no_aux_tax = 0.0;
   next.range_chaos_tax = 0.0;
   next.range_trend_tax = 0.0;
   next.range_confidence_floor = 0.0;
   next.index_opening_impulse_tax = 0.0;
   next.index_noon_transition_tax = 0.0;
   next.rejection_range_boost = 0.0;
   next.confidence_cap = 1.0;
   next.risk_cap = 1.0;
   next.require_aux_support_for_trend = false;
   next.require_support_for_rejection = false;
   next.require_non_poor_renko_for_breakout = false;
    next.require_non_poor_candle_for_breakout = false;
   next.require_non_poor_candle_for_trend = false;
   next.require_non_poor_candle_for_range = false;
   next.require_non_poor_renko_for_range = false;

   int breakout_samples = 0;
   double breakout_weighted_sum = 0.0;
   int trend_hostile_samples = 0;
   double trend_hostile_weighted_sum = 0.0;
   int range_samples = 0;
   double range_weighted_sum = 0.0;
   string family = "";
   MbTuningResolveFamily(symbol,family);
   bool is_fx_asia = (family == "FX_ASIA");
   bool is_fx_cross = (family == "FX_CROSS");
   bool is_index_family = MbTuningIsIndexFamily(family);
   string focus_setup_type = "NONE";
   string focus_market_regime = "UNKNOWN";
   string focus_detail = "no_focus";
   MbTuningResolveDominantFocus(buckets,policy.min_bucket_samples,focus_setup_type,focus_market_regime,focus_detail);
   for(int i = 0; i < ArraySize(buckets); ++i)
     {
      MbTuningBucketStats row = buckets[i];
      bool is_breakout = (row.setup_type == "SETUP_BREAKOUT");
      bool is_trend_like = (row.setup_type == "SETUP_TREND" || row.setup_type == "SETUP_PULLBACK");
      bool is_mean_reversion = (row.setup_type == "SETUP_REJECTION" || row.setup_type == "SETUP_RANGE");

      if(is_breakout)
        {
         breakout_samples += row.samples;
         breakout_weighted_sum += (row.avg_pnl * row.samples);
        }
      if(is_trend_like && (row.market_regime == "BREAKOUT" || row.market_regime == "CHAOS"))
        {
         trend_hostile_samples += row.samples;
         trend_hostile_weighted_sum += (row.avg_pnl * row.samples);
        }
      if(is_mean_reversion)
        {
         range_samples += row.samples;
         range_weighted_sum += (row.avg_pnl * row.samples);
        }

      if(is_breakout && row.market_regime == "CHAOS")
         next.breakout_chaos_tax = MbTuningPenaltyFromAvg(row.avg_pnl,row.samples,policy.min_bucket_samples,0.24,0.02,0.12);
      else if(is_breakout && row.market_regime == "RANGE")
         next.breakout_range_tax = MbTuningPenaltyFromAvg(row.avg_pnl,row.samples,policy.min_bucket_samples,0.22,0.02,0.10);
      else if(is_breakout && row.market_regime == "BREAKOUT" && row.samples >= MathMax(4,policy.min_bucket_samples / 2) && row.avg_pnl <= -0.60)
         next.require_non_poor_renko_for_breakout = true;
      else if(is_breakout && row.market_regime == "BREAKOUT" && row.samples >= MathMax(4,policy.min_bucket_samples / 2) && row.avg_pnl <= -0.50)
         next.require_non_poor_candle_for_breakout = true;
      else if(is_breakout && row.market_regime == "TREND")
         next.breakout_conflict_tax = MbTuningPenaltyFromAvg(row.avg_pnl,row.samples,policy.min_bucket_samples,0.18,0.01,0.08);
      else if(is_trend_like && row.market_regime == "BREAKOUT")
         next.trend_breakout_tax = MathMax(next.trend_breakout_tax,MbTuningPenaltyFromAvg(row.avg_pnl,row.samples,policy.min_bucket_samples,0.24,0.02,0.12));
      else if(is_trend_like && row.market_regime == "CHAOS")
         next.trend_chaos_tax = MathMax(next.trend_chaos_tax,MbTuningPenaltyFromAvg(row.avg_pnl,row.samples,policy.min_bucket_samples,0.22,0.02,0.10));
      else if(is_mean_reversion && row.market_regime == "CHAOS" && row.samples >= MathMax(4,policy.min_bucket_samples / 2) && row.avg_pnl <= -0.80)
         next.require_support_for_rejection = true;
      else if(is_mean_reversion && row.market_regime == "CHAOS")
        {
         next.range_chaos_tax = MathMax(next.range_chaos_tax,MbTuningPenaltyFromAvg(row.avg_pnl,row.samples,policy.min_bucket_samples,0.24,0.02,0.12));
         if(row.samples >= MathMax(4,policy.min_bucket_samples / 2) && row.avg_pnl <= -0.75)
            next.require_non_poor_candle_for_range = true;
         if(row.samples >= MathMax(4,policy.min_bucket_samples / 2) && row.avg_pnl <= -0.65)
            next.require_non_poor_renko_for_range = true;
        }
      else if(is_mean_reversion && (row.market_regime == "TREND" || row.market_regime == "BREAKOUT"))
         next.range_trend_tax = MathMax(next.range_trend_tax,MbTuningPenaltyFromAvg(row.avg_pnl,row.samples,policy.min_bucket_samples,0.22,0.02,0.12));
      else if(is_mean_reversion && row.market_regime == "RANGE")
         next.rejection_range_boost = MathMax(next.rejection_range_boost,MbTuningBoostFromAvg(row.avg_pnl,row.samples,3,0.08,0.02,0.08));
     }

   if(breakout_samples >= policy.min_bucket_samples)
     {
      double breakout_avg = breakout_weighted_sum / (double)breakout_samples;
      next.breakout_global_tax = MbTuningPenaltyFromAvg(breakout_avg,breakout_samples,policy.min_bucket_samples,0.18,0.01,0.08);
     }
   if(trend_hostile_samples >= policy.min_bucket_samples)
     {
      double trend_hostile_avg = trend_hostile_weighted_sum / (double)trend_hostile_samples;
      if(trend_hostile_avg <= -0.40)
         next.require_non_poor_candle_for_trend = true;
     }
   if(range_samples >= policy.min_bucket_samples)
     {
      double range_avg = range_weighted_sum / (double)range_samples;
      if(is_fx_asia || is_fx_cross)
        {
         if(range_avg <= -0.30)
            next.range_confidence_floor = 0.74;
         else if(range_avg <= -0.20)
            next.range_confidence_floor = 0.66;
         else if(range_avg <= -0.12)
            next.range_confidence_floor = 0.58;
        }
      if(is_index_family)
        {
         next.index_opening_impulse_tax = MbTuningPenaltyFromAvg(breakout_samples > 0 ? breakout_weighted_sum / (double)MathMax(1,breakout_samples) : range_avg,MathMax(range_samples,breakout_samples),policy.min_bucket_samples,0.20,0.03,0.10);
         next.index_noon_transition_tax = MbTuningPenaltyFromAvg(range_avg,range_samples,policy.min_bucket_samples,0.18,0.02,0.08);
        }
     }

   if(is_fx_asia && range_samples >= MathMax(4,policy.min_bucket_samples / 2))
      next.range_trend_tax = MathMax(next.range_trend_tax,0.04);
   if(is_fx_cross && range_samples >= MathMax(4,policy.min_bucket_samples / 2))
      next.range_chaos_tax = MathMax(next.range_chaos_tax,0.04);

   double loss_ratio = (state.learning_sample_count > 0 ? (double)state.learning_loss_count / (double)state.learning_sample_count : 0.0);
   if(loss_ratio >= 0.78)
      next.confidence_cap = 0.72;
   else if(loss_ratio >= 0.70)
      next.confidence_cap = 0.80;
   else if(loss_ratio >= 0.62)
      next.confidence_cap = 0.90;

   if(loss_ratio >= 0.78)
      next.risk_cap = 0.82;
   else if(loss_ratio >= 0.70)
      next.risk_cap = 0.90;

   if(state.loss_streak >= 8)
     {
      next.risk_cap = MathMin(next.risk_cap,0.78);
      next.confidence_cap = MathMin(next.confidence_cap,0.75);
     }
   else if(state.loss_streak >= 4)
     {
      next.risk_cap = MathMin(next.risk_cap,0.88);
      next.confidence_cap = MathMin(next.confidence_cap,0.85);
     }

   next.trend_caution_tax = MbTuningClamp((1.0 - next.risk_cap) * 0.50,0.0,0.08);
   next.trend_no_aux_tax = MbTuningClamp((next.trend_breakout_tax + next.trend_chaos_tax) * 0.50,0.0,0.08);
   next.require_aux_support_for_trend = (
      next.trend_breakout_tax >= 0.05 ||
      next.trend_chaos_tax >= 0.05 ||
      state.loss_streak >= 6
   );
   next.last_focus_setup_type = focus_setup_type;
   next.last_focus_market_regime = focus_market_regime;
   MbTuningResolveThoughts(
      next,
      report,
      focus_setup_type,
      focus_market_regime,
      focus_detail,
      next.last_hypothesis_code,
      next.last_hypothesis_detail,
      next.last_counterfactual_code,
      next.last_counterfactual_detail
   );
   MbApplyTuningGuardToLocalPolicy(symbol,next);
   MbTuningApplyBoundedStep(policy,next,contract);

   if(!MbTuningPolicyChanged(policy,next))
     {
      policy.last_focus_setup_type = next.last_focus_setup_type;
      policy.last_focus_market_regime = next.last_focus_market_regime;
      policy.last_hypothesis_code = next.last_hypothesis_code;
      policy.last_hypothesis_detail = next.last_hypothesis_detail;
      policy.last_counterfactual_code = next.last_counterfactual_code;
      policy.last_counterfactual_detail = next.last_counterfactual_detail;
      MbSaveTuningLocalPolicy(symbol,policy);
      MbAppendTuningReasoningEvent(symbol,"LOCAL_AGENT",policy,report);
      out_reason = "NO_CHANGE";
      return false;
     }

   next.revision = policy.revision + 1;
   next.last_action_at = TimeCurrent();
   next.cooldown_until = TimeCurrent() + MathMax(300,MathMax(policy.cooldown_sec,contract.cooldown_after_change_sec));
   MbTuningSummarizeAction(next,next.last_action_code,next.last_action_detail);
   next.action_streak = ((policy.last_action_code == next.last_action_code) ? (policy.action_streak + 1) : 1);
   string repeat_cause_domain = report.normalized_reason.domain;
   string repeat_cause_class = report.normalized_reason.reason_class;
   string repeat_cause_code = report.normalized_reason.reason_code;
   if(repeat_cause_code == "")
      repeat_cause_code = report.reason_code;

   if(MbTuningShouldAvoidRepeat(policy,next.last_action_code,next.last_focus_setup_type,next.last_focus_market_regime,repeat_cause_domain,repeat_cause_class,repeat_cause_code))
     {
      MbTuningLocalPolicy alternative = next;
      bool has_alternative = MbBuildAlternativeExperiment(symbol,policy,alternative);
      if(has_alternative)
        {
         next = alternative;
         next.revision = policy.revision + 1;
         next.last_action_at = TimeCurrent();
         next.cooldown_until = TimeCurrent() + MathMax(300,MathMax(policy.cooldown_sec,contract.cooldown_after_change_sec));
         MbTuningSummarizeAction(next,next.last_action_code,next.last_action_detail);
         next.action_streak = ((policy.last_action_code == next.last_action_code) ? (policy.action_streak + 1) : 1);
        }

      if(!has_alternative || MbTuningShouldAvoidRepeat(policy,next.last_action_code,next.last_focus_setup_type,next.last_focus_market_regime,repeat_cause_domain,repeat_cause_class,repeat_cause_code))
        {
         policy.last_focus_setup_type = next.last_focus_setup_type;
         policy.last_focus_market_regime = next.last_focus_market_regime;
         policy.last_hypothesis_code = "SZUKAJ_NOWEJ_DROGI";
         policy.last_hypothesis_detail = StringFormat(
            "blokada powrotu do fiaska: %s/%s/%s/%s/%s/%s",
            next.last_action_code,
            next.last_focus_setup_type,
            next.last_focus_market_regime,
            repeat_cause_domain,
            repeat_cause_class,
            repeat_cause_code
         );
         policy.last_counterfactual_code = "GDYBY_WROCIC_DO_FIASKA";
         policy.last_counterfactual_detail = "agent powielilby swieza, nieudana regulacje";
         MbSaveTuningLocalPolicy(symbol,policy);
         MbAppendTuningReasoningEvent(symbol,"AVOID_REPEAT",policy,report);
         out_reason = "AVOID_REPEAT_FAILED_PATH";
         return false;
        }
     }

   if(MbCanonicalSymbol(symbol) == "EURUSD")
     {
      string doctrine_code = "";
      string doctrine_detail = "";
      if(!MbCanStartEURUSDForexExperiment(TimeCurrent(),state,next.last_focus_setup_type,next.last_focus_market_regime,doctrine_code,doctrine_detail))
        {
         policy.last_focus_setup_type = next.last_focus_setup_type;
         policy.last_focus_market_regime = next.last_focus_market_regime;
         policy.last_hypothesis_code = doctrine_code;
         policy.last_hypothesis_detail = doctrine_detail;
         policy.last_counterfactual_code = "GDYBY_STROIC_POZA_RDZENIEM_FX";
         policy.last_counterfactual_detail = "agent uczylby sie nowej polityki na cienkiej plynnosci albo fazie przejsciowej";
         MbSaveTuningLocalPolicy(symbol,policy);
         MbAppendTuningReasoningEvent(symbol,"FOREX_DOCTRINE_WAIT",policy,report);
         out_reason = "FOREX_DOCTRINE_WAIT";
         return false;
        }
     }

   MbSaveStableTuningLocalPolicy(symbol,policy);
   MbTuningActivateExperiment(next,state,report);
   next.adaptation_window_started_at = policy.adaptation_window_started_at;
   next.adaptation_changes_in_window = policy.adaptation_changes_in_window + 1;

   policy = next;
   MbSaveTuningLocalPolicy(symbol,policy);
   MbAppendTuningActionEvent(action_log_path,symbol,policy,report);
   MbAppendTuningExperimentEvent(symbol,"START",policy,state,report,policy.last_action_detail);
   MbAppendTuningReasoningEvent(symbol,"LOCAL_AGENT",policy,report);
   out_reason = policy.last_action_code;
   return true;
  }

#endif
