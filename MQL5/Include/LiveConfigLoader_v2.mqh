bool   G_KernelConfigLoaded = false;
bool   G_KernelConfigFailSafe = false;
string G_KernelConfigLastError = "";
string G_KernelConfigHash = "";
ulong  G_LastKernelConfigReloadMs = 0;
ulong  G_LastKernelConfigOpenFailLogMs = 0;

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
   JSONNode *symbols = root_ptr.HasKey("symbols", Array);
   if(!JsonNodeValid(symbols))
     {
      error_msg = "KERNEL_CONFIG_SYMBOLS_MISSING";
      return false;
     }

   InstrumentProfileCacheResetV2();
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
      InstrumentProfileCacheUpsertV2(profile);
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
