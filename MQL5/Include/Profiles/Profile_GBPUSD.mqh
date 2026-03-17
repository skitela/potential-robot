#ifndef PROFILE_GBPUSD_INCLUDED
#define PROFILE_GBPUSD_INCLUDED

#include "..\\Core\\MbRuntimeTypes.mqh"

void LoadProfileGBPUSD(MbSymbolProfile &out)
  {
   MbSymbolProfileReset(out);
   out.symbol = "GBPUSD";
   out.trade_tf = PERIOD_M5;
   out.max_spread_points = 25.0;
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
   out.kill_switch_token_name = "oandakey_gbpusd.token";
   out.kill_switch_max_age_sec = 120;
  }

#endif
