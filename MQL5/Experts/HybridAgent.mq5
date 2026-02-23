//+------------------------------------------------------------------+
//|                                                  HybridAgent.mq5 |
//|                        Execution agent for Python <-> MQL5 stack |
//+------------------------------------------------------------------+
#property copyright "Gemini"
#property link      "https://github.com/gemini"
#property version   "1.11"
#property description "Hybrid execution agent with deterministic REQ/REP contract."

#include <zeromq_bridge.mqh>
#include <Json/Json.mqh>

#define PROTOCOL_VERSION "1.0"

// --- Expert inputs ---
input string InpPythonHost = "127.0.0.1";
input int    InpDataPort   = 5555;
input int    InpCmdPort    = 5556;
input uint   InpTimerSec   = 1;     // EventSetTimer uses seconds
input uint   InpPythonTimeoutSec = 180;
input bool   InpEnablePythonTimeoutWatchdog = false;
input bool   InpAutoRecoverFromTimeout = true;
input uint   InpAccountPulseSec = 5;
input uint   InpReplyCacheSize = 64;
input int    InpSmaFastPeriod = 20;
input int    InpAdxPeriod = 14;
input int    InpAtrPeriod = 14;

string G_Symbol = "";
string G_SymbolUpper = "";
ulong  G_LastPythonMessageTime = 0;
bool   G_IsFailSafeActive = false;

int G_MAFastHandle = INVALID_HANDLE;
int G_ADXHandle = INVALID_HANDLE;
int G_ATRHandle = INVALID_HANDLE;

string G_ReplyCacheMsgId[];
string G_ReplyCachePayload[];
ulong  G_ReplyCacheTs[];

//+------------------------------------------------------------------+
//| Utility helpers                                                   |
//+------------------------------------------------------------------+
string ToUpperAscii(string value)
{
  string out = value;
  int len = StringLen(out);
  for(int i = 0; i < len; i++)
  {
    ushort ch = (ushort)StringGetCharacter(out, i);
    if(ch >= 97 && ch <= 122)
    {
      StringSetCharacter(out, i, (ushort)(ch - 32));
    }
  }
  return out;
}

bool IsCurrentSymbol(string symbol_value)
{
  return (ToUpperAscii(symbol_value) == G_SymbolUpper);
}

string JsonEscape(string value)
{
  string out = value;
  StringReplace(out, "\\", "\\\\");
  StringReplace(out, "\"", "\\\"");
  StringReplace(out, "\r", "\\r");
  StringReplace(out, "\n", "\\n");
  return out;
}

string NormFloat8(double value)
{
  return StringFormat("%.8f", value);
}

string NormInt(long value)
{
  return StringFormat("%I64d", value);
}

bool JsonNodeValid(JSONNode *node)
{
  return (node != NULL && CheckPointer(node) != POINTER_INVALID);
}

string JsonGetString(JSONNode *node, string key, string def_value = "")
{
  if(!JsonNodeValid(node))
    return def_value;
  JSONNode *value = node.HasKey(key);
  if(!JsonNodeValid(value))
    return def_value;
  return value.ToString();
}

double JsonGetDouble(JSONNode *node, string key, double def_value = 0.0)
{
  if(!JsonNodeValid(node))
    return def_value;
  JSONNode *value = node.HasKey(key);
  if(!JsonNodeValid(value))
    return def_value;
  return value.ToDouble();
}

long JsonGetLong(JSONNode *node, string key, long def_value = 0)
{
  if(!JsonNodeValid(node))
    return def_value;
  JSONNode *value = node.HasKey(key);
  if(!JsonNodeValid(value))
    return def_value;
  return value.ToInteger();
}

string Fnv1a32Hex(string text)
{
  uint h = 0x811C9DC5;
  uchar bytes[];
  int n = StringToCharArray(text, bytes, 0, -1, CP_UTF8);
  if(n <= 1)
    return StringFormat("%08X", (int)h);

  for(int i = 0; i < (n - 1); i++)
  {
    h ^= (uint)bytes[i];
    h = (uint)((ulong)h * 0x01000193);
  }
  return StringFormat("%08X", (int)h);
}

string BuildRequestHashSimple(string action, string msg_id)
{
  string sig = ToUpperAscii(action) + "|" + msg_id;
  return Fnv1a32Hex(sig);
}

string BuildRequestHashTrade(
  string action,
  string msg_id,
  string signal,
  string symbol,
  double volume,
  double sl_price,
  double tp_price,
  long magic,
  string comment
)
{
  string sig = ToUpperAscii(action) + "|" + msg_id + "|" + ToUpperAscii(signal) + "|" + ToUpperAscii(symbol)
    + "|" + NormFloat8(volume)
    + "|" + NormFloat8(sl_price)
    + "|" + NormFloat8(tp_price)
    + "|" + NormInt(magic)
    + "|" + comment;
  return Fnv1a32Hex(sig);
}

string BuildResponseHash(
  string status,
  string correlation_id,
  string action,
  long retcode,
  string retcode_str,
  long order_id,
  long deal_id,
  string comment,
  string symbol,
  string error,
  string request_hash
)
{
  string sig = ToUpperAscii(status) + "|" + correlation_id + "|" + ToUpperAscii(action)
    + "|" + NormInt(retcode)
    + "|" + retcode_str
    + "|" + NormInt(order_id)
    + "|" + NormInt(deal_id)
    + "|" + comment
    + "|" + symbol
    + "|" + error
    + "|" + request_hash;
  return Fnv1a32Hex(sig);
}

int ReplyCacheLimit()
{
  return (int)MathMax(4, (int)InpReplyCacheSize);
}

int FindReplyCacheIndex(const string msg_id)
{
  int n = ArraySize(G_ReplyCacheMsgId);
  for(int i = 0; i < n; i++)
  {
    if(G_ReplyCacheMsgId[i] == msg_id)
      return i;
  }
  return -1;
}

bool TryGetCachedReply(const string msg_id, string &reply_json)
{
  if(msg_id == "")
    return false;

  int idx = FindReplyCacheIndex(msg_id);
  if(idx < 0)
    return false;

  reply_json = G_ReplyCachePayload[idx];
  return (reply_json != "");
}

void PutCachedReply(const string msg_id, const string reply_json)
{
  if(msg_id == "" || reply_json == "")
    return;

  int idx = FindReplyCacheIndex(msg_id);
  int n = ArraySize(G_ReplyCacheMsgId);
  ulong now_ts = (ulong)GetTickCount();

  if(idx >= 0)
  {
    G_ReplyCachePayload[idx] = reply_json;
    G_ReplyCacheTs[idx] = now_ts;
    return;
  }

  int lim = ReplyCacheLimit();
  int slot = -1;
  if(n < lim)
  {
    slot = n;
    ArrayResize(G_ReplyCacheMsgId, n + 1);
    ArrayResize(G_ReplyCachePayload, n + 1);
    ArrayResize(G_ReplyCacheTs, n + 1);
  }
  else if(n > 0)
  {
    ulong oldest = G_ReplyCacheTs[0];
    slot = 0;
    for(int i = 1; i < n; i++)
    {
      if(G_ReplyCacheTs[i] < oldest)
      {
        oldest = G_ReplyCacheTs[i];
        slot = i;
      }
    }
  }

  if(slot >= 0)
  {
    G_ReplyCacheMsgId[slot] = msg_id;
    G_ReplyCachePayload[slot] = reply_json;
    G_ReplyCacheTs[slot] = now_ts;
  }
}

bool SendReplyEnvelope(
  string status,
  string correlation_id,
  string action,
  long retcode,
  string retcode_str,
  long order_id,
  long deal_id,
  string comment,
  string symbol,
  string error,
  string request_hash,
  bool cache_reply = true
)
{
  string s_status = ToUpperAscii(status);
  string s_action = ToUpperAscii(action);
  string s_corr = (correlation_id == "" ? "unknown" : correlation_id);
  string s_retcode = retcode_str;
  string s_comment = comment;
  string s_symbol = symbol;
  string s_error = error;
  string s_req_hash = request_hash;

  string response_hash = BuildResponseHash(
    s_status,
    s_corr,
    s_action,
    retcode,
    s_retcode,
    order_id,
    deal_id,
    s_comment,
    s_symbol,
    s_error,
    s_req_hash
  );

  string reply_fmt =
    "{\"status\":\"%s\",\"correlation_id\":\"%s\",\"action\":\"%s\",\"request_hash\":\"%s\","
    + "\"details\":{\"retcode\":%d,\"retcode_str\":\"%s\",\"order\":%I64d,\"deal\":%I64d,\"comment\":\"%s\",\"symbol\":\"%s\"},"
    + "\"error\":\"%s\",\"schema_version\":\"%s\",\"__v\":\"%s\",\"response_hash\":\"%s\"}";

  string reply_json = StringFormat(
    reply_fmt,
    JsonEscape(s_status),
    JsonEscape(s_corr),
    JsonEscape(s_action),
    JsonEscape(s_req_hash),
    (int)retcode,
    JsonEscape(s_retcode),
    (long)order_id,
    (long)deal_id,
    JsonEscape(s_comment),
    JsonEscape(s_symbol),
    JsonEscape(s_error),
    PROTOCOL_VERSION,
    PROTOCOL_VERSION,
    response_hash
  );

  if(cache_reply && correlation_id != "")
    PutCachedReply(correlation_id, reply_json);

  return Zmq_SendReply(reply_json);
}

bool InitIndicatorHandles()
{
  if(G_MAFastHandle != INVALID_HANDLE)
    IndicatorRelease(G_MAFastHandle);
  if(G_ADXHandle != INVALID_HANDLE)
    IndicatorRelease(G_ADXHandle);
  if(G_ATRHandle != INVALID_HANDLE)
    IndicatorRelease(G_ATRHandle);
  G_MAFastHandle = INVALID_HANDLE;
  G_ADXHandle = INVALID_HANDLE;
  G_ATRHandle = INVALID_HANDLE;

  G_MAFastHandle = iMA(G_Symbol, PERIOD_M5, InpSmaFastPeriod, 0, MODE_SMA, PRICE_CLOSE);
  G_ADXHandle = iADX(G_Symbol, PERIOD_M5, InpAdxPeriod);
  G_ATRHandle = iATR(G_Symbol, PERIOD_M5, InpAtrPeriod);

  bool ok = true;
  if(G_MAFastHandle == INVALID_HANDLE)
  {
    Print("WARN: iMA handle init failed for ", G_Symbol);
    ok = false;
  }
  if(G_ADXHandle == INVALID_HANDLE)
  {
    Print("WARN: iADX handle init failed for ", G_Symbol);
    ok = false;
  }
  if(G_ATRHandle == INVALID_HANDLE)
  {
    Print("WARN: iATR handle init failed for ", G_Symbol);
    ok = false;
  }
  return ok;
}

void ReleaseIndicatorHandles()
{
  if(G_MAFastHandle != INVALID_HANDLE)
  {
    IndicatorRelease(G_MAFastHandle);
    G_MAFastHandle = INVALID_HANDLE;
  }
  if(G_ADXHandle != INVALID_HANDLE)
  {
    IndicatorRelease(G_ADXHandle);
    G_ADXHandle = INVALID_HANDLE;
  }
  if(G_ATRHandle != INVALID_HANDLE)
  {
    IndicatorRelease(G_ATRHandle);
    G_ATRHandle = INVALID_HANDLE;
  }
}

bool ReadClosedBarFeatures(double &sma_fast, double &adx, double &atr)
{
  sma_fast = 0.0;
  adx = 0.0;
  atr = 0.0;

  if(G_MAFastHandle == INVALID_HANDLE || G_ADXHandle == INVALID_HANDLE || G_ATRHandle == INVALID_HANDLE)
    return false;

  double b_ma[];
  double b_adx[];
  double b_atr[];

  if(CopyBuffer(G_MAFastHandle, 0, 1, 1, b_ma) != 1)
    return false;
  if(CopyBuffer(G_ADXHandle, 0, 1, 1, b_adx) != 1)
    return false;
  if(CopyBuffer(G_ATRHandle, 0, 1, 1, b_atr) != 1)
    return false;

  if(ArraySize(b_ma) < 1 || ArraySize(b_adx) < 1 || ArraySize(b_atr) < 1)
    return false;

  if(!MathIsValidNumber(b_ma[0]) || !MathIsValidNumber(b_adx[0]) || !MathIsValidNumber(b_atr[0]))
    return false;

  sma_fast = b_ma[0];
  adx = b_adx[0];
  atr = b_atr[0];
  return true;
}

//+------------------------------------------------------------------+
//| Retcode mapping                                                   |
//+------------------------------------------------------------------+
string GetRetcodeString(uint retcode)
{
  switch(retcode)
  {
    case 10004: return "TRADE_RETCODE_REQUOTE";
    case 10006: return "TRADE_RETCODE_REJECT";
    case 10007: return "TRADE_RETCODE_CANCEL";
    case 10008: return "TRADE_RETCODE_PLACED";
    case 10009: return "TRADE_RETCODE_DONE";
    case 10010: return "TRADE_RETCODE_DONE_PARTIAL";
    case 10011: return "TRADE_RETCODE_ERROR";
    case 10012: return "TRADE_RETCODE_TIMEOUT";
    case 10013: return "TRADE_RETCODE_INVALID";
    case 10014: return "TRADE_RETCODE_INVALID_VOLUME";
    case 10015: return "TRADE_RETCODE_INVALID_PRICE";
    case 10016: return "TRADE_RETCODE_INVALID_STOPS";
    case 10017: return "TRADE_RETCODE_TRADE_DISABLED";
    case 10018: return "TRADE_RETCODE_MARKET_CLOSED";
    case 10019: return "TRADE_RETCODE_NO_MONEY";
    case 10020: return "TRADE_RETCODE_PRICE_CHANGED";
    case 10021: return "TRADE_RETCODE_PRICE_OFF";
    case 10022: return "TRADE_RETCODE_INVALID_EXPIRATION";
    case 10023: return "TRADE_RETCODE_ORDER_CHANGED";
    case 10024: return "TRADE_RETCODE_TOO_MANY_REQUESTS";
    case 10025: return "TRADE_RETCODE_NO_CHANGES";
    case 10026: return "TRADE_RETCODE_SERVER_DISABLES_AT";
    case 10027: return "TRADE_RETCODE_CLIENT_DISABLES_AT";
    case 10028: return "TRADE_RETCODE_LOCKED";
    case 10029: return "TRADE_RETCODE_FROZEN";
    case 10030: return "TRADE_RETCODE_INVALID_FILL";
    case 10031: return "TRADE_RETCODE_CONNECTION";
    case 10032: return "TRADE_RETCODE_ONLY_REAL";
    case 10033: return "TRADE_RETCODE_LIMIT_ORDERS";
    case 10034: return "TRADE_RETCODE_LIMIT_VOLUME";
    case 10035: return "TRADE_RETCODE_INVALID_ORDER";
    case 10036: return "TRADE_RETCODE_POSITION_CLOSED";
    case 10038: return "TRADE_RETCODE_INVALID_CLOSE_VOLUME";
    case 10039: return "TRADE_RETCODE_CLOSE_ORDER_EXIST";
    case 10040: return "TRADE_RETCODE_LIMIT_POSITIONS";
    case 10041: return "TRADE_RETCODE_REJECT_CANCEL";
    case 10042: return "TRADE_RETCODE_LONG_ONLY";
    case 10043: return "TRADE_RETCODE_SHORT_ONLY";
    case 10044: return "TRADE_RETCODE_FIFO_CLOSE";
    case 10045: return "TRADE_RETCODE_HEDGE_PROHIBITED";
    default: return "UNKNOWN_RETCODE";
  }
}

//+------------------------------------------------------------------+
//| Fail-safe closeout                                                |
//+------------------------------------------------------------------+
void CloseAllOpenPositions(string reason)
{
  for(int i = PositionsTotal() - 1; i >= 0; i--)
  {
    ulong ticket = PositionGetTicket(i);
    if(ticket <= 0)
      continue;

    string symbol = PositionGetString(POSITION_SYMBOL);
    if(symbol != G_Symbol)
      continue;

    MqlTradeRequest req;
    MqlTradeResult  res;
    ZeroMemory(req);
    ZeroMemory(res);

    req.action = TRADE_ACTION_DEAL;
    req.position = ticket;
    req.symbol = symbol;
    req.volume = PositionGetDouble(POSITION_VOLUME);
    req.magic = (long)PositionGetInteger(POSITION_MAGIC);
    req.comment = reason;
    req.type_filling = ORDER_FILLING_IOC;
    req.deviation = 25;

    long pos_type = PositionGetInteger(POSITION_TYPE);
    if(pos_type == POSITION_TYPE_BUY)
    {
      req.type = ORDER_TYPE_SELL;
      req.price = SymbolInfoDouble(symbol, SYMBOL_BID);
    }
    else
    {
      req.type = ORDER_TYPE_BUY;
      req.price = SymbolInfoDouble(symbol, SYMBOL_ASK);
    }

    if(req.price <= 0.0)
    {
      Print("FAIL_SAFE_CLOSE_SKIP ticket=", (long)ticket, " reason=PRICE_UNAVAILABLE");
      continue;
    }

    if(!OrderSend(req, res))
    {
      Print("FAIL_SAFE_CLOSE_FAIL ticket=", (long)ticket, " err=", GetLastError(), " retcode=", (long)res.retcode);
    }
    else
    {
      Print("FAIL_SAFE_CLOSE_OK ticket=", (long)ticket, " retcode=", (long)res.retcode);
    }
  }
}

//+------------------------------------------------------------------+
//| Telemetry out: closed BAR                                         |
//+------------------------------------------------------------------+
void SendBarData()
{
  static datetime last_bar_time = 0;
  MqlRates rates[];

  if(CopyRates(G_Symbol, PERIOD_M5, 1, 1, rates) <= 0)
    return;

  if(rates[0].time <= last_bar_time)
    return;

  double sma_fast = 0.0;
  double adx = 0.0;
  double atr = 0.0;
  bool has_features = ReadClosedBarFeatures(sma_fast, adx, atr);

  string json = StringFormat(
    "{\"type\":\"BAR\",\"symbol\":\"%s\",\"timeframe\":\"M5\",\"time\":%d,\"open\":%.5f,\"high\":%.5f,\"low\":%.5f,\"close\":%.5f,\"volume\":%I64d",
    JsonEscape(G_SymbolUpper),
    (int)rates[0].time,
    rates[0].open,
    rates[0].high,
    rates[0].low,
    rates[0].close,
    (long)rates[0].tick_volume
  );

  if(has_features)
  {
    json += StringFormat(",\"sma_fast\":%.8f,\"adx\":%.8f,\"atr\":%.8f", sma_fast, adx, atr);
  }

  json += StringFormat(",\"schema_version\":\"%s\",\"__v\":\"%s\"}", PROTOCOL_VERSION, PROTOCOL_VERSION);

  if(Zmq_SendData(json))
    last_bar_time = rates[0].time;
}

//+------------------------------------------------------------------+
//| Telemetry out: latest tick                                        |
//+------------------------------------------------------------------+
void SendTickData()
{
  MqlTick tick;
  if(!SymbolInfoTick(G_Symbol, tick))
    return;

  int digits = (int)SymbolInfoInteger(G_Symbol, SYMBOL_DIGITS);
  int stops_level = (int)SymbolInfoInteger(G_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
  int freeze_level = (int)SymbolInfoInteger(G_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
  double point = SymbolInfoDouble(G_Symbol, SYMBOL_POINT);
  double tick_size = SymbolInfoDouble(G_Symbol, SYMBOL_TRADE_TICK_SIZE);
  double tick_value = SymbolInfoDouble(G_Symbol, SYMBOL_TRADE_TICK_VALUE);
  double vol_min = SymbolInfoDouble(G_Symbol, SYMBOL_VOLUME_MIN);
  double vol_max = SymbolInfoDouble(G_Symbol, SYMBOL_VOLUME_MAX);
  double vol_step = SymbolInfoDouble(G_Symbol, SYMBOL_VOLUME_STEP);
  double spread_points = 0.0;
  if(point > 0.0)
    spread_points = (tick.ask - tick.bid) / point;

  string json = StringFormat(
    "{\"type\":\"TICK\",\"symbol\":\"%s\",\"timestamp_ms\":%I64d,\"bid\":%.5f,\"ask\":%.5f,\"volume\":%I64d,"
    "\"digits\":%d,\"point\":%.10f,\"spread_points\":%.6f,"
    "\"trade_tick_size\":%.10f,\"trade_tick_value\":%.10f,"
    "\"volume_min\":%.6f,\"volume_max\":%.6f,\"volume_step\":%.6f,"
    "\"trade_stops_level\":%d,\"trade_freeze_level\":%d,"
    "\"schema_version\":\"%s\",\"__v\":\"%s\"}",
    JsonEscape(G_SymbolUpper),
    (long)tick.time_msc,
    tick.bid,
    tick.ask,
    (long)tick.volume,
    digits,
    point,
    spread_points,
    tick_size,
    tick_value,
    vol_min,
    vol_max,
    vol_step,
    stops_level,
    freeze_level,
    PROTOCOL_VERSION,
    PROTOCOL_VERSION
  );

  if(!Zmq_SendData(json))
  {
    static ulong last_error_time = 0;
    ulong now_ms = (ulong)GetTickCount();
    if(now_ms - last_error_time > 5000)
    {
      Print("ZMQ_TICK_SEND_FAIL symbol=", G_SymbolUpper);
      last_error_time = now_ms;
    }
  }
}

//+------------------------------------------------------------------+
//| Telemetry out: account snapshot                                  |
//+------------------------------------------------------------------+
void SendAccountData()
{
  static ulong last_sent_ms = 0;
  ulong now_ms = (ulong)GetTickCount();
  uint pulse_sec = (uint)MathMax(1, (int)InpAccountPulseSec);
  if(last_sent_ms > 0 && (now_ms - last_sent_ms) < ((ulong)pulse_sec * 1000))
    return;

  double balance = AccountInfoDouble(ACCOUNT_BALANCE);
  double equity = AccountInfoDouble(ACCOUNT_EQUITY);
  double margin_free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
  double margin_level = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);

  string json = StringFormat(
    "{\"type\":\"ACCOUNT\",\"balance\":%.8f,\"equity\":%.8f,\"margin_free\":%.8f,\"margin_level\":%.8f,"
    "\"timestamp_ms\":%I64d,\"schema_version\":\"%s\",\"__v\":\"%s\"}",
    balance,
    equity,
    margin_free,
    margin_level,
    (long)TimeCurrent() * 1000,
    PROTOCOL_VERSION,
    PROTOCOL_VERSION
  );

  if(Zmq_SendData(json))
    last_sent_ms = now_ms;
}

//+------------------------------------------------------------------+
//| Trade execution                                                    |
//+------------------------------------------------------------------+
void ExecuteTrade(
  string signal,
  string symbol,
  double volume,
  double sl_price,
  double tp_price,
  int magic,
  string comment,
  string msg_id,
  string request_hash
)
{
  string action_reply = "TRADE_REPLY";
  signal = ToUpperAscii(signal);
  string symbol_req = symbol;
  StringTrimLeft(symbol_req);
  StringTrimRight(symbol_req);
  string symbol_key = ToUpperAscii(symbol_req);

  if(G_IsFailSafeActive)
  {
    SendReplyEnvelope(
      "REJECTED", msg_id, action_reply,
      50002, "CUSTOM_RETCODE_FAIL_SAFE_ACTIVE", 0, 0,
      "Rejected due to active FAIL-SAFE mode.", symbol_req,
      "", request_hash, true
    );
    return;
  }

  if(symbol_req == "" || !SymbolSelect(symbol_req, true))
  {
    SendReplyEnvelope(
      "REJECTED", msg_id, action_reply,
      50004, "CUSTOM_RETCODE_INVALID_SYMBOL", 0, 0,
      StringFormat("Invalid symbol in command: %s", symbol_req),
      symbol_req,
      "Invalid symbol.", request_hash, true
    );
    return;
  }

  for(int i = PositionsTotal() - 1; i >= 0; i--)
  {
    ulong pos_ticket = PositionGetTicket(i);
    if(pos_ticket <= 0)
      continue;

    string pos_symbol = ToUpperAscii(PositionGetString(POSITION_SYMBOL));
    if(pos_symbol == symbol_key && (int)PositionGetInteger(POSITION_MAGIC) == magic)
    {
      SendReplyEnvelope(
        "REJECTED", msg_id, action_reply,
        50001, "CUSTOM_RETCODE_DUPLICATE_POSITION", 0, 0,
        "Position already exists for this magic number on the specified symbol.",
        symbol_req,
        "", request_hash, true
      );
      return;
    }
  }

  ENUM_ORDER_TYPE order_type;
  double price = 0.0;

  if(signal == "BUY")
  {
    order_type = ORDER_TYPE_BUY;
    price = SymbolInfoDouble(symbol_req, SYMBOL_ASK);
  }
  else if(signal == "SELL")
  {
    order_type = ORDER_TYPE_SELL;
    price = SymbolInfoDouble(symbol_req, SYMBOL_BID);
  }
  else
  {
    SendReplyEnvelope(
      "REJECTED", msg_id, action_reply,
      50005, "CUSTOM_RETCODE_UNKNOWN_SIGNAL", 0, 0,
      "Unknown signal type in command.",
      symbol_req,
      "Unknown signal type.", request_hash, true
    );
    return;
  }

  if(price <= 0.0)
  {
    SendReplyEnvelope(
      "REJECTED", msg_id, action_reply,
      50006, "CUSTOM_RETCODE_PRICE_UNAVAILABLE", 0, 0,
      "Could not fetch current price for symbol.",
      symbol_req,
      "Price unavailable.", request_hash, true
    );
    return;
  }

  MqlTradeRequest request;
  MqlTradeResult result;
  ZeroMemory(request);
  ZeroMemory(result);

  request.action = TRADE_ACTION_DEAL;
  request.symbol = symbol_req;
  request.volume = volume;
  request.price = price;
  request.sl = sl_price;
  request.tp = tp_price;
  request.magic = magic;
  request.comment = comment;
  request.type = order_type;
  request.type_filling = ORDER_FILLING_FOK;
  request.deviation = 10;

  if(!OrderSend(request, result))
  {
    Print("ORDER_SEND_FAIL msg_id=", msg_id, " err=", GetLastError(), " retcode=", (long)result.retcode);
  }

  long rc = (long)result.retcode;
  if(rc <= 0)
    rc = 10011;

  SendReplyEnvelope(
    "PROCESSED", msg_id, action_reply,
    rc,
    GetRetcodeString((uint)rc),
    (long)result.order,
    (long)result.deal,
    result.comment,
    symbol_req,
    "",
    request_hash,
    true
  );
}

//+------------------------------------------------------------------+
//| Command intake + contract validation                              |
//+------------------------------------------------------------------+
void ProcessCommands()
{
  string command_json = "";
  if(!Zmq_ReceiveRequest(command_json))
    return;

  G_LastPythonMessageTime = (ulong)GetTickCount();

  JSONNode json;
  if(!json.Deserialize(command_json, CP_UTF8))
  {
    string bad_msg_id = "unknown";
    int pos = StringFind(command_json, "\"msg_id\":\"");
    if(pos != -1)
    {
      int end_pos = StringFind(command_json, "\"", pos + 10);
      if(end_pos != -1)
        bad_msg_id = StringSubstr(command_json, pos + 10, end_pos - (pos + 10));
    }

    SendReplyEnvelope(
      "ERROR", bad_msg_id, "ERROR_REPLY",
      50010, "CUSTOM_RETCODE_PARSE_ERROR", 0, 0,
      "Failed to parse command JSON.",
      "",
      "Failed to parse command JSON.",
      "",
      true
    );
    return;
  }

  JSONNode *root = GetPointer(json);
  string msg_id = JsonGetString(root, "msg_id", "");
  if(msg_id == "")
    msg_id = StringFormat("missing-%d", (int)GetTickCount());

  string cached_reply = "";
  if(TryGetCachedReply(msg_id, cached_reply))
  {
    Print("IDEMPOTENCY_HIT msg_id=", msg_id);
    Zmq_SendReply(cached_reply);
    return;
  }

  string action = ToUpperAscii(JsonGetString(root, "action", ""));
  string contract_v = JsonGetString(root, "__v", "");
  string schema_v = JsonGetString(root, "schema_version", "");
  string request_hash = JsonGetString(root, "request_hash", "");

  if(contract_v == "")
    Print("WARN: Missing __v in command msg_id=", msg_id);
  else if(contract_v != PROTOCOL_VERSION)
    Print("WARN: __v mismatch got=", contract_v, " expected=", PROTOCOL_VERSION, " msg_id=", msg_id);

  if(schema_v == "")
    Print("WARN: Missing schema_version in command msg_id=", msg_id);
  else if(schema_v != PROTOCOL_VERSION)
    Print("WARN: schema_version mismatch got=", schema_v, " expected=", PROTOCOL_VERSION, " msg_id=", msg_id);

  if(action == "HEARTBEAT")
  {
    string expected = BuildRequestHashSimple(action, msg_id);
    if(request_hash != "" && request_hash != expected)
    {
      SendReplyEnvelope(
        "REJECTED", msg_id, "HEARTBEAT_REPLY",
        50003, "CUSTOM_RETCODE_REQUEST_HASH_MISMATCH", 0, 0,
        "Request hash mismatch.",
        "",
        "Request hash mismatch.",
        request_hash,
        true
      );
      return;
    }

    SendReplyEnvelope(
      "OK", msg_id, "HEARTBEAT_REPLY",
      0, "", 0, 0,
      "", "", "", request_hash,
      true
    );
    return;
  }

  if(action == "TRADE")
  {
    JSONNode *payload = NULL;
    if(JsonNodeValid(root))
      payload = root.HasKey("payload", Object);
    if(!JsonNodeValid(payload))
    {
      SendReplyEnvelope(
        "ERROR", msg_id, "TRADE_REPLY",
        50011, "CUSTOM_RETCODE_PAYLOAD_INVALID", 0, 0,
        "Payload is not a valid object.",
        "",
        "Payload is not a valid object.",
        request_hash,
        true
      );
      return;
    }

    string signal = ToUpperAscii(JsonGetString(payload, "signal", ""));
    string symbol = JsonGetString(payload, "symbol", "");
    StringTrimLeft(symbol);
    StringTrimRight(symbol);
    string symbol_hash = ToUpperAscii(symbol);
    double volume = JsonGetDouble(payload, "volume", 0.0);
    double sl_price = JsonGetDouble(payload, "sl_price", 0.0);
    double tp_price = JsonGetDouble(payload, "tp_price", 0.0);
    long magic = JsonGetLong(payload, "magic", 0);
    string comment = JsonGetString(payload, "comment", "");

    string expected_hash = BuildRequestHashTrade(
      action,
      msg_id,
      signal,
      symbol_hash,
      volume,
      sl_price,
      tp_price,
      magic,
      comment
    );

    if(request_hash != "" && request_hash != expected_hash)
    {
      SendReplyEnvelope(
        "REJECTED", msg_id, "TRADE_REPLY",
        50003, "CUSTOM_RETCODE_REQUEST_HASH_MISMATCH", 0, 0,
        "Request hash mismatch.",
        symbol,
        "Request hash mismatch.",
        request_hash,
        true
      );
      return;
    }

    ExecuteTrade(signal, symbol, volume, sl_price, tp_price, (int)magic, comment, msg_id, request_hash);
    return;
  }

  SendReplyEnvelope(
    "ERROR", msg_id, "ERROR_REPLY",
    50012, "CUSTOM_RETCODE_UNKNOWN_ACTION", 0, 0,
    "Unknown action specified.",
    "",
    "Unknown action specified.",
    request_hash,
    true
  );
}

//+------------------------------------------------------------------+
//| Expert lifecycle                                                  |
//+------------------------------------------------------------------+
int OnInit()
{
  Print("HybridAgent init...");

  if(!Zmq_Init(InpPythonHost, InpDataPort, InpCmdPort))
  {
    Alert("CRITICAL: ZMQ init failed.");
    return INIT_FAILED;
  }

  if(!EventSetTimer(InpTimerSec))
  {
    Alert("CRITICAL: EventSetTimer failed.");
    Zmq_Deinit();
    return INIT_FAILED;
  }

  G_Symbol = _Symbol;
  G_SymbolUpper = ToUpperAscii(_Symbol);
  G_LastPythonMessageTime = (ulong)GetTickCount();
  G_IsFailSafeActive = false;

  if(!InitIndicatorHandles())
    Print("WARN: indicator handles partially unavailable. BAR feature payload may be incomplete.");

  Print(
    "HybridAgent ready symbol=", G_SymbolUpper,
    " timer_sec=", InpTimerSec,
    " timeout_sec=", InpPythonTimeoutSec,
    " watchdog=", (InpEnablePythonTimeoutWatchdog ? "ON" : "OFF"),
    " account_pulse_sec=", InpAccountPulseSec
  );
  return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
  Print("HybridAgent deinit reason=", reason);
  EventKillTimer();
  ReleaseIndicatorHandles();
  Zmq_Deinit();
}

void OnTimer()
{
  // Always service REQ/REP first so HEARTBEAT and TRADE replies stay responsive.
  ProcessCommands();

  if(InpEnablePythonTimeoutWatchdog && InpPythonTimeoutSec > 0)
  {
    ulong now_ms = (ulong)GetTickCount();
    ulong elapsed_ms = now_ms - G_LastPythonMessageTime;
    if(!G_IsFailSafeActive && elapsed_ms > (InpPythonTimeoutSec * 1000))
    {
      G_IsFailSafeActive = true;
      Alert("FAIL-SAFE ACTIVATED: Python timeout exceeded. Closing open positions.");
      CloseAllOpenPositions("FAIL_SAFE_TIMEOUT");
    }

    if(G_IsFailSafeActive && InpAutoRecoverFromTimeout && elapsed_ms <= (InpPythonTimeoutSec * 1000))
    {
      G_IsFailSafeActive = false;
      Print("FAIL-SAFE CLEARED: Python command channel recovered.");
    }
  }

  // Keep snapshot stream alive even in FAIL-SAFE to avoid stale-data lockup on Python side.
  SendTickData();
  SendBarData();
  SendAccountData();
}

// Intentionally empty: all logic is timer-driven for deterministic cadence.
void OnTick()
{
}
