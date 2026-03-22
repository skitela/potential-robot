#property strict
#property script_show_inputs

input string InpCommonCsvPath = "MAKRO_I_MIKRO_BOT\\qdm_import\\MB_EURUSD_DUKA_M1_PILOT.csv";
input string InpCustomSymbol = "EURUSD_QDM_M1";
input string InpCustomGroup = "Research\\QDM\\Forex";
input string InpBrokerTemplateSymbol = "EURUSD.pro";
input bool   InpSelectSymbolAfterImport = true;

bool EnsureCustomSymbol(const string custom_symbol,const string group_name,const string broker_symbol)
  {
   ResetLastError();
   if(CustomSymbolCreate(custom_symbol,group_name,broker_symbol))
      return(true);

   const int create_error = GetLastError();
   ResetLastError();
   if(SymbolSelect(custom_symbol,true))
      return(true);

   PrintFormat("Custom symbol not ready: %s, create_error=%d, select_error=%d",custom_symbol,create_error,GetLastError());
   return(false);
  }

bool ReadRatesFromCommonCsv(const string relative_csv_path,MqlRates &rates[],int &skipped_non_increasing)
  {
   ArrayResize(rates,0);
   skipped_non_increasing=0;

   const int handle = FileOpen(relative_csv_path,FILE_READ|FILE_TXT|FILE_CSV|FILE_COMMON|FILE_ANSI,',');
   if(handle == INVALID_HANDLE)
     {
      PrintFormat("Failed to open common CSV: %s, error=%d",relative_csv_path,GetLastError());
      return(false);
     }

   int row_count = 0;
   datetime last_time = 0;
   while(!FileIsEnding(handle))
     {
      const string date_part = FileReadString(handle);
      if(FileIsEnding(handle) && StringLen(date_part) == 0)
         break;

      const string time_part = FileReadString(handle);
      const string open_part = FileReadString(handle);
      const string high_part = FileReadString(handle);
      const string low_part = FileReadString(handle);
      const string close_part = FileReadString(handle);
      const string tick_volume_part = FileReadString(handle);
      const string real_volume_part = FileReadString(handle);
      const string spread_part = FileReadString(handle);

      if(StringLen(date_part) == 0 || StringLen(time_part) == 0)
         continue;

      MqlRates rate;
      ZeroMemory(rate);
      rate.time = StringToTime(date_part + " " + time_part);
      rate.open = StringToDouble(open_part);
      rate.high = StringToDouble(high_part);
      rate.low = StringToDouble(low_part);
      rate.close = StringToDouble(close_part);
      rate.tick_volume = (long)StringToInteger(tick_volume_part);
      rate.real_volume = (long)StringToInteger(real_volume_part);
      rate.spread = (int)StringToInteger(spread_part);

      if(rate.time <= 0)
         continue;

      if(last_time > 0 && rate.time <= last_time)
        {
         skipped_non_increasing++;
         continue;
        }

      ArrayResize(rates,row_count + 1);
      rates[row_count] = rate;
      row_count++;
      last_time = rate.time;
     }

   FileClose(handle);
   return(row_count > 0);
  }

void OnStart()
  {
   MqlRates rates[];
   int skipped_non_increasing = 0;
   if(!ReadRatesFromCommonCsv(InpCommonCsvPath,rates,skipped_non_increasing))
     {
      Print("No rates parsed from CSV.");
      return;
     }

   if(!EnsureCustomSymbol(InpCustomSymbol,InpCustomGroup,InpBrokerTemplateSymbol))
      return;

   const datetime from_time = rates[0].time;
   const datetime to_time = rates[ArraySize(rates) - 1].time;

   ResetLastError();
   if(!CustomRatesDelete(InpCustomSymbol,from_time,to_time))
     {
      const int delete_error = GetLastError();
      if(delete_error != 0)
         PrintFormat("CustomRatesDelete notice for %s: %d",InpCustomSymbol,delete_error);
     }

   ResetLastError();
   const int replaced = CustomRatesReplace(InpCustomSymbol,from_time,to_time,rates);
   if(replaced <= 0)
     {
      PrintFormat("CustomRatesReplace failed for %s, error=%d",InpCustomSymbol,GetLastError());
      return;
     }

   if(InpSelectSymbolAfterImport)
      SymbolSelect(InpCustomSymbol,true);

   if(skipped_non_increasing > 0)
      PrintFormat("Skipped %d non-increasing CSV rows for %s before import",skipped_non_increasing,InpCustomSymbol);

   PrintFormat("Imported %d M1 bars into custom symbol %s from %s to %s",
               replaced,
               InpCustomSymbol,
               TimeToString(from_time,TIME_DATE|TIME_MINUTES),
               TimeToString(to_time,TIME_DATE|TIME_MINUTES));
  }
