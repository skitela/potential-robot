#ifndef STRATEGY_DE30_INCLUDED
#define STRATEGY_DE30_INCLUDED

#include <Trade/Trade.mqh>
#include "..\\Core\\MbRuntimeTypes.mqh"
#include "..\\Core\\MbContextPolicy.mqh"
#include "..\\Core\\MbCandleAdvisory.mqh"
#include "..\\Core\\MbRenkoAdvisory.mqh"
#include "..\\Core\\MbAuxSignalFusion.mqh"
#include "..\\Core\\MbTuningTypes.mqh"
#include ".\\Common\\MbFamilyStrategyCommon.mqh"
#include ".\\Common\\MbStrategyCommon.mqh"

int g_DE30_ema_fast_handle = INVALID_HANDLE;
int g_DE30_ema_slow_handle = INVALID_HANDLE;
int g_DE30_atr_handle = INVALID_HANDLE;
int g_DE30_rsi_handle = INVALID_HANDLE;
datetime g_DE30_last_bar_time = 0;
double g_DE30_last_atr_points = 0.0;
datetime g_DE30_last_position_modify = 0;
MbTuningLocalPolicy g_DE30_tuning_policy;

struct DE30LocalRiskPlan
  {
   bool allowed;
   double lots;
   double sl_points;
   double tp_points;
   string reason_code;
  };

MbFamilyStrategyParams BuildDE30Params()
  {
   MbFamilyStrategyParams out;
   out.family_kind = MB_FAMILY_KIND_INDEX_EU;
   out.ema_fast_period = 12;
   out.ema_slow_period = 34;
   out.atr_period = 14;
   out.rsi_period = 14;
   out.base_risk_pct = 0.17;
   out.execution_floor = 0.74;
   out.execution_decay = 0.46;
   out.min_risk_pct = 0.07;
   out.max_risk_pct = 0.22;
   out.sl_atr_multiplier = 1.75;
   out.sl_min_points = 95.0;
   out.tp_atr_multiplier = 2.25;
   out.tp_min_points = 145.0;
   out.trail_atr_multiplier = 1.08;
   out.pressure_step_scale = 7.0;
   out.ready_trigger_abs = 0.82;
   out.caution_trigger_abs = 0.98;
   return out;
  }

bool StrategyDE30Init(const MbSymbolProfile &profile)
  {
   MbFamilyStrategyParams params = BuildDE30Params();
   bool ok = MbFamilyStrategyInit(profile,params,g_DE30_ema_fast_handle,g_DE30_ema_slow_handle,g_DE30_atr_handle,g_DE30_rsi_handle,g_DE30_last_bar_time,g_DE30_last_atr_points,g_DE30_last_position_modify);
   MbTuningLocalPolicyReset(g_DE30_tuning_policy);
   return ok;
  }

void StrategyDE30Deinit()
  {
   MbFamilyStrategyDeinit(g_DE30_ema_fast_handle,g_DE30_ema_slow_handle,g_DE30_atr_handle,g_DE30_rsi_handle,g_DE30_last_bar_time,g_DE30_last_atr_points,g_DE30_last_position_modify);
  }

void StrategyDE30SetTuningPolicy(const MbTuningLocalPolicy &policy)
  {
   g_DE30_tuning_policy = policy;
  }

void ApplyDE30TuningPenalty(
   double &io_confidence_score,
   double &io_risk_multiplier,
   double &io_trigger_abs,
   const double tax
)
  {
   if(tax <= 0.0)
      return;
   io_confidence_score = MathMax(0.0,io_confidence_score - tax);
   io_risk_multiplier = MathMax(0.55,io_risk_multiplier * MathMax(0.70,1.0 - tax));
   io_trigger_abs += (0.60 * tax);
  }

void ApplyDE30TuningBoost(
   double &io_confidence_score,
   double &io_risk_multiplier,
   double &io_trigger_abs,
   const double boost
)
  {
   if(boost <= 0.0)
      return;
   io_confidence_score = MathMin(1.0,io_confidence_score + boost);
   io_risk_multiplier = MathMin(1.05,io_risk_multiplier * (1.0 + (0.40 * boost)));
   io_trigger_abs = MathMax(0.18,io_trigger_abs - (0.50 * boost));
  }

int ResolveDE30MinutesFromWindowStart(const MbSymbolProfile &profile)
  {
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(),tm);
   return (((tm.hour - profile.trade_window_start_hour + 24) % 24) * 60) + tm.min;
  }

int ResolveDE30MinutesToWindowEnd(const MbSymbolProfile &profile)
  {
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(),tm);
   int now_minutes = (tm.hour * 60) + tm.min;
   int end_minutes = (profile.trade_window_end_hour * 60) + 59;
   if(end_minutes >= now_minutes)
      return end_minutes - now_minutes;
   return ((24 * 60) - now_minutes) + end_minutes;
  }

void BuildDE30RiskPlan(
   const MbRuntimeState &state,
   const MbMarketSnapshot &snapshot,
   DE30LocalRiskPlan &out
)
  {
   MbFamilyStrategyParams params = BuildDE30Params();
   MbFamilyStrategyBuildRiskPlan(state,snapshot,g_DE30_last_atr_points,params,out.allowed,out.lots,out.sl_points,out.tp_points,out.reason_code);
  }

void ManageDE30OpenPosition(
   CTrade &trade,
   MbRuntimeState &state,
   const MbSymbolProfile &profile,
   const MbMarketSnapshot &snapshot
)
  {
   MbFamilyStrategyParams params = BuildDE30Params();
   MbFamilyStrategyManagePosition(trade,state,profile,snapshot,g_DE30_last_atr_points,params,g_DE30_last_position_modify);
  }

void EvaluateDE30Strategy(
   const MbRuntimeState &state,
   const MbSymbolProfile &profile,
   const MbMarketSnapshot &snapshot,
   MbSignalDecision &out
)
  {
   MbSignalDecisionReset(out);

   if(state.mode == MB_MODE_BLOCKED || state.mode == MB_MODE_CLOSE_ONLY)
     {
      out.reason_code = "RUNTIME_BLOCK";
      return;
     }

   if(
      g_DE30_ema_fast_handle == INVALID_HANDLE ||
      g_DE30_ema_slow_handle == INVALID_HANDLE ||
      g_DE30_atr_handle == INVALID_HANDLE ||
      g_DE30_rsi_handle == INVALID_HANDLE
   )
     {
      out.reason_code = "INDICATORS_NOT_READY";
      return;
     }

   double ema_fast = 0.0;
   double ema_slow = 0.0;
   double atr_raw = 0.0;
   double rsi = 50.0;
   if(!MbStrategyCopyLastValue(g_DE30_ema_fast_handle,ema_fast))
     {
      out.reason_code = "EMA_FAST_COPY_FAIL";
      return;
     }
   if(!MbStrategyCopyLastValue(g_DE30_ema_slow_handle,ema_slow))
     {
      out.reason_code = "EMA_SLOW_COPY_FAIL";
      return;
     }
   if(!MbStrategyCopyLastValue(g_DE30_atr_handle,atr_raw))
     {
      out.reason_code = "ATR_COPY_FAIL";
      return;
     }
   if(!MbStrategyCopyLastValue(g_DE30_rsi_handle,rsi))
     {
      out.reason_code = "RSI_COPY_FAIL";
      return;
     }

   datetime current_bar_time = 0;
   if(!MbStrategyResolveNewBar(profile.symbol,profile.trade_tf,g_DE30_last_bar_time,current_bar_time,out.reason_code,MbShouldBypassGlobalTeacherLearningNewBar(profile.symbol,state.paper_mode_active)))
      return;

   if(atr_raw <= 0.0)
     {
      out.reason_code = "ATR_INVALID";
      return;
     }

   double ema_delta = (ema_fast - ema_slow) / atr_raw;
   double rsi_shift = (rsi - 50.0) / 25.0;
   double spread_bias = (state.spread_anomaly_streak == 0 ? 1.0 : -1.0);

   double score_trend = (0.60 * ema_delta) + (0.16 * rsi_shift) + (0.24 * spread_bias);
   double score_pullback = (0.36 * rsi_shift) - (0.12 * ema_delta);
   double score_breakout = (0.74 * ema_delta) + (0.26 * spread_bias);
   double score_range = (-0.20 * ema_delta) - (0.14 * rsi_shift) + (0.34 * spread_bias);

   double score = score_trend;
   string setup_reason = "SETUP_TREND";
   double best_abs = MathAbs(score_trend);
   MbStrategySelectBetterScore(score_pullback,"SETUP_PULLBACK",best_abs,score,setup_reason);
   MbStrategySelectBetterScore(score_breakout,"SETUP_BREAKOUT",best_abs,score,setup_reason);
   MbStrategySelectBetterScore(score_range,"SETUP_RANGE",best_abs,score,setup_reason);

   MbFamilyStrategyParams params = BuildDE30Params();
   double trigger_abs = (state.caution_mode ? params.caution_trigger_abs : params.ready_trigger_abs);
   g_DE30_last_atr_points = atr_raw / _Point;
   double trend_strength = ema_delta;

   MbSignalContextAssessment assessment;
   MbAssessSignalContext(profile,state,snapshot,score,setup_reason,trend_strength,rsi,assessment);

   MbCandleAdvisory candle;
   MbEvaluateCandleAdvisory(
      profile.symbol,
      profile.trade_tf,
      (score >= 0.0 ? MB_SIGNAL_BUY : MB_SIGNAL_SELL),
      0.35,
      1.6,
      candle
   );

   MbRenkoAdvisory renko;
   MbEvaluateRenkoAdvisory(
      profile.symbol,
      _Point,
      g_DE30_last_atr_points,
      (score >= 0.0 ? MB_SIGNAL_BUY : MB_SIGNAL_SELL),
      renko
   );

   MbAuxSignalFusion fusion;
   MbAuxSignalFusionReset(assessment.confidence_score,assessment.risk_multiplier,fusion);
   MbApplyAuxSignalFusion((score >= 0.0 ? MB_SIGNAL_BUY : MB_SIGNAL_SELL),candle,renko,fusion);
   string expected_bias = (score >= 0.0 ? "UP" : "DOWN");
   bool candle_supports = (candle.bias == expected_bias);
   bool renko_supports = (renko.bias == expected_bias);
   bool aux_supportive = candle_supports || renko_supports;

   // DE30 should stay selective around the European cash rhythm and the noon handover.
   if(setup_reason == "SETUP_BREAKOUT" && (assessment.market_regime == "CHAOS" || assessment.market_regime == "RANGE"))
     {
      fusion.confidence_score = MathMax(0.0,fusion.confidence_score - 0.07);
      fusion.risk_multiplier = MathMax(0.55,fusion.risk_multiplier * 0.90);
      trigger_abs += 0.06;
     }
   if(setup_reason == "SETUP_BREAKOUT" && assessment.market_regime == "TREND")
     {
      fusion.confidence_score = MathMax(0.0,fusion.confidence_score - 0.05);
      fusion.risk_multiplier = MathMax(0.55,fusion.risk_multiplier * 0.92);
      trigger_abs += 0.04;
     }
   if(setup_reason == "SETUP_BREAKOUT" && assessment.spread_regime == "BAD")
     {
      fusion.confidence_score = MathMax(0.0,fusion.confidence_score - 0.06);
      fusion.risk_multiplier = MathMax(0.55,fusion.risk_multiplier * 0.88);
      trigger_abs += 0.05;
     }
   if(setup_reason == "SETUP_BREAKOUT" && fusion.reason_code == "AUX_CONFLICT_CAUTION")
     {
      fusion.confidence_score = MathMax(0.0,fusion.confidence_score - 0.03);
      fusion.risk_multiplier = MathMax(0.55,fusion.risk_multiplier * 0.95);
      trigger_abs += 0.03;
     }
   if(setup_reason == "SETUP_BREAKOUT" && (renko.quality_grade == "POOR" || renko.quality_grade == "UNKNOWN"))
     {
      fusion.confidence_score = MathMax(0.0,fusion.confidence_score - 0.04);
      fusion.risk_multiplier = MathMax(0.55,fusion.risk_multiplier * 0.93);
      trigger_abs += 0.03;
     }
   if(setup_reason == "SETUP_BREAKOUT" && candle.bias != "NONE" && renko.bias != "NONE" && candle.bias != renko.bias)
     {
      fusion.confidence_score = MathMax(0.0,fusion.confidence_score - 0.04);
      fusion.risk_multiplier = MathMax(0.55,fusion.risk_multiplier * 0.92);
      trigger_abs += 0.04;
     }
   if(setup_reason == "SETUP_BREAKOUT" && assessment.market_regime == "CHAOS" && candle.bias != "NONE" && renko.bias != "NONE" && candle.bias != renko.bias)
     {
      fusion.confidence_score = MathMax(0.0,fusion.confidence_score - 0.05);
      fusion.risk_multiplier = MathMax(0.55,fusion.risk_multiplier * 0.90);
      trigger_abs += 0.05;
     }
   if(setup_reason == "SETUP_BREAKOUT" && (state.loss_streak >= 10 || state.learning_bias <= -0.10))
     {
      fusion.confidence_score = MathMin(fusion.confidence_score,0.44);
      fusion.risk_multiplier = MathMax(0.55,MathMin(fusion.risk_multiplier,0.70));
      trigger_abs += 0.05;
     }
   if(setup_reason == "SETUP_PULLBACK" && assessment.market_regime == "TREND" && assessment.spread_regime != "BAD")
     {
      if(candle.bias == renko.bias && candle.bias != "NONE" && candle.quality_grade != "POOR" && renko.quality_grade != "POOR")
        {
         fusion.confidence_score = MathMin(1.0,fusion.confidence_score + 0.05);
         fusion.risk_multiplier = MathMin(1.03,fusion.risk_multiplier * 1.03);
         trigger_abs = MathMax(0.20,trigger_abs - 0.03);
        }
     }
   if(setup_reason == "SETUP_RANGE" && assessment.market_regime == "RANGE")
     {
      fusion.confidence_score = MathMin(1.0,fusion.confidence_score + 0.05);
      fusion.risk_multiplier = MathMin(1.05,fusion.risk_multiplier * 1.04);
      trigger_abs = MathMax(0.20,trigger_abs - 0.04);
     }
   if(setup_reason == "SETUP_RANGE" && assessment.market_regime == "CHAOS")
     {
      fusion.confidence_score = MathMax(0.0,fusion.confidence_score - 0.06);
      fusion.risk_multiplier = MathMax(0.55,fusion.risk_multiplier * 0.90);
      trigger_abs += 0.05;
     }

   if(g_DE30_tuning_policy.enabled && g_DE30_tuning_policy.trusted_data)
     {
      int minutes_from_start = ResolveDE30MinutesFromWindowStart(profile);
      int minutes_to_end = ResolveDE30MinutesToWindowEnd(profile);

      if(setup_reason == "SETUP_BREAKOUT")
        {
         if(g_DE30_tuning_policy.require_non_poor_candle_for_breakout && candle.quality_grade == "POOR")
           {
            fusion.allow_entry = false;
            fusion.reason_code = "TUNING_BREAKOUT_POOR_CANDLE";
           }
         if(g_DE30_tuning_policy.require_non_poor_renko_for_breakout && (renko.quality_grade == "POOR" || renko.quality_grade == "UNKNOWN"))
           {
            fusion.allow_entry = false;
            fusion.reason_code = "TUNING_BREAKOUT_POOR_RENKO";
           }
         ApplyDE30TuningPenalty(fusion.confidence_score,fusion.risk_multiplier,trigger_abs,g_DE30_tuning_policy.breakout_global_tax);
         if(assessment.market_regime == "CHAOS")
            ApplyDE30TuningPenalty(fusion.confidence_score,fusion.risk_multiplier,trigger_abs,g_DE30_tuning_policy.breakout_chaos_tax);
         if(assessment.market_regime == "RANGE")
            ApplyDE30TuningPenalty(fusion.confidence_score,fusion.risk_multiplier,trigger_abs,g_DE30_tuning_policy.breakout_range_tax);
         if(fusion.reason_code == "AUX_CONFLICT_CAUTION")
            ApplyDE30TuningPenalty(fusion.confidence_score,fusion.risk_multiplier,trigger_abs,g_DE30_tuning_policy.breakout_conflict_tax);
         if(minutes_from_start >= 0 && minutes_from_start < 45)
            ApplyDE30TuningPenalty(fusion.confidence_score,fusion.risk_multiplier,trigger_abs,g_DE30_tuning_policy.index_opening_impulse_tax);
         if(minutes_to_end >= 0 && minutes_to_end < 45)
            ApplyDE30TuningPenalty(fusion.confidence_score,fusion.risk_multiplier,trigger_abs,g_DE30_tuning_policy.index_noon_transition_tax);
        }

      if(setup_reason == "SETUP_TREND" || setup_reason == "SETUP_PULLBACK")
        {
         if(g_DE30_tuning_policy.require_non_poor_candle_for_trend && candle.quality_grade == "POOR")
           {
            fusion.allow_entry = false;
            fusion.reason_code = "TUNING_TRENDLIKE_POOR_CANDLE";
           }
         if(assessment.market_regime == "BREAKOUT")
            ApplyDE30TuningPenalty(fusion.confidence_score,fusion.risk_multiplier,trigger_abs,g_DE30_tuning_policy.trend_breakout_tax);
         if(assessment.market_regime == "CHAOS")
            ApplyDE30TuningPenalty(fusion.confidence_score,fusion.risk_multiplier,trigger_abs,g_DE30_tuning_policy.trend_chaos_tax);
         if(assessment.spread_regime == "CAUTION" || assessment.spread_regime == "BAD")
            ApplyDE30TuningPenalty(fusion.confidence_score,fusion.risk_multiplier,trigger_abs,g_DE30_tuning_policy.trend_caution_tax);
         if(!aux_supportive)
            ApplyDE30TuningPenalty(fusion.confidence_score,fusion.risk_multiplier,trigger_abs,g_DE30_tuning_policy.trend_no_aux_tax);
         if(g_DE30_tuning_policy.require_aux_support_for_trend && !aux_supportive)
            ApplyDE30TuningPenalty(fusion.confidence_score,fusion.risk_multiplier,trigger_abs,0.04);
        }

      if(setup_reason == "SETUP_RANGE")
        {
         if(g_DE30_tuning_policy.require_non_poor_candle_for_range && candle.quality_grade == "POOR")
           {
            fusion.allow_entry = false;
            fusion.reason_code = "TUNING_RANGE_POOR_CANDLE";
           }
         if(g_DE30_tuning_policy.require_non_poor_renko_for_range && (renko.quality_grade == "POOR" || renko.quality_grade == "UNKNOWN"))
           {
            fusion.allow_entry = false;
            fusion.reason_code = "TUNING_RANGE_POOR_RENKO";
           }
         if(g_DE30_tuning_policy.require_support_for_rejection && !aux_supportive)
           {
            fusion.allow_entry = false;
            fusion.reason_code = "TUNING_RANGE_NEEDS_SUPPORT";
           }
         if(assessment.market_regime == "CHAOS")
            ApplyDE30TuningPenalty(fusion.confidence_score,fusion.risk_multiplier,trigger_abs,g_DE30_tuning_policy.range_chaos_tax);
         if(assessment.market_regime == "TREND" || assessment.market_regime == "BREAKOUT")
            ApplyDE30TuningPenalty(fusion.confidence_score,fusion.risk_multiplier,trigger_abs,g_DE30_tuning_policy.range_trend_tax);
         if(assessment.market_regime == "RANGE")
            ApplyDE30TuningBoost(fusion.confidence_score,fusion.risk_multiplier,trigger_abs,g_DE30_tuning_policy.rejection_range_boost);
         if(minutes_to_end >= 0 && minutes_to_end < 45)
            ApplyDE30TuningPenalty(fusion.confidence_score,fusion.risk_multiplier,trigger_abs,g_DE30_tuning_policy.index_noon_transition_tax);
         if(g_DE30_tuning_policy.range_confidence_floor > 0.0 && fusion.confidence_score < g_DE30_tuning_policy.range_confidence_floor)
           {
            fusion.allow_entry = false;
            fusion.reason_code = "TUNING_RANGE_CONFIDENCE_FLOOR";
           }
        }

      fusion.confidence_score = MathMin(fusion.confidence_score,g_DE30_tuning_policy.confidence_cap);
      fusion.risk_multiplier = MathMin(fusion.risk_multiplier,g_DE30_tuning_policy.risk_cap);
     }

   out.market_regime = assessment.market_regime;
   out.spread_regime = assessment.spread_regime;
   out.execution_regime = assessment.execution_regime;
   out.confidence_score = fusion.confidence_score;
   out.risk_multiplier = fusion.risk_multiplier;
   out.setup_type = setup_reason;
   out.candle_bias = candle.bias;
   out.candle_quality_grade = candle.quality_grade;
   out.candle_score = MathMax(candle.score_long,candle.score_short);
   out.renko_bias = renko.bias;
   out.renko_quality_grade = renko.quality_grade;
   out.renko_score = MathMax(renko.score_long,renko.score_short);
   out.renko_run_length = renko.run_length;
   out.renko_reversal_flag = renko.reversal_flag;

   if(out.confidence_score >= 0.75)
      out.confidence_bucket = "HIGH";
   else if(out.confidence_score >= 0.52)
      out.confidence_bucket = "MEDIUM";
   else
      out.confidence_bucket = "LOW";

   if(!MbStrategyFinalizeSignalDecision(score,trigger_abs,setup_reason,current_bar_time,g_DE30_last_bar_time,out))
      return;

   if(!assessment.allow_entry)
     {
      out.valid = false;
      out.reason_code = assessment.reason_code;
      return;
     }

   if(!fusion.allow_entry)
     {
      out.valid = false;
      out.reason_code = fusion.reason_code;
      return;
     }

   out.reason_code = (setup_reason + "_" + out.confidence_bucket + "_" + fusion.reason_code);
  }

#endif
