#ifndef MB_TUNING_HIERARCHY_BRIDGE_INCLUDED
#define MB_TUNING_HIERARCHY_BRIDGE_INCLUDED

#include "MbTuningCoordinator.mqh"
#include "MbTuningGuardMatrix.mqh"

double MbTuningOverlayClamp(const double value,const double lo,const double hi)
  {
   return MathMax(lo,MathMin(hi,value));
  }

bool MbKeepAcceptedPaperExperimentActive(
   const bool paper_lab_active,
   const MbTuningLocalPolicy &policy
)
  {
   return (
      paper_lab_active &&
      policy.experiment_status == "ACCEPTED" &&
      (policy.trust_reason_domain == "RISK" || policy.trust_reason_class == "CONTRACT")
   );
  }

int MbGetAllTuningFamilies(string &out[])
  {
   ArrayResize(out,7);
   out[0] = "FX_MAIN";
   out[1] = "FX_ASIA";
   out[2] = "FX_CROSS";
   out[3] = "METALS_SPOT_PM";
   out[4] = "METALS_FUTURES";
   out[5] = "INDEX_EU";
   out[6] = "INDEX_US";
   return ArraySize(out);
  }

int MbGetTuningFamilySymbols(const string family,string &out[])
  {
   ArrayResize(out,0);

   if(family == "FX_MAIN")
     {
      ArrayResize(out,4);
      out[0] = "EURUSD";
      out[1] = "GBPUSD";
      out[2] = "USDCAD";
      out[3] = "USDCHF";
     }
   else if(family == "FX_ASIA")
     {
      ArrayResize(out,3);
      out[0] = "AUDUSD";
      out[1] = "USDJPY";
      out[2] = "NZDUSD";
     }
   else if(family == "FX_CROSS")
     {
      ArrayResize(out,4);
      out[0] = "EURJPY";
      out[1] = "GBPJPY";
      out[2] = "EURAUD";
      out[3] = "GBPAUD";
     }
   else if(family == "METALS_SPOT_PM")
     {
      ArrayResize(out,2);
      out[0] = "GOLD.pro";
      out[1] = "SILVER.pro";
     }
   else if(family == "METALS_FUTURES")
     {
      ArrayResize(out,2);
      out[0] = "PLATIN.pro";
      out[1] = "COPPER-US.pro";
     }
   else if(family == "INDEX_EU")
     {
      ArrayResize(out,1);
      out[0] = "DE30.pro";
     }
   else if(family == "INDEX_US")
     {
      ArrayResize(out,1);
      out[0] = "US500.pro";
     }

   return ArraySize(out);
  }

void MbBuildEffectiveTuningPolicy(
   const string family,
   const MbTuningLocalPolicy &local_policy,
   MbTuningLocalPolicy &effective_policy,
   MbTuningFamilyPolicy &out_family_policy,
   MbTuningCoordinatorState &out_coordinator_state
)
  {
   effective_policy = local_policy;
   MbTuningFamilyPolicyReset(out_family_policy);
   MbTuningCoordinatorStateReset(out_coordinator_state);

   bool family_loaded = MbLoadTuningFamilyPolicy(family,out_family_policy);
   bool coordinator_loaded = MbLoadTuningCoordinatorState(out_coordinator_state);
   bool paper_lab_active = ((family_loaded && out_family_policy.paper_mode_active) || (coordinator_loaded && out_coordinator_state.paper_mode_active));
   bool preserve_local_paper_caps = MbKeepAcceptedPaperExperimentActive(paper_lab_active,local_policy);

   if(family_loaded)
     {
      // Paper laboratory should keep learning even when live family guards are frozen.
      // Family overlays that describe signal shape remain useful, but hard caps from
      // live protection should not blind paper exploration.
      if(!paper_lab_active)
        {
         effective_policy.confidence_cap = MathMin(effective_policy.confidence_cap,out_family_policy.dominant_confidence_cap);
         effective_policy.risk_cap = MathMin(effective_policy.risk_cap,out_family_policy.dominant_risk_cap);
        }
      effective_policy.breakout_global_tax = MbTuningOverlayClamp(
         effective_policy.breakout_global_tax + out_family_policy.breakout_family_tax,
         0.0,
         0.20
      );
      effective_policy.trend_caution_tax = MbTuningOverlayClamp(
         effective_policy.trend_caution_tax + out_family_policy.trend_family_tax,
         0.0,
         0.16
      );
      effective_policy.rejection_range_boost = MathMax(
         effective_policy.rejection_range_boost,
         out_family_policy.rejection_range_boost
      );
     }

   if(coordinator_loaded && !paper_lab_active)
     {
      effective_policy.confidence_cap = MathMin(effective_policy.confidence_cap,out_coordinator_state.global_confidence_cap);
      effective_policy.risk_cap = MathMin(effective_policy.risk_cap,out_coordinator_state.global_risk_cap);
     }

   // If the last accepted local experiment is being masked only by portfolio/fleet
   // risk state, keep its signal filter active in paper runtime so the laboratory
   // can continue to collect lessons without reopening live risk.
   if(preserve_local_paper_caps)
     {
      effective_policy.trusted_data = true;
      effective_policy.confidence_cap = MathMax(effective_policy.confidence_cap,local_policy.confidence_cap);
      effective_policy.risk_cap = MathMax(effective_policy.risk_cap,local_policy.risk_cap);
     }

   MbApplyTuningGuardToLocalPolicy(family,effective_policy);
  }

bool MbTuningHierarchyBlocksLocalChanges(
   const MbTuningFamilyPolicy &family_policy,
   const MbTuningCoordinatorState &coordinator_state,
   string &out_reason
)
  {
   out_reason = "ALLOW";

   // In paper runtime we still want the local agent and deckhand to learn and
   // adapt. Fleet/family freeze should protect live changes, not blind the
   // paper laboratory after the market reopens.
   if(coordinator_state.paper_mode_active || family_policy.paper_mode_active)
     {
      out_reason = "ALLOW_PAPER_RUNTIME";
      return false;
     }

   if(coordinator_state.freeze_new_changes)
     {
      out_reason = "FLEET_FREEZE";
      return true;
     }

   if(family_policy.freeze_new_changes)
     {
      out_reason = "FAMILY_FREEZE";
      return true;
     }

   return false;
  }

#endif
