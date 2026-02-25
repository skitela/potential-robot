//+------------------------------------------------------------------+
//|                                                  HybridAgent.mq5 |
//|                        Execution agent for Python <-> MQL5 stack |
//+------------------------------------------------------------------+
#property copyright "Gemini"
#property link      "https://github.com/gemini"
#property version   "1.12"
#property description "Hybrid execution agent with deterministic REQ/REP contract and runtime policy fail-safe."

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
input bool   InpPolicyRuntimeEnabled = true;
input bool   InpPolicyRuntimeRequireFile = true;
input bool   InpPolicyRuntimeEnforceEntry = true;
input uint   InpPolicyRuntimeReloadSec = 5;
input string InpPolicyRuntimeRelativePath = "OANDA_MT5_SYSTEM\\policy_runtime.json";
input int    InpSmaFastPeriod = 20;
input int    InpAdxPeriod = 14;
input int    InpAtrPeriod = 14;

string G_Symbol = "";
string G_SymbolUpper = "";
ulong  G_LastPythonMessageTime = 0;
bool   G_IsFailSafeActive = false;
bool   G_PolicyRuntimeLoaded = false;
bool   G_PolicyFailSafeNoTrade = false;
bool   G_PolicyShadowMode = true;
bool   G_PolicyRiskWindowsEnabled = true;
string G_PolicyLastError = "";
ulong  G_LastPolicyReloadMs = 0;

int G_MAFastHandle = INVALID_HANDLE;
int G_ADXHandle = INVALID_HANDLE;
int G_ATRHandle = INVALID_HANDLE;

string G_ReplyCacheMsgId[];
string G_ReplyCachePayload[];
ulong  G_ReplyCacheTs[];

#define POLICY_GROUP_COUNT 5
string G_PolicyGroupNames[POLICY_GROUP_COUNT] = {"FX", "METAL", "INDEX", "CRYPTO", "EQUITY"};
bool   G_PolicyEntryAllowed[POLICY_GROUP_COUNT];
bool   G_PolicyBorrowBlocked[POLICY_GROUP_COUNT];
double G_PolicyPriorityFactor[POLICY_GROUP_COUNT];
string G_PolicyReason[POLICY_GROUP_COUNT];
bool   G_PolicyRiskFriday[POLICY_GROUP_COUNT];
bool   G_PolicyRiskReopen[POLICY_GROUP_COUNT];

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

bool JsonGetBool(JSONNode *node, string key, bool def_value = false)
{
  if(!JsonNodeValid(node))
    return def_value;
  JSONNode *value = node.HasKey(key);
  if(!JsonNodeValid(value))
    return def_value;
  string raw = ToUpperAscii(value.ToString());
  if(raw == "TRUE" || raw == "1" || raw == "YES" || raw == "Y" || raw == "ON")
    return true;
  if(raw == "FALSE" || raw == "0" || raw == "NO" || raw == "N" || raw == "OFF")
    return false;
  return (value.ToInteger() != 0);
}

string TrimString(string value)
{
  string out = value;
  StringTrimLeft(out);
  StringTrimRight(out);
  return out;
}

int PolicyGroupIndex(string group_name)
{
  string g = ToUpperAscii(TrimString(group_name));
  for(int i = 0; i < POLICY_GROUP_COUNT; i++)
  {
    if(g == G_PolicyGroupNames[i])
      return i;
  }
  return -1;
}

void PolicyResetDefaults()
{
  for(int i = 0; i < POLICY_GROUP_COUNT; i++)
  {
    G_PolicyEntryAllowed[i] = true;
    G_PolicyBorrowBlocked[i] = false;
    G_PolicyPriorityFactor[i] = 1.0;
    G_PolicyReason[i] = "NONE";
    G_PolicyRiskFriday[i] = false;
    G_PolicyRiskReopen[i] = false;
  }
  G_PolicyShadowMode = true;
  G_PolicyRiskWindowsEnabled = true;
}

string SymbolBaseUpper(const string symbol_name)
{
  string out = ToUpperAscii(TrimString(symbol_name));
  int dot_pos = StringFind(out, ".");
  if(dot_pos > 0)
    out = StringSubstr(out, 0, dot_pos);
  return out;
}

bool IsLikelyFxSymbol(const string symbol_base)
{
  string s = SymbolBaseUpper(symbol_base);
  if(StringLen(s) != 6)
    return false;
  for(int i = 0; i < 6; i++)
  {
    ushort ch = (ushort)StringGetCharacter(s, i);
    if(ch < 65 || ch > 90)
      return false;
  }
  return true;
}

string GuessGroupForSymbol(const string symbol_name)
{
  string base = SymbolBaseUpper(symbol_name);
  if(base == "")
    return "OTHER";

  if(
    StringFind(base, "XAU") >= 0 || StringFind(base, "XAG") >= 0 ||
    StringFind(base, "GOLD") >= 0 || StringFind(base, "SILVER") >= 0 ||
    StringFind(base, "PLATIN") >= 0 || StringFind(base, "PALLAD") >= 0 ||
    StringFind(base, "COPPER") >= 0 || StringFind(base, "XPT") >= 0 || StringFind(base, "XPD") >= 0
  )
    return "METAL";

  if(
    StringFind(base, "BTC") >= 0 || StringFind(base, "ETH") >= 0 ||
    StringFind(base, "LTC") >= 0 || StringFind(base, "XRP") >= 0 ||
    StringFind(base, "DOGE") >= 0 || StringFind(base, "SOL") >= 0
  )
    return "CRYPTO";

  if(
    StringFind(base, "US500") >= 0 || StringFind(base, "US100") >= 0 ||
    StringFind(base, "US30") >= 0 || StringFind(base, "NAS") >= 0 ||
    StringFind(base, "SPX") >= 0 || StringFind(base, "DAX") >= 0 ||
    StringFind(base, "DE40") >= 0 || StringFind(base, "EU50") >= 0 ||
    StringFind(base, "JP225") >= 0 || StringFind(base, "UK100") >= 0
  )
    return "INDEX";

  if(IsLikelyFxSymbol(base))
    return "FX";

  return "EQUITY";
}

string ResolveTradeGroup(const string payload_group, const string symbol_name)
{
  string g = ToUpperAscii(TrimString(payload_group));
  if(PolicyGroupIndex(g) >= 0)
    return g;
  return GuessGroupForSymbol(symbol_name);
}

bool IsWindowActive(
  datetime local_time,
  int start_hour,
  int start_minute,
  int end_hour,
  int end_minute
)
{
  MqlDateTime ts;
  TimeToStruct(local_time, ts);
  int cur = ts.hour * 60 + ts.min;
  int start = MathMax(0, MathMin(23, start_hour)) * 60 + MathMax(0, MathMin(59, start_minute));
  int end = MathMax(0, MathMin(23, end_hour)) * 60 + MathMax(0, MathMin(59, end_minute));
  if(start == end)
    return true;
  if(start < end)
    return (cur >= start && cur <= end);
  return (cur >= start || cur <= end);
}

bool LoadPolicyRuntimeFile(string &error_msg)
{
  error_msg = "";
  PolicyResetDefaults();

  string rel_path = TrimString(InpPolicyRuntimeRelativePath);
  if(rel_path == "")
  {
    error_msg = "POLICY_RUNTIME_EMPTY_PATH";
    return false;
  }

  int fh = FileOpen(rel_path, FILE_READ | FILE_BIN | FILE_COMMON);
  if(fh == INVALID_HANDLE)
  {
    error_msg = StringFormat("POLICY_RUNTIME_OPEN_FAIL path=%s err=%d", rel_path, (int)GetLastError());
    return false;
  }

  int sz = (int)FileSize(fh);
  if(sz <= 0)
  {
    FileClose(fh);
    error_msg = StringFormat("POLICY_RUNTIME_EMPTY path=%s", rel_path);
    return false;
  }

  uchar bytes[];
  ArrayResize(bytes, sz);
  int read_n = FileReadArray(fh, bytes, 0, sz);
  FileClose(fh);
  if(read_n <= 0)
  {
    error_msg = StringFormat("POLICY_RUNTIME_READ_FAIL path=%s", rel_path);
    return false;
  }

  string json_raw = CharArrayToString(bytes, 0, read_n, CP_UTF8);
  JSONNode root;
  if(!root.Deserialize(json_raw, CP_UTF8))
  {
    error_msg = StringFormat("POLICY_RUNTIME_PARSE_FAIL path=%s", rel_path);
    return false;
  }

  JSONNode *root_ptr = GetPointer(root);
  string schema_v = JsonGetString(root_ptr, "schema_version", "");
  if(schema_v != "" && schema_v != PROTOCOL_VERSION)
  {
    error_msg = StringFormat("POLICY_RUNTIME_SCHEMA_MISMATCH got=%s expected=%s", schema_v, PROTOCOL_VERSION);
    return false;
  }

  JSONNode *flags = root_ptr.HasKey("flags", Object);
  if(JsonNodeValid(flags))
  {
    G_PolicyShadowMode = JsonGetBool(flags, "policy_shadow_mode_enabled", true);
    G_PolicyRiskWindowsEnabled = JsonGetBool(flags, "policy_risk_windows_enabled", true);
  }

  JSONNode *groups = root_ptr.HasKey("groups", Object);
  if(!JsonNodeValid(groups))
  {
    error_msg = "POLICY_RUNTIME_GROUPS_MISSING";
    return false;
  }

  for(int i = 0; i < POLICY_GROUP_COUNT; i++)
  {
    JSONNode *node = groups.HasKey(G_PolicyGroupNames[i], Object);
    if(!JsonNodeValid(node))
      continue;

    G_PolicyEntryAllowed[i] = JsonGetBool(node, "entry_allowed", true);
    G_PolicyBorrowBlocked[i] = JsonGetBool(node, "borrow_blocked", false);
    double pf = JsonGetDouble(node, "priority_factor", 1.0);
    if(!MathIsValidNumber(pf))
      pf = 1.0;
    G_PolicyPriorityFactor[i] = MathMax(0.05, MathMin(1.80, pf));
    string rs = JsonGetString(node, "reason", "NONE");
    if(rs == "")
      rs = "NONE";
    G_PolicyReason[i] = rs;
    G_PolicyRiskFriday[i] = JsonGetBool(node, "risk_friday", false);
    G_PolicyRiskReopen[i] = JsonGetBool(node, "risk_reopen", false);
  }

  return true;
}

void RefreshPolicyRuntime()
{
  if(!InpPolicyRuntimeEnabled)
    return;

  uint reload_sec = (uint)MathMax(1, (int)InpPolicyRuntimeReloadSec);
  ulong now_ms = (ulong)GetTickCount();
  if(G_LastPolicyReloadMs > 0 && (now_ms - G_LastPolicyReloadMs) < ((ulong)reload_sec * 1000))
    return;
  G_LastPolicyReloadMs = now_ms;

  string err = "";
  bool ok = LoadPolicyRuntimeFile(err);
  if(ok)
  {
    bool had_fail = G_PolicyFailSafeNoTrade;
    G_PolicyRuntimeLoaded = true;
    G_PolicyFailSafeNoTrade = false;
    G_PolicyLastError = "";
    if(had_fail)
      Print("POLICY_RUNTIME_RECOVERED path=", TrimString(InpPolicyRuntimeRelativePath));
    return;
  }

  G_PolicyRuntimeLoaded = false;
  G_PolicyLastError = err;
  if(InpPolicyRuntimeRequireFile)
  {
    G_PolicyFailSafeNoTrade = true;
    Print("POLICY_RUNTIME_FAILSAFE reason=", err);
  }
  else
  {
    G_PolicyFailSafeNoTrade = false;
    Print("POLICY_RUNTIME_WARN reason=", err);
  }
}

bool IsRiskWindow(const string group_name, bool &is_friday, bool &is_reopen, string &reason)
{
  is_friday = false;
  is_reopen = false;
  reason = "NONE";

  int idx = PolicyGroupIndex(group_name);
  if(idx < 0)
    return false;
  if(!G_PolicyRuntimeLoaded || !G_PolicyRiskWindowsEnabled)
    return false;

  is_friday = G_PolicyRiskFriday[idx];
  is_reopen = G_PolicyRiskReopen[idx];
  if(is_friday || is_reopen)
  {
    reason = G_PolicyReason[idx];
    if(reason == "")
      reason = "RISK_WINDOW";
    return true;
  }
  return false;
}

bool EntryAllowedForGroup(const string group_name, string &reason)
{
  reason = "NONE";
  if(!InpPolicyRuntimeEnabled || !InpPolicyRuntimeEnforceEntry)
    return true;

  if(G_PolicyFailSafeNoTrade)
  {
    reason = (G_PolicyLastError == "" ? "POLICY_FAILSAFE" : G_PolicyLastError);
    return false;
  }
  if(!G_PolicyRuntimeLoaded)
  {
    if(InpPolicyRuntimeRequireFile)
    {
      reason = "POLICY_RUNTIME_UNAVAILABLE";
      return false;
    }
    return true;
  }
  if(G_PolicyShadowMode)
  {
    reason = "SHADOW_MODE";
    return true;
  }

  int idx = PolicyGroupIndex(group_name);
  if(idx < 0)
  {
    reason = "UNKNOWN_GROUP";
    return false;
  }
  if(!G_PolicyEntryAllowed[idx])
  {
    reason = (G_PolicyReason[idx] == "" ? "ENTRY_BLOCKED" : G_PolicyReason[idx]);
    return false;
  }
  return true;
}

bool BorrowBlockedForGroup(const string group_name)
{
  if(!InpPolicyRuntimeEnabled || !G_PolicyRuntimeLoaded)
    return false;
  int idx = PolicyGroupIndex(group_name);
  if(idx < 0)
    return false;
  return G_PolicyBorrowBlocked[idx];
}

double PriorityFactorForGroup(const string group_name)
{
  if(!InpPolicyRuntimeEnabled || !G_PolicyRuntimeLoaded)
    return 1.0;
  int idx = PolicyGroupIndex(group_name);
  if(idx < 0)
    return 1.0;
  double pf = G_PolicyPriorityFactor[idx];
  if(!MathIsValidNumber(pf))
    return 1.0;
  return MathMax(0.05, MathMin(1.80, pf));
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

ENUM_ORDER_TYPE_FILLING ResolveOrderFilling(const string symbol)
{
  long fm = 0;
  if(SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE, fm))
  {
    if((fm & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;
    if((fm & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;
#ifdef ORDER_FILLING_RETURN
    if((fm & SYMBOL_FILLING_RETURN) == SYMBOL_FILLING_RETURN)
      return ORDER_FILLING_RETURN;
#endif
  }
  return ORDER_FILLING_FOK;
}

string BuildTradeDiag(const string symbol, const ENUM_ORDER_TYPE_FILLING req_fill)
{
  const int term_allowed = (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) != 0 ? 1 : 0);
  const int mql_allowed = (MQLInfoInteger(MQL_TRADE_ALLOWED) != 0 ? 1 : 0);
  const int acc_allowed = (AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) != 0 ? 1 : 0);
  const long acc_mode = (long)AccountInfoInteger(ACCOUNT_TRADE_MODE);
  const long sym_mode = (long)SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
  const long sym_fill = (long)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
  return StringFormat(
    "term=%d mql=%d acc=%d acc_mode=%I64d sym_mode=%I64d sym_fill=%I64d req_fill=%d",
    term_allowed,
    mql_allowed,
    acc_allowed,
    acc_mode,
    sym_mode,
    sym_fill,
    (int)req_fill
  );
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
    req.type_filling = ResolveOrderFilling(symbol);
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
      Print(
        "FAIL_SAFE_CLOSE_FAIL ticket=", (long)ticket,
        " err=", GetLastError(),
        " retcode=", (long)res.retcode,
        " ", BuildTradeDiag(symbol, req.type_filling)
      );
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
  string request_hash,
  string group_hint,
  bool payload_risk_entry_allowed,
  string payload_risk_reason,
  bool payload_risk_friday,
  bool payload_risk_reopen,
  bool payload_policy_shadow
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

  string trade_group = ResolveTradeGroup(group_hint, symbol_req);
  string policy_reason = "NONE";
  bool entry_allowed = EntryAllowedForGroup(trade_group, policy_reason);
  bool risk_friday = false;
  bool risk_reopen = false;
  string risk_reason = "NONE";
  bool in_risk_window = IsRiskWindow(trade_group, risk_friday, risk_reopen, risk_reason);
  bool borrow_blocked = BorrowBlockedForGroup(trade_group);
  double prio_factor = PriorityFactorForGroup(trade_group);

  if(!entry_allowed)
  {
    string deny_reason = (policy_reason == "" ? "ENTRY_BLOCKED" : policy_reason);
    SendReplyEnvelope(
      "REJECTED", msg_id, action_reply,
      50020, "CUSTOM_RETCODE_POLICY_ENTRY_BLOCKED", 0, 0,
      StringFormat("Policy blocked entry group=%s reason=%s", trade_group, deny_reason),
      symbol_req,
      deny_reason, request_hash, true
    );
    Print(
      "ENTRY_SKIP_RISK_WINDOW symbol=", symbol_req,
      " group=", trade_group,
      " friday=", (risk_friday ? "1" : "0"),
      " reopen=", (risk_reopen ? "1" : "0"),
      " reason=", deny_reason,
      " borrow_block=", (borrow_blocked ? "1" : "0"),
      " prio_factor=", DoubleToString(prio_factor, 3)
    );
    return;
  }

  if(!payload_policy_shadow && !payload_risk_entry_allowed)
  {
    string deny_reason_payload = (payload_risk_reason == "" ? "PAYLOAD_RISK_BLOCK" : payload_risk_reason);
    SendReplyEnvelope(
      "REJECTED", msg_id, action_reply,
      50021, "CUSTOM_RETCODE_PAYLOAD_RISK_BLOCK", 0, 0,
      StringFormat("Payload risk blocked entry group=%s reason=%s", trade_group, deny_reason_payload),
      symbol_req,
      deny_reason_payload, request_hash, true
    );
    Print(
      "ENTRY_SKIP_RISK_WINDOW symbol=", symbol_req,
      " group=", trade_group,
      " friday=", (payload_risk_friday ? "1" : "0"),
      " reopen=", (payload_risk_reopen ? "1" : "0"),
      " reason=", deny_reason_payload,
      " source=PAYLOAD"
    );
    return;
  }

  if(in_risk_window || borrow_blocked || prio_factor != 1.0)
  {
    Print(
      "POLICY_CONTEXT symbol=", symbol_req,
      " group=", trade_group,
      " risk_friday=", (risk_friday ? "1" : "0"),
      " risk_reopen=", (risk_reopen ? "1" : "0"),
      " borrow_block=", (borrow_blocked ? "1" : "0"),
      " priority_factor=", DoubleToString(prio_factor, 3),
      " reason=", risk_reason
    );
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

  const ENUM_ORDER_TYPE_FILLING req_fill = ResolveOrderFilling(symbol_req);
  const int term_allowed = (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) != 0 ? 1 : 0);
  const int mql_allowed = (MQLInfoInteger(MQL_TRADE_ALLOWED) != 0 ? 1 : 0);
  const int acc_allowed = (AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) != 0 ? 1 : 0);
  const string trade_diag = BuildTradeDiag(symbol_req, req_fill);
  if(term_allowed == 0 || mql_allowed == 0 || acc_allowed == 0)
  {
    Print("ORDER_PRECHECK_BLOCK msg_id=", msg_id, " ", trade_diag);
    SendReplyEnvelope(
      "REJECTED", msg_id, action_reply,
      10017, "TRADE_RETCODE_TRADE_DISABLED", 0, 0,
      trade_diag,
      symbol_req,
      trade_diag, request_hash, true
    );
    return;
  }

  request.action = TRADE_ACTION_DEAL;
  request.symbol = symbol_req;
  request.volume = volume;
  request.price = price;
  request.sl = sl_price;
  request.tp = tp_price;
  request.magic = magic;
  request.comment = comment;
  request.type = order_type;
  request.type_filling = req_fill;
  request.deviation = 10;

  if(!OrderSend(request, result))
  {
    Print(
      "ORDER_SEND_FAIL msg_id=", msg_id,
      " err=", GetLastError(),
      " retcode=", (long)result.retcode,
      " ", trade_diag,
      " comment=", result.comment
    );
  }

  long rc = (long)result.retcode;
  if(rc <= 0)
    rc = 10011;
  if(rc != 10009 && rc != 10008)
  {
    Print(
      "ORDER_SEND_RESULT msg_id=", msg_id,
      " retcode=", rc,
      " retcode_name=", GetRetcodeString((uint)rc),
      " ", trade_diag,
      " comment=", result.comment
    );
  }

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
    string group_hint = JsonGetString(payload, "group", "");
    bool payload_risk_entry_allowed = JsonGetBool(payload, "risk_entry_allowed", true);
    string payload_risk_reason = JsonGetString(payload, "risk_reason", "NONE");
    bool payload_risk_friday = JsonGetBool(payload, "risk_friday", false);
    bool payload_risk_reopen = JsonGetBool(payload, "risk_reopen", false);
    bool payload_policy_shadow = JsonGetBool(payload, "policy_shadow_mode", true);

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

    ExecuteTrade(
      signal,
      symbol,
      volume,
      sl_price,
      tp_price,
      (int)magic,
      comment,
      msg_id,
      request_hash,
      group_hint,
      payload_risk_entry_allowed,
      payload_risk_reason,
      payload_risk_friday,
      payload_risk_reopen,
      payload_policy_shadow
    );
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
  PolicyResetDefaults();
  G_PolicyRuntimeLoaded = false;
  G_PolicyFailSafeNoTrade = false;
  G_PolicyLastError = "";
  G_LastPolicyReloadMs = 0;
  RefreshPolicyRuntime();

  if(!InitIndicatorHandles())
    Print("WARN: indicator handles partially unavailable. BAR feature payload may be incomplete.");

  Print(
    "HybridAgent ready symbol=", G_SymbolUpper,
    " timer_sec=", InpTimerSec,
    " timeout_sec=", InpPythonTimeoutSec,
    " watchdog=", (InpEnablePythonTimeoutWatchdog ? "ON" : "OFF"),
    " account_pulse_sec=", InpAccountPulseSec,
    " policy_runtime=", (InpPolicyRuntimeEnabled ? "ON" : "OFF"),
    " policy_loaded=", (G_PolicyRuntimeLoaded ? "YES" : "NO"),
    " policy_shadow=", (G_PolicyShadowMode ? "YES" : "NO")
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
  RefreshPolicyRuntime();

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
