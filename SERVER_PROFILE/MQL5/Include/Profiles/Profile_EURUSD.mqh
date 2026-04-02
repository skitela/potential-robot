#ifndef PROFILE_EURUSD_INCLUDED
#define PROFILE_EURUSD_INCLUDED

#include "..\\Core\\MbRuntimeTypes.mqh"

void LoadProfileEURUSD(MbSymbolProfile &out)
  {
   MbSymbolProfileReset(out);
  MbEnableBrokerMetadataImport(out);
   out.symbol = "EURUSD";
   out.trade_tf = PERIOD_M5;
   out.max_spread_points = 24.0;
   out.caution_spread_points = 18.0;
   out.deviation_points = 20;
   out.quotes_tolerance_pct = 0.10;
   out.max_tick_age_sec = 5;
   out.min_margin_free_pct = 120.0;
   out.hard_daily_loss_pct = 2.0;
   out.hard_session_loss_pct = 1.0;
   out.min_seconds_between_entries = 60;
   out.session_profile = "FX_MAIN";
   out.trade_window_start_hour = 8;
   out.trade_window_end_hour = 11;
   out.friday_cutoff_enabled = true;
   out.friday_cutoff_hour = 16;
   out.kill_switch_required = true;
   out.kill_switch_token_name = "oandakey_eurusd.token";
   out.kill_switch_max_age_sec = 120;
   out.max_price_requests_per_sec = 8;
   out.max_price_requests_per_min = 120;
   out.price_requests_eco_threshold_pct = 80;
   out.max_market_orders_per_sec = 2;
   out.max_market_orders_per_min = 12;
   out.market_orders_eco_threshold_pct = 80;
  }

#endif
