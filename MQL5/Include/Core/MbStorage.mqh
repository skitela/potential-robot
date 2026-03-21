#ifndef MB_STORAGE_INCLUDED
#define MB_STORAGE_INCLUDED

#include "MbRuntimeTypes.mqh"
#include "MbStoragePaths.mqh"
#include "MbRuntimeKernel.mqh"

bool MbEnsureDir(const string relative_dir)
  {
   ResetLastError();
   if(FolderCreate(relative_dir, FILE_COMMON))
      return true;

   string probe_path = relative_dir + "\\.__dir_probe__";
   int h = FileOpen(probe_path, FILE_COMMON | FILE_WRITE | FILE_BIN);
   if(h == INVALID_HANDLE)
      return false;
   FileClose(h);
   FileDelete(probe_path, FILE_COMMON);
   return true;
  }

string MbStateFilePath(const string symbol,const string file_name)
  {
   return MbSymbolStateDir(MbCanonicalSymbol(symbol)) + "\\" + file_name;
  }

string MbKeyFilePath(const string symbol,const string file_name)
  {
   return MbRootPath() + "\\key\\" + MbCanonicalSymbol(symbol) + "\\" + file_name;
  }

string MbLogFilePath(const string symbol,const string file_name)
  {
   return MbSymbolLogDir(MbCanonicalSymbol(symbol)) + "\\" + file_name;
  }

string MbRunFilePath(const string symbol,const string file_name)
  {
   return MbSymbolRunDir(MbCanonicalSymbol(symbol)) + "\\" + file_name;
  }

bool MbStorageInit(const string symbol)
  {
   string canonical_symbol = MbCanonicalSymbol(symbol);
   bool ok = true;
   ok = MbEnsureDir(MbRootPath()) && ok;
   ok = MbEnsureDir(MbRootPath() + "\\state") && ok;
   ok = MbEnsureDir(MbGlobalStateDir()) && ok;
   ok = MbEnsureDir(MbRootPath() + "\\state\\_domains") && ok;
   ok = MbEnsureDir(MbRootPath() + "\\logs") && ok;
   ok = MbEnsureDir(MbRootPath() + "\\run") && ok;
   ok = MbEnsureDir(MbRootPath() + "\\key") && ok;
   ok = MbEnsureDir(MbSymbolStateDir(canonical_symbol)) && ok;
   ok = MbEnsureDir(MbSymbolLogDir(canonical_symbol)) && ok;
   ok = MbEnsureDir(MbSymbolRunDir(canonical_symbol)) && ok;
   ok = MbEnsureDir(MbRootPath() + "\\key\\" + canonical_symbol) && ok;
   return ok;
  }

bool MbSaveRuntimeState(MbRuntimeState &state)
  {
   int h = FileOpen(MbStateFilePath(state.symbol,"runtime_state.csv"), FILE_COMMON | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;
   FileWrite(h,"symbol",state.symbol);
   FileWrite(h,"magic",(long)state.magic);
   FileWrite(h,"started_at",(long)state.started_at);
   FileWrite(h,"last_tick_at",(long)state.last_tick_at);
   FileWrite(h,"last_timer_at",(long)state.last_timer_at);
   FileWrite(h,"last_heartbeat_at",(long)state.last_heartbeat_at);
   FileWrite(h,"last_trade_attempt",(long)state.last_trade_attempt);
   FileWrite(h,"last_kill_switch_check",(long)state.last_kill_switch_check);
   FileWrite(h,"last_core_contract_check",(long)state.last_core_contract_check);
   FileWrite(h,"last_closed_deal_ticket",(long)state.last_closed_deal_ticket);
   FileWrite(h,"cooldown_until",(long)state.cooldown_until);
   FileWrite(h,"day_anchor",(long)state.day_anchor);
   FileWrite(h,"session_anchor",(long)state.session_anchor);
   FileWrite(h,"ticks_seen",state.ticks_seen);
   FileWrite(h,"timer_cycles",state.timer_cycles);
   FileWrite(h,"price_requests_sec",state.price_requests_sec);
   FileWrite(h,"price_requests_min",state.price_requests_min);
   FileWrite(h,"order_requests_sec",state.order_requests_sec);
   FileWrite(h,"order_requests_min",state.order_requests_min);
   FileWrite(h,"loss_streak",state.loss_streak);
   FileWrite(h,"exec_error_streak",state.exec_error_streak);
   FileWrite(h,"spread_anomaly_streak",state.spread_anomaly_streak);
   FileWrite(h,"learning_sample_count",state.learning_sample_count);
   FileWrite(h,"learning_win_count",state.learning_win_count);
   FileWrite(h,"learning_loss_count",state.learning_loss_count);
   FileWrite(h,"realized_pnl_lifetime",DoubleToString(state.realized_pnl_lifetime,2));
   FileWrite(h,"realized_pnl_day",DoubleToString(state.realized_pnl_day,2));
   FileWrite(h,"realized_pnl_session",DoubleToString(state.realized_pnl_session,2));
   FileWrite(h,"capital_core_anchor",DoubleToString(state.capital_core_anchor,2));
   FileWrite(h,"equity_anchor_day",DoubleToString(state.equity_anchor_day,2));
   FileWrite(h,"equity_anchor_session",DoubleToString(state.equity_anchor_session,2));
   FileWrite(h,"effective_profit_buffer",DoubleToString(state.effective_profit_buffer,2));
   FileWrite(h,"effective_risk_base",DoubleToString(state.effective_risk_base,2));
   FileWrite(h,"effective_loss_allowance_multiplier",DoubleToString(state.effective_loss_allowance_multiplier,4));
   FileWrite(h,"coordinator_risk_cap",DoubleToString(state.coordinator_risk_cap,4));
   FileWrite(h,"execution_pressure",DoubleToString(state.execution_pressure,6));
   FileWrite(h,"learning_bias",DoubleToString(state.learning_bias,6));
   FileWrite(h,"learning_confidence",DoubleToString(state.learning_confidence,6));
   FileWrite(h,"adaptive_risk_scale",DoubleToString(state.adaptive_risk_scale,6));
   FileWrite(h,"signal_confidence",DoubleToString(state.signal_confidence,6));
   FileWrite(h,"signal_risk_multiplier",DoubleToString(state.signal_risk_multiplier,6));
   FileWrite(h,"candle_score",DoubleToString(state.candle_score,6));
   FileWrite(h,"renko_score",DoubleToString(state.renko_score,6));
   FileWrite(h,"renko_run_length",state.renko_run_length);
   FileWrite(h,"renko_reversal_flag",(state.renko_reversal_flag ? 1 : 0));
   FileWrite(h,"paper_mode_active",(state.paper_mode_active ? 1 : 0));
   FileWrite(h,"trade_rights",(state.trade_rights ? 1 : 0));
   FileWrite(h,"paper_rights",(state.paper_rights ? 1 : 0));
   FileWrite(h,"observation_rights",(state.observation_rights ? 1 : 0));
   FileWrite(h,"kill_switch_cached_halt",(state.kill_switch_cached_halt ? 1 : 0));
   FileWrite(h,"kill_switch_cached_present",(state.kill_switch_cached_present ? 1 : 0));
   FileWrite(h,"capital_core_contract_present",(state.capital_core_contract_present ? 1 : 0));
   FileWrite(h,"capital_core_contract_enabled",(state.capital_core_contract_enabled ? 1 : 0));
   FileWrite(h,"caution_mode",(state.caution_mode ? 1 : 0));
   FileWrite(h,"close_only",(state.close_only ? 1 : 0));
   FileWrite(h,"force_flatten",(state.force_flatten ? 1 : 0));
   FileWrite(h,"halt",(state.halt ? 1 : 0));
    FileWrite(h,"market_regime",state.market_regime);
    FileWrite(h,"spread_regime",state.spread_regime);
    FileWrite(h,"execution_regime",state.execution_regime);
    FileWrite(h,"confidence_bucket",state.confidence_bucket);
    FileWrite(h,"last_setup_type",state.last_setup_type);
    FileWrite(h,"candle_bias",state.candle_bias);
    FileWrite(h,"candle_quality_grade",state.candle_quality_grade);
    FileWrite(h,"renko_bias",state.renko_bias);
    FileWrite(h,"renko_quality_grade",state.renko_quality_grade);
   FileWrite(h,"mode",(int)state.mode);
   FileClose(h);
   state.last_state_save_at = TimeCurrent();
   return true;
  }

bool MbLoadRuntimeState(MbRuntimeState &state)
  {
   int h = FileOpen(MbStateFilePath(state.symbol,"runtime_state.csv"), FILE_COMMON | FILE_READ | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;
   while(!FileIsEnding(h))
     {
      string key = FileReadString(h);
      string value = FileReadString(h);
      if(key == "symbol") state.symbol = value;
      else if(key == "magic") state.magic = (ulong)StringToInteger(value);
      else if(key == "started_at") state.started_at = (datetime)StringToInteger(value);
      else if(key == "last_tick_at") state.last_tick_at = (datetime)StringToInteger(value);
      else if(key == "last_timer_at") state.last_timer_at = (datetime)StringToInteger(value);
      else if(key == "last_heartbeat_at") state.last_heartbeat_at = (datetime)StringToInteger(value);
      else if(key == "last_trade_attempt") state.last_trade_attempt = (datetime)StringToInteger(value);
      else if(key == "last_kill_switch_check") state.last_kill_switch_check = (datetime)StringToInteger(value);
      else if(key == "last_core_contract_check") state.last_core_contract_check = (datetime)StringToInteger(value);
      else if(key == "last_closed_deal_ticket") state.last_closed_deal_ticket = (ulong)StringToInteger(value);
      else if(key == "cooldown_until") state.cooldown_until = (datetime)StringToInteger(value);
      else if(key == "day_anchor") state.day_anchor = (datetime)StringToInteger(value);
      else if(key == "session_anchor") state.session_anchor = (datetime)StringToInteger(value);
      else if(key == "ticks_seen") state.ticks_seen = (long)StringToInteger(value);
      else if(key == "timer_cycles") state.timer_cycles = (long)StringToInteger(value);
      else if(key == "price_requests_sec") state.price_requests_sec = (int)StringToInteger(value);
      else if(key == "price_requests_min") state.price_requests_min = (int)StringToInteger(value);
      else if(key == "order_requests_sec") state.order_requests_sec = (int)StringToInteger(value);
      else if(key == "order_requests_min") state.order_requests_min = (int)StringToInteger(value);
      else if(key == "loss_streak") state.loss_streak = (int)StringToInteger(value);
      else if(key == "exec_error_streak") state.exec_error_streak = (int)StringToInteger(value);
      else if(key == "spread_anomaly_streak") state.spread_anomaly_streak = (int)StringToInteger(value);
      else if(key == "learning_sample_count") state.learning_sample_count = (int)StringToInteger(value);
      else if(key == "learning_win_count") state.learning_win_count = (int)StringToInteger(value);
      else if(key == "learning_loss_count") state.learning_loss_count = (int)StringToInteger(value);
      else if(key == "realized_pnl_lifetime") state.realized_pnl_lifetime = StringToDouble(value);
      else if(key == "realized_pnl_day") state.realized_pnl_day = StringToDouble(value);
      else if(key == "realized_pnl_session") state.realized_pnl_session = StringToDouble(value);
      else if(key == "capital_core_anchor") state.capital_core_anchor = StringToDouble(value);
      else if(key == "equity_anchor_day") state.equity_anchor_day = StringToDouble(value);
      else if(key == "equity_anchor_session") state.equity_anchor_session = StringToDouble(value);
      else if(key == "effective_profit_buffer") state.effective_profit_buffer = StringToDouble(value);
      else if(key == "effective_risk_base") state.effective_risk_base = StringToDouble(value);
      else if(key == "effective_loss_allowance_multiplier") state.effective_loss_allowance_multiplier = StringToDouble(value);
      else if(key == "coordinator_risk_cap") state.coordinator_risk_cap = StringToDouble(value);
      else if(key == "execution_pressure") state.execution_pressure = StringToDouble(value);
      else if(key == "learning_bias") state.learning_bias = StringToDouble(value);
      else if(key == "learning_confidence") state.learning_confidence = StringToDouble(value);
      else if(key == "adaptive_risk_scale") state.adaptive_risk_scale = StringToDouble(value);
      else if(key == "signal_confidence") state.signal_confidence = StringToDouble(value);
      else if(key == "signal_risk_multiplier") state.signal_risk_multiplier = StringToDouble(value);
      else if(key == "candle_score") state.candle_score = StringToDouble(value);
      else if(key == "renko_score") state.renko_score = StringToDouble(value);
      else if(key == "renko_run_length") state.renko_run_length = (int)StringToInteger(value);
      else if(key == "renko_reversal_flag") state.renko_reversal_flag = (StringToInteger(value) != 0);
      else if(key == "paper_mode_active") state.paper_mode_active = (StringToInteger(value) != 0);
      else if(key == "trade_rights") state.trade_rights = (StringToInteger(value) != 0);
      else if(key == "paper_rights") state.paper_rights = (StringToInteger(value) != 0);
      else if(key == "observation_rights") state.observation_rights = (StringToInteger(value) != 0);
      else if(key == "kill_switch_cached_halt") state.kill_switch_cached_halt = (StringToInteger(value) != 0);
      else if(key == "kill_switch_cached_present") state.kill_switch_cached_present = (StringToInteger(value) != 0);
      else if(key == "capital_core_contract_present") state.capital_core_contract_present = (StringToInteger(value) != 0);
      else if(key == "capital_core_contract_enabled") state.capital_core_contract_enabled = (StringToInteger(value) != 0);
      else if(key == "caution_mode") state.caution_mode = (StringToInteger(value) != 0);
      else if(key == "close_only") state.close_only = (StringToInteger(value) != 0);
      else if(key == "force_flatten") state.force_flatten = (StringToInteger(value) != 0);
      else if(key == "halt") state.halt = (StringToInteger(value) != 0);
      else if(key == "market_regime") state.market_regime = value;
      else if(key == "spread_regime") state.spread_regime = value;
      else if(key == "execution_regime") state.execution_regime = value;
      else if(key == "confidence_bucket") state.confidence_bucket = value;
      else if(key == "last_setup_type") state.last_setup_type = value;
      else if(key == "candle_bias") state.candle_bias = value;
      else if(key == "candle_quality_grade") state.candle_quality_grade = value;
      else if(key == "renko_bias") state.renko_bias = value;
      else if(key == "renko_quality_grade") state.renko_quality_grade = value;
      else if(key == "mode") state.mode = (MbRuntimeMode)StringToInteger(value);
     }
   FileClose(h);
   return true;
  }

#endif
