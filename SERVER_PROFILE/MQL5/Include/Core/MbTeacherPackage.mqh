#ifndef MB_TEACHER_PACKAGE_INCLUDED
#define MB_TEACHER_PACKAGE_INCLUDED

struct MbTeacherPackageContract
  {
   bool present;
   bool enabled;
   bool teacher_required;
   bool personal_allowed;
   bool outcome_ready;
   bool local_model_available;
   bool global_model_available;
   bool paper_live_enabled;
   string teacher_scope;
   string teacher_package_mode;
   string teacher_mode;
   string teacher_policy_id;
   string teacher_id;
   string symbol;
   string symbol_family;
   string local_training_mode;
   string runtime_scope;
   string paper_live_bucket;
   string universe_version;
   string plan_hash;
   double min_gate_probability;
   double min_decision_score_pln;
   double max_spread_points;
   double max_server_ping_ms;
   double max_server_latency_us_avg;
  };

void MbTeacherPackageReset(MbTeacherPackageContract &contract)
  {
   contract.present = false;
   contract.enabled = false;
   contract.teacher_required = true;
   contract.personal_allowed = false;
   contract.outcome_ready = false;
   contract.local_model_available = false;
   contract.global_model_available = false;
   contract.paper_live_enabled = false;
   contract.teacher_scope = "GLOBAL";
   contract.teacher_package_mode = "GLOBAL_ONLY";
   contract.teacher_mode = "GLOBAL_ONLY";
   contract.teacher_policy_id = "TEACHER_PROMOTION_POLICY_V1";
   contract.teacher_id = "";
   contract.symbol = "";
   contract.symbol_family = "";
   contract.local_training_mode = "FALLBACK_ONLY";
   contract.runtime_scope = "LAPTOP_ONLY";
   contract.paper_live_bucket = "GLOBAL_TEACHER_ONLY";
   contract.universe_version = "";
   contract.plan_hash = "";
   contract.min_gate_probability = 0.0;
   contract.min_decision_score_pln = 0.0;
   contract.max_spread_points = 0.0;
   contract.max_server_ping_ms = 0.0;
   contract.max_server_latency_us_avg = 0.0;
  }

bool MbTeacherPackageReadBool(const string value)
  {
   string normalized = value;
   StringToUpper(normalized);
   return (normalized == "1" || normalized == "TRUE" || normalized == "YES" || normalized == "ON");
  }

bool MbTeacherPackageLoad(const string rel_path,MbTeacherPackageContract &contract)
  {
   MbTeacherPackageReset(contract);
   if(StringLen(rel_path) <= 0 || !FileIsExist(rel_path,FILE_COMMON))
      return false;

   int handle = FileOpen(rel_path,FILE_COMMON | FILE_READ | FILE_CSV | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;

   while(!FileIsEnding(handle))
     {
      string key = FileReadString(handle);
      string value = FileReadString(handle);
      if(StringLen(key) <= 0)
         continue;

      if(key == "enabled")
         contract.enabled = MbTeacherPackageReadBool(value);
      else if(key == "teacher_required")
         contract.teacher_required = MbTeacherPackageReadBool(value);
      else if(key == "outcome_ready")
         contract.outcome_ready = MbTeacherPackageReadBool(value);
      else if(key == "local_model_available")
         contract.local_model_available = MbTeacherPackageReadBool(value);
      else if(key == "global_model_available")
         contract.global_model_available = MbTeacherPackageReadBool(value);
      else if(key == "paper_live_enabled")
         contract.paper_live_enabled = MbTeacherPackageReadBool(value);
      else if(key == "local_training_mode")
         contract.local_training_mode = value;
      else if(key == "runtime_scope")
         contract.runtime_scope = value;
      else if(key == "paper_live_bucket")
         contract.paper_live_bucket = value;
      else if(key == "universe_version")
         contract.universe_version = value;
      else if(key == "plan_hash")
         contract.plan_hash = value;
      else if(key == "teacher_scope")
         contract.teacher_scope = value;
      else if(key == "teacher_package_mode")
         contract.teacher_package_mode = value;
      else if(key == "teacher_mode")
         contract.teacher_mode = value;
      else if(key == "teacher_policy_id")
         contract.teacher_policy_id = value;
      else if(key == "teacher_id")
         contract.teacher_id = value;
      else if(key == "symbol")
         contract.symbol = value;
      else if(key == "symbol_family")
         contract.symbol_family = value;
      else if(key == "personal_allowed")
         contract.personal_allowed = MbTeacherPackageReadBool(value);
      else if(key == "min_gate_probability")
         contract.min_gate_probability = StringToDouble(value);
      else if(key == "min_decision_score_pln")
         contract.min_decision_score_pln = StringToDouble(value);
      else if(key == "max_spread_points")
         contract.max_spread_points = StringToDouble(value);
      else if(key == "max_server_ping_ms")
         contract.max_server_ping_ms = StringToDouble(value);
      else if(key == "max_server_latency_us_avg")
         contract.max_server_latency_us_avg = StringToDouble(value);
     }

   FileClose(handle);
   contract.present = true;
   if(StringLen(contract.teacher_package_mode) <= 0)
      contract.teacher_package_mode = contract.teacher_mode;
   if(StringLen(contract.teacher_package_mode) <= 0)
      contract.teacher_package_mode = "GLOBAL_ONLY";
   if(StringLen(contract.teacher_mode) <= 0)
      contract.teacher_mode = contract.teacher_package_mode;
   if(StringLen(contract.paper_live_bucket) <= 0)
      contract.paper_live_bucket = "GLOBAL_TEACHER_ONLY";
   return true;
  }

#endif
