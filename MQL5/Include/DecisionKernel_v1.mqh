void DecisionKernelEvaluateV1(
   const KernelRuntimeSnapshotV1 &snapshot,
   const KernelSymbolProfileV1 &profile,
   const CircuitBreakerStateV2 &breaker,
   KernelDecisionResultV1 &decision
)
  {
   decision.action = KERNEL_ALLOW;
   decision.entry_allowed = true;
   decision.close_only = false;
   decision.halt = false;
   decision.reason_code = "NONE";
   decision.source = "KERNEL_LOCAL";
   decision.profile_loaded = profile.loaded;

   if(breaker.halt)
     {
      decision.action = KERNEL_HALT;
      decision.entry_allowed = false;
      decision.close_only = true;
      decision.halt = true;
      decision.reason_code = breaker.reason_code;
      return;
     }

   if(!profile.loaded)
     {
      decision.action = KERNEL_BLOCK;
      decision.entry_allowed = false;
      decision.reason_code = "PROFILE_NOT_LOADED";
      return;
     }

   if(profile.halt)
     {
      decision.action = KERNEL_HALT;
      decision.entry_allowed = false;
      decision.close_only = true;
      decision.halt = true;
      decision.reason_code = (profile.reason_code == "" ? "PROFILE_HALT" : profile.reason_code);
      return;
     }

   if(profile.close_only)
     {
      decision.action = KERNEL_CLOSE_ONLY;
      decision.entry_allowed = false;
      decision.close_only = true;
      decision.reason_code = (profile.reason_code == "" ? "PROFILE_CLOSE_ONLY" : profile.reason_code);
      return;
     }

   if(!profile.entry_allowed)
     {
      decision.action = KERNEL_BLOCK;
      decision.entry_allowed = false;
      decision.reason_code = (profile.reason_code == "" ? "PROFILE_ENTRY_BLOCKED" : profile.reason_code);
      return;
     }

   if(snapshot.ask_lt_bid)
     {
      decision.action = KERNEL_BLOCK;
      decision.entry_allowed = false;
      decision.reason_code = "ASK_LT_BID";
      return;
     }

   if(snapshot.tick_stale)
     {
      decision.action = KERNEL_BLOCK;
      decision.entry_allowed = false;
      decision.reason_code = "STALE_TICK";
      return;
     }

   if(profile.min_tick_rate_1s > 0 && snapshot.tick_rate_1s < profile.min_tick_rate_1s)
     {
      decision.action = KERNEL_BLOCK;
      decision.entry_allowed = false;
      decision.reason_code = "TICK_RATE_LOW";
      return;
     }

   double spread_now = MathMax(snapshot.spread_points, snapshot.spread_p95_points);
   if(profile.spread_cap_points > 0.0 && spread_now > profile.spread_cap_points)
     {
      decision.action = KERNEL_BLOCK;
      decision.entry_allowed = false;
      decision.reason_code = "SPREAD_CAP_EXCEEDED";
      return;
     }
  }
