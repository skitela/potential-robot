#ifndef MB_CONTEXT_POLICY_INCLUDED
#define MB_CONTEXT_POLICY_INCLUDED

#include "MbRuntimeTypes.mqh"

struct MbSignalContextAssessment
  {
   string market_regime;
   string spread_regime;
   string execution_regime;
   string confidence_bucket;
   double confidence_score;
   double risk_multiplier;
   bool allow_entry;
   string reason_code;
  };

void MbSignalContextAssessmentReset(MbSignalContextAssessment &out)
  {
   out.market_regime = "UNKNOWN";
   out.spread_regime = "UNKNOWN";
   out.execution_regime = "UNKNOWN";
   out.confidence_bucket = "LOW";
   out.confidence_score = 0.0;
   out.risk_multiplier = 0.65;
   out.allow_entry = false;
   out.reason_code = "CONTEXT_UNKNOWN";
  }

double MbContextClamp(const double value,const double lo,const double hi)
  {
   return MathMax(lo,MathMin(hi,value));
  }

string MbResolveSpreadRegime(const MbSymbolProfile &profile,const MbMarketSnapshot &snapshot)
  {
   if(snapshot.spread_points <= profile.caution_spread_points)
      return "GOOD";
   if(snapshot.spread_points <= profile.max_spread_points)
      return "CAUTION";
   return "BAD";
  }

string MbResolveExecutionRegime(const MbRuntimeState &state)
  {
   if(state.execution_pressure >= 0.80)
      return "BAD";
   if(state.execution_pressure >= 0.45)
      return "CAUTION";
   return "GOOD";
  }

string MbResolveMarketRegime(
   const double trend_strength,
   const double rsi,
   const string spread_regime,
   const string execution_regime
)
  {
   if(spread_regime == "BAD" || execution_regime == "BAD")
      return "CHAOS";

   double abs_trend = MathAbs(trend_strength);
   double abs_rsi_bias = MathAbs(rsi - 50.0);
   if(abs_trend >= 1.10 && abs_rsi_bias >= 8.0)
      return "BREAKOUT";
   if(abs_trend >= 0.55 && abs_rsi_bias >= 4.0)
      return "TREND";
   if(abs_trend <= 0.25 && abs_rsi_bias <= 8.0)
      return "RANGE";
   return "CHAOS";
  }

double MbSetupRegimeAffinity(const string market_regime,const string setup_type)
  {
   if(market_regime == "TREND")
     {
      if(setup_type == "SETUP_TREND" || setup_type == "SETUP_PULLBACK")
         return 0.12;
      if(setup_type == "SETUP_BREAKOUT")
         return 0.05;
     }
   else if(market_regime == "BREAKOUT")
     {
      if(setup_type == "SETUP_BREAKOUT")
         return 0.12;
      if(setup_type == "SETUP_TREND")
         return 0.04;
     }
   else if(market_regime == "RANGE")
     {
      if(setup_type == "SETUP_REJECTION" || setup_type == "SETUP_RANGE" || setup_type == "SETUP_REVERSAL")
         return 0.12;
      if(setup_type == "SETUP_PULLBACK")
         return 0.03;
     }
   return -0.06;
  }

void MbAssessSignalContext(
   const MbSymbolProfile &profile,
   const MbRuntimeState &state,
   const MbMarketSnapshot &snapshot,
   const double raw_score,
   const string setup_type,
   const double trend_strength,
   const double rsi,
   MbSignalContextAssessment &out
)
  {
   MbSignalContextAssessmentReset(out);

   out.spread_regime = MbResolveSpreadRegime(profile,snapshot);
   out.execution_regime = MbResolveExecutionRegime(state);
   out.market_regime = MbResolveMarketRegime(trend_strength,rsi,out.spread_regime,out.execution_regime);

   double confidence = MbContextClamp(MathAbs(raw_score) / 1.50,0.0,0.85);
   confidence += MbContextClamp(state.learning_bias,-0.10,0.10);
   confidence += MbSetupRegimeAffinity(out.market_regime,setup_type);

   if(out.spread_regime == "CAUTION")
      confidence -= 0.08;
   else if(out.spread_regime == "BAD")
      confidence -= 0.25;

   if(out.execution_regime == "CAUTION")
      confidence -= 0.10;
   else if(out.execution_regime == "BAD")
      confidence -= 0.22;

   if(state.caution_mode)
      confidence -= 0.06;
   if(state.close_only || state.halt)
      confidence -= 0.35;

   confidence += (state.learning_confidence * 0.08);
   out.confidence_score = MbContextClamp(confidence,0.0,1.0);

   if(out.confidence_score >= 0.75)
     {
      out.confidence_bucket = "HIGH";
      out.risk_multiplier = 1.05;
      out.allow_entry = true;
      out.reason_code = "CONTEXT_HIGH";
     }
   else if(out.confidence_score >= 0.52)
     {
      out.confidence_bucket = "MEDIUM";
      out.risk_multiplier = 0.82;
      out.allow_entry = true;
      out.reason_code = "CONTEXT_MEDIUM";
     }
   else
     {
      out.confidence_bucket = "LOW";
      out.risk_multiplier = 0.60;
      out.allow_entry = false;
      out.reason_code = "CONTEXT_LOW_CONFIDENCE";
     }
  }

#endif
