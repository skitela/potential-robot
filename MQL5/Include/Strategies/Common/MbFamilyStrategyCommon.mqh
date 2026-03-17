#ifndef MB_FAMILY_STRATEGY_COMMON_INCLUDED
#define MB_FAMILY_STRATEGY_COMMON_INCLUDED

#include <Trade/Trade.mqh>
#include "..\\..\\Core\\MbRuntimeTypes.mqh"
#include ".\\MbStrategyCommon.mqh"

#define MB_FAMILY_KIND_MAIN 1
#define MB_FAMILY_KIND_ASIA 2
#define MB_FAMILY_KIND_CROSS 3
#define MB_FAMILY_KIND_METAL_SPOT 4
#define MB_FAMILY_KIND_METAL_FUTURES 5
#define MB_FAMILY_KIND_INDEX_EU 6
#define MB_FAMILY_KIND_INDEX_US 7

struct MbFamilyStrategyParams
  {
   int family_kind;
   int ema_fast_period;
   int ema_slow_period;
   int atr_period;
   int rsi_period;
   double base_risk_pct;
   double execution_floor;
   double execution_decay;
   double min_risk_pct;
   double max_risk_pct;
   double sl_atr_multiplier;
   double sl_min_points;
   double tp_atr_multiplier;
   double tp_min_points;
   double trail_atr_multiplier;
   double pressure_step_scale;
   double ready_trigger_abs;
   double caution_trigger_abs;
  };

bool MbFamilyStrategyInit(
   const MbSymbolProfile &profile,
   const MbFamilyStrategyParams &params,
   int &ema_fast_handle,
   int &ema_slow_handle,
   int &atr_handle,
   int &rsi_handle,
   datetime &last_bar_time,
   double &last_atr_points,
   datetime &last_position_modify
)
  {
   bool ok = MbStrategyInitIndicators(
      profile,
      params.ema_fast_period,
      params.ema_slow_period,
      params.atr_period,
      params.rsi_period,
      ema_fast_handle,
      ema_slow_handle,
      atr_handle,
      rsi_handle
   );
   last_bar_time = 0;
   last_atr_points = 0.0;
   last_position_modify = 0;
   return ok;
  }

void MbFamilyStrategyDeinit(
   int &ema_fast_handle,
   int &ema_slow_handle,
   int &atr_handle,
   int &rsi_handle,
   datetime &last_bar_time,
   double &last_atr_points,
   datetime &last_position_modify
)
  {
   MbStrategyReleaseIndicators(ema_fast_handle,ema_slow_handle,atr_handle,rsi_handle);
   last_bar_time = 0;
   last_atr_points = 0.0;
   last_position_modify = 0;
  }

void MbFamilyStrategyBuildRiskPlan(
   const MbRuntimeState &state,
   const MbMarketSnapshot &snapshot,
   const double last_atr_points,
   const MbFamilyStrategyParams &params,
   bool &out_allowed,
   double &out_lots,
   double &out_sl_points,
   double &out_tp_points,
   string &out_reason_code
)
  {
   MbStrategyRiskModel risk_model;
   risk_model.base_risk_pct = params.base_risk_pct;
   risk_model.execution_floor = params.execution_floor;
   risk_model.execution_decay = params.execution_decay;
   risk_model.min_risk_pct = params.min_risk_pct;
   risk_model.max_risk_pct = params.max_risk_pct;
   MbStrategyBuildRiskPlan(
      snapshot,
      state,
      last_atr_points,
      params.sl_atr_multiplier,
      params.sl_min_points,
      params.tp_atr_multiplier,
      params.tp_min_points,
      risk_model,
      out_allowed,
      out_lots,
      out_sl_points,
      out_tp_points,
      out_reason_code
   );
  }

void MbFamilyStrategyManagePosition(
   CTrade &trade,
   MbRuntimeState &state,
   const MbSymbolProfile &profile,
   const MbMarketSnapshot &snapshot,
   const double last_atr_points,
   const MbFamilyStrategyParams &params,
   datetime &last_position_modify
)
  {
   MbStrategyManageTrailingPosition(
      trade,
      state,
      profile,
      snapshot,
      last_atr_points,
      params.trail_atr_multiplier,
      params.pressure_step_scale,
      last_position_modify
   );
  }

void MbFamilyStrategyEvaluate(
   const MbRuntimeState &state,
   const MbSymbolProfile &profile,
   const MbFamilyStrategyParams &params,
   int ema_fast_handle,
   int ema_slow_handle,
   int atr_handle,
   int rsi_handle,
   datetime &io_last_bar_time,
   double &io_last_atr_points,
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
      ema_fast_handle == INVALID_HANDLE ||
      ema_slow_handle == INVALID_HANDLE ||
      atr_handle == INVALID_HANDLE ||
      rsi_handle == INVALID_HANDLE
   )
     {
      out.reason_code = "INDICATORS_NOT_READY";
      return;
     }

   double ema_fast = 0.0;
   double ema_slow = 0.0;
   double atr_raw = 0.0;
   double rsi = 50.0;
   if(!MbStrategyCopyLastValue(ema_fast_handle,ema_fast))
     {
      out.reason_code = "EMA_FAST_COPY_FAIL";
      return;
     }
   if(!MbStrategyCopyLastValue(ema_slow_handle,ema_slow))
     {
      out.reason_code = "EMA_SLOW_COPY_FAIL";
      return;
     }
   if(!MbStrategyCopyLastValue(atr_handle,atr_raw))
     {
      out.reason_code = "ATR_COPY_FAIL";
      return;
     }
   if(!MbStrategyCopyLastValue(rsi_handle,rsi))
     {
      out.reason_code = "RSI_COPY_FAIL";
      return;
     }

   datetime current_bar_time = 0;
   if(!MbStrategyResolveNewBar(profile.symbol,profile.trade_tf,io_last_bar_time,current_bar_time,out.reason_code))
      return;

   if(atr_raw <= 0.0)
     {
      out.reason_code = "ATR_INVALID";
      return;
     }

   double ema_delta = (ema_fast - ema_slow) / atr_raw;
   double rsi_shift = (rsi - 50.0) / 25.0;
   double spread_bias = (state.spread_anomaly_streak == 0 ? 1.0 : -1.0);

   double score_a = 0.0;
   double score_b = 0.0;
   double score_c = 0.0;
   double score_d = 0.0;
   string reason_a = "SETUP_TREND";
   string reason_b = "SETUP_PULLBACK";
   string reason_c = "SETUP_BREAKOUT";
   string reason_d = "SETUP_REVERSAL";

   if(params.family_kind == MB_FAMILY_KIND_MAIN)
     {
      score_a = (0.70 * ema_delta) + (0.30 * rsi_shift);
      score_b = (0.58 * rsi_shift) - (0.20 * ema_delta);
      score_c = (0.78 * ema_delta) + (0.22 * spread_bias);
      score_d = (-0.46 * rsi_shift) + (0.18 * spread_bias);
      reason_d = "SETUP_REJECTION";
     }
   else if(params.family_kind == MB_FAMILY_KIND_ASIA)
     {
      score_a = (0.55 * ema_delta) + (0.20 * rsi_shift) + (0.25 * spread_bias);
      score_b = (0.42 * rsi_shift) - (0.18 * ema_delta);
      score_c = (0.74 * ema_delta) + (0.26 * spread_bias);
      score_d = (-0.20 * ema_delta) - (0.30 * rsi_shift) + (0.50 * spread_bias);
      reason_a = "SETUP_TREND_ASIA";
      reason_b = "SETUP_PULLBACK_ASIA";
      reason_c = "SETUP_BREAKOUT_ASIA";
      reason_d = "SETUP_RANGE";
     }
   else if(params.family_kind == MB_FAMILY_KIND_METAL_SPOT)
     {
      score_a = (0.61 * ema_delta) + (0.14 * rsi_shift) + (0.25 * spread_bias);
      score_b = (0.34 * rsi_shift) - (0.10 * ema_delta);
      score_c = (0.84 * ema_delta) + (0.16 * spread_bias);
      score_d = (-0.30 * rsi_shift) + (0.24 * spread_bias) - (0.10 * ema_delta);
      reason_a = "SETUP_TREND";
      reason_b = "SETUP_PULLBACK";
      reason_c = "SETUP_BREAKOUT";
      reason_d = "SETUP_REJECTION";
     }
   else if(params.family_kind == MB_FAMILY_KIND_METAL_FUTURES)
     {
      score_a = (0.58 * ema_delta) + (0.10 * rsi_shift) + (0.32 * spread_bias);
      score_b = (0.26 * rsi_shift) - (0.08 * ema_delta);
      score_c = (0.88 * ema_delta) + (0.12 * spread_bias);
      score_d = (-0.18 * ema_delta) - (0.18 * rsi_shift) + (0.40 * spread_bias);
      reason_a = "SETUP_TREND";
      reason_b = "SETUP_PULLBACK";
      reason_c = "SETUP_BREAKOUT";
      reason_d = "SETUP_RANGE";
     }
   else if(params.family_kind == MB_FAMILY_KIND_INDEX_EU)
     {
      score_a = (0.60 * ema_delta) + (0.16 * rsi_shift) + (0.24 * spread_bias);
      score_b = (0.36 * rsi_shift) - (0.12 * ema_delta);
      score_c = (0.74 * ema_delta) + (0.26 * spread_bias);
      score_d = (-0.20 * ema_delta) - (0.14 * rsi_shift) + (0.34 * spread_bias);
      reason_a = "SETUP_TREND";
      reason_b = "SETUP_PULLBACK";
      reason_c = "SETUP_BREAKOUT";
      reason_d = "SETUP_RANGE";
     }
   else if(params.family_kind == MB_FAMILY_KIND_INDEX_US)
     {
      score_a = (0.62 * ema_delta) + (0.14 * rsi_shift) + (0.24 * spread_bias);
      score_b = (0.30 * rsi_shift) - (0.10 * ema_delta);
      score_c = (0.82 * ema_delta) + (0.18 * spread_bias);
      score_d = (-0.16 * ema_delta) - (0.12 * rsi_shift) + (0.28 * spread_bias);
      reason_a = "SETUP_TREND";
      reason_b = "SETUP_PULLBACK";
      reason_c = "SETUP_BREAKOUT";
      reason_d = "SETUP_RANGE";
     }
   else
     {
      score_a = (0.62 * ema_delta) + (0.26 * rsi_shift) + (0.12 * spread_bias);
      score_b = (0.48 * rsi_shift) - (0.20 * ema_delta);
      score_c = (0.68 * ema_delta) + (0.32 * spread_bias);
      score_d = (-0.15 * ema_delta) - (0.25 * rsi_shift) + (0.45 * spread_bias);
      reason_d = "SETUP_RANGE";
     }

   double score = score_a;
   string setup_reason = reason_a;
   double best_abs = MathAbs(score_a);
   MbStrategySelectBetterScore(score_b,reason_b,best_abs,score,setup_reason);
   MbStrategySelectBetterScore(score_c,reason_c,best_abs,score,setup_reason);
   MbStrategySelectBetterScore(score_d,reason_d,best_abs,score,setup_reason);

   double trigger_abs = (state.caution_mode ? params.caution_trigger_abs : params.ready_trigger_abs);
   io_last_atr_points = atr_raw / _Point;
   MbStrategyFinalizeSignalDecision(score,trigger_abs,setup_reason,current_bar_time,io_last_bar_time,out);
  }

#endif
