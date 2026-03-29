#ifndef MB_PRETRADE_TRUTH_INCLUDED
#define MB_PRETRADE_TRUTH_INCLUDED

#include "MbRuntimeTypes.mqh"
#include "MbExecutionCommon.mqh"
#include "MbStorage.mqh"

struct MbPreTradeTruthRecord
  {
   string   schema_version;
   string   source;
   string   symbol_alias;
   string   candidate_id;
   string   correlation_id;

   string   order_type;
   string   request_action;
   double   requested_volume;
   double   requested_price;
   double   requested_sl;
   double   requested_tp;

   int      digits;
   double   point;
   double   tick_size;
   double   volume_min;
   double   volume_max;
   double   volume_step;

   double   bid;
   double   ask;
   double   spread_points;

   bool     check_function_ok;
   long     check_retcode;
   string   check_comment;
   double   margin_required;
   double   margin_free;
   double   margin_level;
   double   equity;
   double   balance;

   double   profit_if_tp;
   double   profit_if_sl;

   datetime server_time;
   datetime utc_time;
  };

string MbPreTradeTruthNormalizeText(const string value)
  {
   string out = value;
   StringReplace(out,";",", ");
   StringReplace(out,"\r"," ");
   StringReplace(out,"\n"," ");
   return out;
  }

string MbPreTradeTruthShortSetupToken(const string setup_type)
  {
   string token = MbStoragePathSanitizeToken(setup_type);
   if(StringLen(token) > 3)
      token = StringSubstr(token,0,3);
   return token;
  }

string MbPreTradeTruthBuildCandidateId(const string symbol,const datetime ts,const MbSignalDecision &signal)
  {
   string symbol_token = MbStoragePathSanitizeToken(MbCanonicalSymbol(symbol));
   if(StringLen(symbol_token) > 6)
      symbol_token = StringSubstr(symbol_token,0,6);

   string side_token = "N";
   if(signal.side == MB_SIGNAL_BUY)
      side_token = "B";
   else if(signal.side == MB_SIGNAL_SELL)
      side_token = "S";

   return symbol_token + StringFormat("%I64d",(long)ts) + side_token + MbPreTradeTruthShortSetupToken(signal.setup_type);
  }

string MbPreTradeTruthBuildCorrelationId(const string symbol_alias,const string candidate_id,const datetime server_time)
  {
   return MbStoragePathSanitizeToken(symbol_alias) + "_" + MbStoragePathSanitizeToken(candidate_id) + "_" + StringFormat("%I64d",(long)server_time);
  }

string MbPreTradeTruthBuildRequestComment(const string candidate_id)
  {
   string cid = MbStoragePathSanitizeToken(candidate_id);
   if(StringLen(cid) > 27)
      cid = StringSubstr(cid,0,27);
   return "CID=" + cid;
  }

string MbPreTradeTruthSpoolDir()
  {
   return MbRootPath() + "\\spool\\pretrade_truth";
  }

void MbPreTradeTruthEnsureDirs()
  {
   MbEnsureDir(MbRootPath());
   MbEnsureDir(MbRootPath() + "\\spool");
   MbEnsureDir(MbPreTradeTruthSpoolDir());
  }

void MbPreTradeTruthPrepareMarketRequest(
   const MbSymbolProfile &profile,
   const ulong magic,
   const MbSignalSide side,
   const double lots,
   const double entry_price,
   const double sl_price,
   const double tp_price,
   const string comment,
   MqlTradeRequest &request
)
  {
   ZeroMemory(request);
   request.action = TRADE_ACTION_DEAL;
   request.magic = magic;
   request.symbol = profile.symbol;
   request.volume = lots;
   request.price = entry_price;
   request.sl = sl_price;
   request.tp = tp_price;
   request.deviation = (ulong)profile.deviation_points;
   request.type_filling = MbResolveFilling(profile.symbol);
   request.comment = comment;
   if(side == MB_SIGNAL_BUY)
      request.type = ORDER_TYPE_BUY;
   else if(side == MB_SIGNAL_SELL)
      request.type = ORDER_TYPE_SELL;
  }

double MbPreTradeTruthResolveOpenPrice(const MqlTradeRequest &request,const MqlTick &tick)
  {
   if(request.price > 0.0)
      return request.price;

   ENUM_ORDER_TYPE order_type = (ENUM_ORDER_TYPE)request.type;
   if(order_type == ORDER_TYPE_BUY ||
      order_type == ORDER_TYPE_BUY_LIMIT ||
      order_type == ORDER_TYPE_BUY_STOP ||
      order_type == ORDER_TYPE_BUY_STOP_LIMIT)
      return tick.ask;

   if(order_type == ORDER_TYPE_SELL ||
      order_type == ORDER_TYPE_SELL_LIMIT ||
      order_type == ORDER_TYPE_SELL_STOP ||
      order_type == ORDER_TYPE_SELL_STOP_LIMIT)
      return tick.bid;

   return (tick.ask > 0.0 ? tick.ask : tick.bid);
  }

bool MbPreTradeTruthEvaluate(
   const string source,
   const string symbol_alias,
   const string candidate_id,
   const MqlTradeRequest &request,
   MbPreTradeTruthRecord &out_record
)
  {
   ZeroMemory(out_record);

   if(StringLen(request.symbol) <= 0)
      return false;

   MqlTick tick;
   ZeroMemory(tick);
   if(!SymbolInfoTick(request.symbol,tick))
      return false;

   MqlTradeCheckResult check;
   ZeroMemory(check);
   bool check_ok = OrderCheck(request,check);

   double point = SymbolInfoDouble(request.symbol,SYMBOL_POINT);
   double tick_size = SymbolInfoDouble(request.symbol,SYMBOL_TRADE_TICK_SIZE);
   double volume_min = SymbolInfoDouble(request.symbol,SYMBOL_VOLUME_MIN);
   double volume_max = SymbolInfoDouble(request.symbol,SYMBOL_VOLUME_MAX);
   double volume_step = SymbolInfoDouble(request.symbol,SYMBOL_VOLUME_STEP);
   int digits = (int)SymbolInfoInteger(request.symbol,SYMBOL_DIGITS);
   double spread_points = 0.0;
   if(point > 0.0)
      spread_points = (tick.ask - tick.bid) / point;

   double open_price = MbPreTradeTruthResolveOpenPrice(request,tick);
   double profit_if_tp = 0.0;
   if(request.tp > 0.0)
      OrderCalcProfit((ENUM_ORDER_TYPE)request.type,request.symbol,request.volume,open_price,request.tp,profit_if_tp);

   double profit_if_sl = 0.0;
   if(request.sl > 0.0)
      OrderCalcProfit((ENUM_ORDER_TYPE)request.type,request.symbol,request.volume,open_price,request.sl,profit_if_sl);

   datetime server_time = TimeTradeServer();
   if(server_time <= 0)
      server_time = TimeCurrent();

   out_record.schema_version = "1.0";
   out_record.source = source;
   out_record.symbol_alias = MbCanonicalSymbol(symbol_alias);
   out_record.candidate_id = candidate_id;
   out_record.correlation_id = MbPreTradeTruthBuildCorrelationId(out_record.symbol_alias,candidate_id,server_time);
   out_record.order_type = EnumToString((ENUM_ORDER_TYPE)request.type);
   out_record.request_action = EnumToString((ENUM_TRADE_REQUEST_ACTIONS)request.action);
   out_record.requested_volume = request.volume;
   out_record.requested_price = open_price;
   out_record.requested_sl = request.sl;
   out_record.requested_tp = request.tp;
   out_record.digits = digits;
   out_record.point = point;
   out_record.tick_size = tick_size;
   out_record.volume_min = volume_min;
   out_record.volume_max = volume_max;
   out_record.volume_step = volume_step;
   out_record.bid = tick.bid;
   out_record.ask = tick.ask;
   out_record.spread_points = spread_points;
   out_record.check_function_ok = check_ok;
   out_record.check_retcode = (long)check.retcode;
   out_record.check_comment = MbPreTradeTruthNormalizeText(check.comment);
   out_record.margin_required = check.margin;
   out_record.margin_free = check.margin_free;
   out_record.margin_level = check.margin_level;
   out_record.equity = check.equity;
   out_record.balance = check.balance;
   out_record.profit_if_tp = profit_if_tp;
   out_record.profit_if_sl = profit_if_sl;
   out_record.server_time = server_time;
   out_record.utc_time = TimeGMT();
   return true;
  }

int MbPreTradeTruthOpenAppend(const string symbol_alias)
  {
   MbPreTradeTruthEnsureDirs();
   string path = MbPreTradeTruthSpoolDir() + "\\pretrade_truth_" + MbStoragePathSanitizeToken(symbol_alias) + ".csv";
   int handle = FileOpen(path,FILE_COMMON | FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE,';');
   if(handle == INVALID_HANDLE)
      return INVALID_HANDLE;

   if(FileSize(handle) == 0)
     {
      FileWrite(
         handle,
         "schema_version",
         "source",
         "symbol_alias",
         "candidate_id",
         "correlation_id",
         "order_type",
         "request_action",
         "requested_volume",
         "requested_price",
         "requested_sl",
         "requested_tp",
         "digits",
         "point",
         "tick_size",
         "volume_min",
         "volume_max",
         "volume_step",
         "bid",
         "ask",
         "spread_points",
         "check_function_ok",
         "check_retcode",
         "check_comment",
         "margin_required",
         "margin_free",
         "margin_level",
         "equity",
         "balance",
         "profit_if_tp",
         "profit_if_sl",
         "server_time",
         "utc_time"
      );
     }

   FileSeek(handle,0,SEEK_END);
   return handle;
  }

bool MbPreTradeTruthWriteRecord(const MbPreTradeTruthRecord &record)
  {
   int handle = MbPreTradeTruthOpenAppend(record.symbol_alias);
   if(handle == INVALID_HANDLE)
      return false;

   FileWrite(
      handle,
      record.schema_version,
      record.source,
      record.symbol_alias,
      record.candidate_id,
      record.correlation_id,
      record.order_type,
      record.request_action,
      DoubleToString(record.requested_volume,8),
      DoubleToString(record.requested_price,record.digits),
      DoubleToString(record.requested_sl,record.digits),
      DoubleToString(record.requested_tp,record.digits),
      IntegerToString(record.digits),
      DoubleToString(record.point,10),
      DoubleToString(record.tick_size,10),
      DoubleToString(record.volume_min,8),
      DoubleToString(record.volume_max,8),
      DoubleToString(record.volume_step,8),
      DoubleToString(record.bid,record.digits),
      DoubleToString(record.ask,record.digits),
      DoubleToString(record.spread_points,4),
      (record.check_function_ok ? "1" : "0"),
      StringFormat("%I64d",record.check_retcode),
      record.check_comment,
      DoubleToString(record.margin_required,2),
      DoubleToString(record.margin_free,2),
      DoubleToString(record.margin_level,4),
      DoubleToString(record.equity,2),
      DoubleToString(record.balance,2),
      DoubleToString(record.profit_if_tp,2),
      DoubleToString(record.profit_if_sl,2),
      TimeToString(record.server_time,TIME_DATE | TIME_SECONDS),
      TimeToString(record.utc_time,TIME_DATE | TIME_SECONDS)
   );
   FileFlush(handle);
   FileClose(handle);
   return true;
  }

bool MbPreTradeTruthEvaluateAndWrite(
   const string source,
   const string symbol_alias,
   const string candidate_id,
   const MqlTradeRequest &request,
   MbPreTradeTruthRecord &out_record
)
  {
   if(!MbPreTradeTruthEvaluate(source,symbol_alias,candidate_id,request,out_record))
      return false;
   return MbPreTradeTruthWriteRecord(out_record);
  }

#endif