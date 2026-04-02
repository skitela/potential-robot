#ifndef MB_RATE_GUARD_INCLUDED
#define MB_RATE_GUARD_INCLUDED

#include "MbRuntimeTypes.mqh"

void MbMarkPriceProbe(MbRuntimeState &state)
  {
   datetime now_ts = TimeCurrent();
   if(state.price_budget_sec_anchor <= 0 || now_ts != state.price_budget_sec_anchor)
     {
      state.price_budget_sec_anchor = now_ts;
      state.price_requests_sec = 0;
     }
   if(state.price_budget_min_anchor <= 0 || (now_ts - state.price_budget_min_anchor) >= 60)
     {
      state.price_budget_min_anchor = now_ts;
      state.price_requests_min = 0;
     }
   state.price_requests_sec++;
   state.price_requests_min++;
  }

void MbMarkOrderSend(MbRuntimeState &state)
  {
   datetime now_ts = TimeCurrent();
   state.last_trade_attempt = now_ts;
   if(state.order_budget_sec_anchor <= 0 || now_ts != state.order_budget_sec_anchor)
     {
      state.order_budget_sec_anchor = now_ts;
      state.order_requests_sec = 0;
     }
   if(state.order_budget_min_anchor <= 0 || (now_ts - state.order_budget_min_anchor) >= 60)
     {
      state.order_budget_min_anchor = now_ts;
      state.order_requests_min = 0;
     }
   state.order_requests_sec++;
   state.order_requests_min++;
  }

void MbRefreshRateGuardWindows(MbRuntimeState &state)
  {
   datetime now_ts = TimeCurrent();

   if(state.price_budget_sec_anchor <= 0 || now_ts != state.price_budget_sec_anchor)
     {
      state.price_budget_sec_anchor = now_ts;
      state.price_requests_sec = 0;
     }
   if(state.price_budget_min_anchor <= 0 || (now_ts - state.price_budget_min_anchor) >= 60)
     {
      state.price_budget_min_anchor = now_ts;
      state.price_requests_min = 0;
     }

   if(state.order_budget_sec_anchor <= 0 || now_ts != state.order_budget_sec_anchor)
     {
      state.order_budget_sec_anchor = now_ts;
      state.order_requests_sec = 0;
     }
   if(state.order_budget_min_anchor <= 0 || (now_ts - state.order_budget_min_anchor) >= 60)
     {
      state.order_budget_min_anchor = now_ts;
      state.order_requests_min = 0;
     }
  }

void MbRateGuardEvaluate(const MbSymbolProfile &profile,const MbRuntimeState &state,MbRateGuardState &out)
  {
   MbRateGuardStateReset(out);

   if(state.order_requests_sec > profile.max_market_orders_per_sec || state.order_requests_min > profile.max_market_orders_per_min)
     {
      out.allowed = false;
      out.halt = true;
      out.reason_code = "BROKER_ORDER_RATE_LIMIT";
      return;
     }

   if(state.price_requests_sec > profile.max_price_requests_per_sec || state.price_requests_min > profile.max_price_requests_per_min)
     {
      out.allowed = false;
      out.halt = true;
      out.reason_code = "BROKER_PRICE_RATE_LIMIT";
      return;
     }

   int price_sec_eco = (profile.max_price_requests_per_sec * profile.price_requests_eco_threshold_pct) / 100;
   int price_min_eco = (profile.max_price_requests_per_min * profile.price_requests_eco_threshold_pct) / 100;
   int order_sec_eco = (profile.max_market_orders_per_sec * profile.market_orders_eco_threshold_pct) / 100;
   int order_min_eco = (profile.max_market_orders_per_min * profile.market_orders_eco_threshold_pct) / 100;

   if(state.price_requests_sec >= price_sec_eco || state.price_requests_min >= price_min_eco)
     {
      out.caution_mode = true;
      out.reason_code = "BROKER_PRICE_RATE_ECO";
     }
   if(state.order_requests_sec >= order_sec_eco || state.order_requests_min >= order_min_eco)
     {
      out.caution_mode = true;
      out.reason_code = "BROKER_ORDER_RATE_ECO";
     }
  }

#endif
