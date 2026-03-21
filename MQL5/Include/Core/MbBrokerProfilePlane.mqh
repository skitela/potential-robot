#ifndef MB_BROKER_PROFILE_PLANE_INCLUDED
#define MB_BROKER_PROFILE_PLANE_INCLUDED

#include "MbRuntimeTypes.mqh"
#include "MbStorage.mqh"
#include "MbStatusPlane.mqh"

string MbFillingModeLabel(const ENUM_ORDER_TYPE_FILLING filling)
  {
   switch(filling)
     {
      case ORDER_FILLING_FOK: return "FOK";
      case ORDER_FILLING_IOC: return "IOC";
      case ORDER_FILLING_RETURN: return "RETURN";
     }
   return "UNKNOWN";
  }

void MbFlushBrokerProfile(
   const MbSymbolProfile &profile,
   const MbRuntimeState &state,
   const MbMarketSnapshot &snapshot
)
  {
   int h = FileOpen(MbStateFilePath(profile.symbol,"broker_profile.json"), FILE_COMMON | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;

   string payload = StringFormat(
      "{\"schema_version\":\"1.1\",\"symbol\":\"%s\",\"session_profile\":\"%s\",\"terminal_connected\":%s,\"terminal_ping_ms\":%I64d,\"trade_permissions_ok\":%s,\"raw_trade_permissions_ok\":%s,\"paper_runtime_override_active\":%s,\"term_trade_allowed\":%s,\"mql_trade_allowed\":%s,\"account_trade_allowed\":%s,\"account_trade_mode\":%I64d,\"symbol_trade_mode\":%I64d,\"stops_level\":%d,\"freeze_level\":%d,\"spread_points\":%.2f,\"tick_time_msc\":%I64d,\"tick_age_ms\":%I64d,\"tick_value\":%.6f,\"tick_size\":%.8f,\"volume_min\":%.2f,\"volume_step\":%.2f,\"volume_max\":%.2f,\"cache_valid\":%s,\"runtime_mode\":\"%s\",\"force_flatten\":%s,\"allowed_direction\":\"%s\",\"cooldown_left_sec\":%d,\"incident_pressure\":%d,\"ts_utc\":%I64d}",
      profile.symbol,
      profile.session_profile,
      MbJsonBool(snapshot.terminal_connected),
      snapshot.terminal_ping_last_ms,
      MbJsonBool(snapshot.trade_permissions_ok),
      MbJsonBool(snapshot.raw_trade_permissions_ok),
      MbJsonBool(snapshot.paper_runtime_override_active),
      MbJsonBool(snapshot.term_trade_allowed),
      MbJsonBool(snapshot.mql_trade_allowed),
      MbJsonBool(snapshot.account_trade_allowed),
      snapshot.account_trade_mode,
      snapshot.symbol_trade_mode,
      snapshot.stops_level,
      snapshot.freeze_level,
      snapshot.spread_points,
      snapshot.tick_time_msc,
      snapshot.tick_age_ms,
      snapshot.tick_value,
      snapshot.tick_size,
      snapshot.vol_min,
      snapshot.vol_step,
      snapshot.vol_max,
      MbJsonBool(snapshot.valid),
      MbRuntimeModeLabelForState(state),
      MbJsonBool(state.force_flatten),
      MbResolveAllowedDirectionForState(state),
      MbCooldownLeftSec(state),
      MbIncidentPressure(state),
      (long)TimeCurrent()
   );
   FileWriteString(h,payload);
   FileClose(h);
  }

#endif
