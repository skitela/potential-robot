#ifndef MB_TUNING_COORDINATOR_INCLUDED
#define MB_TUNING_COORDINATOR_INCLUDED

#include "MbTuningFamilyAgent.mqh"

bool MbTuningCoordinatorChanged(const MbTuningCoordinatorState &lhs,const MbTuningCoordinatorState &rhs)
  {
   if(lhs.trusted_data != rhs.trusted_data)
      return true;
   if(lhs.freeze_new_changes != rhs.freeze_new_changes)
      return true;
   if(lhs.family_count != rhs.family_count)
      return true;
   if(lhs.trusted_family_count != rhs.trusted_family_count)
      return true;
   if(lhs.degraded_family_count != rhs.degraded_family_count)
      return true;
   if(lhs.paper_mode_active != rhs.paper_mode_active)
      return true;
   if(MathAbs(lhs.aggregate_realized_pnl_day - rhs.aggregate_realized_pnl_day) > 0.005)
      return true;
   if(MathAbs(lhs.aggregate_equity_anchor_day - rhs.aggregate_equity_anchor_day) > 0.005)
      return true;
   if(MathAbs(lhs.fleet_daily_loss_pct - rhs.fleet_daily_loss_pct) > 0.0005)
      return true;
   if(lhs.max_local_changes_per_cycle != rhs.max_local_changes_per_cycle)
      return true;
   if(MathAbs(lhs.global_confidence_cap - rhs.global_confidence_cap) > 0.0005)
      return true;
   if(MathAbs(lhs.global_risk_cap - rhs.global_risk_cap) > 0.0005)
      return true;
   if(lhs.trust_reason != rhs.trust_reason)
      return true;
   return false;
  }

void MbTuningSummarizeCoordinatorAction(const MbTuningCoordinatorState &state,string &out_code,string &out_detail)
  {
   out_code = "REBALANCE_FLEET";

   if(state.trust_reason == "FLEET_DAILY_LOSS_DEFENSIVE" && !state.freeze_new_changes)
      out_code = "DEFENSIVE_FLEET";
   else if(state.freeze_new_changes)
      out_code = "FREEZE_FLEET";
   else if(state.degraded_family_count >= 2)
      out_code = "COOL_FLEET";
   else if(state.max_local_changes_per_cycle <= 1)
      out_code = "LIMIT_CHANGE_BUDGET";

   out_detail = StringFormat(
      "trust=%s;families=%d;trusted=%d;degraded=%d;conf=%.2f;risk=%.2f;budget=%d;freeze=%s",
      state.trust_reason,
      state.family_count,
      state.trusted_family_count,
      state.degraded_family_count,
      state.global_confidence_cap,
      state.global_risk_cap,
      state.max_local_changes_per_cycle,
      (state.freeze_new_changes ? "1" : "0")
   );
  }

int MbLoadCoordinatorFamilyPolicies(const string &families[],MbTuningFamilyPolicy &out[])
  {
   ArrayResize(out,0);
   for(int i = 0; i < ArraySize(families); ++i)
     {
      MbTuningFamilyPolicy policy;
      MbTuningFamilyPolicyReset(policy);
      if(!MbLoadTuningFamilyPolicy(families[i],policy))
         continue;

      int next = ArraySize(out);
      ArrayResize(out,next + 1);
      out[next] = policy;
     }
   return ArraySize(out);
  }

bool MbRunTuningCoordinator(const string &families[],MbTuningCoordinatorState &state,string &out_reason)
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION) != 0)
     {
      out_reason = "OPTIMIZATION_RUNTIME";
      return false;
     }

   out_reason = "NO_CHANGE";
   state.last_eval_at = TimeCurrent();

   if(!state.enabled)
     {
      out_reason = "TUNING_DISABLED";
      return false;
     }

   MbTuningFamilyPolicy family_policies[];
   int family_count = MbLoadCoordinatorFamilyPolicies(families,family_policies);
   if(family_count <= 0)
     {
      state.trusted_data = false;
      state.trust_reason = "NO_FAMILY_POLICIES";
      out_reason = state.trust_reason;
      return false;
     }

   int trusted_family_count = 0;
   int degraded_family_count = 0;
   double confidence_sum = 0.0;
   double risk_sum = 0.0;
   int trusted_caps = 0;
   bool fleet_mode_set = false;
   bool fleet_paper_mode = false;
   double fleet_realized_pnl_day = 0.0;
   double fleet_equity_anchor_day = 0.0;

   for(int i = 0; i < ArraySize(family_policies); ++i)
     {
      MbTuningFamilyPolicy row = family_policies[i];
      if(row.trusted_data)
        {
         trusted_family_count++;
         confidence_sum += row.dominant_confidence_cap;
         risk_sum += row.dominant_risk_cap;
         trusted_caps++;
        }

      if(row.aggregate_equity_anchor_day > 0.0)
        {
         if(!fleet_mode_set)
           {
            fleet_mode_set = true;
            fleet_paper_mode = row.paper_mode_active;
           }

         if(row.paper_mode_active == fleet_paper_mode)
           {
            fleet_realized_pnl_day += row.aggregate_realized_pnl_day;
            fleet_equity_anchor_day += row.aggregate_equity_anchor_day;
           }
        }

      if(
         row.freeze_new_changes ||
         row.dominant_risk_cap < 0.90 ||
         row.degraded_symbol_count >= MathMax(1,row.symbol_count - 1)
      )
         degraded_family_count++;
     }

   MbTuningCoordinatorState next = state;
   next.family_count = family_count;
   next.trusted_family_count = trusted_family_count;
   next.degraded_family_count = degraded_family_count;
   next.paper_mode_active = fleet_paper_mode;
   next.aggregate_realized_pnl_day = fleet_realized_pnl_day;
   next.aggregate_equity_anchor_day = fleet_equity_anchor_day;
   next.fleet_daily_loss_pct = MbCapitalRiskLossPctFromRealized(fleet_equity_anchor_day,fleet_realized_pnl_day);
   next.global_confidence_cap = (trusted_caps > 0 ? MbTuningFamilyClamp(confidence_sum / (double)trusted_caps,0.72,1.0) : 1.0);
   next.global_risk_cap = (trusted_caps > 0 ? MbTuningFamilyClamp(risk_sum / (double)trusted_caps,0.72,1.0) : 1.0);
   next.freeze_new_changes = false;
   next.max_local_changes_per_cycle = 2;

   if(trusted_family_count <= 0)
      next.trust_reason = "NO_TRUSTED_FAMILIES";
   else if(trusted_family_count < family_count)
      next.trust_reason = "PARTIAL_TRUST";
   else
      next.trust_reason = "TRUSTED";
   next.trusted_data = (trusted_family_count > 0);

   if(degraded_family_count >= 2)
     {
      next.global_confidence_cap = MathMin(next.global_confidence_cap,0.84);
      next.global_risk_cap = MathMin(next.global_risk_cap,0.82);
      next.max_local_changes_per_cycle = 1;
     }

   if(degraded_family_count >= family_count && family_count > 0)
     {
      if(next.paper_mode_active && trusted_family_count > 0)
        {
         next.freeze_new_changes = false;
         next.max_local_changes_per_cycle = MathMax(next.max_local_changes_per_cycle,1);
         next.global_confidence_cap = MathMin(next.global_confidence_cap,0.80);
         next.global_risk_cap = MathMin(next.global_risk_cap,0.70);
        }
      else
        {
         next.freeze_new_changes = true;
         next.max_local_changes_per_cycle = 0;
        }
     }
   else if(trusted_family_count < family_count && family_count > 1)
      next.max_local_changes_per_cycle = 1;

   if(!next.trusted_data)
      next.freeze_new_changes = true;

   bool pre_capital_freeze = next.freeze_new_changes;
   bool pre_capital_trusted_data = next.trusted_data;
   string pre_capital_trust_reason = next.trust_reason;
   int pre_capital_change_budget = next.max_local_changes_per_cycle;

   if(fleet_equity_anchor_day > 0.0)
     {
      MbCapitalRiskContract contract;
      MbResolveCapitalRiskContract(fleet_paper_mode,contract);

      if(next.fleet_daily_loss_pct >= contract.account_hard_daily_loss_pct)
        {
         if(fleet_paper_mode)
           {
            next.global_confidence_cap = MathMin(next.global_confidence_cap,0.80);
            next.global_risk_cap = MathMin(next.global_risk_cap,contract.soft_loss_risk_factor);
            next.trusted_data = pre_capital_trusted_data;
            if(pre_capital_trusted_data)
              {
               next.freeze_new_changes = false;
               next.max_local_changes_per_cycle = 1;
               next.trust_reason = "FLEET_DAILY_LOSS_DEFENSIVE";
              }
            else
              {
               next.freeze_new_changes = pre_capital_freeze;
               next.max_local_changes_per_cycle = (pre_capital_freeze ? pre_capital_change_budget : 0);
               next.trust_reason = pre_capital_trust_reason;
              }
           }
         else
           {
            next.global_confidence_cap = 0.0;
            next.global_risk_cap = 0.0;
            next.freeze_new_changes = true;
            next.max_local_changes_per_cycle = 0;
            next.trusted_data = false;
            next.trust_reason = "FLEET_DAILY_LOSS_HARD";
           }
        }
      else if(next.fleet_daily_loss_pct >= contract.account_soft_daily_loss_pct)
        {
         next.global_confidence_cap = MathMin(next.global_confidence_cap,0.78);
         next.global_risk_cap = MathMin(next.global_risk_cap,contract.soft_loss_risk_factor);
         next.max_local_changes_per_cycle = MathMin(next.max_local_changes_per_cycle,1);
         if(next.trust_reason == "TRUSTED")
            next.trust_reason = "FLEET_DAILY_LOSS_SOFT";
        }
     }

   bool force_recheck_paper_hard = (fleet_paper_mode && state.trust_reason == "FLEET_DAILY_LOSS_HARD");
   if(!force_recheck_paper_hard && state.cooldown_until > 0 && TimeCurrent() < state.cooldown_until && trusted_family_count == state.trusted_family_count && degraded_family_count == state.degraded_family_count)
     {
      out_reason = "COOLDOWN";
      return false;
     }

   if(!MbTuningCoordinatorChanged(state,next))
     {
      out_reason = "NO_CHANGE";
      return false;
     }

   next.revision = state.revision + 1;
   next.last_action_at = TimeCurrent();
   next.cooldown_until = TimeCurrent() + MathMax(900,state.cooldown_sec);
   MbTuningSummarizeCoordinatorAction(next,next.last_action_code,next.last_action_detail);

   state = next;
   MbSaveTuningCoordinatorState(state);
   MbAppendTuningCoordinatorActionEvent(state);
   out_reason = state.last_action_code;
   return true;
  }

#endif
