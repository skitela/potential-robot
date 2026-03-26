#ifndef MB_TUNING_FAMILY_AGENT_INCLUDED
#define MB_TUNING_FAMILY_AGENT_INCLUDED

#include "MbTuningStorage.mqh"
#include "MbTuningGuardMatrix.mqh"

double MbTuningSymbolLossRatio(const MbTuningSymbolSnapshot &snapshot)
  {
   if(snapshot.learning_sample_count <= 0)
      return 0.0;
   return (double)snapshot.learning_loss_count / (double)snapshot.learning_sample_count;
  }

double MbTuningFamilyClamp(const double value,const double lo,const double hi)
  {
   return MathMax(lo,MathMin(hi,value));
  }

bool MbTuningFamilyPolicyChanged(const MbTuningFamilyPolicy &lhs,const MbTuningFamilyPolicy &rhs)
  {
   if(lhs.trusted_data != rhs.trusted_data)
      return true;
   if(lhs.freeze_new_changes != rhs.freeze_new_changes)
      return true;
   if(lhs.symbol_count != rhs.symbol_count)
      return true;
   if(lhs.trusted_symbol_count != rhs.trusted_symbol_count)
      return true;
   if(lhs.degraded_symbol_count != rhs.degraded_symbol_count)
      return true;
   if(lhs.chaos_symbol_count != rhs.chaos_symbol_count)
      return true;
   if(lhs.bad_spread_symbol_count != rhs.bad_spread_symbol_count)
      return true;
   if(lhs.last_total_samples != rhs.last_total_samples)
      return true;
   if(lhs.paper_mode_active != rhs.paper_mode_active)
      return true;
   if(MathAbs(lhs.aggregate_realized_pnl_day - rhs.aggregate_realized_pnl_day) > 0.005)
      return true;
   if(MathAbs(lhs.aggregate_equity_anchor_day - rhs.aggregate_equity_anchor_day) > 0.005)
      return true;
   if(MathAbs(lhs.family_daily_loss_pct - rhs.family_daily_loss_pct) > 0.0005)
      return true;
   if(MathAbs(lhs.dominant_confidence_cap - rhs.dominant_confidence_cap) > 0.0005)
      return true;
   if(MathAbs(lhs.dominant_risk_cap - rhs.dominant_risk_cap) > 0.0005)
      return true;
   if(MathAbs(lhs.breakout_family_tax - rhs.breakout_family_tax) > 0.0005)
      return true;
   if(MathAbs(lhs.trend_family_tax - rhs.trend_family_tax) > 0.0005)
      return true;
   if(MathAbs(lhs.rejection_range_boost - rhs.rejection_range_boost) > 0.0005)
      return true;
   if(lhs.trust_reason != rhs.trust_reason)
      return true;
   return false;
  }

void MbTuningSummarizeFamilyAction(const MbTuningFamilyPolicy &policy,string &out_code,string &out_detail)
  {
   out_code = "REBALANCE_FAMILY";

   if(policy.trust_reason == "FAMILY_DAILY_LOSS_DEFENSIVE" && !policy.freeze_new_changes)
      out_code = "DEFENSIVE_FAMILY";
   else if(policy.freeze_new_changes)
      out_code = "FREEZE_FAMILY";
   else if(policy.breakout_family_tax >= policy.trend_family_tax && policy.breakout_family_tax >= 0.05)
      out_code = "DAMP_FAMILY_BREAKOUT";
   else if(policy.trend_family_tax >= 0.05)
      out_code = "DAMP_FAMILY_TREND";
   else if(policy.rejection_range_boost > 0.02)
      out_code = "BOOST_FAMILY_REJECTION";

   out_detail = StringFormat(
      "trust=%s;symbols=%d;trusted=%d;degraded=%d;chaos=%d;bad_spread=%d;conf=%.2f;risk=%.2f;breakout=%.2f;trend=%.2f;rejection=%.2f;freeze=%s",
      policy.trust_reason,
      policy.symbol_count,
      policy.trusted_symbol_count,
      policy.degraded_symbol_count,
      policy.chaos_symbol_count,
      policy.bad_spread_symbol_count,
      policy.dominant_confidence_cap,
      policy.dominant_risk_cap,
      policy.breakout_family_tax,
      policy.trend_family_tax,
      policy.rejection_range_boost,
      (policy.freeze_new_changes ? "1" : "0")
   );
  }

bool MbLoadTuningSymbolSnapshot(const string family,const string symbol,MbTuningSymbolSnapshot &out)
  {
   MbTuningSymbolSnapshotReset(out);
   out.symbol = MbCanonicalSymbol(symbol);
   out.family = family;

   MbRuntimeState state;
   MbRuntimeReset(state);
   state.symbol = out.symbol;
   if(MbLoadRuntimeState(state))
     {
      out.runtime_present = true;
      out.learning_sample_count = state.learning_sample_count;
      out.learning_win_count = state.learning_win_count;
      out.learning_loss_count = state.learning_loss_count;
      out.loss_streak = state.loss_streak;
      out.paper_mode_active = state.paper_mode_active;
      out.adaptive_risk_scale = state.adaptive_risk_scale;
      out.learning_bias = state.learning_bias;
      out.realized_pnl_day = state.realized_pnl_day;
      out.equity_anchor_day = state.equity_anchor_day;
      out.daily_loss_pct = MbCapitalRiskLossPctFromRealized(state.equity_anchor_day,state.realized_pnl_day);
      out.market_regime = state.market_regime;
      out.spread_regime = state.spread_regime;
      out.execution_regime = state.execution_regime;
      out.last_setup_type = state.last_setup_type;
     }

   MbTuningLocalPolicy local_policy;
   MbTuningLocalPolicyReset(local_policy);
   if(MbLoadTuningLocalPolicy(out.symbol,local_policy))
     {
      out.local_policy_present = true;
      out.local_policy_trusted = local_policy.trusted_data;
      out.confidence_cap = local_policy.confidence_cap;
      out.risk_cap = local_policy.risk_cap;
      out.breakout_tax = MbTuningFamilyClamp(
         local_policy.breakout_global_tax +
         local_policy.breakout_chaos_tax +
         local_policy.breakout_range_tax +
         local_policy.breakout_conflict_tax,
         0.0,
         0.30
      );
      out.trend_tax = MbTuningFamilyClamp(
         local_policy.trend_breakout_tax +
         local_policy.trend_chaos_tax +
         local_policy.trend_caution_tax +
         local_policy.trend_no_aux_tax,
         0.0,
         0.30
      );
      out.rejection_boost = local_policy.rejection_range_boost;
      out.trust_reason = local_policy.trust_reason;
     }
   else
      out.trust_reason = (out.runtime_present ? "RUNTIME_ONLY" : "MISSING");

   return (out.runtime_present || out.local_policy_present);
  }

int MbBuildFamilySymbolSnapshots(const string family,const string &symbols[],MbTuningSymbolSnapshot &out[])
  {
   ArrayResize(out,0);
   for(int i = 0; i < ArraySize(symbols); ++i)
     {
      MbTuningSymbolSnapshot row;
      if(!MbLoadTuningSymbolSnapshot(family,symbols[i],row))
         continue;

      int next = ArraySize(out);
      ArrayResize(out,next + 1);
      out[next] = row;
     }

   return ArraySize(out);
  }

bool MbRunTuningFamilyAgent(const string family,const string &symbols[],MbTuningFamilyPolicy &policy,string &out_reason)
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION) != 0)
     {
      out_reason = "OPTIMIZATION_RUNTIME";
      return false;
     }

   out_reason = "NO_CHANGE";
   policy.last_eval_at = TimeCurrent();

   if(!policy.enabled)
     {
      out_reason = "TUNING_DISABLED";
      return false;
     }

   MbTuningSymbolSnapshot snapshots[];
   int symbol_count = MbBuildFamilySymbolSnapshots(family,symbols,snapshots);
   if(symbol_count <= 0)
     {
      policy.trusted_data = false;
      policy.trust_reason = "NO_SYMBOLS";
      out_reason = policy.trust_reason;
      return false;
     }

   int total_samples = 0;
   int trusted_symbols = 0;
   int degraded_symbols = 0;
   int chaos_symbols = 0;
   int bad_spread_symbols = 0;
   int breakout_votes = 0;
   int trend_votes = 0;
   int rejection_sources = 0;
   double rejection_sum = 0.0;
   double confidence_sum = 0.0;
   double risk_sum = 0.0;
   int cap_sources = 0;
   bool family_mode_set = false;
   bool family_paper_mode = false;
   double family_realized_pnl_day = 0.0;
   double family_equity_anchor_day = 0.0;
   int majority = (symbol_count / 2) + (symbol_count % 2);

   for(int i = 0; i < ArraySize(snapshots); ++i)
     {
      MbTuningSymbolSnapshot row = snapshots[i];
      double loss_ratio = MbTuningSymbolLossRatio(row);
      bool trusted_symbol = (row.runtime_present && row.learning_sample_count >= 6);
      bool degraded_symbol = (
         loss_ratio >= 0.70 ||
         row.loss_streak >= 8 ||
         row.spread_regime == "BAD"
      );

      total_samples += row.learning_sample_count;
      if(row.runtime_present && row.equity_anchor_day > 0.0)
        {
         if(!family_mode_set)
           {
            family_mode_set = true;
            family_paper_mode = row.paper_mode_active;
           }

         if(row.paper_mode_active == family_paper_mode)
           {
            family_realized_pnl_day += row.realized_pnl_day;
            family_equity_anchor_day += row.equity_anchor_day;
           }
        }
      if(trusted_symbol)
         trusted_symbols++;
      if(degraded_symbol)
         degraded_symbols++;
      if(row.market_regime == "CHAOS")
         chaos_symbols++;
      if(row.spread_regime == "BAD")
         bad_spread_symbols++;

      if((row.last_setup_type == "SETUP_BREAKOUT" && degraded_symbol) || row.breakout_tax >= 0.05)
         breakout_votes++;
      if(((row.last_setup_type == "SETUP_TREND" || row.last_setup_type == "SETUP_PULLBACK") && degraded_symbol) || row.trend_tax >= 0.05 || row.market_regime == "CHAOS")
         trend_votes++;

      if(row.rejection_boost > 0.02)
        {
         rejection_sum += row.rejection_boost;
         rejection_sources++;
        }

      if(row.local_policy_present && row.local_policy_trusted)
        {
         confidence_sum += row.confidence_cap;
         risk_sum += row.risk_cap;
         cap_sources++;
        }
      else if(trusted_symbol)
        {
         confidence_sum += 1.0;
         risk_sum += MbTuningFamilyClamp(row.adaptive_risk_scale,0.75,1.0);
         cap_sources++;
        }
     }

   MbTuningFamilyPolicy next = policy;
   next.symbol_count = symbol_count;
   next.trusted_symbol_count = trusted_symbols;
   next.degraded_symbol_count = degraded_symbols;
   next.chaos_symbol_count = chaos_symbols;
   next.bad_spread_symbol_count = bad_spread_symbols;
   next.last_total_samples = total_samples;
   next.paper_mode_active = family_paper_mode;
   next.aggregate_realized_pnl_day = family_realized_pnl_day;
   next.aggregate_equity_anchor_day = family_equity_anchor_day;
   next.family_daily_loss_pct = MbCapitalRiskLossPctFromRealized(family_equity_anchor_day,family_realized_pnl_day);
   next.dominant_confidence_cap = (cap_sources > 0 ? MbTuningFamilyClamp(confidence_sum / (double)cap_sources,0.72,1.0) : 1.0);
   next.dominant_risk_cap = (cap_sources > 0 ? MbTuningFamilyClamp(risk_sum / (double)cap_sources,0.72,1.0) : 1.0);
   next.breakout_family_tax = 0.0;
   next.trend_family_tax = 0.0;
   next.rejection_range_boost = (rejection_sources > 0 ? MbTuningFamilyClamp(rejection_sum / (double)rejection_sources,0.0,0.06) : 0.0);
   next.freeze_new_changes = false;

   if(trusted_symbols <= 0)
      next.trust_reason = "NO_TRUSTED_SYMBOLS";
   else if(total_samples < MathMax(policy.min_family_samples,12 * symbol_count))
      next.trust_reason = "LOW_FAMILY_SAMPLE";
   else
      next.trust_reason = "TRUSTED";
   next.trusted_data = (next.trust_reason == "TRUSTED");

   if(!next.trusted_data)
     {
      next.freeze_new_changes = true;
      next.dominant_confidence_cap = MathMin(next.dominant_confidence_cap,0.90);
      next.dominant_risk_cap = MathMin(next.dominant_risk_cap,0.90);
     }

   if(degraded_symbols >= majority)
     {
      next.dominant_confidence_cap = MathMin(next.dominant_confidence_cap,0.86);
      next.dominant_risk_cap = MathMin(next.dominant_risk_cap,0.84);
     }

   if(bad_spread_symbols >= majority)
     {
      next.dominant_confidence_cap = MathMin(next.dominant_confidence_cap,0.82);
      next.dominant_risk_cap = MathMin(next.dominant_risk_cap,0.80);
      next.freeze_new_changes = true;
     }

   if(chaos_symbols >= majority || breakout_votes >= majority)
      next.breakout_family_tax = 0.06;
   else if(breakout_votes > 0 && degraded_symbols > 0)
      next.breakout_family_tax = 0.03;

   if(chaos_symbols >= majority || trend_votes >= majority)
      next.trend_family_tax = 0.05;
   else if(trend_votes > 0 && degraded_symbols > 0)
      next.trend_family_tax = 0.02;

   if(degraded_symbols >= (symbol_count - 1))
      next.freeze_new_changes = true;

   bool pre_capital_freeze = next.freeze_new_changes;
   bool pre_capital_trusted_data = next.trusted_data;
   string pre_capital_trust_reason = next.trust_reason;

   if(family_equity_anchor_day > 0.0)
     {
      MbCapitalRiskContract contract;
      MbResolveCapitalRiskContract(family_paper_mode,contract);
      if(next.family_daily_loss_pct >= contract.family_hard_daily_loss_pct)
        {
         if(family_paper_mode)
           {
            next.dominant_confidence_cap = MathMin(next.dominant_confidence_cap,0.78);
            next.dominant_risk_cap = MathMin(next.dominant_risk_cap,contract.soft_loss_risk_factor);
            next.freeze_new_changes = pre_capital_freeze;
            next.trusted_data = pre_capital_trusted_data;
            if(pre_capital_trusted_data)
               next.trust_reason = "FAMILY_DAILY_LOSS_DEFENSIVE";
            else
               next.trust_reason = pre_capital_trust_reason;
           }
         else
           {
            next.dominant_confidence_cap = 0.0;
            next.dominant_risk_cap = 0.0;
            next.freeze_new_changes = true;
            next.trusted_data = false;
            next.trust_reason = "FAMILY_DAILY_LOSS_HARD";
           }
        }
     }

   MbApplyTuningGuardToFamilyPolicy(family,next);

   bool force_recheck_paper_hard = (family_paper_mode && policy.trust_reason == "FAMILY_DAILY_LOSS_HARD");
   if(!force_recheck_paper_hard && policy.cooldown_until > 0 && TimeCurrent() < policy.cooldown_until && total_samples == policy.last_total_samples)
     {
      out_reason = "COOLDOWN";
      return false;
     }

   if(!MbTuningFamilyPolicyChanged(policy,next))
     {
      out_reason = "NO_CHANGE";
      return false;
     }

   next.revision = policy.revision + 1;
   next.last_action_at = TimeCurrent();
   next.cooldown_until = TimeCurrent() + MathMax(600,policy.cooldown_sec);
   MbTuningSummarizeFamilyAction(next,next.last_action_code,next.last_action_detail);

   policy = next;
   MbSaveTuningFamilyPolicy(family,policy);
   MbAppendTuningFamilyActionEvent(family,policy);
   out_reason = policy.last_action_code;
   return true;
  }

#endif
