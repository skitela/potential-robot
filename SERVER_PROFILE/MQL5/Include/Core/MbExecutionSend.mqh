#ifndef MB_EXECUTION_SEND_INCLUDED
#define MB_EXECUTION_SEND_INCLUDED

#include <Trade/Trade.mqh>
#include "MbRuntimeTypes.mqh"
#include "MbExecutionCommon.mqh"

bool MbHasPosition(const string symbol,const ulong magic)
  {
   if(PositionSelect(symbol))
     {
      if((ulong)PositionGetInteger(POSITION_MAGIC) == magic)
         return true;
     }

   for(int i = PositionsTotal() - 1; i >= 0; --i)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != magic)
         continue;
      return true;
     }
   return false;
  }

MbExecutionResult MbExecuteMarketOrder(
   CTrade &trade,
   const MbSymbolProfile &profile,
   const MbSignalSide side,
   const double lots,
   const double entry_price,
   const double sl_price,
   const double tp_price,
   const string comment
)
  {
   MbExecutionResult out;
   MbExecutionResultReset(out);

   for(int attempt = 0; attempt < 2; attempt++)
     {
      uint send_t0 = GetTickCount();
      bool ok = false;
      if(side == MB_SIGNAL_BUY)
         ok = trade.Buy(lots,profile.symbol,entry_price,sl_price,tp_price,comment);
      else if(side == MB_SIGNAL_SELL)
         ok = trade.Sell(lots,profile.symbol,entry_price,sl_price,tp_price,comment);
      else
        {
         out.reason = "NO_SIGNAL";
         return out;
        }

      long retcode = (long)trade.ResultRetcode();
      out.retcode = retcode;
      out.retcode_name = MbClassifyRetcode(retcode);
      out.executed_price = trade.ResultPrice();
      out.retries_used = attempt;
      out.order_send_ms = (long)(GetTickCount() - send_t0);

      if(ok && (retcode == 10008 || retcode == 10009 || retcode == 10010))
        {
         out.ok = true;
         out.reason = "ORDER_SENT";
         if(out.executed_price > 0.0 && entry_price > 0.0)
            out.slippage_points = MathAbs(out.executed_price - entry_price) / _Point;
         return out;
        }

      if(!MbShouldRetryRetcode(retcode))
        {
         out.reason = out.retcode_name;
         return out;
        }

      if(attempt < 1)
        {
         int retry_delay_ms = MbRetryDelayMs(retcode);
         if(retry_delay_ms > 0)
            Sleep(retry_delay_ms);
        }
     }

   out.reason = out.retcode_name;
   if(out.executed_price > 0.0 && entry_price > 0.0)
      out.slippage_points = MathAbs(out.executed_price - entry_price) / _Point;
   return out;
  }

#endif
