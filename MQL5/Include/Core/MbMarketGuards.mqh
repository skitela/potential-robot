#ifndef MB_MARKET_GUARDS_INCLUDED
#define MB_MARKET_GUARDS_INCLUDED

#include "MbRuntimeTypes.mqh"
#include "MbCapitalRiskContract.mqh"
#include "MbSessionGuard.mqh"

enum MbGuardVerdict
  {
   MB_GUARD_OK = 0,
   MB_GUARD_BLOCK = 1,
   MB_GUARD_HALT = 2
  };

bool MbEntryFrequencyOk(const MbSymbolProfile &profile,const MbRuntimeState &state,string &reason_code)
  {
   if(state.last_trade_attempt > 0 && (TimeCurrent() - state.last_trade_attempt) < profile.min_seconds_between_entries)
     {
      reason_code = "ENTRY_COOLDOWN";
      return false;
     }
   reason_code = "OK";
   return true;
  }

bool MbLossCapsOk(const MbSymbolProfile &profile,const MbMarketSnapshot &snapshot,MbRuntimeState &state,string &reason_code)
  {
   if(snapshot.equity <= 0.0)
     {
      reason_code = "EQUITY_INVALID";
      return false;
     }

   bool paper_mode = (snapshot.paper_runtime_override_active || state.paper_mode_active);
   MbCapitalRiskContract contract;
   MbResolveCapitalRiskContract(paper_mode,contract);
   MbCapitalRiskRefreshState(paper_mode,contract,snapshot,state);

   if(MbCapitalRiskCoreFloorBreached(paper_mode,state,snapshot))
     {
      reason_code = "CORE_CAPITAL_FLOOR";
      return false;
     }

   if(state.equity_anchor_day > 0.0)
     {
      double dd_day_pct = (paper_mode
                           ? MbCapitalRiskLossPctFromRealized(state.equity_anchor_day,state.realized_pnl_day)
                           : MbCapitalRiskLossPctFromEquity(state.equity_anchor_day,snapshot.equity));
      if(dd_day_pct >= MbCapitalRiskResolveHardDailyLossPct(paper_mode,contract,state))
        {
         reason_code = "DAILY_LOSS_HARD";
         return false;
        }
     }

   if(state.equity_anchor_session > 0.0)
     {
      double dd_session_pct = (paper_mode
                               ? MbCapitalRiskLossPctFromRealized(state.equity_anchor_session,state.realized_pnl_session)
                               : MbCapitalRiskLossPctFromEquity(state.equity_anchor_session,snapshot.equity));
      if(dd_session_pct >= MbCapitalRiskResolveHardSessionLossPct(paper_mode,contract,state))
        {
         reason_code = "SESSION_LOSS_HARD";
         return false;
        }
     }

   if(state.equity_anchor_day > 0.0)
     {
      double symbol_loss_pct = MbCapitalRiskLossPctFromRealized(state.equity_anchor_day,state.realized_pnl_day);
      if(symbol_loss_pct >= contract.symbol_hard_daily_loss_pct)
        {
         reason_code = "SYMBOL_DAILY_LOSS_HARD";
         return false;
        }
     }

   reason_code = "OK";
   return true;
  }

bool MbMarginGuardOk(const MbSymbolProfile &profile,const MbMarketSnapshot &snapshot,string &reason_code)
  {
   if(snapshot.equity <= 0.0)
     {
      reason_code = "EQUITY_INVALID";
      return false;
     }

   double margin_free_pct = 100.0 * MathMax(0.0,snapshot.margin_free) / snapshot.equity;
   if(margin_free_pct < profile.min_margin_free_pct)
     {
      reason_code = "MARGIN_FREE_LOW";
      return false;
     }

   reason_code = "OK";
   return true;
  }

datetime MbResolveSessionAnchorTs(const MbSymbolProfile &profile,const datetime now_ts)
  {
   MqlDateTime tm;
   TimeToStruct(now_ts,tm);
   tm.hour = profile.trade_window_start_hour;
   tm.min = 0;
   tm.sec = 0;
   datetime anchor = StructToTime(tm);
   if(now_ts < anchor)
      anchor -= 24 * 60 * 60;
   return anchor;
  }

void MbRefreshRiskAnchors(const MbSymbolProfile &profile,const MbMarketSnapshot &snapshot,MbRuntimeState &state)
  {
   if(!snapshot.valid || snapshot.equity <= 0.0)
      return;

   bool paper_mode = (snapshot.paper_runtime_override_active || state.paper_mode_active);
   MbCapitalRiskContract contract;
   MbResolveCapitalRiskContract(paper_mode,contract);
   MbCapitalRiskRefreshState(paper_mode,contract,snapshot,state);

   datetime now_ts = TimeCurrent();

   MqlDateTime now_tm;
   TimeToStruct(now_ts,now_tm);
   MqlDateTime day_tm;
   day_tm = now_tm;
   day_tm.hour = 0;
   day_tm.min = 0;
   day_tm.sec = 0;
   datetime current_day_anchor = StructToTime(day_tm);
   if(state.day_anchor != current_day_anchor)
     {
      state.day_anchor = current_day_anchor;
      state.equity_anchor_day = snapshot.equity;
      state.realized_pnl_day = 0.0;
     }

   datetime current_session_anchor = MbResolveSessionAnchorTs(profile,now_ts);
   if(state.session_anchor != current_session_anchor)
     {
      state.session_anchor = current_session_anchor;
      state.equity_anchor_session = snapshot.equity;
      state.realized_pnl_session = 0.0;
     }
  }

MbGuardVerdict MbEvaluateMarketEntryGuards(
   const MbSymbolProfile &profile,
   const MbMarketSnapshot &snapshot,
   MbRuntimeState &state,
   string &reason_code
)
  {
   reason_code = "OK";
   MbRefreshRiskAnchors(profile,snapshot,state);

   if(!MbInTradeWindow(profile))
     {
      reason_code = "OUTSIDE_TRADE_WINDOW";
      return MB_GUARD_BLOCK;
     }

   if(state.cooldown_until > 0 && TimeCurrent() < state.cooldown_until)
     {
      reason_code = "SELF_HEAL_COOLDOWN";
      return MB_GUARD_BLOCK;
     }

   if(!snapshot.valid)
     {
      reason_code = "SNAPSHOT_INVALID";
      return MB_GUARD_BLOCK;
     }

   if(!snapshot.terminal_connected)
     {
      reason_code = "TERMINAL_DISCONNECTED";
      return MB_GUARD_HALT;
     }

   if(snapshot.bid <= 0.0 || snapshot.ask <= 0.0 || snapshot.ask < snapshot.bid)
     {
      reason_code = "BROKEN_TICK";
      return MB_GUARD_BLOCK;
     }

   if(snapshot.spread_points > profile.max_spread_points)
     {
      reason_code = "SPREAD_CAP_EXCEEDED";
      return MB_GUARD_BLOCK;
     }

   if(snapshot.refreshed_at <= 0 || (TimeCurrent() - snapshot.refreshed_at) > profile.max_tick_age_sec)
     {
      reason_code = "CACHE_STALE";
      return MB_GUARD_BLOCK;
     }

   if(snapshot.tick_age_ms > ((long)profile.max_tick_age_sec * 1000))
     {
      reason_code = "TICK_STALE";
      return MB_GUARD_BLOCK;
     }

   if(!snapshot.trade_permissions_ok)
     {
      reason_code = "TRADE_DISABLED";
      return MB_GUARD_HALT;
     }

   if(!MbLossCapsOk(profile,snapshot,state,reason_code))
      return MB_GUARD_HALT;

   if(!MbMarginGuardOk(profile,snapshot,reason_code))
      return MB_GUARD_HALT;

   if(!MbEntryFrequencyOk(profile,state,reason_code))
      return MB_GUARD_BLOCK;

   bool paper_mode = (snapshot.paper_runtime_override_active || state.paper_mode_active);
   if(snapshot.terminal_ping_last_us >= 100000)
      state.caution_mode = true;
   if(!paper_mode && snapshot.terminal_ping_last_us >= 180000)
     {
      reason_code = "PING_TOO_HIGH";
      return MB_GUARD_BLOCK;
     }

   if(snapshot.spread_points > profile.caution_spread_points)
     {
      state.caution_mode = true;
      state.spread_anomaly_streak++;
     }
   else
     {
      state.caution_mode = false;
      state.spread_anomaly_streak = 0;
     }

   return MB_GUARD_OK;
  }

#endif
