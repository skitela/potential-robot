#ifndef MB_MARKET_STATE_INCLUDED
#define MB_MARKET_STATE_INCLUDED

#include "MbRuntimeTypes.mqh"

void MbRefreshMarketSnapshot(const MbSymbolProfile &profile,MbMarketSnapshot &snapshot)
  {
   MqlTick tick;
   MbMarketSnapshotReset(snapshot);
   snapshot.terminal_connected = (TerminalInfoInteger(TERMINAL_CONNECTED) != 0);
   snapshot.terminal_ping_last_us = MathMax(0,(long)TerminalInfoInteger(TERMINAL_PING_LAST));
   snapshot.terminal_ping_last_ms = (long)MathRound((double)snapshot.terminal_ping_last_us / 1000.0);
   snapshot.term_trade_allowed = (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) != 0);
   snapshot.mql_trade_allowed = (MQLInfoInteger(MQL_TRADE_ALLOWED) != 0);
   snapshot.account_trade_allowed = (AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) != 0);
   snapshot.account_trade_mode = (long)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   snapshot.symbol_trade_mode = (long)SymbolInfoInteger(profile.symbol,SYMBOL_TRADE_MODE);
   snapshot.stops_level = (int)SymbolInfoInteger(profile.symbol,SYMBOL_TRADE_STOPS_LEVEL);
   snapshot.freeze_level = (int)SymbolInfoInteger(profile.symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   snapshot.margin_free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   snapshot.equity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(SymbolInfoTick(profile.symbol,tick))
     {
      snapshot.bid = tick.bid;
      snapshot.ask = tick.ask;
      snapshot.tick_time_msc = (long)tick.time_msc;
      snapshot.tick_age_ms = MathMax(0,(long)(TimeCurrent() * 1000) - snapshot.tick_time_msc);
     }

   if(snapshot.bid > 0.0 && snapshot.ask > 0.0 && snapshot.ask >= snapshot.bid)
      snapshot.spread_points = (snapshot.ask - snapshot.bid) / _Point;

   SymbolInfoDouble(profile.symbol,SYMBOL_TRADE_TICK_VALUE,snapshot.tick_value);
   SymbolInfoDouble(profile.symbol,SYMBOL_TRADE_TICK_SIZE,snapshot.tick_size);
   SymbolInfoDouble(profile.symbol,SYMBOL_VOLUME_STEP,snapshot.vol_step);
   SymbolInfoDouble(profile.symbol,SYMBOL_VOLUME_MIN,snapshot.vol_min);
   SymbolInfoDouble(profile.symbol,SYMBOL_VOLUME_MAX,snapshot.vol_max);

   snapshot.raw_trade_permissions_ok = (snapshot.term_trade_allowed && snapshot.mql_trade_allowed && snapshot.account_trade_allowed);
   snapshot.trade_permissions_ok = snapshot.raw_trade_permissions_ok;
   snapshot.diag = StringFormat(
      "conn=%d ping_ms=%I64d term=%d mql=%d acc=%d raw=%d acc_mode=%I64d sym_mode=%I64d stops=%d freeze=%d tick_age_ms=%I64d vol_min=%.2f step=%.2f",
      (int)snapshot.terminal_connected,
      snapshot.terminal_ping_last_ms,
      (int)snapshot.term_trade_allowed,
      (int)snapshot.mql_trade_allowed,
      (int)snapshot.account_trade_allowed,
      (int)snapshot.raw_trade_permissions_ok,
      snapshot.account_trade_mode,
      snapshot.symbol_trade_mode,
      snapshot.stops_level,
      snapshot.freeze_level,
      snapshot.tick_age_ms,
      snapshot.vol_min,
      snapshot.vol_step
   );
   snapshot.refreshed_at = TimeCurrent();
   snapshot.valid = true;
  }

void MbRefreshTickSnapshot(const MbSymbolProfile &profile,MbMarketSnapshot &snapshot)
  {
   MqlTick tick;
   if(!SymbolInfoTick(profile.symbol,tick))
      return;
   snapshot.bid = tick.bid;
   snapshot.ask = tick.ask;
   snapshot.tick_time_msc = (long)tick.time_msc;
   snapshot.tick_age_ms = MathMax(0,(long)(TimeCurrent() * 1000) - snapshot.tick_time_msc);
   snapshot.spread_points = 0.0;
   if(snapshot.bid > 0.0 && snapshot.ask > 0.0 && snapshot.ask >= snapshot.bid)
      snapshot.spread_points = (snapshot.ask - snapshot.bid) / _Point;
   snapshot.refreshed_at = TimeCurrent();
   snapshot.valid = true;
  }

bool MbTickFreshEnough(const MbMarketSnapshot &snapshot,const int max_age_sec)
  {
   if(!snapshot.valid)
      return false;
   return (snapshot.tick_age_ms <= (long)(MathMax(1,max_age_sec) * 1000));
  }

bool MbSpreadWithinCap(const MbMarketSnapshot &snapshot,const double max_spread_points)
  {
   if(!snapshot.valid)
      return false;
   return (snapshot.spread_points <= max_spread_points);
  }

#endif
