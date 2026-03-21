#ifndef MB_EXECUTION_PRECHECK_INCLUDED
#define MB_EXECUTION_PRECHECK_INCLUDED

#include "MbRuntimeTypes.mqh"
#include "MbExecutionCommon.mqh"

bool MbShouldBypassExecutionPrecheckInPaper(const string reason_code)
  {
   return (
      reason_code == "ORDER_CHECK_FAIL" ||
      reason_code == "ORDER_CHECK_REJECT" ||
      reason_code == "ORDER_CALC_MARGIN_FAIL" ||
      reason_code == "MARGIN_REQUIRED_EXCEEDED" ||
      reason_code == "QUOTE_TOLERANCE_EXCEEDED"
   );
  }

void MbMarkExecutionPrecheckBypassedForPaper(MbExecutionCheck &check)
  {
   check.allowed = true;
   check.reason = "PAPER_PRECHECK_BYPASS_OK";
   check.order_check_retcode = 0;
  }

bool MbVolumeWithinSymbolConstraints(const MbMarketSnapshot &snapshot,const double lots,string &reason_code,string &diag_suffix)
  {
   reason_code = "OK";
   diag_suffix = "";

   if(snapshot.vol_min > 0.0 && lots < (snapshot.vol_min - 1e-9))
     {
      reason_code = "LOTS_BELOW_MIN";
      diag_suffix = StringFormat(" vol_min=%.4f",snapshot.vol_min);
      return false;
     }

   if(snapshot.vol_max > 0.0 && lots > (snapshot.vol_max + 1e-9))
     {
      reason_code = "LOTS_ABOVE_MAX";
      diag_suffix = StringFormat(" vol_max=%.4f",snapshot.vol_max);
      return false;
     }

   if(snapshot.vol_step > 0.0)
     {
      double origin = (snapshot.vol_min > 0.0 ? snapshot.vol_min : 0.0);
      double relative = lots - origin;
      if(relative < -1e-9)
        {
         reason_code = "LOTS_BELOW_MIN";
         diag_suffix = StringFormat(" vol_min=%.4f",snapshot.vol_min);
         return false;
        }

      double steps = relative / snapshot.vol_step;
      double nearest_steps = MathRound(steps);
      double distance = MathAbs(steps - nearest_steps);
      if(distance > 1e-6)
        {
         reason_code = "LOTS_STEP_INVALID";
         diag_suffix = StringFormat(" vol_step=%.4f lots=%.4f",snapshot.vol_step,lots);
         return false;
        }
     }

   return true;
  }

bool MbSignalSideAllowedByTradeMode(const MbMarketSnapshot &snapshot,const MbSignalSide side,string &reason_code)
  {
   reason_code = "OK";

   if(side == MB_SIGNAL_BUY && snapshot.symbol_trade_mode == (long)SYMBOL_TRADE_MODE_SHORTONLY)
     {
      reason_code = "SYMBOL_BUY_BLOCKED_BY_TRADE_MODE";
      return false;
     }

   if(side == MB_SIGNAL_SELL && snapshot.symbol_trade_mode == (long)SYMBOL_TRADE_MODE_LONGONLY)
     {
      reason_code = "SYMBOL_SELL_BLOCKED_BY_TRADE_MODE";
      return false;
     }

   return true;
  }

double MbResolveModeledCommissionPoints(const MbSymbolProfile &profile)
  {
   string family = profile.session_profile;
   if(StringFind(family,"FX_",0) == 0)
      return 0.6;
   if(family == "INDEX_EU" || family == "INDEX_US")
      return 1.2;
   if(family == "METALS_SPOT_PM")
      return 1.5;
   if(family == "METALS_FUTURES")
      return 2.0;
   return 0.8;
  }

double MbResolveModeledSlippagePoints(const MbSymbolProfile &profile,const MbMarketSnapshot &snapshot)
  {
   double deviation_component = MathMax(0.5,(double)profile.deviation_points * 0.15);
   double ping_component = 0.5;
   if(snapshot.terminal_ping_last_ms > 0)
      ping_component = MathMin(5.0,(double)snapshot.terminal_ping_last_ms / 25.0);
   return MathMax(deviation_component,ping_component);
  }

double MbResolveSafetyMarginPoints(const MbMarketSnapshot &snapshot)
  {
   return MathMax(2.0,snapshot.spread_points * 0.15);
  }

MbExecutionCheck MbBuildExecutionCheck(
   const MbSymbolProfile &profile,
   const MbMarketSnapshot &snapshot,
   const MbSignalSide side,
   const double lots,
   const double entry_price,
   const double sl_price,
   const double tp_price
)
  {
   MbExecutionCheck out;
   MbExecutionCheckReset(out);
   out.filling = MbResolveFilling(profile.symbol);

   if(side == MB_SIGNAL_NONE)
     {
      out.reason = "NO_SIGNAL";
      return out;
     }

   if(lots <= 0.0)
     {
      out.reason = "LOTS_INVALID";
      return out;
     }

   if(entry_price <= 0.0 || sl_price <= 0.0 || tp_price <= 0.0)
     {
      out.reason = "PRICE_INVALID";
      return out;
     }

   if(!snapshot.valid)
     {
      out.reason = "SNAPSHOT_INVALID";
      return out;
     }

   string trade_mode_reason = "OK";
   if(!MbSignalSideAllowedByTradeMode(snapshot,side,trade_mode_reason))
     {
      out.reason = trade_mode_reason;
      out.diag = StringFormat(" symbol_trade_mode=%I64d",(long)snapshot.symbol_trade_mode);
      return out;
     }

   string volume_reason = "OK";
   string volume_diag = "";
   if(!MbVolumeWithinSymbolConstraints(snapshot,lots,volume_reason,volume_diag))
     {
      out.reason = volume_reason;
      out.diag = "volume_guard" + volume_diag;
      return out;
     }

   int min_stop = MathMax(snapshot.stops_level,snapshot.freeze_level);
   double dist_sl = MathAbs(entry_price - sl_price) / _Point;
   double dist_tp = MathAbs(entry_price - tp_price) / _Point;
   out.diag = StringFormat("stops=%d freeze=%d dist_sl=%.2f dist_tp=%.2f",snapshot.stops_level,snapshot.freeze_level,dist_sl,dist_tp);
   if(min_stop > 0 && (dist_sl < min_stop || dist_tp < min_stop))
     {
      out.reason = "STOPS_TOO_CLOSE";
      return out;
     }

   double quote_ref = (side == MB_SIGNAL_BUY ? snapshot.ask : snapshot.bid);
   if(quote_ref > 0.0)
     {
      double quote_diff_pct = 100.0 * MathAbs(entry_price - quote_ref) / quote_ref;
      if(quote_diff_pct > profile.quotes_tolerance_pct)
        {
         out.reason = "QUOTE_TOLERANCE_EXCEEDED";
         out.diag = out.diag + StringFormat(" quote_diff_pct=%.4f",quote_diff_pct);
         return out;
        }
     }

   double expected_move_points = MathAbs(entry_price - tp_price) / _Point;
   double modeled_slippage_points = MbResolveModeledSlippagePoints(profile,snapshot);
   double modeled_commission_points = MbResolveModeledCommissionPoints(profile);
   double safety_margin_points = MbResolveSafetyMarginPoints(snapshot);
   double modeled_total_cost_points = snapshot.spread_points + modeled_slippage_points + modeled_commission_points + safety_margin_points;

   out.diag = out.diag + StringFormat(
      " expected_move=%.2f spread=%.2f slip=%.2f comm=%.2f safety=%.2f total_cost=%.2f",
      expected_move_points,
      snapshot.spread_points,
      modeled_slippage_points,
      modeled_commission_points,
      safety_margin_points,
      modeled_total_cost_points
   );

   if(expected_move_points <= modeled_total_cost_points)
     {
      out.reason = "NET_EDGE_TOO_SMALL";
      return out;
     }

   MqlTradeRequest req;
   ZeroMemory(req);
   req.action = TRADE_ACTION_DEAL;
   req.symbol = profile.symbol;
   req.volume = lots;
   req.price = entry_price;
   req.sl = sl_price;
   req.tp = tp_price;
   req.deviation = (ulong)profile.deviation_points;
   req.type_filling = out.filling;
   req.type = (side == MB_SIGNAL_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);

   if(!OrderCalcMargin(req.type,profile.symbol,req.volume,entry_price,out.margin_required))
     {
      out.reason = "ORDER_CALC_MARGIN_FAIL";
      return out;
     }

   if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) < out.margin_required)
     {
      out.reason = "MARGIN_REQUIRED_EXCEEDED";
      return out;
     }

   MqlTradeCheckResult chk;
   ZeroMemory(chk);
   if(!OrderCheck(req,chk))
     {
      out.order_check_retcode = (long)chk.retcode;
      out.reason = "ORDER_CHECK_FAIL";
      out.diag = out.diag + StringFormat(" order_check=%I64d",out.order_check_retcode);
      return out;
     }

   out.order_check_retcode = (long)chk.retcode;
   if(out.order_check_retcode != 0)
     {
      out.reason = "ORDER_CHECK_REJECT";
      out.diag = out.diag + StringFormat(" order_check=%I64d",out.order_check_retcode);
      return out;
     }

   out.allowed = true;
   out.reason = "OK";
   return out;
  }

#endif
