#ifndef MB_PAPER_TRADING_INCLUDED
#define MB_PAPER_TRADING_INCLUDED

#include "MbRuntimeTypes.mqh"
#include "MbStorage.mqh"

struct MbPaperPositionState
  {
   bool active;
   MbSignalSide side;
   double lots;
   double entry_price;
   double sl_price;
   double tp_price;
   double last_mark_price;
   double opened_spread_points;
   datetime opened_at;
   datetime expires_at;
   string entry_reason;
   string setup_type;
   string market_regime;
   string spread_regime;
   string execution_regime;
   string confidence_bucket;
   double confidence_score;
   double risk_multiplier;
   string candle_bias;
   string candle_quality_grade;
   double candle_score;
   string renko_bias;
   string renko_quality_grade;
   double renko_score;
   int renko_run_length;
   bool renko_reversal_flag;
   double modeled_slippage_points;
   double modeled_commission_points;
   double gross_pln;
   double spread_cost_pln;
   double slippage_cost_pln;
   double commission_pln;
   double swap_pln;
   double extra_fee_pln;
   double net_pln;
  };

void MbPaperPositionReset(MbPaperPositionState &state)
  {
   state.active = false;
   state.side = MB_SIGNAL_NONE;
   state.lots = 0.0;
   state.entry_price = 0.0;
   state.sl_price = 0.0;
   state.tp_price = 0.0;
   state.last_mark_price = 0.0;
   state.opened_spread_points = 0.0;
   state.opened_at = 0;
   state.expires_at = 0;
   state.entry_reason = "";
   state.setup_type = "NONE";
   state.market_regime = "UNKNOWN";
   state.spread_regime = "UNKNOWN";
   state.execution_regime = "UNKNOWN";
   state.confidence_bucket = "LOW";
   state.confidence_score = 0.0;
   state.risk_multiplier = 1.0;
   state.candle_bias = "NONE";
   state.candle_quality_grade = "UNKNOWN";
   state.candle_score = 0.0;
   state.renko_bias = "NONE";
   state.renko_quality_grade = "UNKNOWN";
   state.renko_score = 0.0;
   state.renko_run_length = 0;
   state.renko_reversal_flag = false;
   state.modeled_slippage_points = 0.0;
   state.modeled_commission_points = 0.0;
   state.gross_pln = 0.0;
   state.spread_cost_pln = 0.0;
   state.slippage_cost_pln = 0.0;
   state.commission_pln = 0.0;
   state.swap_pln = 0.0;
   state.extra_fee_pln = 0.0;
   state.net_pln = 0.0;
  }

bool MbSavePaperPosition(const string symbol,const MbPaperPositionState &state)
  {
   int h = FileOpen(MbStateFilePath(symbol,"paper_position.csv"), FILE_COMMON | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;
   FileWrite(h,"active",(state.active ? 1 : 0));
   FileWrite(h,"side",(int)state.side);
   FileWrite(h,"lots",DoubleToString(state.lots,4));
   FileWrite(h,"entry_price",DoubleToString(state.entry_price,_Digits));
   FileWrite(h,"sl_price",DoubleToString(state.sl_price,_Digits));
   FileWrite(h,"tp_price",DoubleToString(state.tp_price,_Digits));
   FileWrite(h,"last_mark_price",DoubleToString(state.last_mark_price,_Digits));
   FileWrite(h,"opened_spread_points",DoubleToString(state.opened_spread_points,2));
   FileWrite(h,"opened_at",(long)state.opened_at);
   FileWrite(h,"expires_at",(long)state.expires_at);
   FileWrite(h,"entry_reason",state.entry_reason);
   FileWrite(h,"setup_type",state.setup_type);
   FileWrite(h,"market_regime",state.market_regime);
   FileWrite(h,"spread_regime",state.spread_regime);
   FileWrite(h,"execution_regime",state.execution_regime);
   FileWrite(h,"confidence_bucket",state.confidence_bucket);
   FileWrite(h,"confidence_score",DoubleToString(state.confidence_score,4));
   FileWrite(h,"risk_multiplier",DoubleToString(state.risk_multiplier,4));
   FileWrite(h,"candle_bias",state.candle_bias);
   FileWrite(h,"candle_quality_grade",state.candle_quality_grade);
   FileWrite(h,"candle_score",DoubleToString(state.candle_score,4));
   FileWrite(h,"renko_bias",state.renko_bias);
   FileWrite(h,"renko_quality_grade",state.renko_quality_grade);
   FileWrite(h,"renko_score",DoubleToString(state.renko_score,4));
   FileWrite(h,"renko_run_length",state.renko_run_length);
   FileWrite(h,"renko_reversal_flag",(state.renko_reversal_flag ? 1 : 0));
   FileWrite(h,"modeled_slippage_points",DoubleToString(state.modeled_slippage_points,4));
   FileWrite(h,"modeled_commission_points",DoubleToString(state.modeled_commission_points,4));
   FileWrite(h,"gross_pln",DoubleToString(state.gross_pln,6));
   FileWrite(h,"spread_cost_pln",DoubleToString(state.spread_cost_pln,6));
   FileWrite(h,"slippage_cost_pln",DoubleToString(state.slippage_cost_pln,6));
   FileWrite(h,"commission_pln",DoubleToString(state.commission_pln,6));
   FileWrite(h,"swap_pln",DoubleToString(state.swap_pln,6));
   FileWrite(h,"extra_fee_pln",DoubleToString(state.extra_fee_pln,6));
   FileWrite(h,"net_pln",DoubleToString(state.net_pln,6));
   FileClose(h);
   return true;
  }

bool MbLoadPaperPosition(const string symbol,MbPaperPositionState &state)
  {
   MbPaperPositionReset(state);
   int h = FileOpen(MbStateFilePath(symbol,"paper_position.csv"), FILE_COMMON | FILE_READ | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;
   while(!FileIsEnding(h))
     {
      string key = FileReadString(h);
      string value = FileReadString(h);
      if(key == "active") state.active = (StringToInteger(value) != 0);
      else if(key == "side") state.side = (MbSignalSide)StringToInteger(value);
      else if(key == "lots") state.lots = StringToDouble(value);
      else if(key == "entry_price") state.entry_price = StringToDouble(value);
      else if(key == "sl_price") state.sl_price = StringToDouble(value);
      else if(key == "tp_price") state.tp_price = StringToDouble(value);
      else if(key == "last_mark_price") state.last_mark_price = StringToDouble(value);
      else if(key == "opened_spread_points") state.opened_spread_points = StringToDouble(value);
      else if(key == "opened_at") state.opened_at = (datetime)StringToInteger(value);
      else if(key == "expires_at") state.expires_at = (datetime)StringToInteger(value);
      else if(key == "entry_reason") state.entry_reason = value;
      else if(key == "setup_type") state.setup_type = value;
      else if(key == "market_regime") state.market_regime = value;
      else if(key == "spread_regime") state.spread_regime = value;
      else if(key == "execution_regime") state.execution_regime = value;
      else if(key == "confidence_bucket") state.confidence_bucket = value;
      else if(key == "confidence_score") state.confidence_score = StringToDouble(value);
      else if(key == "risk_multiplier") state.risk_multiplier = StringToDouble(value);
      else if(key == "candle_bias") state.candle_bias = value;
      else if(key == "candle_quality_grade") state.candle_quality_grade = value;
      else if(key == "candle_score") state.candle_score = StringToDouble(value);
      else if(key == "renko_bias") state.renko_bias = value;
      else if(key == "renko_quality_grade") state.renko_quality_grade = value;
      else if(key == "renko_score") state.renko_score = StringToDouble(value);
      else if(key == "renko_run_length") state.renko_run_length = (int)StringToInteger(value);
      else if(key == "renko_reversal_flag") state.renko_reversal_flag = (StringToInteger(value) != 0);
      else if(key == "modeled_slippage_points") state.modeled_slippage_points = StringToDouble(value);
      else if(key == "modeled_commission_points") state.modeled_commission_points = StringToDouble(value);
      else if(key == "gross_pln") state.gross_pln = StringToDouble(value);
      else if(key == "spread_cost_pln") state.spread_cost_pln = StringToDouble(value);
      else if(key == "slippage_cost_pln") state.slippage_cost_pln = StringToDouble(value);
      else if(key == "commission_pln") state.commission_pln = StringToDouble(value);
      else if(key == "swap_pln") state.swap_pln = StringToDouble(value);
      else if(key == "extra_fee_pln") state.extra_fee_pln = StringToDouble(value);
      else if(key == "net_pln") state.net_pln = StringToDouble(value);
     }
   FileClose(h);
   return true;
  }

double MbPaperPointsToMoney(
   const MbMarketSnapshot &snapshot,
   const double lots,
   const double points
)
  {
   if(lots <= 0.0 || points <= 0.0 || snapshot.tick_size <= 0.0 || snapshot.tick_value <= 0.0 || _Point <= 0.0)
      return 0.0;

   double price_distance = points * _Point;
   return ((price_distance / snapshot.tick_size) * snapshot.tick_value * lots);
  }

void MbPaperRefreshEconomics(
   const MbMarketSnapshot &snapshot,
   MbPaperPositionState &state,
   const double gross_pnl,
   const datetime now_ts
)
  {
   state.gross_pln = gross_pnl;
   // Paper PnL is already marked from executable bid/ask prices, so spread is implicit there.
   state.spread_cost_pln = 0.0;
   state.slippage_cost_pln = MbPaperPointsToMoney(snapshot,state.lots,state.modeled_slippage_points);
   state.commission_pln = MbPaperPointsToMoney(snapshot,state.lots,state.modeled_commission_points);
   if(state.opened_at <= 0 || now_ts <= state.opened_at || (now_ts - state.opened_at) < 86400)
      state.swap_pln = 0.0;
   state.net_pln = state.gross_pln - state.slippage_cost_pln - state.commission_pln - state.swap_pln - state.extra_fee_pln;
  }

bool MbPaperHasOpenPosition(const MbPaperPositionState &state)
  {
   return state.active;
  }

bool MbPaperReadContractValue(const string symbol,const string key_name,string &out_value)
  {
   out_value = "";
   string contract_path = MbStateFilePath(symbol,"student_gate_contract.csv");
   if(!FileIsExist(contract_path,FILE_COMMON))
      return false;

   int h = FileOpen(contract_path, FILE_COMMON | FILE_READ | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;

   while(!FileIsEnding(h))
     {
      string key = FileReadString(h);
      string value = FileReadString(h);
      if(key == key_name)
        {
         out_value = value;
         FileClose(h);
         return true;
        }
     }

   FileClose(h);
   return false;
  }

bool MbPaperReadBoolContractValue(const string symbol,const string key_name)
  {
   string value = "";
   if(!MbPaperReadContractValue(symbol,key_name,value))
      return false;
   StringToUpper(value);
   return (value == "1" || value == "TRUE" || value == "YES" || value == "ON");
  }

bool MbPaperLiveUniverseAllowsSymbol(const string symbol,string &out_bucket,string &out_runtime_scope)
  {
   out_bucket = "";
   out_runtime_scope = "";
   MbPaperReadContractValue(symbol,"paper_live_bucket",out_bucket);
   MbPaperReadContractValue(symbol,"runtime_scope",out_runtime_scope);
   return MbPaperReadBoolContractValue(symbol,"paper_live_enabled");
  }

bool MbPaperOpenPosition(
   MbPaperPositionState &state,
   const MbSignalSide side,
   const double lots,
   const double entry_price,
   const double sl_price,
   const double tp_price,
   const double spread_points,
   const datetime now_ts,
   const int hold_seconds,
   const string reason_code,
   const string setup_type,
   const string market_regime,
   const string spread_regime,
   const string execution_regime,
   const string confidence_bucket,
   const double confidence_score,
   const double risk_multiplier,
   const string candle_bias,
   const string candle_quality_grade,
   const double candle_score,
   const string renko_bias,
   const string renko_quality_grade,
   const double renko_score,
   const int renko_run_length,
   const bool renko_reversal_flag,
   const double modeled_slippage_points,
   const double modeled_commission_points,
   const bool enforce_paper_live_scope = false
)
  {
   if(enforce_paper_live_scope)
     {
      string paper_live_bucket = "";
      string runtime_scope = "";
      if(!MbPaperLiveUniverseAllowsSymbol(Symbol(),paper_live_bucket,runtime_scope))
        {
         MbPaperPositionReset(state);
         state.entry_reason = "PAPER_LIVE_SYMBOL_DISABLED";
         state.setup_type = "PAPER_LIVE_SYMBOL_DISABLED";
         state.spread_regime = paper_live_bucket;
         state.execution_regime = runtime_scope;
         return false;
        }
     }

   state.active = true;
   state.side = side;
   state.lots = lots;
   state.entry_price = entry_price;
   state.sl_price = sl_price;
   state.tp_price = tp_price;
   state.last_mark_price = entry_price;
   state.opened_spread_points = spread_points;
   state.opened_at = now_ts;
   state.expires_at = (now_ts + MathMax(60,hold_seconds));
   state.entry_reason = reason_code;
   state.setup_type = setup_type;
   state.market_regime = market_regime;
   state.spread_regime = spread_regime;
   state.execution_regime = execution_regime;
   state.confidence_bucket = confidence_bucket;
   state.confidence_score = confidence_score;
   state.risk_multiplier = risk_multiplier;
   state.candle_bias = candle_bias;
   state.candle_quality_grade = candle_quality_grade;
   state.candle_score = candle_score;
   state.renko_bias = renko_bias;
   state.renko_quality_grade = renko_quality_grade;
   state.renko_score = renko_score;
   state.renko_run_length = renko_run_length;
   state.renko_reversal_flag = renko_reversal_flag;
   state.modeled_slippage_points = MathMax(0.0,modeled_slippage_points);
   state.modeled_commission_points = MathMax(0.0,modeled_commission_points);
   state.gross_pln = 0.0;
   state.spread_cost_pln = 0.0;
   state.slippage_cost_pln = 0.0;
   state.commission_pln = 0.0;
   state.swap_pln = 0.0;
   state.extra_fee_pln = 0.0;
   state.net_pln = 0.0;
   return true;
  }

bool MbPaperOpenPosition(
   MbPaperPositionState &state,
   const MbSignalSide side,
   const double lots,
   const double entry_price,
   const double sl_price,
   const double tp_price,
   const double spread_points,
   const datetime now_ts,
   const int hold_seconds,
   const string reason_code
)
  {
   return MbPaperOpenPosition(
      state,
      side,
      lots,
      entry_price,
      sl_price,
      tp_price,
      spread_points,
      now_ts,
      hold_seconds,
      reason_code,
      reason_code,
      "UNKNOWN",
      "UNKNOWN",
      "UNKNOWN",
      "LOW",
      0.0,
      1.0,
      "NONE",
      "UNKNOWN",
      0.0,
      "NONE",
      "UNKNOWN",
      0.0,
      0,
      false,
      0.0,
      0.0,
      false
   );
  }

double MbPaperProfitMoney(
   const MbMarketSnapshot &snapshot,
   const MbPaperPositionState &state,
   const double close_price
)
  {
   if(snapshot.tick_size <= 0.0 || snapshot.tick_value <= 0.0 || state.lots <= 0.0)
      return 0.0;

   double price_delta = 0.0;
   if(state.side == MB_SIGNAL_BUY)
      price_delta = (close_price - state.entry_price);
   else if(state.side == MB_SIGNAL_SELL)
      price_delta = (state.entry_price - close_price);

   return ((price_delta / snapshot.tick_size) * snapshot.tick_value * state.lots);
  }

bool MbPaperMaybeClosePosition(
   const MbMarketSnapshot &snapshot,
   MbPaperPositionState &state,
   const datetime now_ts,
   double &pnl_money,
   string &close_reason,
   MbPaperPositionState &closed_state
)
  {
   pnl_money = 0.0;
   close_reason = "";
   MbPaperPositionReset(closed_state);
   if(!state.active)
      return false;

   double mark_price = 0.0;
   if(state.side == MB_SIGNAL_BUY)
      mark_price = snapshot.bid;
   else if(state.side == MB_SIGNAL_SELL)
      mark_price = snapshot.ask;
   else
      return false;

   state.last_mark_price = mark_price;

   bool should_close = false;
   if(state.side == MB_SIGNAL_BUY)
     {
      if(state.sl_price > 0.0 && mark_price <= state.sl_price)
        {
         should_close = true;
         close_reason = "PAPER_SL";
        }
      else if(state.tp_price > 0.0 && mark_price >= state.tp_price)
        {
         should_close = true;
         close_reason = "PAPER_TP";
        }
     }
   else if(state.side == MB_SIGNAL_SELL)
     {
      if(state.sl_price > 0.0 && mark_price >= state.sl_price)
        {
         should_close = true;
         close_reason = "PAPER_SL";
        }
      else if(state.tp_price > 0.0 && mark_price <= state.tp_price)
        {
         should_close = true;
         close_reason = "PAPER_TP";
        }
     }

   if(!should_close && state.expires_at > 0 && now_ts >= state.expires_at)
     {
      should_close = true;
      close_reason = "PAPER_TIMEOUT";
     }

   if(!should_close)
      return false;

   pnl_money = MbPaperProfitMoney(snapshot,state,mark_price);
   MbPaperRefreshEconomics(snapshot,state,pnl_money,now_ts);
   closed_state = state;
   MbPaperPositionReset(state);
   return true;
  }

bool MbPaperMaybeClosePosition(
   const MbMarketSnapshot &snapshot,
   MbPaperPositionState &state,
   const datetime now_ts,
   double &pnl_money,
   string &close_reason
)
  {
   MbPaperPositionState ignored_closed_state;
   MbPaperPositionReset(ignored_closed_state);
   return MbPaperMaybeClosePosition(snapshot,state,now_ts,pnl_money,close_reason,ignored_closed_state);
  }

#endif
