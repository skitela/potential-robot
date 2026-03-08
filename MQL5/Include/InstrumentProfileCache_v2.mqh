#define KERNEL_PROFILE_CACHE_CAP 128

string G_KernelProfileSymbols[KERNEL_PROFILE_CACHE_CAP];
KernelSymbolProfileV1 G_KernelProfileRows[KERNEL_PROFILE_CACHE_CAP];
int G_KernelProfileCount = 0;

void InstrumentProfileCacheResetV2()
  {
   G_KernelProfileCount = 0;
   for(int i = 0; i < KERNEL_PROFILE_CACHE_CAP; i++)
     {
      G_KernelProfileSymbols[i] = "";
      G_KernelProfileRows[i].symbol = "";
      G_KernelProfileRows[i].symbol_base = "";
      G_KernelProfileRows[i].group_name = "";
      G_KernelProfileRows[i].entry_allowed = true;
      G_KernelProfileRows[i].close_only = false;
      G_KernelProfileRows[i].halt = false;
      G_KernelProfileRows[i].reason_code = "NONE";
      G_KernelProfileRows[i].spread_cap_points = 0.0;
      G_KernelProfileRows[i].max_latency_ms = 0.0;
      G_KernelProfileRows[i].min_tick_rate_1s = 0;
      G_KernelProfileRows[i].min_liquidity_score = 0.0;
      G_KernelProfileRows[i].min_tradeability_score = 0.0;
      G_KernelProfileRows[i].min_setup_quality_score = 0.0;
      G_KernelProfileRows[i].loaded = false;
     }
  }

int InstrumentProfileCacheFindIndexV2(const string symbol_name)
  {
   string symbol_base = SymbolBaseUpper(symbol_name);
   for(int i = 0; i < G_KernelProfileCount; i++)
     {
      if(G_KernelProfileSymbols[i] == symbol_base)
         return i;
     }
   return -1;
  }

bool InstrumentProfileCacheUpsertV2(const KernelSymbolProfileV1 &profile)
  {
   string symbol_base = SymbolBaseUpper(profile.symbol);
   if(symbol_base == "")
      return false;

   int idx = InstrumentProfileCacheFindIndexV2(symbol_base);
   if(idx < 0)
     {
      if(G_KernelProfileCount >= KERNEL_PROFILE_CACHE_CAP)
         return false;
      idx = G_KernelProfileCount;
      G_KernelProfileCount++;
     }

   G_KernelProfileSymbols[idx] = symbol_base;
   G_KernelProfileRows[idx] = profile;
   G_KernelProfileRows[idx].symbol_base = symbol_base;
   G_KernelProfileRows[idx].loaded = true;
   return true;
  }

bool InstrumentProfileCacheGetV2(const string symbol_name, KernelSymbolProfileV1 &profile)
  {
   int idx = InstrumentProfileCacheFindIndexV2(symbol_name);
   if(idx < 0)
      return false;
   profile = G_KernelProfileRows[idx];
   return bool(profile.loaded);
  }
