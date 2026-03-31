#ifndef MB_GLOBAL_TEACHER_LEARNING_DIAGNOSTIC_INCLUDED
#define MB_GLOBAL_TEACHER_LEARNING_DIAGNOSTIC_INCLUDED

#include "MbRuntimeKernel.mqh"
#include "MbTuningTypes.mqh"

datetime g_mb_global_teacher_diag_last_reload_local = 0;
bool g_mb_global_teacher_diag_loaded = false;
bool g_mb_global_teacher_diag_enabled = false;
int g_mb_global_teacher_diag_max_age_sec = 43200;
int g_mb_global_teacher_diag_force_scan_interval_sec = 60;
bool g_mb_global_teacher_diag_allow_low_conversion_ratio = true;
bool g_mb_global_teacher_diag_allow_forefield_dirty = true;
bool g_mb_global_teacher_diag_allow_portfolio_heat = true;
bool g_mb_global_teacher_diag_allow_family_freeze_relief = true;
bool g_mb_global_teacher_diag_allow_fleet_freeze_relief = true;
bool g_mb_global_teacher_diag_relax_tuning_gates = true;
bool g_mb_global_teacher_diag_relax_cost_gates = true;
double g_mb_global_teacher_diag_breakout_gate_abs = 0.16;
double g_mb_global_teacher_diag_trend_gate_abs = 0.14;
double g_mb_global_teacher_diag_range_gate_abs = 0.10;
double g_mb_global_teacher_diag_rejection_gate_abs = 0.10;
datetime g_mb_global_teacher_diag_last_timer_scan_ts = 0;
string g_mb_global_teacher_diag_last_timer_scan_symbol = "";

string MbGlobalTeacherLearningDiagnosticPath()
  {
   return "MAKRO_I_MIKRO_BOT\\run\\global_teacher_cohort_diagnostic.csv";
  }

bool MbIsGlobalTeacherLearningDiagnosticSymbol(const string symbol)
  {
   string canonical = MbCanonicalSymbol(symbol);
   return (
      canonical == "DE30" ||
      canonical == "GOLD" ||
      canonical == "SILVER" ||
      canonical == "USDJPY" ||
      canonical == "USDCHF" ||
      canonical == "COPPER-US" ||
      canonical == "COPPERUS" ||
      canonical == "EURAUD" ||
      canonical == "EURUSD" ||
      canonical == "GBPUSD"
   );
  }

void MbResetGlobalTeacherLearningDiagnosticState()
  {
   g_mb_global_teacher_diag_enabled = false;
   g_mb_global_teacher_diag_max_age_sec = 43200;
   g_mb_global_teacher_diag_force_scan_interval_sec = 60;
   g_mb_global_teacher_diag_allow_low_conversion_ratio = true;
   g_mb_global_teacher_diag_allow_forefield_dirty = true;
   g_mb_global_teacher_diag_allow_portfolio_heat = true;
   g_mb_global_teacher_diag_allow_family_freeze_relief = true;
   g_mb_global_teacher_diag_allow_fleet_freeze_relief = true;
   g_mb_global_teacher_diag_relax_tuning_gates = true;
   g_mb_global_teacher_diag_relax_cost_gates = true;
   g_mb_global_teacher_diag_breakout_gate_abs = 0.16;
   g_mb_global_teacher_diag_trend_gate_abs = 0.14;
   g_mb_global_teacher_diag_range_gate_abs = 0.10;
   g_mb_global_teacher_diag_rejection_gate_abs = 0.10;
  }

bool MbGlobalTeacherLearningDiagnosticParseBool(const string value,const bool fallback)
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

int MbGlobalTeacherLearningDiagnosticParseInt(const string value,const int fallback)
  {
   string normalized = value;
   StringTrimLeft(normalized);
   StringTrimRight(normalized);
   if(StringLen(normalized) <= 0)
      return fallback;
   return (int)StringToInteger(normalized);
  }

double MbGlobalTeacherLearningDiagnosticParseDouble(const string value,const double fallback)
  {
   string normalized = value;
   StringTrimLeft(normalized);
   StringTrimRight(normalized);
   if(StringLen(normalized) <= 0)
      return fallback;
   return StringToDouble(normalized);
  }

void MbLoadGlobalTeacherLearningDiagnostic(const bool force_reload = false)
  {
   datetime now_local = TimeLocal();
   if(!force_reload && g_mb_global_teacher_diag_loaded && g_mb_global_teacher_diag_last_reload_local > 0 && (now_local - g_mb_global_teacher_diag_last_reload_local) < 5)
      return;

   g_mb_global_teacher_diag_loaded = true;
   g_mb_global_teacher_diag_last_reload_local = now_local;
   MbResetGlobalTeacherLearningDiagnosticState();

   string rel_path = MbGlobalTeacherLearningDiagnosticPath();
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
         g_mb_global_teacher_diag_enabled = MbGlobalTeacherLearningDiagnosticParseBool(value,g_mb_global_teacher_diag_enabled);
      else if(key == "max_age_sec")
         g_mb_global_teacher_diag_max_age_sec = MathMax(60,MbGlobalTeacherLearningDiagnosticParseInt(value,g_mb_global_teacher_diag_max_age_sec));
      else if(key == "force_scan_interval_sec")
         g_mb_global_teacher_diag_force_scan_interval_sec = MathMax(5,MbGlobalTeacherLearningDiagnosticParseInt(value,g_mb_global_teacher_diag_force_scan_interval_sec));
      else if(key == "allow_low_conversion_ratio")
         g_mb_global_teacher_diag_allow_low_conversion_ratio = MbGlobalTeacherLearningDiagnosticParseBool(value,g_mb_global_teacher_diag_allow_low_conversion_ratio);
      else if(key == "allow_forefield_dirty")
         g_mb_global_teacher_diag_allow_forefield_dirty = MbGlobalTeacherLearningDiagnosticParseBool(value,g_mb_global_teacher_diag_allow_forefield_dirty);
      else if(key == "allow_portfolio_heat")
         g_mb_global_teacher_diag_allow_portfolio_heat = MbGlobalTeacherLearningDiagnosticParseBool(value,g_mb_global_teacher_diag_allow_portfolio_heat);
      else if(key == "allow_family_freeze_relief")
         g_mb_global_teacher_diag_allow_family_freeze_relief = MbGlobalTeacherLearningDiagnosticParseBool(value,g_mb_global_teacher_diag_allow_family_freeze_relief);
      else if(key == "allow_fleet_freeze_relief")
         g_mb_global_teacher_diag_allow_fleet_freeze_relief = MbGlobalTeacherLearningDiagnosticParseBool(value,g_mb_global_teacher_diag_allow_fleet_freeze_relief);
      else if(key == "relax_tuning_gates")
         g_mb_global_teacher_diag_relax_tuning_gates = MbGlobalTeacherLearningDiagnosticParseBool(value,g_mb_global_teacher_diag_relax_tuning_gates);
      else if(key == "relax_cost_gates")
         g_mb_global_teacher_diag_relax_cost_gates = MbGlobalTeacherLearningDiagnosticParseBool(value,g_mb_global_teacher_diag_relax_cost_gates);
      else if(key == "breakout_gate_abs")
         g_mb_global_teacher_diag_breakout_gate_abs = MbGlobalTeacherLearningDiagnosticParseDouble(value,g_mb_global_teacher_diag_breakout_gate_abs);
      else if(key == "trend_gate_abs")
         g_mb_global_teacher_diag_trend_gate_abs = MbGlobalTeacherLearningDiagnosticParseDouble(value,g_mb_global_teacher_diag_trend_gate_abs);
      else if(key == "range_gate_abs")
         g_mb_global_teacher_diag_range_gate_abs = MbGlobalTeacherLearningDiagnosticParseDouble(value,g_mb_global_teacher_diag_range_gate_abs);
      else if(key == "rejection_gate_abs")
         g_mb_global_teacher_diag_rejection_gate_abs = MbGlobalTeacherLearningDiagnosticParseDouble(value,g_mb_global_teacher_diag_rejection_gate_abs);
     }

   FileClose(handle);

   if(modified_local > 0 && (now_local - (datetime)modified_local) > g_mb_global_teacher_diag_max_age_sec)
      g_mb_global_teacher_diag_enabled = false;
  }

bool MbIsGlobalTeacherLearningDiagnosticActive(const string symbol,const bool paper_mode_active)
  {
   if(!paper_mode_active)
      return false;
   if(!MbIsGlobalTeacherLearningDiagnosticSymbol(symbol))
      return false;

   string rel_path = MbGlobalTeacherLearningDiagnosticPath();
   bool file_present = FileIsExist(rel_path,FILE_COMMON);
   MbLoadGlobalTeacherLearningDiagnostic();
   if(file_present && !g_mb_global_teacher_diag_enabled)
      g_mb_global_teacher_diag_enabled = true;
   return g_mb_global_teacher_diag_enabled;
  }

bool MbShouldBypassGlobalTeacherLearningSoftReject(
   const string symbol,
   const bool paper_mode_active,
   const string setup_type,
   const string reason_code
)
  {
   if(!MbIsGlobalTeacherLearningDiagnosticActive(symbol,paper_mode_active))
      return false;
   if(setup_type == "NONE" || StringLen(setup_type) <= 0)
      return false;

   if(reason_code == "SCORE_BELOW_TRIGGER")
      return true;
   if(reason_code == "LOW_CONFIDENCE" || reason_code == "CONTEXT_LOW_CONFIDENCE")
      return true;
   if(reason_code == "AUX_CONFLICT_BLOCK")
      return true;
   if(StringFind(reason_code,"FOREFIELD_DIRTY_",0) == 0 && g_mb_global_teacher_diag_allow_forefield_dirty)
      return true;
   if(StringFind(reason_code,"PAPER_CONVERSION_BLOCKED_",0) == 0 && g_mb_global_teacher_diag_allow_low_conversion_ratio)
      return true;

   return false;
  }

bool MbShouldRelaxGlobalTeacherLearningTuningGate(const string symbol,const bool paper_mode_active)
  {
   if(!MbIsGlobalTeacherLearningDiagnosticActive(symbol,paper_mode_active))
      return false;
   return g_mb_global_teacher_diag_relax_tuning_gates;
  }

bool MbShouldRelaxGlobalTeacherLearningCostGate(const string symbol,const bool paper_mode_active)
  {
   if(!MbIsGlobalTeacherLearningDiagnosticActive(symbol,paper_mode_active))
      return false;
   return g_mb_global_teacher_diag_relax_cost_gates;
  }

bool MbShouldForceGlobalTeacherLearningTimerScan(
   const string symbol,
   const bool paper_mode_active,
   const datetime now_ts
)
  {
   if(!MbIsGlobalTeacherLearningDiagnosticActive(symbol,paper_mode_active))
      return false;

   string canonical = MbCanonicalSymbol(symbol);
   if(
      g_mb_global_teacher_diag_last_timer_scan_ts > 0 &&
      g_mb_global_teacher_diag_last_timer_scan_symbol == canonical &&
      (now_ts - g_mb_global_teacher_diag_last_timer_scan_ts) < g_mb_global_teacher_diag_force_scan_interval_sec
   )
      return false;

   g_mb_global_teacher_diag_last_timer_scan_ts = now_ts;
   g_mb_global_teacher_diag_last_timer_scan_symbol = canonical;
   return true;
  }

void MbApplyGlobalTeacherLearningTuningRescue(
   const string symbol,
   const bool paper_mode_active,
   MbTuningFamilyPolicy &family_policy,
   MbTuningCoordinatorState &coordinator_state
)
  {
   if(!MbIsGlobalTeacherLearningDiagnosticActive(symbol,paper_mode_active))
      return;

   family_policy.paper_mode_active = true;
   if(g_mb_global_teacher_diag_allow_family_freeze_relief)
     {
      family_policy.freeze_new_changes = false;
      family_policy.dominant_confidence_cap = 1.0;
      family_policy.dominant_risk_cap = 1.0;
      family_policy.breakout_family_tax = 0.0;
      family_policy.trend_family_tax = 0.0;
      if(family_policy.last_action_code == "FREEZE_FAMILY" || family_policy.last_action_code == "DEFENSIVE_FAMILY")
        {
         family_policy.last_action_code = "GLOBAL_TEACHER_RELAX_FAMILY";
         family_policy.last_action_detail = "paper global teacher diagnostic removed family freeze overlays";
        }
     }

   coordinator_state.paper_mode_active = true;
   if(g_mb_global_teacher_diag_allow_fleet_freeze_relief)
     {
      coordinator_state.freeze_new_changes = false;
      coordinator_state.global_confidence_cap = 1.0;
      coordinator_state.global_risk_cap = 1.0;
      if(
         coordinator_state.last_action_code == "FREEZE_FLEET" ||
         coordinator_state.last_action_code == "DEFENSIVE_FLEET" ||
         coordinator_state.last_action_code == "COOL_FLEET" ||
         coordinator_state.last_action_code == "LIMIT_CHANGE_BUDGET"
      )
        {
         coordinator_state.last_action_code = "GLOBAL_TEACHER_RELAX_FLEET";
         coordinator_state.last_action_detail = "paper global teacher diagnostic removed fleet freeze overlays";
        }
     }
  }

bool MbShouldBypassGlobalTeacherLearningCandidateArbitration(
   const string symbol,
   const bool paper_mode_active,
   const string reason_code,
   const string setup_type,
   const double score,
   const string execution_regime,
   const string spread_regime
)
  {
   if(!MbIsGlobalTeacherLearningDiagnosticActive(symbol,paper_mode_active))
      return false;
   if(reason_code != "PORTFOLIO_HEAT_BLOCK" || !g_mb_global_teacher_diag_allow_portfolio_heat)
      return false;
   if(setup_type == "NONE" || StringLen(setup_type) <= 0)
      return false;
   if(execution_regime == "BAD")
      return false;
   if(spread_regime == "BAD")
      return false;
   if(MathAbs(score) < 0.08)
      return false;
   return true;
  }

double MbResolveGlobalTeacherLearningGateAbs(
   const string symbol,
   const string setup_type,
   const bool paper_mode_active,
   const double current_gate_abs
)
  {
   if(!MbIsGlobalTeacherLearningDiagnosticActive(symbol,paper_mode_active))
      return current_gate_abs;

   double diagnostic_gate_abs = current_gate_abs;
   if(setup_type == "SETUP_BREAKOUT")
      diagnostic_gate_abs = g_mb_global_teacher_diag_breakout_gate_abs;
   else if(setup_type == "SETUP_TREND")
      diagnostic_gate_abs = g_mb_global_teacher_diag_trend_gate_abs;
   else if(setup_type == "SETUP_RANGE")
      diagnostic_gate_abs = g_mb_global_teacher_diag_range_gate_abs;
   else if(setup_type == "SETUP_REJECTION")
      diagnostic_gate_abs = g_mb_global_teacher_diag_rejection_gate_abs;

   if(diagnostic_gate_abs <= 0.0)
      return current_gate_abs;
   if(current_gate_abs <= 0.0)
      return diagnostic_gate_abs;
   return MathMin(current_gate_abs,diagnostic_gate_abs);
  }

#endif
