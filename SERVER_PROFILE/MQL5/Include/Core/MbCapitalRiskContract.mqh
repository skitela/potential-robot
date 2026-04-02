#ifndef MB_CAPITAL_RISK_CONTRACT_INCLUDED
#define MB_CAPITAL_RISK_CONTRACT_INCLUDED

#include "MbRuntimeTypes.mqh"
#include "MbCoreCapitalContract.mqh"

struct MbCapitalRiskContract
  {
   double risk_per_trade_base_pct;
   double risk_per_trade_min_pct;
   double risk_per_trade_max_pct;
   double account_soft_daily_loss_pct;
   double account_hard_daily_loss_pct;
   double account_hard_session_loss_pct;
   double family_hard_daily_loss_pct;
   double symbol_hard_daily_loss_pct;
   double max_open_risk_pct;
   double soft_loss_risk_factor;
   double profit_buffer_participation_factor;
   double daily_loss_relax_start_buffer_pct;
   double daily_loss_relax_soft_buffer_pct;
   double daily_loss_relax_full_buffer_pct;
   double daily_loss_relax_soft_max_multiplier;
   double daily_loss_relax_hard_max_multiplier;
  };

void MbCapitalRiskContractReset(MbCapitalRiskContract &contract)
  {
   contract.risk_per_trade_base_pct = 0.25;
   contract.risk_per_trade_min_pct = 0.10;
   contract.risk_per_trade_max_pct = 0.50;
   contract.account_soft_daily_loss_pct = 1.00;
   contract.account_hard_daily_loss_pct = 1.50;
   contract.account_hard_session_loss_pct = 0.75;
   contract.family_hard_daily_loss_pct = 0.60;
   contract.symbol_hard_daily_loss_pct = 0.40;
   contract.max_open_risk_pct = 1.25;
   contract.soft_loss_risk_factor = 0.50;
   contract.profit_buffer_participation_factor = 0.50;
   contract.daily_loss_relax_start_buffer_pct = 10.0;
   contract.daily_loss_relax_soft_buffer_pct = 25.0;
   contract.daily_loss_relax_full_buffer_pct = 50.0;
   contract.daily_loss_relax_soft_max_multiplier = 1.25;
   contract.daily_loss_relax_hard_max_multiplier = 1.50;
  }

void MbResolveCapitalRiskContract(const bool paper_mode,MbCapitalRiskContract &contract)
  {
   MbCapitalRiskContractReset(contract);

   if(!paper_mode)
      return;

   contract.risk_per_trade_base_pct = 0.50;
   contract.risk_per_trade_min_pct = 0.20;
   contract.risk_per_trade_max_pct = 0.75;
   contract.account_soft_daily_loss_pct = 2.00;
   contract.account_hard_daily_loss_pct = 4.00;
   contract.account_hard_session_loss_pct = 1.50;
   contract.family_hard_daily_loss_pct = 1.20;
   contract.symbol_hard_daily_loss_pct = 0.80;
   contract.max_open_risk_pct = 2.00;
   contract.soft_loss_risk_factor = 0.60;
   contract.profit_buffer_participation_factor = 0.50;
   contract.daily_loss_relax_start_buffer_pct = 10.0;
   contract.daily_loss_relax_soft_buffer_pct = 25.0;
   contract.daily_loss_relax_full_buffer_pct = 50.0;
   contract.daily_loss_relax_soft_max_multiplier = 1.25;
   contract.daily_loss_relax_hard_max_multiplier = 1.50;
  }

double MbCapitalRiskEffectiveCapitalTotal(const MbRuntimeState &state)
  {
   if(state.capital_core_anchor <= 0.0)
      return 0.0;

   return (state.capital_core_anchor + state.realized_pnl_lifetime);
  }

double MbCapitalRiskProfitBuffer(const MbRuntimeState &state)
  {
   if(state.capital_core_anchor <= 0.0)
      return 0.0;

   return MathMax(0.0,MbCapitalRiskEffectiveCapitalTotal(state) - state.capital_core_anchor);
  }

double MbCapitalRiskBufferPctOfCore(const MbRuntimeState &state)
  {
   if(state.capital_core_anchor <= 0.0)
      return 0.0;

   return 100.0 * MbCapitalRiskProfitBuffer(state) / state.capital_core_anchor;
  }

double MbCapitalRiskLossAllowanceMultiplier(const bool paper_mode,const MbCapitalRiskContract &contract,const MbRuntimeState &state)
  {
   if(paper_mode)
      return 1.0;

   double buffer_pct = MbCapitalRiskBufferPctOfCore(state);
   if(buffer_pct <= contract.daily_loss_relax_start_buffer_pct)
      return 1.0;

   if(buffer_pct <= contract.daily_loss_relax_soft_buffer_pct)
     {
      double span = MathMax(0.0001,contract.daily_loss_relax_soft_buffer_pct - contract.daily_loss_relax_start_buffer_pct);
      double progress = (buffer_pct - contract.daily_loss_relax_start_buffer_pct) / span;
      return (1.0 + ((contract.daily_loss_relax_soft_max_multiplier - 1.0) * progress));
     }

   if(buffer_pct <= contract.daily_loss_relax_full_buffer_pct)
     {
      double span = MathMax(0.0001,contract.daily_loss_relax_full_buffer_pct - contract.daily_loss_relax_soft_buffer_pct);
      double progress = (buffer_pct - contract.daily_loss_relax_soft_buffer_pct) / span;
      return (contract.daily_loss_relax_soft_max_multiplier + ((contract.daily_loss_relax_hard_max_multiplier - contract.daily_loss_relax_soft_max_multiplier) * progress));
     }

   return contract.daily_loss_relax_hard_max_multiplier;
  }

double MbCapitalRiskResolveRiskBase(const bool paper_mode,const MbCapitalRiskContract &contract,const MbRuntimeState &state,const MbMarketSnapshot &snapshot)
  {
   double core_capital = state.capital_core_anchor;
   if(core_capital <= 0.0)
      core_capital = snapshot.equity;

   if(core_capital <= 0.0)
      return 0.0;

   double profit_buffer = MbCapitalRiskProfitBuffer(state);
   if(paper_mode)
      return (core_capital + (profit_buffer * contract.profit_buffer_participation_factor));

   return (core_capital + (profit_buffer * contract.profit_buffer_participation_factor));
  }

void MbCapitalRiskRefreshState(const bool paper_mode,const MbCapitalRiskContract &contract,const MbMarketSnapshot &snapshot,MbRuntimeState &state)
  {
   if(snapshot.equity <= 0.0)
      return;

   MbRefreshManualCoreCapital(paper_mode,snapshot,state);

   state.effective_profit_buffer = MbCapitalRiskProfitBuffer(state);
   state.effective_risk_base = MbCapitalRiskResolveRiskBase(paper_mode,contract,state,snapshot);
   state.effective_loss_allowance_multiplier = MbCapitalRiskLossAllowanceMultiplier(paper_mode,contract,state);
  }

double MbCapitalRiskResolveSoftDailyLossPct(const bool paper_mode,const MbCapitalRiskContract &contract,const MbRuntimeState &state)
  {
   return (contract.account_soft_daily_loss_pct * MbCapitalRiskLossAllowanceMultiplier(paper_mode,contract,state));
  }

double MbCapitalRiskResolveHardDailyLossPct(const bool paper_mode,const MbCapitalRiskContract &contract,const MbRuntimeState &state)
  {
   return (contract.account_hard_daily_loss_pct * MbCapitalRiskLossAllowanceMultiplier(paper_mode,contract,state));
  }

double MbCapitalRiskResolveHardSessionLossPct(const bool paper_mode,const MbCapitalRiskContract &contract,const MbRuntimeState &state)
  {
   return (contract.account_hard_session_loss_pct * MbCapitalRiskLossAllowanceMultiplier(paper_mode,contract,state));
  }

bool MbCapitalRiskCoreFloorBreached(const bool paper_mode,const MbRuntimeState &state,const MbMarketSnapshot &snapshot)
  {
   if(paper_mode)
      return false;
   if(state.capital_core_anchor <= 0.0 || snapshot.equity <= 0.0)
      return false;

   return (snapshot.equity <= state.capital_core_anchor);
  }

double MbCapitalRiskLossPctFromRealized(const double anchor_equity,const double realized_pnl)
  {
   if(anchor_equity <= 0.0)
      return 0.0;

   return 100.0 * MathMax(0.0,-realized_pnl) / anchor_equity;
  }

double MbCapitalRiskLossPctFromEquity(const double anchor_equity,const double current_equity)
  {
   if(anchor_equity <= 0.0)
      return 0.0;

   return 100.0 * MathMax(0.0,(anchor_equity - current_equity) / anchor_equity);
  }

bool MbCapitalRiskSoftLossTriggered(const bool paper_mode,const MbRuntimeState &state,const MbMarketSnapshot &snapshot)
  {
   MbCapitalRiskContract contract;
   MbResolveCapitalRiskContract(paper_mode,contract);

   double loss_pct = 0.0;
   if(paper_mode)
      loss_pct = MbCapitalRiskLossPctFromRealized(state.equity_anchor_day,state.realized_pnl_day);
   else
      loss_pct = MbCapitalRiskLossPctFromEquity(state.equity_anchor_day,snapshot.equity);

   return (loss_pct >= MbCapitalRiskResolveSoftDailyLossPct(paper_mode,contract,state));
  }

double MbClampRiskMultiplierToContract(const bool paper_mode,const double multiplier)
  {
   MbCapitalRiskContract contract;
   MbResolveCapitalRiskContract(paper_mode,contract);

   double capped = MathMax(0.0,MathMin(1.0,multiplier));
   if(contract.risk_per_trade_max_pct <= 0.0)
      return 0.0;

   return capped;
  }

#endif
