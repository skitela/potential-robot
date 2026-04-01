#ifndef MB_STRATEGY_COMMON_INCLUDED
#define MB_STRATEGY_COMMON_INCLUDED

#include <Trade/Trade.mqh>
#include "..\\..\\Core\\MbRuntimeTypes.mqh"
#include "..\\..\\Core\\MbCapitalRiskContract.mqh"
#include "..\\..\\Core\\MbFirstWaveTruthDiagnostic.mqh"
#include "..\\..\\Core\\MbGlobalTeacherLearningDiagnostic.mqh"
#include "..\\..\\Core\\MbLearningPolicy.mqh"

struct MbStrategyRiskModel
  {
   double base_risk_pct;
   double execution_floor;
   double execution_decay;
   double min_risk_pct;
   double max_risk_pct;
  };

void MbStrategyBuildRiskPlan(
   const MbMarketSnapshot &snapshot,
   const MbRuntimeState &state,
   const double last_atr_points,
   const double sl_atr_multiplier,
   const double sl_min_points,
   const double tp_atr_multiplier,
   const double tp_min_points,
   const MbStrategyRiskModel &risk_model,
   bool &out_allowed,
   double &out_lots,
   double &out_sl_points,
   double &out_tp_points,
   string &out_reason_code
)
  {
   out_allowed = false;
   out_lots = 0.0;
   out_sl_points = MathMax(last_atr_points * sl_atr_multiplier,sl_min_points);
   out_tp_points = MathMax(last_atr_points * tp_atr_multiplier,tp_min_points);
   out_reason_code = "UNKNOWN";

   if(last_atr_points <= 0.0)
     {
      out_reason_code = "ATR_INVALID";
      return;
     }

   if(snapshot.equity <= 0.0 || snapshot.margin_free <= 0.0)
     {
      out_reason_code = "ACCOUNT_STATE_INVALID";
      return;
     }

   double margin_free_pct = 100.0 * MathMax(0.0,snapshot.margin_free) / snapshot.equity;
   if(margin_free_pct < 120.0)
     {
      out_reason_code = "MARGIN_GUARD";
      return;
     }

   out_lots = MbStrategyComputeLots(snapshot,state,out_sl_points,risk_model);
   if(out_lots <= 0.0)
     {
      out_reason_code = "LOTS_ZERO";
      return;
     }

   out_allowed = true;
   out_reason_code = "OK";
  }

double MbStrategyClamp(const double value,const double lo,const double hi)
  {
   return MathMax(lo,MathMin(hi,value));
  }

bool MbStrategyCopyStableValue(const int handle,const int shift,double &out_value)
  {
   if(handle == INVALID_HANDLE)
      return false;

   int bars_ready = BarsCalculated(handle);
   if(bars_ready <= shift)
      return false;

   double buf[1];
   if(CopyBuffer(handle,0,shift,1,buf) < 1)
      return false;

   out_value = buf[0];
   return true;
  }

bool MbStrategyCopyLastValue(const int handle,double &out_value)
  {
   // Shared strategy hot-path should consume the last closed bar, not the current
   // forming one. This keeps indicator reads aligned with new-bar decisions.
   return MbStrategyCopyStableValue(handle,1,out_value);
  }

bool MbStrategyResolveNewBar(
   const string symbol,
   const ENUM_TIMEFRAMES trade_tf,
   const datetime last_bar_time,
   datetime &out_current_bar_time,
   string &out_reason_code,
   const bool allow_same_bar_scan = false
)
  {
   datetime bar_times[1];
   if(CopyTime(symbol,trade_tf,0,1,bar_times) < 1)
     {
      out_reason_code = "BAR_TIME_COPY_FAIL";
      return false;
     }

   out_current_bar_time = bar_times[0];
   if(out_current_bar_time <= 0)
     {
      out_reason_code = "BAR_TIME_INVALID";
      return false;
     }

   if(out_current_bar_time == last_bar_time)
     {
         if(allow_same_bar_scan)
            {
             out_reason_code = "OK";
             return true;
            }
      out_reason_code = "WAIT_NEW_BAR";
      return false;
     }

   out_reason_code = "OK";
   return true;
  }

void MbStrategySelectBetterScore(
   const double candidate_score,
   const string candidate_reason,
   double &io_best_abs,
   double &io_score,
   string &io_reason
)
  {
   double candidate_abs = MathAbs(candidate_score);
   if(candidate_abs > io_best_abs)
     {
      io_best_abs = candidate_abs;
      io_score = candidate_score;
     io_reason = candidate_reason;
     }
  }

bool MbStrategyFinalizeSignalDecision(
   const double score,
   const double trigger_abs,
   const string setup_reason,
   const datetime current_bar_time,
   datetime &io_last_bar_time,
   MbSignalDecision &out
)
  {
   out.score = score;
   if(MathAbs(score) < trigger_abs)
     {
      out.reason_code = "SCORE_BELOW_TRIGGER";
      return false;
     }

   out.valid = true;
   out.side = (score >= 0.0 ? MB_SIGNAL_BUY : MB_SIGNAL_SELL);
   out.reason_code = setup_reason;
   io_last_bar_time = current_bar_time;
   return true;
  }

void MbStrategyReleaseIndicators(
   int &ema_fast_handle,
   int &ema_slow_handle,
   int &atr_handle,
   int &rsi_handle
)
  {
   if(ema_fast_handle != INVALID_HANDLE) IndicatorRelease(ema_fast_handle);
   if(ema_slow_handle != INVALID_HANDLE) IndicatorRelease(ema_slow_handle);
   if(atr_handle != INVALID_HANDLE) IndicatorRelease(atr_handle);
   if(rsi_handle != INVALID_HANDLE) IndicatorRelease(rsi_handle);

   ema_fast_handle = INVALID_HANDLE;
   ema_slow_handle = INVALID_HANDLE;
   atr_handle = INVALID_HANDLE;
   rsi_handle = INVALID_HANDLE;
  }

bool MbStrategyInitIndicators(
   const MbSymbolProfile &profile,
   const int ema_fast_period,
   const int ema_slow_period,
   const int atr_period,
   const int rsi_period,
   int &ema_fast_handle,
   int &ema_slow_handle,
   int &atr_handle,
   int &rsi_handle
)
  {
   MbStrategyReleaseIndicators(ema_fast_handle,ema_slow_handle,atr_handle,rsi_handle);

   ema_fast_handle = iMA(profile.symbol,profile.trade_tf,ema_fast_period,0,MODE_EMA,PRICE_CLOSE);
   ema_slow_handle = iMA(profile.symbol,profile.trade_tf,ema_slow_period,0,MODE_EMA,PRICE_CLOSE);
   atr_handle = iATR(profile.symbol,profile.trade_tf,atr_period);
   rsi_handle = iRSI(profile.symbol,profile.trade_tf,rsi_period,PRICE_CLOSE);

   return (
      ema_fast_handle != INVALID_HANDLE &&
      ema_slow_handle != INVALID_HANDLE &&
      atr_handle != INVALID_HANDLE &&
      rsi_handle != INVALID_HANDLE
   );
  }

double MbStrategyComputeLots(
   const MbMarketSnapshot &snapshot,
   const MbRuntimeState &state,
   const double sl_points,
   const MbStrategyRiskModel &risk_model
)
  {
   if(sl_points <= 0.0 || snapshot.tick_value <= 0.0 || snapshot.tick_size <= 0.0 || snapshot.vol_step <= 0.0)
      return 0.0;

   MbCapitalRiskContract contract;
   MbResolveCapitalRiskContract(snapshot.paper_runtime_override_active,contract);

   double risk_min_pct = MathMax(0.0,contract.risk_per_trade_min_pct);
   double risk_max_pct = MathMax(risk_min_pct,MathMin(risk_model.max_risk_pct,contract.risk_per_trade_max_pct));
   double risk_base_pct = MathMax(risk_min_pct,MathMin(risk_model.base_risk_pct,contract.risk_per_trade_base_pct));
   double pressure_factor = MathMax(risk_model.execution_floor,1.0 - (state.execution_pressure * risk_model.execution_decay));
   double risk_pct = risk_base_pct * pressure_factor * (1.0 + ((MathMax(0.75,state.adaptive_risk_scale) - 1.0) * state.learning_confidence));
   risk_pct *= MbStrategyClamp(state.coordinator_risk_cap,0.0,1.0);
   if(MbCapitalRiskSoftLossTriggered(snapshot.paper_runtime_override_active,state,snapshot))
      risk_pct *= contract.soft_loss_risk_factor;
   risk_pct = MbStrategyClamp(risk_pct,risk_min_pct,risk_max_pct);

   double risk_capital = MbCapitalRiskResolveRiskBase(snapshot.paper_runtime_override_active,contract,state,snapshot);
   if(risk_capital <= 0.0)
      return 0.0;

   double risk_money = risk_capital * (risk_pct / 100.0);
   double money_per_lot = (sl_points * _Point / snapshot.tick_size) * snapshot.tick_value;
   if(money_per_lot <= 0.0)
      return 0.0;

   double raw = risk_money / money_per_lot;
   double stepped = MathFloor(raw / snapshot.vol_step) * snapshot.vol_step;
   return MbStrategyClamp(stepped,snapshot.vol_min,snapshot.vol_max);
  }

void MbStrategyManageTrailingPosition(
   CTrade &trade,
   MbRuntimeState &state,
   const MbSymbolProfile &profile,
   const MbMarketSnapshot &snapshot,
   const double last_atr_points,
   const double trail_atr_multiplier,
   const double pressure_step_scale,
   datetime &last_position_modify
)
  {
   if(!PositionSelect(profile.symbol))
      return;
   if((ulong)PositionGetInteger(POSITION_MAGIC) != state.magic)
      return;
   if(state.force_flatten)
     {
      if(trade.PositionClose(profile.symbol))
         last_position_modify = TimeCurrent();
      return;
     }
   if(last_atr_points <= 0.0)
      return;
   if(!snapshot.valid || snapshot.bid <= 0.0 || snapshot.ask <= 0.0)
      return;
   if(snapshot.tick_age_ms > MathMax(500,(long)(profile.max_tick_age_sec * 500)))
      return;
   if(state.execution_pressure >= 0.80)
      return;

   long pos_type = PositionGetInteger(POSITION_TYPE);
   double sl = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);
   double trail = last_atr_points * trail_atr_multiplier * _Point;
   double min_step_points = (double)MathMax(2,MathMax(snapshot.stops_level,snapshot.freeze_level));
   min_step_points = MathMax(min_step_points,2.0 + (state.execution_pressure * pressure_step_scale));
   double min_step_price = min_step_points * _Point;
   int modify_cooldown_sec = 3 + (int)MathRound(state.execution_pressure * 4.0);
   if(last_position_modify > 0 && (TimeCurrent() - last_position_modify) < modify_cooldown_sec)
      return;

   if(pos_type == POSITION_TYPE_BUY)
     {
      double new_sl = snapshot.bid - trail;
      if(sl == 0.0 || new_sl > (sl + min_step_price))
        {
         if(trade.PositionModify(profile.symbol,new_sl,tp))
            last_position_modify = TimeCurrent();
        }
     }
   else if(pos_type == POSITION_TYPE_SELL)
     {
      double new_sl = snapshot.ask + trail;
      if(sl == 0.0 || new_sl < (sl - min_step_price))
        {
         if(trade.PositionModify(profile.symbol,new_sl,tp))
            last_position_modify = TimeCurrent();
        }
     }
  }

#endif
