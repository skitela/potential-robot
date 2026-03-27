#property strict
#property script_show_inputs

input string InpOutputRoot = "MAKRO_I_MIKRO_BOT\\broker_tail";
input string InpExportNames = "MB_GOLD_DUKA;MB_SILVER_DUKA;MB_US500_DUKA";
input string InpSymbolAliases = "GOLD;SILVER;US500";
input string InpBrokerSymbols = "GOLD.pro;SILVER.pro;US500.pro";
input int    InpHoursBack = 96;

bool SplitList(const string value,string &parts[])
  {
   ArrayResize(parts,0);
   string normalized = value;
   StringTrimLeft(normalized);
   StringTrimRight(normalized);
   if(StringLen(normalized) == 0)
      return(false);

   const int count = StringSplit(normalized,';',parts);
   if(count <= 0)
      return(false);

   for(int i=0; i<count; ++i)
     {
      StringTrimLeft(parts[i]);
      StringTrimRight(parts[i]);
     }

   return(true);
  }

datetime ResolveNow()
  {
   datetime server_time = TimeTradeServer();
   if(server_time > 0)
      return(server_time);
   return(TimeCurrent());
  }

bool WaitForSymbolSeries(const string broker_symbol,const ENUM_TIMEFRAMES timeframe)
  {
   SymbolSelect(broker_symbol,true);
   for(int attempt=0; attempt<20; ++attempt)
     {
      if((long)SeriesInfoInteger(broker_symbol,timeframe,SERIES_SYNCHRONIZED) != 0)
         return(true);
      Sleep(500);
     }
   return((long)SeriesInfoInteger(broker_symbol,timeframe,SERIES_SYNCHRONIZED) != 0);
  }

bool ExportOneSymbol(const string export_name,
                     const string symbol_alias,
                     const string broker_symbol,
                     const datetime from_time,
                     const datetime to_time,
                     int &rows_written)
  {
   rows_written = 0;
   if(!WaitForSymbolSeries(broker_symbol,PERIOD_M1))
     {
      PrintFormat("BROKER_TAIL_EXPORT_WARN symbol=%s reason=series_not_synchronized",broker_symbol);
      return(false);
     }

   MqlRates rates[];
   ArraySetAsSeries(rates,false);
   ResetLastError();
   const int copied = CopyRates(broker_symbol,PERIOD_M1,from_time,to_time,rates);
   if(copied <= 0)
     {
      PrintFormat("BROKER_TAIL_EXPORT_WARN symbol=%s reason=copy_rates_failed error=%d",broker_symbol,GetLastError());
      return(false);
     }

   const double point = SymbolInfoDouble(broker_symbol,SYMBOL_POINT);
   const int digits = (int)SymbolInfoInteger(broker_symbol,SYMBOL_DIGITS);
   const string relative_path = StringFormat("%s\\%s_BROKER_TAIL.csv",InpOutputRoot,export_name);
   const int handle = FileOpen(relative_path,FILE_WRITE|FILE_TXT|FILE_CSV|FILE_COMMON|FILE_ANSI,',');
   if(handle == INVALID_HANDLE)
     {
      PrintFormat("BROKER_TAIL_EXPORT_WARN symbol=%s reason=file_open_failed error=%d path=%s",broker_symbol,GetLastError(),relative_path);
      return(false);
     }

   FileWrite(handle,
             "export_name",
             "symbol_alias",
             "broker_symbol",
             "bar_minute",
             "tick_count",
             "bid_open",
             "bid_high",
             "bid_low",
             "bid_close",
             "ask_open",
             "ask_high",
             "ask_low",
             "ask_close",
             "mid_open",
             "mid_high",
             "mid_low",
             "mid_close",
             "spread_mean",
             "spread_max",
             "mid_range_1m",
             "mid_return_1m",
             "source_kind");

   for(int i=0; i<copied; ++i)
     {
      const MqlRates rate = rates[i];
      if(rate.time < from_time || rate.time > to_time)
         continue;

      const double spread_value = (double)rate.spread * point;
      const double bid_open = rate.open;
      const double bid_high = rate.high;
      const double bid_low = rate.low;
      const double bid_close = rate.close;
      const double ask_open = bid_open + spread_value;
      const double ask_high = bid_high + spread_value;
      const double ask_low = bid_low + spread_value;
      const double ask_close = bid_close + spread_value;
      const double mid_open = (bid_open + ask_open) / 2.0;
      const double mid_high = (bid_high + ask_high) / 2.0;
      const double mid_low = (bid_low + ask_low) / 2.0;
      const double mid_close = (bid_close + ask_close) / 2.0;
      const double mid_range = mid_high - mid_low;
      const double mid_return = (MathAbs(mid_open) > 0.0 ? (mid_close - mid_open) / mid_open : 0.0);

      FileWrite(handle,
                export_name,
                symbol_alias,
                broker_symbol,
                TimeToString(rate.time,TIME_DATE|TIME_MINUTES),
                (long)rate.tick_volume,
                DoubleToString(bid_open,digits),
                DoubleToString(bid_high,digits),
                DoubleToString(bid_low,digits),
                DoubleToString(bid_close,digits),
                DoubleToString(ask_open,digits),
                DoubleToString(ask_high,digits),
                DoubleToString(ask_low,digits),
                DoubleToString(ask_close,digits),
                DoubleToString(mid_open,digits),
                DoubleToString(mid_high,digits),
                DoubleToString(mid_low,digits),
                DoubleToString(mid_close,digits),
                DoubleToString(spread_value,digits),
                DoubleToString(spread_value,digits),
                DoubleToString(mid_range,digits),
                DoubleToString(mid_return,8),
                "broker_tail");
      rows_written++;
     }

   FileClose(handle);
   PrintFormat("BROKER_TAIL_EXPORT_OK export=%s alias=%s broker=%s rows=%d from=%s to=%s path=%s",
               export_name,
               symbol_alias,
               broker_symbol,
               rows_written,
               TimeToString(from_time,TIME_DATE|TIME_MINUTES),
               TimeToString(to_time,TIME_DATE|TIME_MINUTES),
               relative_path);
   return(rows_written > 0);
  }

void OnStart()
  {
   string export_names[];
   string aliases[];
   string broker_symbols[];
   if(!SplitList(InpExportNames,export_names) || !SplitList(InpSymbolAliases,aliases) || !SplitList(InpBrokerSymbols,broker_symbols))
     {
      Print("BROKER_TAIL_EXPORT_FATAL reason=invalid_lists");
      return;
     }

   const int symbol_count = ArraySize(export_names);
   if(symbol_count <= 0 || ArraySize(aliases) != symbol_count || ArraySize(broker_symbols) != symbol_count)
     {
      PrintFormat("BROKER_TAIL_EXPORT_FATAL reason=list_length_mismatch exports=%d aliases=%d brokers=%d",
                  symbol_count,
                  ArraySize(aliases),
                  ArraySize(broker_symbols));
      return;
     }

   const datetime to_time = ResolveNow();
   const int hours_back = MathMax(InpHoursBack,1);
   const datetime from_time = to_time - (hours_back * 60 * 60);

   int total_files = 0;
   int total_rows = 0;
   for(int i=0; i<symbol_count; ++i)
     {
      int rows = 0;
      if(ExportOneSymbol(export_names[i],aliases[i],broker_symbols[i],from_time,to_time,rows))
        {
         total_files++;
         total_rows += rows;
        }
     }

   PrintFormat("BROKER_TAIL_EXPORT_SUMMARY files=%d rows=%d from=%s to=%s",
               total_files,
               total_rows,
               TimeToString(from_time,TIME_DATE|TIME_MINUTES),
               TimeToString(to_time,TIME_DATE|TIME_MINUTES));
  }
