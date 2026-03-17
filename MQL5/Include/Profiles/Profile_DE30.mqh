#ifndef PROFILE_DE30_INCLUDED
#define PROFILE_DE30_INCLUDED

#include "..\\Core\\MbRuntimeTypes.mqh"

void LoadProfileDE30(MbSymbolProfile &out)
  {
   MbSymbolProfileReset(out);
   out.symbol = "DE30.pro";
   out.trade_tf = PERIOD_M5;
   out.max_spread_points = 110.0;
   out.caution_spread_points = 70.0;
   out.deviation_points = 40;
   out.quotes_tolerance_pct = 0.10;
   out.max_tick_age_sec = 6;
   out.min_margin_free_pct = 145.0;
   out.hard_daily_loss_pct = 2.0;
   out.hard_session_loss_pct = 1.0;
   out.min_seconds_between_entries = 90;
   out.session_profile = "INDEX_EU";
   out.trade_window_start_hour = 12;
   out.trade_window_end_hour = 14;
   out.friday_cutoff_enabled = true;
   out.friday_cutoff_hour = 17;
   out.kill_switch_required = true;
   out.kill_switch_token_name = "oandakey_de30.token";
   out.kill_switch_max_age_sec = 120;
   out.max_price_requests_per_sec = 6;
   out.max_price_requests_per_min = 90;
   out.price_requests_eco_threshold_pct = 80;
   out.max_market_orders_per_sec = 1;
   out.max_market_orders_per_min = 6;
   out.market_orders_eco_threshold_pct = 80;
  }

#endif


