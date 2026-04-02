#ifndef STRATEGY_EURUSD_INCLUDED
#define STRATEGY_EURUSD_INCLUDED

#include <Trade/Trade.mqh>
#include "..\\Core\\MbRuntimeTypes.mqh"
#include "..\\Core\\MbContextPolicy.mqh"
#include "..\\Core\\MbCandleAdvisory.mqh"
#include "..\\Core\\MbRenkoAdvisory.mqh"
#include "..\\Core\\MbAuxSignalFusion.mqh"
#include "..\\Core\\MbTuningTypes.mqh"
#include "..\\Core\\MbForexDoctrineEURUSD.mqh"
#include ".\\Common\\MbStrategyCommon.mqh"

int g_eurusd_ema_fast_handle = INVALID_HANDLE;
int g_eurusd_ema_slow_handle = INVALID_HANDLE;
int g_eurusd_atr_handle = INVALID_HANDLE;
int g_eurusd_rsi_handle = INVALID_HANDLE;
datetime g_eurusd_last_bar_time = 0;
double g_eurusd_last_atr_points = 0.0;
datetime g_eurusd_last_position_modify = 0;
MbTuningLocalPolicy g_eurusd_tuning_policy;

struct EurUsdLocalRiskPlan
  {
   bool allowed;
   double lots;
   double sl_points;
   double tp_points;
   string reason_code;
  };

bool StrategyEURUSDInit(const MbSymbolProfile &profile)
  {
   bool ok = MbStrategyInitIndicators(profile,12,34,14,14,g_eurusd_ema_fast_handle,g_eurusd_ema_slow_handle,g_eurusd_atr_handle,g_eurusd_rsi_handle);
   g_eurusd_last_bar_time = 0;
   MbTuningLocalPolicyReset(g_eurusd_tuning_policy);
   if(!ok)
      PrintFormat("MB_EURUSD_INIT_FAIL stage=INDICATORS symbol=%s tf=%s ema_fast=%d ema_slow=%d atr=%d rsi=%d",
                  profile.symbol,
                  EnumToString(profile.trade_tf),
                  g_eurusd_ema_fast_handle,
                  g_eurusd_ema_slow_handle,
                  g_eurusd_atr_handle,
                  g_eurusd_rsi_handle);
   return ok;
  }

void StrategyEURUSDDeinit()
  {
   MbStrategyReleaseIndicators(g_eurusd_ema_fast_handle,g_eurusd_ema_slow_handle,g_eurusd_atr_handle,g_eurusd_rsi_handle);
   g_eurusd_last_bar_time = 0;
   g_eurusd_last_atr_points = 0.0;
   g_eurusd_last_position_modify = 0;
  }

double StrategyEURUSDComputeLots(
   const MbMarketSnapshot &snapshot,
   const MbRuntimeState &state,
   const double sl_points
)
  {
   MbStrategyRiskModel risk_model;
   risk_model.base_risk_pct = 0.35;
   risk_model.execution_floor = 0.70;
   risk_model.execution_decay = 0.50;
   risk_model.min_risk_pct = 0.20;
   risk_model.max_risk_pct = 0.50;
  return MbStrategyComputeLots(snapshot,state,sl_points,risk_model);
  }

void StrategyEURUSDSetTuningPolicy(const MbTuningLocalPolicy &policy)
  {
   g_eurusd_tuning_policy = policy;
  }

void ApplyEURUSDTuningPenalty(
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

void ApplyEURUSDTuningBoost(
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

void BuildEURUSDRiskPlan(
   const MbRuntimeState &state,
   const MbMarketSnapshot &snapshot,
   EurUsdLocalRiskPlan &out
)
  {
   MbStrategyRiskModel risk_model;
   risk_model.base_risk_pct = 0.35;
   risk_model.execution_floor = 0.70;
   risk_model.execution_decay = 0.50;
   risk_model.min_risk_pct = 0.20;
   risk_model.max_risk_pct = 0.50;
   MbStrategyBuildRiskPlan(snapshot,state,g_eurusd_last_atr_points,1.80,40.0,2.40,60.0,risk_model,out.allowed,out.lots,out.sl_points,out.tp_points,out.reason_code);
  }

void ManageEURUSDOpenPosition(
   CTrade &trade,
   MbRuntimeState &state,
   const MbSymbolProfile &profile,
   const MbMarketSnapshot &snapshot
)
  {
   MbStrategyManageTrailingPosition(trade,state,profile,snapshot,g_eurusd_last_atr_points,1.20,6.0,g_eurusd_last_position_modify);
  }

void EvaluateEURUSDStrategy(
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
      g_eurusd_ema_fast_handle == INVALID_HANDLE ||
      g_eurusd_ema_slow_handle == INVALID_HANDLE ||
      g_eurusd_atr_handle == INVALID_HANDLE ||
      g_eurusd_rsi_handle == INVALID_HANDLE
   )
     {
      out.reason_code = "INDICATORS_NOT_READY";
      return;
     }

   double ema_fast = 0.0;
   double ema_slow = 0.0;
   double atr_raw = 0.0;
   double rsi = 50.0;
   if(!MbStrategyCopyLastValue(g_eurusd_ema_fast_handle,ema_fast))
     {
      out.reason_code = "EMA_FAST_COPY_FAIL";
      return;
     }
   if(!MbStrategyCopyLastValue(g_eurusd_ema_slow_handle,ema_slow))
     {
      out.reason_code = "EMA_SLOW_COPY_FAIL";
      return;
     }
   if(!MbStrategyCopyLastValue(g_eurusd_atr_handle,atr_raw))
     {
      out.reason_code = "ATR_COPY_FAIL";
      return;
     }
   if(!MbStrategyCopyLastValue(g_eurusd_rsi_handle,rsi))
     {
      out.reason_code = "RSI_COPY_FAIL";
      return;
     }

   datetime current_bar_time = 0;
   if(!MbStrategyResolveNewBar(profile.symbol,profile.trade_tf,g_eurusd_last_bar_time,current_bar_time,out.reason_code,MbShouldBypassGlobalTeacherLearningNewBar(profile.symbol,state.paper_mode_active)))
      return;

   if(atr_raw <= 0.0)
     {
      out.reason_code = "ATR_INVALID";
      return;
     }

   double score_trend = (0.65 * ((ema_fast - ema_slow) / atr_raw)) + (0.35 * ((rsi - 50.0) / 25.0));
   double score_pullback = (0.55 * ((rsi - 50.0) / 18.0)) - (0.25 * ((ema_fast - ema_slow) / atr_raw));
   double score_breakout = (0.80 * ((ema_fast - ema_slow) / atr_raw)) + (0.20 * (state.spread_anomaly_streak == 0 ? 1.0 : -1.0));
   double score_rejection = (-0.50 * ((rsi - 50.0) / 20.0)) + (0.20 * (state.spread_anomaly_streak == 0 ? 1.0 : -1.0));

   double score = score_trend;
   string setup_reason = "SETUP_TREND";
   double best_abs = MathAbs(score_trend);
   MbStrategySelectBetterScore(score_pullback,"SETUP_PULLBACK",best_abs,score,setup_reason);
   MbStrategySelectBetterScore(score_breakout,"SETUP_BREAKOUT",best_abs,score,setup_reason);
   MbStrategySelectBetterScore(score_rejection,"SETUP_REJECTION",best_abs,score,setup_reason);

   double trigger_abs = (state.caution_mode ? 0.90 : 0.72);
   g_eurusd_last_atr_points = atr_raw / _Point;
   double trend_strength = ((ema_fast - ema_slow) / atr_raw);
   MbSignalContextAssessment assessment;
   MbAssessSignalContext(profile,state,snapshot,score,setup_reason,trend_strength,rsi,assessment);
   MbEurUsdForexDoctrine forex_doctrine;
   MbAssessEURUSDForexDoctrine(
      current_bar_time,
      setup_reason,
      assessment.market_regime,
      assessment.spread_regime,
      assessment.execution_regime,
      forex_doctrine
   );

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
      g_eurusd_last_atr_points,
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

   // Breakout entries in chaotic conditions were the weakest recent bucket.
   // Tighten them slightly instead of disabling them entirely.
   if(setup_reason == "SETUP_BREAKOUT" && assessment.market_regime == "CHAOS")
     {
      fusion.confidence_score = MathMax(0.0,fusion.confidence_score - 0.06);
      fusion.risk_multiplier = MathMax(0.55,fusion.risk_multiplier * 0.90);
      trigger_abs += 0.06;
     }
   // Breakout underperformed across all observed regimes, so add a light global tax.
   if(setup_reason == "SETUP_BREAKOUT")
     {
      fusion.confidence_score = MathMax(0.0,fusion.confidence_score - 0.02);
      fusion.risk_multiplier = MathMax(0.55,fusion.risk_multiplier * 0.96);
      trigger_abs += 0.03;
     }
   // Range breakouts also underperform; keep them possible but more selective.
   if(setup_reason == "SETUP_BREAKOUT" && assessment.market_regime == "RANGE")
     {
      fusion.confidence_score = MathMax(0.0,fusion.confidence_score - 0.05);
      fusion.risk_multiplier = MathMax(0.55,fusion.risk_multiplier * 0.92);
      trigger_abs += 0.05;
     }
   // If auxiliary layers actively disagree, breakout should pay a higher entry tax.
   if(setup_reason == "SETUP_BREAKOUT" && fusion.reason_code == "AUX_CONFLICT_CAUTION")
     {
      fusion.confidence_score = MathMax(0.0,fusion.confidence_score - 0.04);
      fusion.risk_multiplier = MathMax(0.55,fusion.risk_multiplier * 0.93);
      trigger_abs += 0.04;
     }
   // Rejection in range is the healthiest observed bucket, so give it a gentle advantage.
   if(setup_reason == "SETUP_REJECTION" && assessment.market_regime == "RANGE")
     {
      fusion.confidence_score = MathMin(1.0,fusion.confidence_score + 0.05);
      fusion.risk_multiplier = MathMin(1.05,fusion.risk_multiplier * 1.03);
      trigger_abs = MathMax(0.20,trigger_abs - 0.04);
     }
   // Trend entries still leak too often into hostile contexts. Tax them lightly
   // when the market looks transitional or the supporting layers do not agree.
   if(setup_reason == "SETUP_TREND" && assessment.spread_regime == "CAUTION")
     {
      fusion.confidence_score = MathMax(0.0,fusion.confidence_score - 0.03);
      fusion.risk_multiplier = MathMax(0.55,fusion.risk_multiplier * 0.95);
      trigger_abs += 0.02;
     }
   if(setup_reason == "SETUP_TREND" && assessment.market_regime == "BREAKOUT")
     {
      fusion.confidence_score = MathMax(0.0,fusion.confidence_score - 0.05);
      fusion.risk_multiplier = MathMax(0.55,fusion.risk_multiplier * 0.93);
      trigger_abs += 0.04;
     }
   if(setup_reason == "SETUP_TREND" && assessment.market_regime == "CHAOS")
     {
      fusion.confidence_score = MathMax(0.0,fusion.confidence_score - 0.07);
      fusion.risk_multiplier = MathMax(0.55,fusion.risk_multiplier * 0.90);
      trigger_abs += 0.05;
     }
   if(setup_reason == "SETUP_TREND" && !aux_supportive)
     {
      fusion.confidence_score = MathMax(0.0,fusion.confidence_score - 0.03);
      fusion.risk_multiplier = MathMax(0.55,fusion.risk_multiplier * 0.95);
      trigger_abs += 0.02;
     }

   if(setup_reason == "SETUP_BREAKOUT")
      ApplyEURUSDTuningPenalty(fusion.confidence_score,fusion.risk_multiplier,trigger_abs,forex_doctrine.breakout_tax);
   else if(setup_reason == "SETUP_TREND" || setup_reason == "SETUP_PULLBACK")
      ApplyEURUSDTuningPenalty(fusion.confidence_score,fusion.risk_multiplier,trigger_abs,forex_doctrine.trend_tax);
   else if(setup_reason == "SETUP_REJECTION")
      ApplyEURUSDTuningPenalty(fusion.confidence_score,fusion.risk_multiplier,trigger_abs,forex_doctrine.rejection_tax);

   fusion.confidence_score = MathMin(fusion.confidence_score,forex_doctrine.confidence_cap);
   fusion.risk_multiplier = MathMin(fusion.risk_multiplier,forex_doctrine.risk_cap);

   if(forex_doctrine.phase_code == "ROLLOVER_RISK" &&
      (setup_reason == "SETUP_BREAKOUT" || setup_reason == "SETUP_TREND" || setup_reason == "SETUP_PULLBACK"))
     {
      fusion.allow_entry = false;
      fusion.reason_code = "FOREX_DOCTRINE_ROLLOVER";
     }

   if(g_eurusd_tuning_policy.enabled && g_eurusd_tuning_policy.trusted_data)
     {
      if(setup_reason == "SETUP_BREAKOUT")
        {
         if(g_eurusd_tuning_policy.require_non_poor_candle_for_breakout && candle.quality_grade == "POOR")
           {
            fusion.allow_entry = false;
            fusion.reason_code = "TUNING_BREAKOUT_POOR_CANDLE";
           }
         if(g_eurusd_tuning_policy.require_non_poor_renko_for_breakout && (renko.quality_grade == "POOR" || renko.quality_grade == "UNKNOWN"))
           {
            fusion.allow_entry = false;
            fusion.reason_code = "TUNING_BREAKOUT_POOR_RENKO";
           }
         ApplyEURUSDTuningPenalty(fusion.confidence_score,fusion.risk_multiplier,trigger_abs,g_eurusd_tuning_policy.breakout_global_tax);
         if(assessment.market_regime == "CHAOS")
            ApplyEURUSDTuningPenalty(fusion.confidence_score,fusion.risk_multiplier,trigger_abs,g_eurusd_tuning_policy.breakout_chaos_tax);
         if(assessment.market_regime == "RANGE")
            ApplyEURUSDTuningPenalty(fusion.confidence_score,fusion.risk_multiplier,trigger_abs,g_eurusd_tuning_policy.breakout_range_tax);
         if(fusion.reason_code == "AUX_CONFLICT_CAUTION")
            ApplyEURUSDTuningPenalty(fusion.confidence_score,fusion.risk_multiplier,trigger_abs,g_eurusd_tuning_policy.breakout_conflict_tax);
        }

      if(setup_reason == "SETUP_TREND")
        {
         if(g_eurusd_tuning_policy.require_non_poor_candle_for_trend && candle.quality_grade == "POOR")
           {
            fusion.allow_entry = false;
            fusion.reason_code = "TUNING_TREND_POOR_CANDLE";
           }
         if(assessment.market_regime == "BREAKOUT")
            ApplyEURUSDTuningPenalty(fusion.confidence_score,fusion.risk_multiplier,trigger_abs,g_eurusd_tuning_policy.trend_breakout_tax);
         if(assessment.market_regime == "CHAOS")
            ApplyEURUSDTuningPenalty(fusion.confidence_score,fusion.risk_multiplier,trigger_abs,g_eurusd_tuning_policy.trend_chaos_tax);
         if(assessment.spread_regime == "CAUTION" || assessment.spread_regime == "BAD")
            ApplyEURUSDTuningPenalty(fusion.confidence_score,fusion.risk_multiplier,trigger_abs,g_eurusd_tuning_policy.trend_caution_tax);
         if(!aux_supportive)
            ApplyEURUSDTuningPenalty(fusion.confidence_score,fusion.risk_multiplier,trigger_abs,g_eurusd_tuning_policy.trend_no_aux_tax);
         if(g_eurusd_tuning_policy.require_aux_support_for_trend && !aux_supportive)
            ApplyEURUSDTuningPenalty(fusion.confidence_score,fusion.risk_multiplier,trigger_abs,0.04);
        }

      if(setup_reason == "SETUP_REJECTION")
        {
         if(g_eurusd_tuning_policy.require_support_for_rejection && !aux_supportive)
           {
            fusion.allow_entry = false;
            fusion.reason_code = "TUNING_REJECTION_NEEDS_SUPPORT";
           }
         if(assessment.market_regime == "RANGE")
            ApplyEURUSDTuningBoost(fusion.confidence_score,fusion.risk_multiplier,trigger_abs,g_eurusd_tuning_policy.rejection_range_boost);
        }

      fusion.confidence_score = MathMin(fusion.confidence_score,g_eurusd_tuning_policy.confidence_cap);
      fusion.risk_multiplier = MathMin(fusion.risk_multiplier,g_eurusd_tuning_policy.risk_cap);
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

   if(!MbStrategyFinalizeSignalDecision(score,trigger_abs,setup_reason,current_bar_time,g_eurusd_last_bar_time,out))
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
