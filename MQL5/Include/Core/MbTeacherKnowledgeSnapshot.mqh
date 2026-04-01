#ifndef MB_TEACHER_KNOWLEDGE_SNAPSHOT_INCLUDED
#define MB_TEACHER_KNOWLEDGE_SNAPSHOT_INCLUDED

string MbTeacherEscapeJson(const string value)
  {
   string out = value;
   StringReplace(out,"\\","\\\\");
   StringReplace(out,"\"","\\\"");
   return out;
  }

bool MbTeacherWriteKnowledgeSnapshot(
   const string rel_path,
   const string symbol,
   const string teacher_id,
   const string teacher_scope,
   const string teacher_package_mode,
   const bool teacher_present,
   const bool personal_allowed,
   const bool gate_visible,
   const bool lesson_ready,
   const bool knowledge_ready,
   const string reason_code,
   const string runtime_scope,
   const string local_training_mode,
   const double teacher_score,
   const double student_score,
   const double spread_points,
   const double server_ping_ms,
   const double server_latency_us_avg
)
  {
   if(StringLen(rel_path) <= 0)
      return false;

   int handle = FileOpen(rel_path,FILE_COMMON | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;

   string payload = StringFormat(
      "{\"schema_version\":\"1.0\",\"symbol\":\"%s\",\"generated_at_utc\":%I64d,\"teacher_present\":%s,\"teacher_id\":\"%s\",\"teacher_scope\":\"%s\",\"teacher_package_mode\":\"%s\",\"teacher_mode\":\"%s\",\"personal_allowed\":%s,\"gate_visible\":%s,\"lesson_ready\":%s,\"knowledge_ready\":%s,\"reason_code\":\"%s\",\"runtime_scope\":\"%s\",\"local_training_mode\":\"%s\",\"teacher_score\":%.6f,\"student_score\":%.6f,\"spread_points\":%.6f,\"server_ping_ms\":%.6f,\"server_latency_us_avg\":%.6f}",
      MbTeacherEscapeJson(symbol),
      (long)TimeGMT(),
      (teacher_present ? "true" : "false"),
      MbTeacherEscapeJson(teacher_id),
      MbTeacherEscapeJson(teacher_scope),
      MbTeacherEscapeJson(teacher_package_mode),
      MbTeacherEscapeJson(teacher_package_mode),
      (personal_allowed ? "true" : "false"),
      (gate_visible ? "true" : "false"),
      (lesson_ready ? "true" : "false"),
      (knowledge_ready ? "true" : "false"),
      MbTeacherEscapeJson(reason_code),
      MbTeacherEscapeJson(runtime_scope),
      MbTeacherEscapeJson(local_training_mode),
      teacher_score,
      student_score,
      spread_points,
      server_ping_ms,
      server_latency_us_avg
   );
   FileWriteString(handle,payload);
   FileClose(handle);
   return true;
  }

#endif
