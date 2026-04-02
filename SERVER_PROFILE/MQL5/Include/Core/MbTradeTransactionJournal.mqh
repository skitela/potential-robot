#ifndef MB_TRADE_TRANSACTION_JOURNAL_INCLUDED
#define MB_TRADE_TRANSACTION_JOURNAL_INCLUDED

#include "MbStorage.mqh"
#include "MbExecutionCommon.mqh"
#include "MbRuntimeKernel.mqh"

string g_mb_trade_transaction_queue[];
string g_mb_trade_transaction_queue_path = "";

void MbTradeTransactionJournalInit(const string rel_path)
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION) != 0)
     {
      g_mb_trade_transaction_queue_path = "";
      ArrayResize(g_mb_trade_transaction_queue,0);
      return;
     }

   g_mb_trade_transaction_queue_path = rel_path;
   ArrayResize(g_mb_trade_transaction_queue,0);
  }

void MbTradeTransactionJournalFlush()
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION) != 0)
     {
      ArrayResize(g_mb_trade_transaction_queue,0);
      return;
     }

   int queued = ArraySize(g_mb_trade_transaction_queue);
   if(queued <= 0 || StringLen(g_mb_trade_transaction_queue_path) <= 0)
      return;

   int h = FileOpen(g_mb_trade_transaction_queue_path, FILE_COMMON | FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;
   FileSeek(h,0,SEEK_END);
   for(int i = 0; i < queued; ++i)
      FileWriteString(h,g_mb_trade_transaction_queue[i] + "\n");
   FileClose(h);
   ArrayResize(g_mb_trade_transaction_queue,0);
  }

void MbAppendTradeTransactionEvent(
   const string rel_path,
   const string symbol,
   const ulong magic,
   const MqlTradeTransaction &trans,
   const MqlTradeRequest &request,
   const MqlTradeResult &result
)
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION) != 0)
      return;

   string payload = StringFormat(
      "{\"ts_utc\":%I64d,\"symbol\":\"%s\",\"magic\":%I64u,\"trans_type\":%d,\"order\":%I64u,\"deal\":%I64u,\"request_action\":%d,\"request_magic\":%I64u,\"request_symbol\":\"%s\",\"request_volume\":%.2f,\"request_price\":%.8f,\"result_retcode\":%I64d,\"result_retcode_name\":\"%s\",\"result_order\":%I64u,\"result_deal\":%I64u,\"result_price\":%.8f}",
      (long)TimeCurrent(),
      symbol,
      magic,
      (int)trans.type,
      (ulong)trans.order,
      (ulong)trans.deal,
      (int)request.action,
      (ulong)request.magic,
      request.symbol,
      request.volume,
      request.price,
      (long)result.retcode,
      MbClassifyRetcode((long)result.retcode),
      (ulong)result.order,
      (ulong)result.deal,
      result.price
   );

   if(StringLen(g_mb_trade_transaction_queue_path) > 0 && rel_path == g_mb_trade_transaction_queue_path)
     {
      int next = ArraySize(g_mb_trade_transaction_queue);
      ArrayResize(g_mb_trade_transaction_queue,next + 1);
      g_mb_trade_transaction_queue[next] = payload;
      if(ArraySize(g_mb_trade_transaction_queue) >= 32)
         MbTradeTransactionJournalFlush();
      return;
     }

   int h = FileOpen(rel_path, FILE_COMMON | FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;
   FileSeek(h,0,SEEK_END);
   FileWriteString(h,payload + "\n");
   FileClose(h);
  }

bool MbTransactionMatchesLocalBot(
   const string symbol,
   const ulong magic,
   const MqlTradeTransaction &trans,
   const MqlTradeRequest &request
)
  {
   string local_symbol = MbCanonicalSymbol(symbol);
   string request_symbol = MbCanonicalSymbol(request.symbol);
   string trans_symbol = MbCanonicalSymbol(trans.symbol);

   if(StringLen(request_symbol) > 0 && request_symbol == local_symbol && (ulong)request.magic == magic)
      return true;

   if(trans.deal > 0 && HistoryDealSelect((ulong)trans.deal))
     {
      if(MbCanonicalSymbol(HistoryDealGetString((ulong)trans.deal,DEAL_SYMBOL)) == local_symbol &&
         (ulong)HistoryDealGetInteger((ulong)trans.deal,DEAL_MAGIC) == magic)
         return true;
      return false;
     }

   if(trans.order > 0 && HistoryOrderSelect((ulong)trans.order))
     {
      if(MbCanonicalSymbol(HistoryOrderGetString((ulong)trans.order,ORDER_SYMBOL)) == local_symbol &&
         (ulong)HistoryOrderGetInteger((ulong)trans.order,ORDER_MAGIC) == magic)
         return true;
      return false;
     }

   if(StringLen(trans_symbol) > 0 && trans_symbol == local_symbol)
     {
      // Do not attribute by symbol alone. Without request/order/deal magic the event
      // is ambiguous and can poison local learning/execution feedback.
      return false;
     }

   return false;
  }

#endif
