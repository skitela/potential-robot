#ifndef MB_CANDLE_ADVISORY_INCLUDED
#define MB_CANDLE_ADVISORY_INCLUDED

struct MbCandleAdvisory
  {
   bool ready;
   bool no_trade_hint;
   string bias;
   string quality_grade;
   string reason_code;
   string patterns;
   double score_long;
   double score_short;
  };

void MbCandleAdvisoryReset(MbCandleAdvisory &out)
  {
   out.ready = false;
   out.no_trade_hint = false;
   out.bias = "NONE";
   out.quality_grade = "UNKNOWN";
   out.reason_code = "CANDLE_NOT_EVALUATED";
   out.patterns = "NONE";
   out.score_long = 0.0;
   out.score_short = 0.0;
  }

double MbCandleSafeRatio(const double num,const double den)
  {
   if(den <= 0.0)
      return 0.0;
   return (num / den);
  }

bool MbLoadRecentBars(
   const string symbol,
   const ENUM_TIMEFRAMES timeframe,
   const int count,
   MqlRates &rates[]
)
  {
   ArrayResize(rates,0);
   int copied = CopyRates(symbol,timeframe,0,count,rates);
   if(copied < count)
      return false;
   ArraySetAsSeries(rates,true);
   return true;
  }

void MbEvaluateCandleAdvisory(
   const string symbol,
   const ENUM_TIMEFRAMES timeframe,
   const MbSignalSide intended_side,
   const double min_body_to_range,
   const double pin_wick_ratio_min,
   MbCandleAdvisory &out
)
  {
   MbCandleAdvisoryReset(out);

   MqlRates rates[];
   if(!MbLoadRecentBars(symbol,timeframe,3,rates))
     {
      out.reason_code = "CANDLE_RATES_NOT_READY";
      return;
     }

   MqlRates curr = rates[1];
   MqlRates prev = rates[2];

   double rng = MathMax(0.0,curr.high - curr.low);
   if(rng <= 0.0)
     {
      out.reason_code = "CANDLE_RANGE_ZERO";
      return;
     }

   double body = MathAbs(curr.close - curr.open);
   double upper_wick = MathMax(0.0,curr.high - MathMax(curr.open,curr.close));
   double lower_wick = MathMax(0.0,MathMin(curr.open,curr.close) - curr.low);
   double body_to_range = MbCandleSafeRatio(body,rng);

   bool bullish_engulf =
      (curr.close > curr.open) &&
      (prev.close < prev.open) &&
      (curr.open <= prev.close) &&
      (curr.close >= prev.open) &&
      (body_to_range >= min_body_to_range);

   bool bearish_engulf =
      (curr.close < curr.open) &&
      (prev.close > prev.open) &&
      (curr.open >= prev.close) &&
      (curr.close <= prev.open) &&
      (body_to_range >= min_body_to_range);

   bool bullish_pin =
      (curr.close >= curr.open) &&
      (lower_wick > 0.0) &&
      (MbCandleSafeRatio(lower_wick,MathMax(body,0.0000001)) >= pin_wick_ratio_min);

   bool bearish_pin =
      (curr.close <= curr.open) &&
      (upper_wick > 0.0) &&
      (MbCandleSafeRatio(upper_wick,MathMax(body,0.0000001)) >= pin_wick_ratio_min);

   if(bullish_engulf)
     {
      out.score_long += 0.65;
      out.patterns = (out.patterns == "NONE" ? "BULLISH_ENGULFING" : out.patterns + "|BULLISH_ENGULFING");
     }
   if(bearish_engulf)
     {
      out.score_short += 0.65;
      out.patterns = (out.patterns == "NONE" ? "BEARISH_ENGULFING" : out.patterns + "|BEARISH_ENGULFING");
     }
   if(bullish_pin)
     {
      out.score_long += 0.35;
      out.patterns = (out.patterns == "NONE" ? "BULLISH_PIN_REJECTION" : out.patterns + "|BULLISH_PIN_REJECTION");
     }
   if(bearish_pin)
     {
      out.score_short += 0.35;
      out.patterns = (out.patterns == "NONE" ? "BEARISH_PIN_REJECTION" : out.patterns + "|BEARISH_PIN_REJECTION");
     }

   if(body_to_range >= min_body_to_range && curr.close > curr.open && curr.close > prev.close)
     {
      out.score_long += 0.15;
      out.patterns = (out.patterns == "NONE" ? "BULLISH_BODY_MOMENTUM" : out.patterns + "|BULLISH_BODY_MOMENTUM");
     }
   if(body_to_range >= min_body_to_range && curr.close < curr.open && curr.close < prev.close)
     {
      out.score_short += 0.15;
      out.patterns = (out.patterns == "NONE" ? "BEARISH_BODY_MOMENTUM" : out.patterns + "|BEARISH_BODY_MOMENTUM");
     }

   out.score_long = MathMax(0.0,MathMin(1.0,out.score_long));
   out.score_short = MathMax(0.0,MathMin(1.0,out.score_short));
   if(out.score_long > out.score_short)
      out.bias = "UP";
   else if(out.score_short > out.score_long)
      out.bias = "DOWN";
   else
      out.bias = "NONE";

   double max_score = MathMax(out.score_long,out.score_short);
   out.quality_grade = "POOR";
   if(max_score >= 0.70)
      out.quality_grade = "GOOD";
   else if(max_score >= 0.35)
      out.quality_grade = "FAIR";

   if((intended_side == MB_SIGNAL_BUY && out.bias == "DOWN") || (intended_side == MB_SIGNAL_SELL && out.bias == "UP"))
      out.no_trade_hint = true;

   out.reason_code = "CANDLE_NEUTRAL";
   if(out.no_trade_hint)
      out.reason_code = "CANDLE_CONFLICT";
   else if(out.bias == "UP")
      out.reason_code = "CANDLE_BULLISH";
   else if(out.bias == "DOWN")
      out.reason_code = "CANDLE_BEARISH";

   out.ready = true;
  }

#endif
