#ifndef MB_RUNTIME_LOG_ROTATION_INCLUDED
#define MB_RUNTIME_LOG_ROTATION_INCLUDED

#include "MbStorage.mqh"

string MbRuntimeLogFileName(const string rel_path)
  {
   for(int i = StringLen(rel_path) - 1; i >= 0; --i)
     {
      if(StringGetCharacter(rel_path,i) == '\\')
         return StringSubstr(rel_path,i + 1);
     }
   return rel_path;
  }

string MbRuntimeLogParentDir(const string rel_path)
  {
   for(int i = StringLen(rel_path) - 1; i >= 0; --i)
     {
      if(StringGetCharacter(rel_path,i) == '\\')
         return StringSubstr(rel_path,0,i);
     }
   return "";
  }

ulong MbRuntimeLogRotationThresholdBytes(const string file_name)
  {
   if(file_name == "incident_journal.jsonl")
      return (ulong)(8 * 1024 * 1024);
   if(file_name == "decision_events.csv")
      return (ulong)(8 * 1024 * 1024);
   if(file_name == "candidate_signals.csv")
      return (ulong)(24 * 1024 * 1024);
   if(file_name == "execution_telemetry.csv")
      return (ulong)(12 * 1024 * 1024);
   return (ulong)0;
  }

void MbRotateRuntimeLogIfOversized(const string rel_path)
  {
   if(StringLen(rel_path) <= 0 || !FileIsExist(rel_path,FILE_COMMON))
      return;

   string file_name = MbRuntimeLogFileName(rel_path);
   ulong threshold_bytes = MbRuntimeLogRotationThresholdBytes(file_name);
   if(threshold_bytes <= 0)
      return;

   int read_handle = FileOpen(rel_path,FILE_COMMON | FILE_READ | FILE_BIN);
   if(read_handle == INVALID_HANDLE)
      return;

   ulong current_size = (ulong)FileSize(read_handle);
   FileClose(read_handle);
   if(current_size <= threshold_bytes)
      return;

   string parent_dir = MbRuntimeLogParentDir(rel_path);
   if(StringLen(parent_dir) <= 0)
      return;

   string archive_dir = parent_dir + "\\archive";
   if(!MbEnsureDir(archive_dir))
      return;

   string archive_path = StringFormat("%s\\%I64d_%s",archive_dir,(long)TimeCurrent(),file_name);
   FileDelete(archive_path,FILE_COMMON);
   if(!FileMove(rel_path,FILE_COMMON,archive_path,FILE_COMMON))
      return;
  }

#endif
