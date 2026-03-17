#ifndef MB_EXECUTION_PRECHECK_INCLUDED
#define MB_EXECUTION_PRECHECK_INCLUDED

#include "MbRuntimeTypes.mqh"
#include "MbExecutionCommon.mqh"

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
