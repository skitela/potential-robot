struct CircuitBreakerStateV2
  {
   bool   close_only;
   bool   halt;
   string reason_code;
  };

void CircuitBreakerEvaluateV2(CircuitBreakerStateV2 &state)
  {
   state.close_only = false;
   state.halt = false;
   state.reason_code = "NONE";

   if(G_KernelConfigFailSafe)
     {
      state.halt = true;
      state.reason_code = (G_KernelConfigLastError == "" ? "KERNEL_CONFIG_FAILSAFE" : G_KernelConfigLastError);
      return;
     }

   if(G_PolicyFailSafeNoTrade)
     {
      state.halt = true;
      state.reason_code = (G_PolicyLastError == "" ? "POLICY_RUNTIME_FAILSAFE" : G_PolicyLastError);
      return;
     }

   if(G_IsFailSafeActive)
     {
      state.halt = true;
      state.reason_code = "PYTHON_TIMEOUT_FAILSAFE";
      return;
     }
  }
