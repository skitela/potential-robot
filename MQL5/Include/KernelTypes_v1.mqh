// Lightweight kernel contracts for local shadow evaluation on MQL5 side.

enum KernelDecisionActionV1
  {
   KERNEL_ALLOW = 0,
   KERNEL_BLOCK = 1,
   KERNEL_CLOSE_ONLY = 2,
   KERNEL_HALT = 3
  };

struct KernelSymbolProfileV1
  {
   string symbol;
   string symbol_base;
   string group_name;
   bool   entry_allowed;
   bool   close_only;
   bool   halt;
   string reason_code;
   double spread_cap_points;
   double max_latency_ms;
   int    min_tick_rate_1s;
   double min_liquidity_score;
   double min_tradeability_score;
   double min_setup_quality_score;
   bool   loaded;
  };

struct KernelRuntimeSnapshotV1
  {
   string symbol;
   string symbol_base;
   string group_name;
   double spread_points;
   double spread_mean_points;
   double spread_p95_points;
   double tick_gap_sec;
   double price_jump_points;
   int    tick_rate_1s;
   bool   burst_flag;
   bool   ask_lt_bid;
   bool   tick_stale;
   bool   has_open_position;
   bool   snapshot_valid;
  };

struct KernelDecisionResultV1
  {
   int    action;
   bool   entry_allowed;
   bool   close_only;
   bool   halt;
   string reason_code;
   string source;
   bool   profile_loaded;
  };

string KernelDecisionActionToString(const int action)
  {
   if(action == KERNEL_BLOCK)
      return "BLOCK";
   if(action == KERNEL_CLOSE_ONLY)
      return "CLOSE_ONLY";
   if(action == KERNEL_HALT)
      return "HALT";
   return "ALLOW";
  }
