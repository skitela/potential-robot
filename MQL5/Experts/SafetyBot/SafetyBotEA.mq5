//+------------------------------------------------------------------+
//|                                                  SafetyBotEA.mq5 |
//|   Legacy placeholder retained only to prevent accidental usage.  |
//+------------------------------------------------------------------+
#property copyright "OANDA_MT5_SYSTEM"
#property link      "local"
#property version   "2.00"
#property description "DEPRECATED placeholder. Use HybridAgent.mq5 as the active EA."

input bool InpShowDeprecationAlert = true;

int OnInit()
{
   if (InpShowDeprecationAlert)
   {
      Alert("SafetyBotEA is deprecated. Attach HybridAgent.mq5 instead.");
   }
   Print("SafetyBotEA DEPRECATED: initialization blocked. Use HybridAgent.mq5.");
   return(INIT_FAILED);
}

void OnDeinit(const int reason)
{
   Print("SafetyBotEA DEPRECATED: deinit reason=", reason);
}

void OnTick()
{
   // Intentionally empty. This EA is not part of the active architecture.
}

