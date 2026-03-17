#ifndef MB_CONFIG_ENVELOPE_INCLUDED
#define MB_CONFIG_ENVELOPE_INCLUDED

ulong MbFnv1a64(const string text)
  {
   uchar data[];
   StringToCharArray(text,data,0,StringLen(text));
   ulong hash = 1469598103934665603;
   for(int i = 0; i < ArraySize(data); i++)
     {
      hash ^= (ulong)data[i];
      hash *= 1099511628211;
     }
   return hash;
  }

bool MbWriteAtomicTextFile(const string rel_path,const string payload)
  {
   string tmp_path = rel_path + ".tmp";
   int h = FileOpen(tmp_path, FILE_COMMON | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;
   FileWriteString(h,payload);
   FileClose(h);
   FileDelete(rel_path, FILE_COMMON);
   return FileMove(tmp_path, 0, rel_path, FILE_COMMON);
  }

string MbBuildConfigEnvelope(const string config_name,const string payload)
  {
   ulong config_hash = MbFnv1a64(payload);
   return StringFormat(
      "{\"schema_version\":\"1.0\",\"config_name\":\"%s\",\"config_hash\":\"%I64u\",\"payload\":%s}",
      config_name,
      config_hash,
      payload
   );
  }

bool MbFlushConfigEnvelope(const string rel_path,const string config_name,const string payload)
  {
   return MbWriteAtomicTextFile(rel_path,MbBuildConfigEnvelope(config_name,payload));
  }

#endif
