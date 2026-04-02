#ifndef MB_RENKO_ADVISORY_INCLUDED
#define MB_RENKO_ADVISORY_INCLUDED

struct MbRenkoAdvisory
  {
   bool ready;
   bool reversal_flag;
   string bias;
   string quality_grade;
   string reason_code;
   double score_long;
   double score_short;
   double brick_size_points;
   int bricks_count;
   int run_length;
  };

void MbRenkoAdvisoryReset(MbRenkoAdvisory &out)
  {
   out.ready = false;
   out.reversal_flag = false;
   out.bias = "NONE";
   out.quality_grade = "UNKNOWN";
   out.reason_code = "RENKO_NOT_EVALUATED";
   out.score_long = 0.0;
   out.score_short = 0.0;
   out.brick_size_points = 0.0;
   out.bricks_count = 0;
   out.run_length = 0;
  }

void MbEvaluateRenkoAdvisory(
   const string symbol,
   const double point,
   const double atr_points,
   const MbSignalSide intended_side,
   MbRenkoAdvisory &out
)
  {
   MbRenkoAdvisoryReset(out);
   if(point <= 0.0 || atr_points <= 0.0)
     {
      out.reason_code = "RENKO_INVALID_CONFIG";
      return;
     }

   MqlTick ticks[];
   int copied = CopyTicks(symbol,ticks,COPY_TICKS_INFO,0,320);
   if(copied < 40)
     {
      out.reason_code = "RENKO_TICKS_NOT_READY";
      return;
     }

   double brick_size_points = MathMax(4.0,MathMin(12.0,MathRound(atr_points * 0.35)));
   double brick_size_price = brick_size_points * point;
   if(brick_size_price <= 0.0)
     {
      out.reason_code = "RENKO_BRICK_INVALID";
      return;
     }

   int last_dir = 0;
   int run_length = 0;
   int bricks = 0;
   double last_close = ((ticks[0].bid + ticks[0].ask) * 0.5);
   for(int i = 1; i < copied; ++i)
     {
      double px = ((ticks[i].bid + ticks[i].ask) * 0.5);
      while(px >= (last_close + brick_size_price))
        {
         bool reversal = (last_dir == -1);
         run_length = (reversal ? 1 : (last_dir == 1 ? run_length + 1 : 1));
         out.reversal_flag = reversal;
         last_close += brick_size_price;
         last_dir = 1;
         bricks++;
        }
      while(px <= (last_close - brick_size_price))
        {
         bool reversal = (last_dir == 1);
         run_length = (reversal ? 1 : (last_dir == -1 ? run_length + 1 : 1));
         out.reversal_flag = reversal;
         last_close -= brick_size_price;
         last_dir = -1;
         bricks++;
        }
     }

   if(bricks < 2 || last_dir == 0)
     {
      out.reason_code = "RENKO_NOT_ENOUGH_MOVE";
      return;
     }

   out.ready = true;
   out.brick_size_points = brick_size_points;
   out.bricks_count = bricks;
   out.run_length = run_length;
   out.bias = (last_dir > 0 ? "UP" : "DOWN");

   double base_score = MathMin(1.0,0.25 + (0.18 * MathMin(4,run_length)));
   if(out.reversal_flag)
      base_score = MathMax(0.20,base_score - 0.18);

   if(out.bias == "UP")
      out.score_long = base_score;
   else
      out.score_short = base_score;

   double max_score = MathMax(out.score_long,out.score_short);
   out.quality_grade = "POOR";
   if(max_score >= 0.75)
      out.quality_grade = "GOOD";
   else if(max_score >= 0.45)
      out.quality_grade = "FAIR";

   out.reason_code = "RENKO_OK";
   if((intended_side == MB_SIGNAL_BUY && out.bias == "DOWN") || (intended_side == MB_SIGNAL_SELL && out.bias == "UP"))
      out.reason_code = (out.reversal_flag ? "RENKO_REVERSAL_CONFLICT" : "RENKO_CONFLICT");
  }

#endif
