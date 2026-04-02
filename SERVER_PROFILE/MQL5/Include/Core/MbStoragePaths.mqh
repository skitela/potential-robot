#ifndef MB_STORAGE_PATHS_INCLUDED
#define MB_STORAGE_PATHS_INCLUDED

string g_mb_root_path_override = "";

string MbStoragePathSanitizeToken(const string value)
  {
   string out = "";
   int len = StringLen(value);
   for(int i = 0; i < len; ++i)
     {
      ushort ch = StringGetCharacter(value,i);
      bool ok =
         (ch >= 'A' && ch <= 'Z') ||
         (ch >= 'a' && ch <= 'z') ||
         (ch >= '0' && ch <= '9') ||
         ch == '_' ||
         ch == '-';
      out += (ok ? ShortToString((short)ch) : "_");
     }
   if(out == "")
      out = "DEFAULT";
   return out;
  }

void MbSetRootPathOverride(const string root_path)
  {
   g_mb_root_path_override = root_path;
  }

void MbClearRootPathOverride()
  {
   g_mb_root_path_override = "";
  }

bool MbIsStrategyTesterRuntime()
  {
   return (MQLInfoInteger(MQL_TESTER) != 0 || MQLInfoInteger(MQL_OPTIMIZATION) != 0);
  }

bool MbHasStrategyTesterSandbox()
  {
   return (StringFind(MbRootPath(),"MAKRO_I_MIKRO_BOT_TESTER_") == 0);
  }

void MbEnableStrategyTesterSandbox(const string sandbox_tag)
  {
   string sanitized = MbStoragePathSanitizeToken(sandbox_tag);
   MbSetRootPathOverride("MAKRO_I_MIKRO_BOT_TESTER_" + sanitized);
  }

string MbRootPath()
  {
   if(StringLen(g_mb_root_path_override) > 0)
      return g_mb_root_path_override;
   return "MAKRO_I_MIKRO_BOT";
  }

string MbSymbolStateDir(const string symbol)
  {
   return MbRootPath() + "\\state\\" + symbol;
  }

string MbGlobalStateDir()
  {
   return MbRootPath() + "\\state\\_global";
  }

string MbDomainStateDir(const string domain)
  {
   return MbRootPath() + "\\state\\_domains\\" + domain;
  }

string MbSymbolLogDir(const string symbol)
  {
   return MbRootPath() + "\\logs\\" + symbol;
  }

string MbSymbolRunDir(const string symbol)
  {
   return MbRootPath() + "\\run\\" + symbol;
  }

#endif
