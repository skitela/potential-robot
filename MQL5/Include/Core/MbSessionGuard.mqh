#ifndef MB_SESSION_GUARD_INCLUDED
#define MB_SESSION_GUARD_INCLUDED

#include "MbRuntimeTypes.mqh"

bool MbInTradeWindow(const MbSymbolProfile &profile)
  {
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(),tm);
   if(profile.friday_cutoff_enabled && tm.day_of_week == 5 && tm.hour >= profile.friday_cutoff_hour)
      return false;
   if(profile.trade_window_start_hour <= profile.trade_window_end_hour)
      return (tm.hour >= profile.trade_window_start_hour && tm.hour <= profile.trade_window_end_hour);
   return (tm.hour >= profile.trade_window_start_hour || tm.hour <= profile.trade_window_end_hour);
  }

string MbSessionLabel(const MbSymbolProfile &profile)
  {
   return profile.session_profile;
  }

#endif
