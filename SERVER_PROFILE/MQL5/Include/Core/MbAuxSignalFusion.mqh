#ifndef MB_AUX_SIGNAL_FUSION_INCLUDED
#define MB_AUX_SIGNAL_FUSION_INCLUDED

#include "MbRuntimeTypes.mqh"
#include "MbCandleAdvisory.mqh"
#include "MbRenkoAdvisory.mqh"

struct MbAuxSignalFusion
  {
   bool allow_entry;
   string reason_code;
   double confidence_score;
   double risk_multiplier;
  };

void MbAuxSignalFusionReset(const double base_confidence,const double base_risk,MbAuxSignalFusion &out)
  {
   out.allow_entry = true;
   out.reason_code = "AUX_OK";
   out.confidence_score = base_confidence;
   out.risk_multiplier = base_risk;
  }

void MbApplyAuxSignalFusion(
   const MbSignalSide intended_side,
   const MbCandleAdvisory &candle,
   const MbRenkoAdvisory &renko,
   MbAuxSignalFusion &out
)
  {
   int conflicts = 0;
   int aligns = 0;
   double candle_max_score = MathMax(candle.score_long,candle.score_short);
   bool candle_actionable = (candle.ready && candle_max_score >= 0.35 && candle.quality_grade != "POOR");
   double renko_max_score = MathMax(renko.score_long,renko.score_short);
   bool renko_actionable = (renko.ready && renko_max_score >= 0.45 && renko.quality_grade != "POOR");

   if(candle_actionable)
     {
      double intended_score = (intended_side == MB_SIGNAL_BUY ? candle.score_long : candle.score_short);
      bool conflict = candle.no_trade_hint;
      bool align = ((intended_side == MB_SIGNAL_BUY && candle.bias == "UP") || (intended_side == MB_SIGNAL_SELL && candle.bias == "DOWN"));
      if(conflict)
        {
         conflicts++;
         out.confidence_score -= (intended_score >= 0.60 ? 0.18 : 0.10);
         out.risk_multiplier -= (intended_score >= 0.60 ? 0.15 : 0.08);
        }
      else if(align)
        {
         aligns++;
         out.confidence_score += (intended_score >= 0.60 ? 0.10 : 0.05);
         out.risk_multiplier += (intended_score >= 0.60 ? 0.07 : 0.03);
        }
     }

   if(renko_actionable)
     {
      double intended_score = (intended_side == MB_SIGNAL_BUY ? renko.score_long : renko.score_short);
      bool conflict = ((intended_side == MB_SIGNAL_BUY && renko.bias == "DOWN") || (intended_side == MB_SIGNAL_SELL && renko.bias == "UP"));
      bool align = ((intended_side == MB_SIGNAL_BUY && renko.bias == "UP") || (intended_side == MB_SIGNAL_SELL && renko.bias == "DOWN"));
      if(conflict)
        {
         conflicts++;
         out.confidence_score -= (renko.reversal_flag ? 0.20 : 0.12);
         out.risk_multiplier -= (renko.reversal_flag ? 0.18 : 0.08);
        }
      else if(align)
        {
         aligns++;
         out.confidence_score += (renko.run_length >= 3 ? 0.12 : 0.06);
         out.risk_multiplier += (renko.run_length >= 3 ? 0.09 : 0.04);
        }
     }

   if(conflicts >= 2 && aligns == 0)
     {
      out.allow_entry = false;
      out.reason_code = "AUX_CONFLICT_BLOCK";
     }
   else if(conflicts > aligns && conflicts > 0)
      out.reason_code = "AUX_CONFLICT_CAUTION";
   else if(aligns >= 2)
      out.reason_code = "AUX_ALIGNMENT_GOOD";
   else if(aligns == 1)
      out.reason_code = "AUX_ALIGNMENT_LIGHT";
   else if(!candle_actionable && !renko_actionable)
      out.reason_code = "AUX_INCONCLUSIVE";
   else
      out.reason_code = "AUX_MIXED";

   out.confidence_score = MathMax(0.0,MathMin(1.0,out.confidence_score));
   out.risk_multiplier = MathMax(0.55,MathMin(1.25,out.risk_multiplier));
  }

#endif
