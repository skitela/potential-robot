#pragma once

struct MbExecutionSnapshot
{
   string   symbol_alias;
   string   broker_symbol;
   double   spread_points;
   double   tick_size;
   double   tick_value;
   double   terminal_ping_ms;
   double   local_latency_us_avg;
   double   local_latency_us_max;
   double   runtime_latency_us;
   datetime ts_server;
   bool     broker_session_open;
   bool     server_ping_contract_enabled;
};
