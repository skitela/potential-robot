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

bool MirrorIntegerProperty(const string broker_symbol,
                           const string custom_symbol,
                           const ENUM_SYMBOL_INFO_INTEGER property_id,
                           const string property_name,
                           int &applied_count,
                           int &failed_count)
  {
   long value = 0;
   ResetLastError();
   if(!SymbolInfoInteger(broker_symbol,property_id,value))
     {
      failed_count++;
      PrintFormat("Failed to read integer property %s from %s err=%d",property_name,broker_symbol,GetLastError());
      ResetLastError();
      return(false);
     }

   ResetLastError();
   if(CustomSymbolSetInteger(custom_symbol,property_id,value))
     {
      applied_count++;
      return(true);
     }

   failed_count++;
   PrintFormat("Failed to set integer property %s on %s err=%d",property_name,custom_symbol,GetLastError());
   ResetLastError();
   return(false);
  }

bool MirrorDoubleProperty(const string broker_symbol,
                          const string custom_symbol,
                          const ENUM_SYMBOL_INFO_DOUBLE property_id,
                          const string property_name,
                          int &applied_count,
                          int &failed_count)
  {
   double value = 0.0;
   ResetLastError();
   if(!SymbolInfoDouble(broker_symbol,property_id,value))
     {
      failed_count++;
      PrintFormat("Failed to read double property %s from %s err=%d",property_name,broker_symbol,GetLastError());
      ResetLastError();
      return(false);
     }

   ResetLastError();
   if(CustomSymbolSetDouble(custom_symbol,property_id,value))
     {
      applied_count++;
      return(true);
     }

   failed_count++;
   PrintFormat("Failed to set double property %s on %s err=%d",property_name,custom_symbol,GetLastError());
   ResetLastError();
   return(false);
  }

bool MirrorStringProperty(const string broker_symbol,
                          const string custom_symbol,
                          const ENUM_SYMBOL_INFO_STRING property_id,
                          const string property_name,
                          int &applied_count,
                          int &failed_count)
  {
   string value = "";
   ResetLastError();
   if(!SymbolInfoString(broker_symbol,property_id,value))
     {
      failed_count++;
      PrintFormat("Failed to read string property %s from %s err=%d",property_name,broker_symbol,GetLastError());
      ResetLastError();
      return(false);
     }

   ResetLastError();
   if(CustomSymbolSetString(custom_symbol,property_id,value))
     {
      applied_count++;
      return(true);
     }

   failed_count++;
   PrintFormat("Failed to set string property %s on %s err=%d",property_name,custom_symbol,GetLastError());
   ResetLastError();
   return(false);
  }

void CopyBrokerMarginRates(const string broker_symbol,const string custom_symbol,int &copied_count,int &failed_count)
  {
   ENUM_ORDER_TYPE order_types[] =
     {
      ORDER_TYPE_BUY,
      ORDER_TYPE_SELL,
      ORDER_TYPE_BUY_LIMIT,
      ORDER_TYPE_SELL_LIMIT,
      ORDER_TYPE_BUY_STOP,
      ORDER_TYPE_SELL_STOP,
      ORDER_TYPE_BUY_STOP_LIMIT,
      ORDER_TYPE_SELL_STOP_LIMIT
     };

   for(int i = 0; i < ArraySize(order_types); ++i)
     {
      double initial_margin_rate = 0.0;
      double maintenance_margin_rate = 0.0;
      ResetLastError();
      if(!SymbolInfoMarginRate(broker_symbol,order_types[i],initial_margin_rate,maintenance_margin_rate))
        {
         failed_count++;
         PrintFormat("Failed to read margin rates from %s for order_type=%d err=%d",broker_symbol,(int)order_types[i],GetLastError());
         ResetLastError();
         continue;
        }

      ResetLastError();
      if(CustomSymbolSetMarginRate(custom_symbol,order_types[i],initial_margin_rate,maintenance_margin_rate))
        {
         copied_count++;
         continue;
        }

      failed_count++;
      PrintFormat("Failed to set margin rates on %s for order_type=%d err=%d",custom_symbol,(int)order_types[i],GetLastError());
      ResetLastError();
     }
  }

void CopyBrokerProperties(const string broker_symbol,const string custom_symbol)
  {
   if(StringLen(broker_symbol) == 0 || StringLen(custom_symbol) == 0)
      return;

   int integer_applied = 0;
   int integer_failed = 0;
   int double_applied = 0;
   int double_failed = 0;
   int string_applied = 0;
   int string_failed = 0;
   int margin_copied = 0;
   int margin_failed = 0;

   MirrorIntegerProperty(broker_symbol,custom_symbol,SYMBOL_CHART_MODE,"SYMBOL_CHART_MODE",integer_applied,integer_failed);
   MirrorIntegerProperty(broker_symbol,custom_symbol,SYMBOL_DIGITS,"SYMBOL_DIGITS",integer_applied,integer_failed);
   MirrorIntegerProperty(broker_symbol,custom_symbol,SYMBOL_SPREAD_FLOAT,"SYMBOL_SPREAD_FLOAT",integer_applied,integer_failed);
   MirrorIntegerProperty(broker_symbol,custom_symbol,SYMBOL_SPREAD,"SYMBOL_SPREAD",integer_applied,integer_failed);
   MirrorIntegerProperty(broker_symbol,custom_symbol,SYMBOL_TRADE_MODE,"SYMBOL_TRADE_MODE",integer_applied,integer_failed);
   MirrorIntegerProperty(broker_symbol,custom_symbol,SYMBOL_TRADE_EXEMODE,"SYMBOL_TRADE_EXEMODE",integer_applied,integer_failed);
   MirrorIntegerProperty(broker_symbol,custom_symbol,SYMBOL_TRADE_CALC_MODE,"SYMBOL_TRADE_CALC_MODE",integer_applied,integer_failed);
   MirrorIntegerProperty(broker_symbol,custom_symbol,SYMBOL_TRADE_STOPS_LEVEL,"SYMBOL_TRADE_STOPS_LEVEL",integer_applied,integer_failed);
   MirrorIntegerProperty(broker_symbol,custom_symbol,SYMBOL_TRADE_FREEZE_LEVEL,"SYMBOL_TRADE_FREEZE_LEVEL",integer_applied,integer_failed);
   MirrorIntegerProperty(broker_symbol,custom_symbol,SYMBOL_SWAP_MODE,"SYMBOL_SWAP_MODE",integer_applied,integer_failed);
   MirrorIntegerProperty(broker_symbol,custom_symbol,SYMBOL_SWAP_ROLLOVER3DAYS,"SYMBOL_SWAP_ROLLOVER3DAYS",integer_applied,integer_failed);
   MirrorIntegerProperty(broker_symbol,custom_symbol,SYMBOL_EXPIRATION_MODE,"SYMBOL_EXPIRATION_MODE",integer_applied,integer_failed);
   MirrorIntegerProperty(broker_symbol,custom_symbol,SYMBOL_FILLING_MODE,"SYMBOL_FILLING_MODE",integer_applied,integer_failed);
   MirrorIntegerProperty(broker_symbol,custom_symbol,SYMBOL_ORDER_MODE,"SYMBOL_ORDER_MODE",integer_applied,integer_failed);

   MirrorDoubleProperty(broker_symbol,custom_symbol,SYMBOL_POINT,"SYMBOL_POINT",double_applied,double_failed);
   MirrorDoubleProperty(broker_symbol,custom_symbol,SYMBOL_TRADE_TICK_SIZE,"SYMBOL_TRADE_TICK_SIZE",double_applied,double_failed);
   MirrorDoubleProperty(broker_symbol,custom_symbol,SYMBOL_TRADE_TICK_VALUE,"SYMBOL_TRADE_TICK_VALUE",double_applied,double_failed);
   MirrorDoubleProperty(broker_symbol,custom_symbol,SYMBOL_TRADE_TICK_VALUE_PROFIT,"SYMBOL_TRADE_TICK_VALUE_PROFIT",double_applied,double_failed);
   MirrorDoubleProperty(broker_symbol,custom_symbol,SYMBOL_TRADE_TICK_VALUE_LOSS,"SYMBOL_TRADE_TICK_VALUE_LOSS",double_applied,double_failed);
   MirrorDoubleProperty(broker_symbol,custom_symbol,SYMBOL_TRADE_CONTRACT_SIZE,"SYMBOL_TRADE_CONTRACT_SIZE",double_applied,double_failed);
   MirrorDoubleProperty(broker_symbol,custom_symbol,SYMBOL_VOLUME_MIN,"SYMBOL_VOLUME_MIN",double_applied,double_failed);
   MirrorDoubleProperty(broker_symbol,custom_symbol,SYMBOL_VOLUME_MAX,"SYMBOL_VOLUME_MAX",double_applied,double_failed);
   MirrorDoubleProperty(broker_symbol,custom_symbol,SYMBOL_VOLUME_STEP,"SYMBOL_VOLUME_STEP",double_applied,double_failed);
   MirrorDoubleProperty(broker_symbol,custom_symbol,SYMBOL_VOLUME_LIMIT,"SYMBOL_VOLUME_LIMIT",double_applied,double_failed);
   MirrorDoubleProperty(broker_symbol,custom_symbol,SYMBOL_SWAP_LONG,"SYMBOL_SWAP_LONG",double_applied,double_failed);
   MirrorDoubleProperty(broker_symbol,custom_symbol,SYMBOL_SWAP_SHORT,"SYMBOL_SWAP_SHORT",double_applied,double_failed);
   MirrorDoubleProperty(broker_symbol,custom_symbol,SYMBOL_MARGIN_INITIAL,"SYMBOL_MARGIN_INITIAL",double_applied,double_failed);
   MirrorDoubleProperty(broker_symbol,custom_symbol,SYMBOL_MARGIN_MAINTENANCE,"SYMBOL_MARGIN_MAINTENANCE",double_applied,double_failed);

   MirrorStringProperty(broker_symbol,custom_symbol,SYMBOL_DESCRIPTION,"SYMBOL_DESCRIPTION",string_applied,string_failed);
   MirrorStringProperty(broker_symbol,custom_symbol,SYMBOL_CURRENCY_BASE,"SYMBOL_CURRENCY_BASE",string_applied,string_failed);
   MirrorStringProperty(broker_symbol,custom_symbol,SYMBOL_CURRENCY_PROFIT,"SYMBOL_CURRENCY_PROFIT",string_applied,string_failed);
   MirrorStringProperty(broker_symbol,custom_symbol,SYMBOL_CURRENCY_MARGIN,"SYMBOL_CURRENCY_MARGIN",string_applied,string_failed);

   CopyBrokerMarginRates(broker_symbol,custom_symbol,margin_copied,margin_failed);

   PrintFormat("Copied broker properties from %s to %s: integer=%d failed_integer=%d double=%d failed_double=%d string=%d failed_string=%d margin=%d failed_margin=%d",
               broker_symbol,
               custom_symbol,
               integer_applied,
               integer_failed,
               double_applied,
               double_failed,
               string_applied,
               string_failed,
               margin_copied,
               margin_failed);
  }

void CopySessionsForDay(const string broker_symbol,
                        const string custom_symbol,
                        const ENUM_DAY_OF_WEEK day_of_week,
                        const bool trade_sessions,
                        int &copied_count,
                        int &failed_count)
  {
   for(uint session_index = 0; session_index < 16; ++session_index)
     {
      datetime from_time = 0;
      datetime to_time = 0;
      const bool source_ok = trade_sessions
         ? SymbolInfoSessionTrade(broker_symbol,day_of_week,session_index,from_time,to_time)
         : SymbolInfoSessionQuote(broker_symbol,day_of_week,session_index,from_time,to_time);
      if(!source_ok)
         break;

      ResetLastError();
      const bool apply_ok = trade_sessions
         ? CustomSymbolSetSessionTrade(custom_symbol,day_of_week,session_index,from_time,to_time)
         : CustomSymbolSetSessionQuote(custom_symbol,day_of_week,session_index,from_time,to_time);
      if(apply_ok)
         copied_count++;
      else
        {
         failed_count++;
         PrintFormat("Failed to copy %s session for %s day=%d idx=%d err=%d",
                     (trade_sessions ? "trade" : "quote"),
                     custom_symbol,
                     (int)day_of_week,
                     (int)session_index,
                     GetLastError());
         ResetLastError();
        }
     }
  }

void CopyBrokerSessions(const string broker_symbol,const string custom_symbol)
  {
   if(StringLen(broker_symbol) == 0 || StringLen(custom_symbol) == 0)
      return;

   int copied_trade = 0;
   int copied_quote = 0;
   int failed_trade = 0;
   int failed_quote = 0;

   for(int day = (int)SUNDAY; day <= (int)SATURDAY; ++day)
     {
      const ENUM_DAY_OF_WEEK day_of_week = (ENUM_DAY_OF_WEEK)day;
      CopySessionsForDay(broker_symbol,custom_symbol,day_of_week,true,copied_trade,failed_trade);
      CopySessionsForDay(broker_symbol,custom_symbol,day_of_week,false,copied_quote,failed_quote);
     }

   PrintFormat("Copied broker sessions from %s to %s: trade=%d quote=%d failed_trade=%d failed_quote=%d",
               broker_symbol,
               custom_symbol,
               copied_trade,
               copied_quote,
               failed_trade,
               failed_quote);
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

   CopyBrokerProperties(InpBrokerTemplateSymbol,InpCustomSymbol);
   CopyBrokerSessions(InpBrokerTemplateSymbol,InpCustomSymbol);

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
