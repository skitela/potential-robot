#property strict
#property script_show_inputs

#include "..\\Include\\Core\\MbTuningCoordinator.mqh"

void OnStart()
  {
   string fx_main[] = {"EURUSD","GBPUSD","USDCAD","USDCHF"};
   string fx_asia[] = {"USDJPY","AUDUSD","NZDUSD"};
   string fx_cross[] = {"EURJPY","GBPJPY","EURAUD","GBPAUD"};
   string families[] = {"FX_MAIN","FX_ASIA","FX_CROSS"};

   MbTuningFamilyPolicy family_policy;
   string reason = "";

   MbTuningFamilyPolicyReset(family_policy);
   MbRunTuningFamilyAgent("FX_MAIN",fx_main,family_policy,reason);

   MbTuningFamilyPolicyReset(family_policy);
   MbRunTuningFamilyAgent("FX_ASIA",fx_asia,family_policy,reason);

   MbTuningFamilyPolicyReset(family_policy);
   MbRunTuningFamilyAgent("FX_CROSS",fx_cross,family_policy,reason);

   MbTuningCoordinatorState coordinator;
   MbTuningCoordinatorStateReset(coordinator);
   MbRunTuningCoordinator(families,coordinator,reason);
  }
