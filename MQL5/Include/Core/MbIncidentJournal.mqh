#ifndef MB_INCIDENT_JOURNAL_INCLUDED
#define MB_INCIDENT_JOURNAL_INCLUDED

#include "MbExecutionCommon.mqh"

string g_mb_incident_queue[];
string g_mb_incident_queue_path = "";

void MbIncidentJournalInit(const string rel_path)
  {
   g_mb_incident_queue_path = rel_path;
   ArrayResize(g_mb_incident_queue,0);
  }

void MbIncidentJournalFlush()
  {
   int queued = ArraySize(g_mb_incident_queue);
   if(queued <= 0 || StringLen(g_mb_incident_queue_path) <= 0)
      return;

   int h = FileOpen(g_mb_incident_queue_path, FILE_COMMON | FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;
   FileSeek(h,0,SEEK_END);
   for(int i = 0; i < queued; ++i)
      FileWriteString(h,g_mb_incident_queue[i] + "\n");
   FileClose(h);
   ArrayResize(g_mb_incident_queue,0);
  }

void MbIncidentJournalAppend(const string rel_path,const string payload)
  {
   if(StringLen(g_mb_incident_queue_path) > 0 && rel_path == g_mb_incident_queue_path)
     {
      int next = ArraySize(g_mb_incident_queue);
      ArrayResize(g_mb_incident_queue,next + 1);
      g_mb_incident_queue[next] = payload;
      if(ArraySize(g_mb_incident_queue) >= 32)
         MbIncidentJournalFlush();
      return;
     }

   int h = FileOpen(rel_path, FILE_COMMON | FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;
   FileSeek(h,0,SEEK_END);
   FileWriteString(h,payload + "\n");
   FileClose(h);
  }

void MbIncidentNoteRetcode(
   const string rel_path,
   const string symbol,
   const string source,
   const long retcode_num,
   const string retcode_name,
   const int attempt
)
  {
   string payload = StringFormat(
      "{\"ts_utc\":%I64d,\"type\":\"retcode\",\"class\":\"%s\",\"severity\":\"%s\",\"source\":\"%s\",\"symbol\":\"%s\",\"retcode_num\":%I64d,\"retcode_name\":\"%s\",\"attempt\":%d}",
      (long)TimeCurrent(),
      MbIncidentClassFromRetcode(retcode_num,retcode_name),
      MbIncidentSeverityFromRetcode(retcode_num,retcode_name),
      source,
      symbol,
      retcode_num,
      retcode_name,
      attempt
   );
   MbIncidentJournalAppend(rel_path,payload);
  }

void MbIncidentNoteGuard(
   const string rel_path,
   const string symbol,
   const string guard_name,
   const string reason_code,
   const string severity,
   const string category
)
  {
   string payload = StringFormat(
      "{\"ts_utc\":%I64d,\"type\":\"guard\",\"class\":\"%s\",\"severity\":\"%s\",\"source\":\"%s\",\"symbol\":\"%s\",\"reason\":\"%s\"}",
      (long)TimeCurrent(),
      category,
      severity,
      guard_name,
      symbol,
      reason_code
   );
   MbIncidentJournalAppend(rel_path,payload);
  }

#endif
