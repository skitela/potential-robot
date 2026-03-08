bool   G_KernelConfigLoaded = false;
bool   G_KernelConfigFailSafe = false;
string G_KernelConfigLastError = "";
string G_KernelConfigHash = "";
ulong  G_LastKernelConfigReloadMs = 0;
ulong  G_LastKernelConfigOpenFailLogMs = 0;

string KernelConfigSigBool(const bool value)
  {
   return (value ? "1" : "0");
  }

string KernelConfigSigFloat(const double value)
  {
   return DoubleToString(value, 6);
  }

string KernelConfigBuildRowSignature(const KernelSymbolProfileV1 &profile)
  {
   return StringFormat(
      "symbol=%s;group=%s;entry_allowed=%s;close_only=%s;halt=%s;reason=%s;spread_cap_points=%s;max_latency_ms=%s;min_tick_rate_1s=%d;min_liquidity_score=%s;min_tradeability_score=%s;min_setup_quality_score=%s",
      profile.symbol,
      profile.group_name,
      KernelConfigSigBool(profile.entry_allowed),
      KernelConfigSigBool(profile.close_only),
      KernelConfigSigBool(profile.halt),
      profile.reason_code,
      KernelConfigSigFloat(profile.spread_cap_points),
      KernelConfigSigFloat(profile.max_latency_ms),
      profile.min_tick_rate_1s,
      KernelConfigSigFloat(profile.min_liquidity_score),
      KernelConfigSigFloat(profile.min_tradeability_score),
      KernelConfigSigFloat(profile.min_setup_quality_score)
   );
  }

string KernelConfigBuildSignatureV1(
   const string schema_version,
   const string generated_at_utc,
   const string policy_version,
   const string &row_signatures[]
)
  {
   string out = StringFormat(
      "schema_version=%s\ngenerated_at_utc=%s\npolicy_version=%s\nsymbols_n=%d",
      schema_version,
      generated_at_utc,
      policy_version,
      ArraySize(row_signatures)
   );
   for(int i = 0; i < ArraySize(row_signatures); i++)
      out += ("\n" + row_signatures[i]);
   return out;
  }

bool KernelConfigIsHex64(const string value)
  {
   if(StringLen(value) != 64)
      return false;
   for(int i = 0; i < 64; i++)
     {
      ushort c = (ushort)StringGetCharacter(value, i);
      bool is_num = (c >= '0' && c <= '9');
      bool is_low = (c >= 'a' && c <= 'f');
      bool is_up = (c >= 'A' && c <= 'F');
      if(!(is_num || is_low || is_up))
         return false;
     }
   return true;
  }

bool KernelConfigSha256Hex(const string payload, string &hex_out)
  {
   hex_out = "";
   uchar data[];
   int n = StringToCharArray(payload, data, 0, -1, CP_UTF8);
   if(n > 0)
      ArrayResize(data, n - 1); // strip trailing NUL from StringToCharArray
   uchar key[];
   ArrayResize(key, 0);
   uchar digest[];
   ResetLastError();
   if(!CryptEncode(CRYPT_HASH_SHA256, data, key, digest))
      return false;

   string out = "";
   for(int i = 0; i < ArraySize(digest); i++)
      out += StringFormat("%02x", (int)digest[i]);
   hex_out = StringToLower(out);
   return true;
  }

bool LoadKernelConfigFileV2(string &error_msg)
  {
   error_msg = "";
   string rel_path = TrimString(InpKernelConfigRelativePath);
   if(rel_path == "")
     {
      error_msg = "KERNEL_CONFIG_EMPTY_PATH";
      return false;
     }

   int fh = FileOpen(rel_path, FILE_READ | FILE_BIN | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE)
     {
      error_msg = StringFormat("KERNEL_CONFIG_OPEN_FAIL path=%s err=%d", rel_path, (int)GetLastError());
      return false;
     }

   int sz = (int)FileSize(fh);
   if(sz <= 0)
     {
      FileClose(fh);
      error_msg = StringFormat("KERNEL_CONFIG_EMPTY path=%s", rel_path);
      return false;
     }

   uchar bytes[];
   ArrayResize(bytes, sz);
   uint read_u = FileReadArray(fh, bytes, 0, sz);
   FileClose(fh);
   int read_n = (int)read_u;
   if(read_n <= 0)
     {
      error_msg = StringFormat("KERNEL_CONFIG_READ_FAIL path=%s", rel_path);
      return false;
     }

   string json_raw = CharArrayToString(bytes, 0, read_n, CP_UTF8);
   JSONNode root;
   if(!root.Deserialize(json_raw, CP_UTF8))
     {
      error_msg = StringFormat("KERNEL_CONFIG_PARSE_FAIL path=%s", rel_path);
      return false;
     }

   JSONNode *root_ptr = GetPointer(root);
   string schema_v = JsonGetString(root_ptr, "schema_version", "");
   if(schema_v != "kernel_config_v1")
     {
      error_msg = StringFormat("KERNEL_CONFIG_SCHEMA_MISMATCH got=%s expected=kernel_config_v1", schema_v);
      return false;
     }

   string cfg_hash = JsonGetString(root_ptr, "config_hash", "");
   string hash_method = JsonGetString(root_ptr, "hash_method", "");
   string hash_scope = JsonGetString(root_ptr, "hash_scope", "");
   string generated_at_utc = JsonGetString(root_ptr, "generated_at_utc", "");
   string policy_version = JsonGetString(root_ptr, "policy_version", "");
   if(hash_method != "sha256_sig_v1")
     {
      error_msg = StringFormat("KERNEL_CONFIG_HASH_METHOD_MISMATCH got=%s expected=sha256_sig_v1", hash_method);
      return false;
     }
   if(hash_scope != "kernel_core_v1")
     {
      error_msg = StringFormat("KERNEL_CONFIG_HASH_SCOPE_MISMATCH got=%s expected=kernel_core_v1", hash_scope);
      return false;
     }
   if(!KernelConfigIsHex64(cfg_hash))
     {
      error_msg = "KERNEL_CONFIG_HASH_INVALID_FORMAT";
      return false;
     }
   JSONNode *symbols = root_ptr.HasKey("symbols", Array);
   if(!JsonNodeValid(symbols))
     {
      error_msg = "KERNEL_CONFIG_SYMBOLS_MISSING";
      return false;
     }

   InstrumentProfileCacheResetV2();
   string row_signatures[];
   ArrayResize(row_signatures, 0);
   int rows = symbols.Size();
   for(int i = 0; i < rows; i++)
     {
      JSONNode *row = symbols[i];
      if(!JsonNodeValid(row))
         continue;

      KernelSymbolProfileV1 profile;
      profile.symbol = TrimString(JsonGetString(row, "symbol", ""));
      if(profile.symbol == "")
         continue;
      profile.symbol_base = SymbolBaseUpper(profile.symbol);
      profile.group_name = ToUpperAscii(TrimString(JsonGetString(row, "group", GuessGroupForSymbol(profile.symbol))));
      profile.entry_allowed = JsonGetBool(row, "entry_allowed", true);
      profile.close_only = JsonGetBool(row, "close_only", false);
      profile.halt = JsonGetBool(row, "halt", false);
      profile.reason_code = ToUpperAscii(TrimString(JsonGetString(row, "reason", "NONE")));
      if(profile.reason_code == "")
         profile.reason_code = "NONE";
      profile.spread_cap_points = MathMax(0.0, JsonGetDouble(row, "spread_cap_points", 0.0));
      profile.max_latency_ms = MathMax(0.0, JsonGetDouble(row, "max_latency_ms", 0.0));
      profile.min_tick_rate_1s = (int)MathMax(0, JsonGetLong(row, "min_tick_rate_1s", 0));
      profile.min_liquidity_score = MathMax(0.0, MathMin(1.0, JsonGetDouble(row, "min_liquidity_score", 0.0)));
      profile.min_tradeability_score = MathMax(0.0, MathMin(1.0, JsonGetDouble(row, "min_tradeability_score", 0.0)));
      profile.min_setup_quality_score = MathMax(0.0, MathMin(1.0, JsonGetDouble(row, "min_setup_quality_score", 0.0)));
      profile.loaded = true;
      int idx = ArraySize(row_signatures);
      ArrayResize(row_signatures, idx + 1);
      row_signatures[idx] = KernelConfigBuildRowSignature(profile);
      InstrumentProfileCacheUpsertV2(profile);
     }

   string signature = KernelConfigBuildSignatureV1(schema_v, generated_at_utc, policy_version, row_signatures);
   string calc_hash = "";
   if(!KernelConfigSha256Hex(signature, calc_hash))
     {
      error_msg = StringFormat("KERNEL_CONFIG_HASH_COMPUTE_FAIL err=%d", (int)GetLastError());
      return false;
     }
   string cfg_hash_l = StringToLower(cfg_hash);
   if(calc_hash != cfg_hash_l)
     {
      error_msg = StringFormat("KERNEL_CONFIG_HASH_MISMATCH got=%s calc=%s", cfg_hash_l, calc_hash);
      return false;
     }

   G_KernelConfigHash = cfg_hash;
   return true;
  }

void RefreshKernelConfigV2()
  {
   if(!InpKernelConfigEnabled)
      return;

   uint reload_sec = (uint)MathMax(1, (int)InpKernelConfigReloadSec);
   ulong now_ms = (ulong)GetTickCount();
   if(G_LastKernelConfigReloadMs > 0 && (now_ms - G_LastKernelConfigReloadMs) < ((ulong)reload_sec * 1000))
      return;
   G_LastKernelConfigReloadMs = now_ms;

   bool had_loaded = G_KernelConfigLoaded;
   string err = "";
   bool ok = LoadKernelConfigFileV2(err);
   if(ok)
     {
      if(G_KernelConfigFailSafe)
         Print("KERNEL_CONFIG_RECOVERED path=", TrimString(InpKernelConfigRelativePath));
      G_KernelConfigLoaded = true;
      G_KernelConfigFailSafe = false;
      G_KernelConfigLastError = "";
      G_LastKernelConfigOpenFailLogMs = 0;
      return;
     }

   G_KernelConfigLastError = err;
   if(had_loaded && StringFind(err, "KERNEL_CONFIG_OPEN_FAIL", 0) >= 0)
     {
      G_KernelConfigLoaded = true;
      G_KernelConfigFailSafe = false;
      if(ShouldEmitLogThrottled(G_LastKernelConfigOpenFailLogMs, InpKernelConfigOpenFailLogThrottleSec))
         Print("KERNEL_CONFIG_OPEN_RETRY reason=", err);
      return;
     }

   G_KernelConfigLoaded = false;
   if(InpKernelConfigRequireFile)
     {
      G_KernelConfigFailSafe = true;
      Print("KERNEL_CONFIG_FAILSAFE reason=", err);
     }
   else
     {
      G_KernelConfigFailSafe = false;
      Print("KERNEL_CONFIG_WARN reason=", err);
     }
  }
