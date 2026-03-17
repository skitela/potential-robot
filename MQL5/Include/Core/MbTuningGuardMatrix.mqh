#ifndef MB_TUNING_GUARD_MATRIX_INCLUDED
#define MB_TUNING_GUARD_MATRIX_INCLUDED

#include "MbTuningTypes.mqh"
#include "MbRuntimeKernel.mqh"

bool MbResolveTuningGuardFamily(const string family_or_symbol,string &out_family)
  {
   string key = MbCanonicalSymbol(family_or_symbol);
   out_family = "";

   if(
      key == "FX_MAIN" ||
      key == "EURUSD" ||
      key == "GBPUSD" ||
      key == "USDCAD" ||
      key == "USDCHF"
   )
     {
      out_family = "FX_MAIN";
      return true;
     }

   if(
      key == "FX_ASIA" ||
      key == "AUDUSD" ||
      key == "USDJPY" ||
      key == "NZDUSD"
   )
     {
      out_family = "FX_ASIA";
      return true;
     }

   if(
      key == "FX_CROSS" ||
      key == "EURJPY" ||
      key == "GBPJPY" ||
      key == "EURAUD" ||
      key == "GBPAUD"
   )
     {
      out_family = "FX_CROSS";
      return true;
     }

   if(
      key == "METALS_SPOT_PM" ||
      key == "GOLD" ||
      key == "SILVER"
   )
     {
      out_family = "METALS_SPOT_PM";
      return true;
     }

   if(
      key == "METALS_FUTURES" ||
      key == "PLATIN" ||
      key == "COPPER-US" ||
      key == "COPPER-USPRO" ||
      key == "COPPER-USPRO,M5" ||
      key == "COPPER-USPRO,M1" ||
      key == "COPPERUS"
   )
     {
      out_family = "METALS_FUTURES";
      return true;
     }

   if(key == "INDEX_EU" || key == "DE30")
     {
      out_family = "INDEX_EU";
      return true;
     }

   if(key == "INDEX_US" || key == "US500")
     {
      out_family = "INDEX_US";
      return true;
     }

   return false;
  }

bool MbResolveTuningGuardCaps(const string family_or_symbol,double &out_confidence_cap,double &out_risk_cap)
  {
   string family = "";
   out_confidence_cap = 1.0;
   out_risk_cap = 1.0;

   if(!MbResolveTuningGuardFamily(family_or_symbol,family))
      return false;

   if(family == "FX_MAIN")
     {
      out_confidence_cap = 0.92;
      out_risk_cap = 0.88;
      return true;
     }

   if(family == "FX_ASIA")
     {
      out_confidence_cap = 0.88;
      out_risk_cap = 0.80;
      return true;
     }

   if(family == "FX_CROSS")
     {
      out_confidence_cap = 0.82;
      out_risk_cap = 0.65;
      return true;
     }

   if(family == "METALS_SPOT_PM")
     {
      out_confidence_cap = 0.84;
      out_risk_cap = 0.72;
      return true;
     }

   if(family == "METALS_FUTURES")
     {
      out_confidence_cap = 0.80;
      out_risk_cap = 0.65;
      return true;
     }

   if(family == "INDEX_EU")
     {
      out_confidence_cap = 0.78;
      out_risk_cap = 0.70;
      return true;
     }

   if(family == "INDEX_US")
     {
      out_confidence_cap = 0.82;
      out_risk_cap = 0.72;
      return true;
     }

   return false;
  }

void MbApplyTuningGuardCaps(const string family_or_symbol,double &io_confidence_cap,double &io_risk_cap)
  {
   double guard_confidence_cap = 1.0;
   double guard_risk_cap = 1.0;
   if(!MbResolveTuningGuardCaps(family_or_symbol,guard_confidence_cap,guard_risk_cap))
      return;

   io_confidence_cap = MathMin(io_confidence_cap,guard_confidence_cap);
   io_risk_cap = MathMin(io_risk_cap,guard_risk_cap);
  }

void MbApplyTuningGuardToLocalPolicy(const string family_or_symbol,MbTuningLocalPolicy &io_policy)
  {
   MbApplyTuningGuardCaps(family_or_symbol,io_policy.confidence_cap,io_policy.risk_cap);
  }

void MbApplyTuningGuardToFamilyPolicy(const string family_or_symbol,MbTuningFamilyPolicy &io_policy)
  {
   MbApplyTuningGuardCaps(family_or_symbol,io_policy.dominant_confidence_cap,io_policy.dominant_risk_cap);
  }

#endif
