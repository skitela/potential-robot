#ifndef MB_FIRST_WAVE_TRUTH_DIAGNOSTIC_INCLUDED
#define MB_FIRST_WAVE_TRUTH_DIAGNOSTIC_INCLUDED

#include "MbRuntimeKernel.mqh"

datetime g_mb_first_wave_truth_diag_last_reload_local = 0;
bool g_mb_first_wave_truth_diag_loaded = false;
bool g_mb_first_wave_truth_diag_enabled = false;
int g_mb_first_wave_truth_diag_max_age_sec = 1800;
bool g_mb_first_wave_truth_diag_allow_symbol_daily_loss_hard = false;
bool g_mb_first_wave_truth_diag_allow_central_state_stale = false;
bool g_mb_first_wave_truth_diag_allow_low_conversion_ratio = false;
bool g_mb_first_wave_truth_diag_allow_forefield_dirty = false;
bool g_mb_first_wave_truth_diag_allow_bootstrap_low_sample = false;
bool g_mb_first_wave_truth_diag_allow_bootstrap_empty_buckets = false;
bool g_mb_first_wave_truth_diag_relax_symbol_cost_gates = false;
int g_mb_first_wave_truth_diag_force_scan_interval_sec = 0;
double g_mb_first_wave_truth_diag_breakout_gate_abs = 0.28;
double g_mb_first_wave_truth_diag_trend_gate_abs = 0.24;
double g_mb_first_wave_truth_diag_range_gate_abs = 0.16;
double g_mb_first_wave_truth_diag_rejection_gate_abs = 0.16;
bool g_mb_first_wave_truth_diag_timer_scan_active = false;
string g_mb_first_wave_truth_diag_timer_scan_symbol = "";

string MbFirstWaveTruthDiagnosticPath()
  {
   return "MAKRO_I_MIKRO_BOT\\run\\first_wave_truth_diagnostic.csv";
  }

bool MbIsFirstWaveTruthDiagnosticSymbol(const string symbol)
  {
   string canonical = MbCanonicalSymbol(symbol);
   return (
      canonical == "US500" ||
      canonical == "EURJPY" ||
      canonical == "AUDUSD" ||
      canonical == "USDCAD"
   );
  }

void MbResetFirstWaveTruthDiagnosticState()
  {
   g_mb_first_wave_truth_diag_enabled = false;
   g_mb_first_wave_truth_diag_max_age_sec = 1800;
   g_mb_first_wave_truth_diag_allow_symbol_daily_loss_hard = false;
   g_mb_first_wave_truth_diag_allow_central_state_stale = false;
   g_mb_first_wave_truth_diag_allow_low_conversion_ratio = false;
   g_mb_first_wave_truth_diag_allow_forefield_dirty = false;
   g_mb_first_wave_truth_diag_allow_bootstrap_low_sample = false;
   g_mb_first_wave_truth_diag_allow_bootstrap_empty_buckets = false;
   g_mb_first_wave_truth_diag_relax_symbol_cost_gates = false;
   g_mb_first_wave_truth_diag_force_scan_interval_sec = 0;
   g_mb_first_wave_truth_diag_breakout_gate_abs = 0.28;
   g_mb_first_wave_truth_diag_trend_gate_abs = 0.24;
   g_mb_first_wave_truth_diag_range_gate_abs = 0.16;
   g_mb_first_wave_truth_diag_rejection_gate_abs = 0.16;
   g_mb_first_wave_truth_diag_timer_scan_active = false;
   g_mb_first_wave_truth_diag_timer_scan_symbol = "";
  }

bool MbFirstWaveTruthDiagnosticParseBool(const string value,const bool fallback)
  {
   string normalized = value;
   StringTrimLeft(normalized);
   StringTrimRight(normalized);
   StringToUpper(normalized);

   if(normalized == "1" || normalized == "TRUE" || normalized == "YES" || normalized == "ON" || normalized == "ENABLE" || normalized == "ENABLED")
      return true;
   if(normalized == "0" || normalized == "FALSE" || normalized == "NO" || normalized == "OFF" || normalized == "DISABLE" || normalized == "DISABLED")
      return false;
   return fallback;
  }

int MbFirstWaveTruthDiagnosticParseInt(const string value,const int fallback)
  {
   string normalized = value;
   StringTrimLeft(normalized);
   StringTrimRight(normalized);
   if(StringLen(normalized) <= 0)
      return fallback;
   return (int)StringToInteger(normalized);
  }

double MbFirstWaveTruthDiagnosticParseDouble(const string value,const double fallback)
  {
   string normalized = value;
   StringTrimLeft(normalized);
   StringTrimRight(normalized);
   if(StringLen(normalized) <= 0)
      return fallback;
   return StringToDouble(normalized);
  }

void MbLoadFirstWaveTruthDiagnostic(const bool force_reload = false)
  {
   datetime now_local = TimeLocal();
   if(!force_reload && g_mb_first_wave_truth_diag_loaded && g_mb_first_wave_truth_diag_last_reload_local > 0 && (now_local - g_mb_first_wave_truth_diag_last_reload_local) < 5)
      return;

   g_mb_first_wave_truth_diag_loaded = true;
   g_mb_first_wave_truth_diag_last_reload_local = now_local;
   MbResetFirstWaveTruthDiagnosticState();

   string rel_path = MbFirstWaveTruthDiagnosticPath();
   if(!FileIsExist(rel_path,FILE_COMMON))
      return;

   int handle = FileOpen(rel_path,FILE_COMMON | FILE_READ | FILE_CSV | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return;

   long modified_local = FileGetInteger(handle,FILE_MODIFY_DATE);
   while(!FileIsEnding(handle))
     {
      string key = FileReadString(handle);
      string value = FileReadString(handle);

      if(key == "enabled")
         g_mb_first_wave_truth_diag_enabled = MbFirstWaveTruthDiagnosticParseBool(value,g_mb_first_wave_truth_diag_enabled);
      else if(key == "max_age_sec")
         g_mb_first_wave_truth_diag_max_age_sec = MathMax(60,MbFirstWaveTruthDiagnosticParseInt(value,g_mb_first_wave_truth_diag_max_age_sec));
      else if(key == "allow_symbol_daily_loss_hard")
         g_mb_first_wave_truth_diag_allow_symbol_daily_loss_hard = MbFirstWaveTruthDiagnosticParseBool(value,g_mb_first_wave_truth_diag_allow_symbol_daily_loss_hard);
      else if(key == "allow_central_state_stale")
         g_mb_first_wave_truth_diag_allow_central_state_stale = MbFirstWaveTruthDiagnosticParseBool(value,g_mb_first_wave_truth_diag_allow_central_state_stale);
      else if(key == "allow_low_conversion_ratio")
         g_mb_first_wave_truth_diag_allow_low_conversion_ratio = MbFirstWaveTruthDiagnosticParseBool(value,g_mb_first_wave_truth_diag_allow_low_conversion_ratio);
      else if(key == "allow_forefield_dirty")
         g_mb_first_wave_truth_diag_allow_forefield_dirty = MbFirstWaveTruthDiagnosticParseBool(value,g_mb_first_wave_truth_diag_allow_forefield_dirty);
      else if(key == "allow_bootstrap_low_sample")
         g_mb_first_wave_truth_diag_allow_bootstrap_low_sample = MbFirstWaveTruthDiagnosticParseBool(value,g_mb_first_wave_truth_diag_allow_bootstrap_low_sample);
      else if(key == "allow_bootstrap_empty_buckets")
         g_mb_first_wave_truth_diag_allow_bootstrap_empty_buckets = MbFirstWaveTruthDiagnosticParseBool(value,g_mb_first_wave_truth_diag_allow_bootstrap_empty_buckets);
      else if(key == "relax_symbol_cost_gates")
         g_mb_first_wave_truth_diag_relax_symbol_cost_gates = MbFirstWaveTruthDiagnosticParseBool(value,g_mb_first_wave_truth_diag_relax_symbol_cost_gates);
      else if(key == "force_scan_interval_sec")
         g_mb_first_wave_truth_diag_force_scan_interval_sec = MathMax(0,MbFirstWaveTruthDiagnosticParseInt(value,g_mb_first_wave_truth_diag_force_scan_interval_sec));
      else if(key == "breakout_gate_abs")
         g_mb_first_wave_truth_diag_breakout_gate_abs = MbFirstWaveTruthDiagnosticParseDouble(value,g_mb_first_wave_truth_diag_breakout_gate_abs);
      else if(key == "trend_gate_abs")
         g_mb_first_wave_truth_diag_trend_gate_abs = MbFirstWaveTruthDiagnosticParseDouble(value,g_mb_first_wave_truth_diag_trend_gate_abs);
      else if(key == "range_gate_abs")
         g_mb_first_wave_truth_diag_range_gate_abs = MbFirstWaveTruthDiagnosticParseDouble(value,g_mb_first_wave_truth_diag_range_gate_abs);
      else if(key == "rejection_gate_abs")
         g_mb_first_wave_truth_diag_rejection_gate_abs = MbFirstWaveTruthDiagnosticParseDouble(value,g_mb_first_wave_truth_diag_rejection_gate_abs);
     }

   FileClose(handle);

   if(modified_local > 0 && (now_local - (datetime)modified_local) > g_mb_first_wave_truth_diag_max_age_sec)
      g_mb_first_wave_truth_diag_enabled = false;
  }

bool MbIsFirstWaveTruthDiagnosticActive(const string symbol,const bool paper_mode_active)
  {
   if(!paper_mode_active)
      return false;
   if(!MbIsFirstWaveTruthDiagnosticSymbol(symbol))
      return false;

   MbLoadFirstWaveTruthDiagnostic();
   return g_mb_first_wave_truth_diag_enabled;
  }

bool MbShouldBypassFirstWaveTruthDiagnosticGuard(const string symbol,const bool paper_mode_active,const string reason_code)
  {
   if(!MbIsFirstWaveTruthDiagnosticActive(symbol,paper_mode_active))
      return false;

   if(reason_code == "SYMBOL_DAILY_LOSS_HARD" && g_mb_first_wave_truth_diag_allow_symbol_daily_loss_hard)
      return true;
   if(reason_code == "CENTRAL_STATE_STALE" && g_mb_first_wave_truth_diag_allow_central_state_stale)
      return true;
   if(reason_code == "LOW_SAMPLE" && g_mb_first_wave_truth_diag_allow_bootstrap_low_sample)
      return true;
   if(reason_code == "BUCKETS_EMPTY" && g_mb_first_wave_truth_diag_allow_bootstrap_empty_buckets)
      return true;
   if(StringFind(reason_code,"PAPER_CONVERSION_BLOCKED_",0) == 0 && g_mb_first_wave_truth_diag_allow_low_conversion_ratio)
      return true;
   if(StringFind(reason_code,"FOREFIELD_DIRTY_",0) == 0 && g_mb_first_wave_truth_diag_allow_forefield_dirty)
      return true;

   return false;
  }

bool MbShouldRelaxFirstWaveTruthDiagnosticTuningGate(const string symbol,const bool paper_mode_active)
  {
   return MbIsFirstWaveTruthDiagnosticActive(symbol,paper_mode_active);
  }

bool MbShouldRelaxFirstWaveTruthDiagnosticCostGate(const string symbol,const bool paper_mode_active)
  {
   if(!MbIsFirstWaveTruthDiagnosticActive(symbol,paper_mode_active))
      return false;
   return g_mb_first_wave_truth_diag_relax_symbol_cost_gates;
  }

int MbResolveFirstWaveTruthDiagnosticForceScanIntervalSec(const string symbol,const bool paper_mode_active)
  {
   if(!MbIsFirstWaveTruthDiagnosticActive(symbol,paper_mode_active))
      return 0;
   return g_mb_first_wave_truth_diag_force_scan_interval_sec;
  }

void MbBeginFirstWaveTruthDiagnosticTimerScan(const string symbol,const bool paper_mode_active)
  {
   g_mb_first_wave_truth_diag_timer_scan_active = false;
   g_mb_first_wave_truth_diag_timer_scan_symbol = "";

   if(!MbIsFirstWaveTruthDiagnosticActive(symbol,paper_mode_active))
      return;
   if(g_mb_first_wave_truth_diag_force_scan_interval_sec <= 0)
      return;

   g_mb_first_wave_truth_diag_timer_scan_active = true;
   g_mb_first_wave_truth_diag_timer_scan_symbol = MbCanonicalSymbol(symbol);
  }

void MbEndFirstWaveTruthDiagnosticTimerScan()
  {
   g_mb_first_wave_truth_diag_timer_scan_active = false;
   g_mb_first_wave_truth_diag_timer_scan_symbol = "";
  }

bool MbShouldBypassFirstWaveTruthDiagnosticNewBar(const string symbol,const bool paper_mode_active)
  {
   if(!g_mb_first_wave_truth_diag_timer_scan_active)
      return false;
   if(MbCanonicalSymbol(symbol) != g_mb_first_wave_truth_diag_timer_scan_symbol)
      return false;
   if(!MbIsFirstWaveTruthDiagnosticActive(symbol,paper_mode_active))
      return false;
   return (g_mb_first_wave_truth_diag_force_scan_interval_sec > 0);
  }

bool MbShouldBypassFirstWaveTruthDiagnosticSoftReject(
   const string symbol,
   const bool paper_mode_active,
   const string setup_type,
   const string reason_code
)
  {
   if(!MbIsFirstWaveTruthDiagnosticActive(symbol,paper_mode_active))
      return false;
   if(setup_type == "NONE" || StringLen(setup_type) <= 0)
      return false;

   if(reason_code == "SCORE_BELOW_TRIGGER")
      return true;
   if(reason_code == "LOW_CONFIDENCE" || reason_code == "CONTEXT_LOW_CONFIDENCE")
      return true;
   if(reason_code == "AUX_CONFLICT_BLOCK")
      return true;
   if(StringFind(reason_code,"FOREFIELD_DIRTY_",0) == 0 && g_mb_first_wave_truth_diag_allow_forefield_dirty)
      return true;
   if(StringFind(reason_code,"PAPER_CONVERSION_BLOCKED_",0) == 0 && g_mb_first_wave_truth_diag_allow_low_conversion_ratio)
      return true;

   return false;
  }

bool MbShouldBypassFirstWaveTruthDiagnosticRateGuard(
   const string symbol,
   const bool paper_mode_active,
   const string reason_code
)
  {
   if(!MbIsFirstWaveTruthDiagnosticActive(symbol,paper_mode_active))
      return false;

   if(reason_code == "BROKER_ORDER_RATE_LIMIT")
      return true;
   if(reason_code == "BROKER_PRICE_RATE_LIMIT")
      return true;

   return false;
  }

bool MbShouldBypassFirstWaveTruthDiagnosticExecutionPrecheck(
   const string symbol,
   const bool paper_mode_active,
   const string reason_code
)
  {
   if(!MbIsFirstWaveTruthDiagnosticActive(symbol,paper_mode_active))
      return false;

   if(reason_code == "NET_EDGE_TOO_SMALL_FOR_TIME_STOP")
      return true;
   if(reason_code == "NET_EDGE_TOO_SMALL")
      return true;

   return false;
  }

double MbResolveFirstWaveTruthDiagnosticGateAbs(
   const string symbol,
   const string setup_type,
   const bool paper_mode_active,
   const double current_gate_abs
)
  {
   if(!MbIsFirstWaveTruthDiagnosticActive(symbol,paper_mode_active))
      return current_gate_abs;

   double diagnostic_gate_abs = current_gate_abs;
   if(setup_type == "SETUP_BREAKOUT")
      diagnostic_gate_abs = g_mb_first_wave_truth_diag_breakout_gate_abs;
   else if(setup_type == "SETUP_TREND")
      diagnostic_gate_abs = g_mb_first_wave_truth_diag_trend_gate_abs;
   else if(setup_type == "SETUP_RANGE")
      diagnostic_gate_abs = g_mb_first_wave_truth_diag_range_gate_abs;
   else if(setup_type == "SETUP_REJECTION")
      diagnostic_gate_abs = g_mb_first_wave_truth_diag_rejection_gate_abs;

   if(diagnostic_gate_abs <= 0.0)
      return current_gate_abs;
   if(current_gate_abs <= 0.0)
      return diagnostic_gate_abs;
   return MathMin(current_gate_abs,diagnostic_gate_abs);
  }

#endif
