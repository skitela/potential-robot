#ifndef MB_EXECUTION_TRUTH_FEED_INCLUDED
#define MB_EXECUTION_TRUTH_FEED_INCLUDED

#include "MbExecutionCommon.mqh"
#include "MbStorage.mqh"

struct MbExecutionTruthRecord
  {
   string   schema_version;
   string   source;
   string   symbol_alias;
   string   candidate_id;

   string   trans_type;
   string   request_action;
   string   request_type;
   long     result_retcode;

   ulong    order_ticket;
   ulong    deal_ticket;
   ulong    position_ticket;

   double   request_volume;
   double   request_price;
   double   execution_volume;
   double   execution_price;

   double   bid;
   double   ask;
   double   point;
   int      digits;
   double   spread_points;
   double   slippage_points;

   double   commission;
   double   swap;
   double   fee;
   double   profit;
   double   net_observed;

   string   deal_entry;
   string   deal_reason;
   string   request_comment;
   string   deal_comment;

   datetime server_time;
   long     time_msc;
  };

string MbExecutionTruthNormalizeText(const string value)
  {
   string out = value;
   StringReplace(out,";",", ");
   StringReplace(out,"\r"," ");
   StringReplace(out,"\n"," ");
   return out;
  }

string MbExecutionTruthSpoolDir()
  {
   return MbRootPath() + "\\spool\\execution_truth";
  }

string MbExecutionTruthSpoolFilePath(const string symbol_alias)
  {
   return MbExecutionTruthSpoolDir() + "\\execution_truth_" + MbStoragePathSanitizeToken(MbCanonicalSymbol(symbol_alias)) + ".csv";
  }

void MbExecutionTruthDebugLog(const string stage,const string detail)
  {
   MbEnsureDir(MbRootPath());
   MbEnsureDir(MbRootPath() + "\\run");
   string path = MbRootPath() + "\\run\\mt5_truth_debug.csv";
   int handle = FileOpen(path,FILE_COMMON | FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE,';');
   if(handle == INVALID_HANDLE)
      return;
   if(FileSize(handle) == 0)
      FileWrite(handle,"ts","stage","detail");
   FileSeek(handle,0,SEEK_END);
   FileWrite(handle,TimeToString(TimeCurrent(),TIME_DATE | TIME_SECONDS),stage,MbExecutionTruthNormalizeText(detail));
   FileFlush(handle);
   FileClose(handle);
  }

void MbExecutionTruthEnsureDirs()
  {
   MbEnsureDir(MbRootPath());
   MbEnsureDir(MbRootPath() + "\\spool");
   MbEnsureDir(MbExecutionTruthSpoolDir());
  }

string MbExecutionTruthExtractCandidateId(const string comment)
  {
   if(StringLen(comment) <= 0)
      return "";

   int pos = StringFind(comment,"CID=");
   if(pos < 0)
      return "";

   string tail = StringSubstr(comment,pos + 4);
   int sep = StringFind(tail,"|");
   if(sep >= 0)
      tail = StringSubstr(tail,0,sep);
   return MbStoragePathSanitizeToken(tail);
  }

double MbExecutionTruthResolveSignedSlippage(const string request_type,const double request_price,const double execution_price,const double point)
  {
   if(point <= 0.0 || request_price <= 0.0 || execution_price <= 0.0)
      return 0.0;

   double raw = (execution_price - request_price) / point;
   string request_token = request_type;
   StringToUpper(request_token);
   if(StringFind(request_token,"SELL") >= 0)
      return -raw;
   return raw;
  }

int MbExecutionTruthOpenAppend(const string symbol_alias)
  {
   MbExecutionTruthEnsureDirs();
   string path = MbExecutionTruthSpoolFilePath(symbol_alias);
   ResetLastError();
   int handle = FileOpen(path,FILE_COMMON | FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE,';');
   if(handle == INVALID_HANDLE)
     {
      MbExecutionTruthDebugLog(
         "EXEC_APPEND_FAIL",
         "symbol_alias=" + MbCanonicalSymbol(symbol_alias) + ";path=" + path + ";error=" + IntegerToString(GetLastError())
      );
      return INVALID_HANDLE;
     }

   if(FileSize(handle) == 0)
     {
      FileWrite(
         handle,
         "schema_version",
         "source",
         "symbol_alias",
         "candidate_id",
         "trans_type",
         "request_action",
         "request_type",
         "result_retcode",
         "order_ticket",
         "deal_ticket",
         "position_ticket",
         "request_volume",
         "request_price",
         "execution_volume",
         "execution_price",
         "bid",
         "ask",
         "point",
         "digits",
         "spread_points",
         "slippage_points",
         "commission",
         "swap",
         "fee",
         "profit",
         "net_observed",
         "deal_entry",
         "deal_reason",
         "request_comment",
         "deal_comment",
         "server_time",
         "time_msc"
      );
     }

   FileSeek(handle,0,SEEK_END);
   return handle;
  }

bool MbExecutionTruthCapture(
   const string source,
   const string symbol_alias,
   const MqlTradeTransaction &trans,
   const MqlTradeRequest &request,
   const MqlTradeResult &result
)
  {
   string symbol = trans.symbol;
   if(StringLen(symbol) <= 0)
      symbol = request.symbol;
   if(StringLen(symbol) <= 0)
      symbol = symbol_alias;
   if(StringLen(symbol) <= 0)
      return false;

   MqlTick tick;
   ZeroMemory(tick);
   SymbolInfoTick(symbol,tick);

   MbExecutionTruthRecord record;
   ZeroMemory(record);
   record.schema_version = "1.0";
   record.source = source;
   record.symbol_alias = MbCanonicalSymbol(symbol_alias);
   record.candidate_id = MbExecutionTruthExtractCandidateId(request.comment);
   record.trans_type = EnumToString((ENUM_TRADE_TRANSACTION_TYPE)trans.type);
   record.request_action = EnumToString((ENUM_TRADE_REQUEST_ACTIONS)request.action);
   record.request_type = EnumToString((ENUM_ORDER_TYPE)request.type);
   record.result_retcode = (long)result.retcode;
   record.order_ticket = (ulong)trans.order;
   record.deal_ticket = (ulong)trans.deal;
   record.position_ticket = (ulong)trans.position;
   record.request_volume = request.volume;
   record.request_price = (request.price > 0.0 ? request.price : result.price);
   record.execution_volume = (trans.volume > 0.0 ? trans.volume : result.volume);
   record.execution_price = (trans.price > 0.0 ? trans.price : result.price);
   record.digits = (int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
   record.point = SymbolInfoDouble(symbol,SYMBOL_POINT);
   record.bid = tick.bid;
   record.ask = tick.ask;
   if(record.point > 0.0)
      record.spread_points = (record.ask - record.bid) / record.point;
   record.slippage_points = MbExecutionTruthResolveSignedSlippage(record.request_type,record.request_price,record.execution_price,record.point);
   record.request_comment = MbExecutionTruthNormalizeText(request.comment);
   record.server_time = TimeCurrent();
   record.time_msc = (long)GetMicrosecondCount();
   record.deal_entry = "";
   record.deal_reason = "";
   record.deal_comment = "";
   record.commission = 0.0;
   record.swap = 0.0;
   record.fee = 0.0;
   record.profit = 0.0;
   record.net_observed = 0.0;

   if(record.deal_ticket > 0 && HistoryDealSelect(record.deal_ticket))
     {
      record.execution_price = HistoryDealGetDouble(record.deal_ticket,DEAL_PRICE);
      record.execution_volume = HistoryDealGetDouble(record.deal_ticket,DEAL_VOLUME);
      record.commission = HistoryDealGetDouble(record.deal_ticket,DEAL_COMMISSION);
      record.swap = HistoryDealGetDouble(record.deal_ticket,DEAL_SWAP);
      record.fee = HistoryDealGetDouble(record.deal_ticket,DEAL_FEE);
      record.profit = HistoryDealGetDouble(record.deal_ticket,DEAL_PROFIT);
      record.net_observed = record.profit + record.commission + record.swap + record.fee;
      record.deal_entry = EnumToString((ENUM_DEAL_ENTRY)HistoryDealGetInteger(record.deal_ticket,DEAL_ENTRY));
      record.deal_reason = EnumToString((ENUM_DEAL_REASON)HistoryDealGetInteger(record.deal_ticket,DEAL_REASON));
      record.deal_comment = MbExecutionTruthNormalizeText(HistoryDealGetString(record.deal_ticket,DEAL_COMMENT));
      if(StringLen(record.candidate_id) <= 0)
         record.candidate_id = MbExecutionTruthExtractCandidateId(HistoryDealGetString(record.deal_ticket,DEAL_COMMENT));
      record.slippage_points = MbExecutionTruthResolveSignedSlippage(record.request_type,record.request_price,record.execution_price,record.point);
     }

   int handle = MbExecutionTruthOpenAppend(record.symbol_alias);
   if(handle == INVALID_HANDLE)
      return false;

   FileWrite(
      handle,
      record.schema_version,
      record.source,
      record.symbol_alias,
      record.candidate_id,
      record.trans_type,
      record.request_action,
      record.request_type,
      StringFormat("%I64d",record.result_retcode),
      StringFormat("%I64u",record.order_ticket),
      StringFormat("%I64u",record.deal_ticket),
      StringFormat("%I64u",record.position_ticket),
      DoubleToString(record.request_volume,8),
      DoubleToString(record.request_price,record.digits),
      DoubleToString(record.execution_volume,8),
      DoubleToString(record.execution_price,record.digits),
      DoubleToString(record.bid,record.digits),
      DoubleToString(record.ask,record.digits),
      DoubleToString(record.point,10),
      IntegerToString(record.digits),
      DoubleToString(record.spread_points,4),
      DoubleToString(record.slippage_points,4),
      DoubleToString(record.commission,2),
      DoubleToString(record.swap,2),
      DoubleToString(record.fee,2),
      DoubleToString(record.profit,2),
      DoubleToString(record.net_observed,2),
      record.deal_entry,
      record.deal_reason,
      record.request_comment,
      record.deal_comment,
      TimeToString(record.server_time,TIME_DATE | TIME_SECONDS),
      StringFormat("%I64d",record.time_msc)
   );
   FileFlush(handle);
   FileClose(handle);
   return true;
  }

bool MbExecutionTruthWritePaperOpen(
   const string source,
   const string symbol_alias,
   const string runtime_symbol,
   const string candidate_id,
   const MbSignalSide side,
   const double lots,
   const double request_price,
   const double execution_price,
   const double bid,
   const double ask,
   const datetime server_time,
   const string request_comment
)
  {
   string symbol = runtime_symbol;
   if(StringLen(symbol) <= 0)
      symbol = symbol_alias;
   if(StringLen(symbol) <= 0 || StringLen(candidate_id) <= 0)
      return false;

   MbExecutionTruthRecord record;
   ZeroMemory(record);
   record.schema_version = "1.0";
   record.source = source;
   record.symbol_alias = MbCanonicalSymbol(symbol_alias);
   record.candidate_id = candidate_id;
   record.trans_type = "PAPER_OPEN";
   record.request_action = "TRADE_ACTION_DEAL";
   if(side == MB_SIGNAL_SELL)
      record.request_type = "ORDER_TYPE_SELL";
   else
      record.request_type = "ORDER_TYPE_BUY";
   record.result_retcode = 0;
   record.order_ticket = 0;
   record.deal_ticket = 0;
   record.position_ticket = 0;
   record.request_volume = lots;
   record.request_price = request_price;
   record.execution_volume = lots;
   record.execution_price = execution_price;
   record.digits = (int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
   record.point = SymbolInfoDouble(symbol,SYMBOL_POINT);
   record.bid = bid;
   record.ask = ask;
   if(record.point > 0.0)
      record.spread_points = (record.ask - record.bid) / record.point;
   record.slippage_points = MbExecutionTruthResolveSignedSlippage(record.request_type,record.request_price,record.execution_price,record.point);
   record.commission = 0.0;
   record.swap = 0.0;
   record.fee = 0.0;
   record.profit = 0.0;
   record.net_observed = 0.0;
   record.deal_entry = "DEAL_ENTRY_IN";
   record.deal_reason = "DEAL_REASON_EXPERT";
   record.request_comment = MbExecutionTruthNormalizeText(request_comment);
   record.deal_comment = MbExecutionTruthNormalizeText(request_comment);
   record.server_time = server_time;
   record.time_msc = (long)GetMicrosecondCount();

   int handle = MbExecutionTruthOpenAppend(record.symbol_alias);
   if(handle == INVALID_HANDLE)
     {
      MbExecutionTruthDebugLog(
         "EXEC_PAPER_OPEN_FAIL",
         "symbol_alias=" + MbCanonicalSymbol(symbol_alias) + ";runtime_symbol=" + runtime_symbol + ";candidate_id=" + candidate_id + ";target_path=" + MbExecutionTruthSpoolFilePath(symbol_alias)
      );
      return false;
     }

   FileWrite(
      handle,
      record.schema_version,
      record.source,
      record.symbol_alias,
      record.candidate_id,
      record.trans_type,
      record.request_action,
      record.request_type,
      StringFormat("%I64d",record.result_retcode),
      StringFormat("%I64u",record.order_ticket),
      StringFormat("%I64u",record.deal_ticket),
      StringFormat("%I64u",record.position_ticket),
      DoubleToString(record.request_volume,8),
      DoubleToString(record.request_price,record.digits),
      DoubleToString(record.execution_volume,8),
      DoubleToString(record.execution_price,record.digits),
      DoubleToString(record.bid,record.digits),
      DoubleToString(record.ask,record.digits),
      DoubleToString(record.point,10),
      IntegerToString(record.digits),
      DoubleToString(record.spread_points,4),
      DoubleToString(record.slippage_points,4),
      DoubleToString(record.commission,2),
      DoubleToString(record.swap,2),
      DoubleToString(record.fee,2),
      DoubleToString(record.profit,2),
      DoubleToString(record.net_observed,2),
      record.deal_entry,
      record.deal_reason,
      record.request_comment,
      record.deal_comment,
      TimeToString(record.server_time,TIME_DATE | TIME_SECONDS),
      StringFormat("%I64d",record.time_msc)
   );
   FileFlush(handle);
   FileClose(handle);
   MbExecutionTruthDebugLog(
      "EXEC_PAPER_OPEN_OK",
      "symbol_alias=" + MbCanonicalSymbol(symbol_alias) + ";runtime_symbol=" + runtime_symbol + ";candidate_id=" + candidate_id + ";target_path=" + MbExecutionTruthSpoolFilePath(symbol_alias)
   );
   return true;
  }

#endif
