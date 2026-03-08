struct StateCacheV1
  {
   double spread_points;
   double spread_mean_points;
   double spread_p95_points;
   double tick_gap_sec;
   double price_jump_points;
   int    tick_rate_1s;
   bool   burst_flag;
   bool   ask_lt_bid;
   bool   tick_stale;
   bool   valid;
  };

void StateCacheResetV1(StateCacheV1 &cache)
  {
   cache.spread_points = 0.0;
   cache.spread_mean_points = 0.0;
   cache.spread_p95_points = 0.0;
   cache.tick_gap_sec = 0.0;
   cache.price_jump_points = 0.0;
   cache.tick_rate_1s = 0;
   cache.burst_flag = false;
   cache.ask_lt_bid = false;
   cache.tick_stale = false;
   cache.valid = false;
  }

void StateCacheUpdateFromGlobalsV1(StateCacheV1 &cache)
  {
   cache.spread_points = 0.0;
   if(G_MicroSpreadCount > 0)
      cache.spread_points = G_MicroSpreadRing[(G_MicroSpreadPos + ArraySize(G_MicroSpreadRing) - 1) % ArraySize(G_MicroSpreadRing)];
   cache.spread_mean_points = MicroSpreadMeanPoints();
   cache.spread_p95_points = MicroSpreadP95Points();
   cache.tick_gap_sec = G_MicroTickGapSec;
   cache.price_jump_points = G_MicroPriceJumpPoints;
   cache.tick_rate_1s = G_MicroTickRate1s;
   cache.burst_flag = G_MicroBurstFlag;
   cache.ask_lt_bid = G_MicroAskLtBid;
   cache.tick_stale = (cache.tick_gap_sec > ((double)InpP0TickStaleMs / 1000.0));
   cache.valid = true;
  }

void StateCacheBuildSnapshotV1(
   const string symbol_name,
   const string group_name,
   const bool has_open_position,
   const StateCacheV1 &cache,
   KernelRuntimeSnapshotV1 &snapshot
)
  {
   snapshot.symbol = symbol_name;
   snapshot.symbol_base = SymbolBaseUpper(symbol_name);
   snapshot.group_name = group_name;
   snapshot.spread_points = cache.spread_points;
   snapshot.spread_mean_points = cache.spread_mean_points;
   snapshot.spread_p95_points = cache.spread_p95_points;
   snapshot.tick_gap_sec = cache.tick_gap_sec;
   snapshot.price_jump_points = cache.price_jump_points;
   snapshot.tick_rate_1s = cache.tick_rate_1s;
   snapshot.burst_flag = cache.burst_flag;
   snapshot.ask_lt_bid = cache.ask_lt_bid;
   snapshot.tick_stale = cache.tick_stale;
   snapshot.has_open_position = has_open_position;
   snapshot.snapshot_valid = cache.valid;
  }
