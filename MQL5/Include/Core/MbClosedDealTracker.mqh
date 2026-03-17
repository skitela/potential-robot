#ifndef MB_CLOSED_DEAL_TRACKER_INCLUDED
#define MB_CLOSED_DEAL_TRACKER_INCLUDED

#include "MbRuntimeTypes.mqh"
#include "MbLearningPolicy.mqh"

double MbClampLearningBias(const double value)
  {
   return MathMax(-0.25,MathMin(0.25,value));
  }

double MbClampAdaptiveRiskScale(const double value)
  {
   return MathMax(0.75,MathMin(1.10,value));
  }

void MbUpdateLearningFromClosedDeal(MbRuntimeState &state,const double pnl)
  {
   state.learning_bias = MbClampLearningBias(state.learning_bias * 0.90);
   state.adaptive_risk_scale = MbClampAdaptiveRiskScale(1.0 + ((state.adaptive_risk_scale - 1.0) * 0.90));
   state.learning_confidence = MbLearningConfidenceFromSamples(state.learning_sample_count);

   if(pnl == 0.0)
      return;

   if(state.learning_sample_count < MbLearningMinSamplesForBias())
      return;

   double confidence = state.learning_confidence;

   if(pnl > 0.0)
     {
      state.learning_bias = MbClampLearningBias(state.learning_bias + MbLearningBiasWinStep(confidence));
      if(state.learning_sample_count >= MbLearningMinSamplesForRisk())
         state.adaptive_risk_scale = MbClampAdaptiveRiskScale(state.adaptive_risk_scale + MbLearningRiskWinStep(confidence));
     }
   else if(pnl < 0.0)
     {
      state.learning_bias = MbClampLearningBias(state.learning_bias - MbLearningBiasLossStep(confidence));
      if(state.learning_sample_count >= MbLearningMinSamplesForRisk())
         state.adaptive_risk_scale = MbClampAdaptiveRiskScale(state.adaptive_risk_scale - MbLearningRiskLossStep(confidence));
     }
  }

bool MbProcessClosedDealFeedback(const string symbol,const ulong magic,const ulong deal_ticket,MbRuntimeState &state)
  {
   if(deal_ticket == 0 || deal_ticket <= state.last_closed_deal_ticket)
      return false;
   if(!HistoryDealSelect(deal_ticket))
      return false;
   if((ulong)HistoryDealGetInteger(deal_ticket,DEAL_MAGIC) != magic)
      return false;
   if(HistoryDealGetString(deal_ticket,DEAL_SYMBOL) != symbol)
      return false;
   if((int)HistoryDealGetInteger(deal_ticket,DEAL_ENTRY) != DEAL_ENTRY_OUT)
      return false;

   double pnl = HistoryDealGetDouble(deal_ticket,DEAL_PROFIT)
      + HistoryDealGetDouble(deal_ticket,DEAL_SWAP)
      + HistoryDealGetDouble(deal_ticket,DEAL_COMMISSION);
   datetime deal_time = (datetime)HistoryDealGetInteger(deal_ticket,DEAL_TIME);

   state.realized_pnl_lifetime += pnl;
   if(state.day_anchor > 0 && deal_time >= state.day_anchor)
      state.realized_pnl_day += pnl;
   if(state.session_anchor > 0 && deal_time >= state.session_anchor)
      state.realized_pnl_session += pnl;

   if(pnl < 0.0)
     {
      state.loss_streak++;
      state.learning_sample_count++;
      state.learning_loss_count++;
     }
   else if(pnl > 0.0)
     {
      state.loss_streak = 0;
      state.learning_sample_count++;
      state.learning_win_count++;
     }

   MbUpdateLearningFromClosedDeal(state,pnl);

   state.last_closed_deal_ticket = deal_ticket;
   return true;
  }

void MbProcessSyntheticClosedDealFeedback(MbRuntimeState &state,const double pnl,const datetime deal_time)
  {
   state.realized_pnl_lifetime += pnl;
   if(state.day_anchor > 0 && deal_time >= state.day_anchor)
      state.realized_pnl_day += pnl;
   if(state.session_anchor > 0 && deal_time >= state.session_anchor)
      state.realized_pnl_session += pnl;

   if(pnl < 0.0)
     {
      state.loss_streak++;
      state.learning_sample_count++;
      state.learning_loss_count++;
     }
   else if(pnl > 0.0)
     {
      state.loss_streak = 0;
      state.learning_sample_count++;
      state.learning_win_count++;
     }

   MbUpdateLearningFromClosedDeal(state,pnl);
  }

#endif
