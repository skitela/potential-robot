#ifndef PROFILE_GBPJPY_INCLUDED
#define PROFILE_GBPJPY_INCLUDED

#include "..\\Core\\MbRuntimeTypes.mqh"

void LoadProfileGBPJPY(MbSymbolProfile &out)
  {
   MbSymbolProfileReset(out);
   out.symbol = "GBPJPY";
   out.trade_tf = PERIOD_M5;
   out.max_spread_points = 48.0;
   out.caution_spread_points = 36.0;
   out.deviation_points = 20;
   out.quotes_tolerance_pct = 0.10;
   out.max_tick_age_sec = 5;
   out.min_margin_free_pct = 120.0;
   out.hard_daily_loss_pct = 2.0;
   out.hard_session_loss_pct = 1.0;
   out.min_seconds_between_entries = 60;
   out.session_profile = "FX_CROSS";
   out.trade_window_start_hour = 7;
   out.trade_window_end_hour = 12;
   out.friday_cutoff_enabled = true;
   out.friday_cutoff_hour = 16;
   out.kill_switch_required = true;
   out.kill_switch_token_name = "oandakey_gbpjpy.token";
   out.kill_switch_max_age_sec = 120;
  }

#endif
