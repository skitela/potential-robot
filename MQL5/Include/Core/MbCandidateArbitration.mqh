#ifndef MB_CANDIDATE_ARBITRATION_INCLUDED
#define MB_CANDIDATE_ARBITRATION_INCLUDED

#include "MbStorage.mqh"
#include "MbPaperTrading.mqh"
#include "MbCapitalRiskContract.mqh"
#include "MbGlobalTeacherLearningDiagnostic.mqh"

struct MbCandidateArbitrationSnapshot
  {
   datetime ts;
   string symbol;
   string arbitration_group;
   bool valid;
   bool paper_mode_active;
   string reason_code;
   string setup_type;
   MbSignalSide side;
   double score;
   double confidence_score;
   double risk_multiplier;
   double lots;
   double planned_risk_money;
   double spread_points;
   string market_regime;
   string spread_regime;
   string execution_regime;
   string confidence_bucket;
   double priority;
  };

struct MbCandidateArbitrationVerdict
  {
   bool entry_allowed;
   bool selected;
   bool near_tie;
   int candidate_count;
   string arbitration_group;
   string selected_symbol;
   string reason_code;
   double local_priority;
   double selected_priority;
   double runner_up_priority;
  };

double MbCandidateArbitrationGuardSentinel()
  {
   return 1.0e100;
  }

void MbCandidateArbitrationVerdictReset(MbCandidateArbitrationVerdict &out)
  {
   out.entry_allowed = true;
   out.selected = true;
   out.near_tie = false;
   out.candidate_count = 0;
   out.arbitration_group = "";
   out.selected_symbol = "";
   out.reason_code = "NONE";
   out.local_priority = 0.0;
   out.selected_priority = 0.0;
   out.runner_up_priority = 0.0;
  }

string MbResolveCandidateArbitrationGroup(const string session_profile)
  {
   if(session_profile == "METALS_SPOT_PM" || session_profile == "METALS_FUTURES")
      return "METALS";
   return session_profile;
  }

string MbCandidateArbitrationSymbolKey(const string symbol)
  {
   string key = MbCanonicalSymbol(symbol);
   int qdm_pos = StringFind(key,"_QDM_");
   if(qdm_pos > 0)
      key = StringSubstr(key,0,qdm_pos);
   return key;
  }

int MbGetCandidateArbitrationSymbols(const string arbitration_group,string &out[])
  {
   ArrayResize(out,0);

   if(arbitration_group == "FX_MAIN")
     {
      ArrayResize(out,4);
      out[0] = "EURUSD";
      out[1] = "GBPUSD";
      out[2] = "USDCAD";
      out[3] = "USDCHF";
      return 4;
     }
   if(arbitration_group == "FX_ASIA")
     {
      ArrayResize(out,2);
      out[0] = "USDJPY";
      out[1] = "AUDUSD";
      return 2;
     }
   if(arbitration_group == "FX_CROSS")
     {
      ArrayResize(out,2);
      out[0] = "EURJPY";
      out[1] = "EURAUD";
      return 2;
     }
   if(arbitration_group == "METALS")
     {
      ArrayResize(out,3);
      out[0] = "GOLD.pro";
      out[1] = "SILVER.pro";
      out[2] = "COPPER-US.pro";
      return 3;
     }
   if(arbitration_group == "INDEX_EU")
     {
      ArrayResize(out,1);
      out[0] = "DE30.pro";
      return 1;
     }
   if(arbitration_group == "INDEX_US")
     {
      ArrayResize(out,1);
      out[0] = "US500.pro";
      return 1;
     }

  return 0;
  }

int MbGetCandidateArbitrationFleetSymbols(string &out[])
  {
   ArrayResize(out,13);
   out[0] = "EURUSD";
   out[1] = "GBPUSD";
   out[2] = "USDCAD";
   out[3] = "USDCHF";
   out[4] = "USDJPY";
   out[5] = "AUDUSD";
   out[6] = "EURJPY";
   out[7] = "EURAUD";
   out[8] = "GOLD.pro";
   out[9] = "SILVER.pro";
   out[10] = "COPPER-US.pro";
   out[11] = "DE30.pro";
   out[12] = "US500.pro";
   return 13;
  }

bool MbIsCandidateArbitrationTrackedMagic(const ulong magic)
  {
   return (
      magic == 910101UL ||
      magic == 910102UL ||
      magic == 910103UL ||
      magic == 910104UL ||
      magic == 910105UL ||
      magic == 910106UL ||
      magic == 910107UL ||
      magic == 910108UL ||
      magic == 910109UL ||
      magic == 910110UL ||
      magic == 920201UL ||
      magic == 920202UL ||
      magic == 930301UL ||
      magic == 930302UL
   );
  }

string MbCandidateArbitrationGroupStateDir(const string arbitration_group)
  {
   return MbRootPath() + "\\state\\_groups\\" + arbitration_group;
  }

string MbCandidateArbitrationSnapshotPath(const string arbitration_group,const string symbol)
  {
   return MbCandidateArbitrationGroupStateDir(arbitration_group) + "\\candidate_" + MbCandidateArbitrationSymbolKey(symbol) + ".csv";
  }

string MbCandidateArbitrationStatePath(const string arbitration_group)
  {
   return MbCandidateArbitrationGroupStateDir(arbitration_group) + "\\candidate_arbiter_state.csv";
  }

bool MbEnsureCandidateArbitrationStorage(const string arbitration_group)
  {
   bool ok = true;
   ok = MbEnsureDir(MbRootPath() + "\\state\\_groups") && ok;
   ok = MbEnsureDir(MbCandidateArbitrationGroupStateDir(arbitration_group)) && ok;
   return ok;
  }

double MbEstimateCandidateRiskMoney(const MbMarketSnapshot &market,const double lots,const double sl_points)
  {
   if(lots <= 0.0 || sl_points <= 0.0)
      return 0.0;
   if(market.tick_size <= 0.0 || market.tick_value <= 0.0 || _Point <= 0.0)
      return 0.0;

   double price_distance = sl_points * _Point;
   return (price_distance / market.tick_size) * market.tick_value * lots;
  }

double MbEstimateCandidateRiskMoneyForSymbol(
   const string symbol,
   const double lots,
   const double open_price,
   const double sl_price
)
  {
   if(lots <= 0.0 || open_price <= 0.0 || sl_price <= 0.0)
      return 0.0;

   double tick_size = 0.0;
   double tick_value = 0.0;
   if(!SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE,tick_size))
      return 0.0;
   if(!SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE,tick_value))
      return 0.0;
   if(tick_size <= 0.0 || tick_value <= 0.0)
      return 0.0;

   double price_distance = MathAbs(open_price - sl_price);
   return (price_distance / tick_size) * tick_value * lots;
  }

double MbCandidateArbitrationLiveOpenRiskMoney()
  {
   double total_money = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      ulong magic = (ulong)PositionGetInteger(POSITION_MAGIC);
      if(!MbIsCandidateArbitrationTrackedMagic(magic))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      double lots = PositionGetDouble(POSITION_VOLUME);
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl_price = PositionGetDouble(POSITION_SL);

      if(lots <= 0.0 || open_price <= 0.0 || sl_price <= 0.0)
         return MbCandidateArbitrationGuardSentinel();

      total_money += MbEstimateCandidateRiskMoneyForSymbol(symbol,lots,open_price,sl_price);
     }

   return total_money;
  }

double MbCandidateArbitrationPaperOpenRiskMoney()
  {
   string symbols[];
   int count = MbGetCandidateArbitrationFleetSymbols(symbols);
   double total_money = 0.0;

   for(int i = 0; i < count; ++i)
     {
      MbPaperPositionState paper_state;
      if(!MbLoadPaperPosition(symbols[i],paper_state))
         continue;
      if(!paper_state.active)
         continue;
      if(paper_state.lots <= 0.0 || paper_state.entry_price <= 0.0 || paper_state.sl_price <= 0.0)
         return MbCandidateArbitrationGuardSentinel();

      total_money += MbEstimateCandidateRiskMoneyForSymbol(
         symbols[i],
         paper_state.lots,
         paper_state.entry_price,
         paper_state.sl_price
      );
     }

   return total_money;
  }

double MbCandidateArbitrationOpenRiskMoney(const bool paper_mode_active)
  {
   if(paper_mode_active)
      return MbCandidateArbitrationPaperOpenRiskMoney();
   return MbCandidateArbitrationLiveOpenRiskMoney();
  }

double MbCandidateSpreadFactor(const string spread_regime)
  {
   if(spread_regime == "TIGHT")
      return 1.05;
   if(spread_regime == "WIDE")
      return 0.82;
   if(spread_regime == "EXTREME" || spread_regime == "BLOCKED")
      return 0.60;
   return 1.00;
  }

double MbCandidateExecutionFactor(const string execution_regime)
  {
   if(execution_regime == "CLEAN")
      return 1.04;
   if(execution_regime == "DEGRADED" || execution_regime == "STRESSED")
      return 0.82;
   return 1.00;
  }

double MbCandidateConfidenceFactor(const string confidence_bucket,const double confidence_score)
  {
   double factor = 0.75 + (MathMax(0.0,MathMin(1.0,confidence_score)) * 0.50);
   if(confidence_bucket == "HIGH")
      factor *= 1.08;
   else if(confidence_bucket == "LOW")
      factor *= 0.92;
   return factor;
  }

double MbComputeCandidatePriority(const MbCandidateArbitrationSnapshot &snapshot)
  {
   double priority = MathAbs(snapshot.score);
   priority *= MbCandidateConfidenceFactor(snapshot.confidence_bucket,snapshot.confidence_score);
   priority *= MbCandidateSpreadFactor(snapshot.spread_regime);
   priority *= MbCandidateExecutionFactor(snapshot.execution_regime);

   if(snapshot.risk_multiplier > 1.10)
      priority *= 0.98;
   else if(snapshot.risk_multiplier < 0.75)
      priority *= 0.96;

   if(snapshot.planned_risk_money > 0.0)
      priority *= 1.0 / (1.0 + MathMin(0.25,snapshot.planned_risk_money / 1000.0));

   return MathMax(0.0,priority);
  }

bool MbSaveCandidateArbitrationSnapshot(const string arbitration_group,const MbCandidateArbitrationSnapshot &snapshot)
  {
   if(StringLen(arbitration_group) <= 0 || !MbEnsureCandidateArbitrationStorage(arbitration_group))
      return false;

   int h = FileOpen(MbCandidateArbitrationSnapshotPath(arbitration_group,snapshot.symbol),FILE_COMMON | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;

   FileWrite(h,"ts",(long)snapshot.ts);
   FileWrite(h,"symbol",MbCandidateArbitrationSymbolKey(snapshot.symbol));
   FileWrite(h,"arbitration_group",arbitration_group);
   FileWrite(h,"valid",(snapshot.valid ? 1 : 0));
   FileWrite(h,"paper_mode_active",(snapshot.paper_mode_active ? 1 : 0));
   FileWrite(h,"reason_code",snapshot.reason_code);
   FileWrite(h,"setup_type",snapshot.setup_type);
   FileWrite(h,"side",(int)snapshot.side);
   FileWrite(h,"score",DoubleToString(snapshot.score,6));
   FileWrite(h,"confidence_score",DoubleToString(snapshot.confidence_score,6));
   FileWrite(h,"risk_multiplier",DoubleToString(snapshot.risk_multiplier,6));
   FileWrite(h,"lots",DoubleToString(snapshot.lots,4));
   FileWrite(h,"planned_risk_money",DoubleToString(snapshot.planned_risk_money,4));
   FileWrite(h,"spread_points",DoubleToString(snapshot.spread_points,2));
   FileWrite(h,"market_regime",snapshot.market_regime);
   FileWrite(h,"spread_regime",snapshot.spread_regime);
   FileWrite(h,"execution_regime",snapshot.execution_regime);
   FileWrite(h,"confidence_bucket",snapshot.confidence_bucket);
   FileWrite(h,"priority",DoubleToString(snapshot.priority,6));
   FileClose(h);
   return true;
  }

bool MbLoadCandidateArbitrationSnapshot(const string arbitration_group,const string symbol,MbCandidateArbitrationSnapshot &out)
  {
   out.ts = 0;
   out.symbol = MbCandidateArbitrationSymbolKey(symbol);
   out.arbitration_group = arbitration_group;
   out.valid = false;
   out.paper_mode_active = false;
   out.reason_code = "";
   out.setup_type = "";
   out.side = MB_SIGNAL_NONE;
   out.score = 0.0;
   out.confidence_score = 0.0;
   out.risk_multiplier = 0.0;
   out.lots = 0.0;
   out.planned_risk_money = 0.0;
   out.spread_points = 0.0;
   out.market_regime = "";
   out.spread_regime = "";
   out.execution_regime = "";
   out.confidence_bucket = "";
   out.priority = 0.0;

   int h = FileOpen(MbCandidateArbitrationSnapshotPath(arbitration_group,symbol),FILE_COMMON | FILE_READ | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;

   while(!FileIsEnding(h))
     {
      string key = FileReadString(h);
      string value = FileReadString(h);
      if(key == "ts") out.ts = (datetime)StringToInteger(value);
      else if(key == "symbol") out.symbol = MbCandidateArbitrationSymbolKey(value);
      else if(key == "arbitration_group") out.arbitration_group = value;
      else if(key == "valid") out.valid = (StringToInteger(value) != 0);
      else if(key == "paper_mode_active") out.paper_mode_active = (StringToInteger(value) != 0);
      else if(key == "reason_code") out.reason_code = value;
      else if(key == "setup_type") out.setup_type = value;
      else if(key == "side") out.side = (MbSignalSide)StringToInteger(value);
      else if(key == "score") out.score = StringToDouble(value);
      else if(key == "confidence_score") out.confidence_score = StringToDouble(value);
      else if(key == "risk_multiplier") out.risk_multiplier = StringToDouble(value);
      else if(key == "lots") out.lots = StringToDouble(value);
      else if(key == "planned_risk_money") out.planned_risk_money = StringToDouble(value);
      else if(key == "spread_points") out.spread_points = StringToDouble(value);
      else if(key == "market_regime") out.market_regime = value;
      else if(key == "spread_regime") out.spread_regime = value;
      else if(key == "execution_regime") out.execution_regime = value;
      else if(key == "confidence_bucket") out.confidence_bucket = value;
      else if(key == "priority") out.priority = StringToDouble(value);
     }

   FileClose(h);
   return true;
  }

void MbClearCandidateArbitrationSnapshot(const string session_profile,const string symbol)
  {
   string arbitration_group = MbResolveCandidateArbitrationGroup(session_profile);
   if(StringLen(arbitration_group) <= 0)
      return;
   FileDelete(MbCandidateArbitrationSnapshotPath(arbitration_group,symbol),FILE_COMMON);
  }

string MbLoadCandidateArbitrationLastSelected(const string arbitration_group)
  {
   int h = FileOpen(MbCandidateArbitrationStatePath(arbitration_group),FILE_COMMON | FILE_READ | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return "";

   string selected_symbol = "";
   while(!FileIsEnding(h))
     {
      string key = FileReadString(h);
      string value = FileReadString(h);
      if(key == "selected_symbol")
        {
         selected_symbol = MbCandidateArbitrationSymbolKey(value);
         break;
        }
     }
   FileClose(h);
   return selected_symbol;
  }

bool MbSaveCandidateArbitrationState(
   const string arbitration_group,
   const datetime ts,
   const string selected_symbol,
   const string reason_code,
   const int candidate_count,
   const bool near_tie,
   const double selected_priority,
   const double runner_up_priority
)
  {
   if(StringLen(arbitration_group) <= 0 || !MbEnsureCandidateArbitrationStorage(arbitration_group))
      return false;

   int h = FileOpen(MbCandidateArbitrationStatePath(arbitration_group),FILE_COMMON | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;

   FileWrite(h,"ts",(long)ts);
   FileWrite(h,"selected_symbol",MbCandidateArbitrationSymbolKey(selected_symbol));
   FileWrite(h,"reason_code",reason_code);
   FileWrite(h,"candidate_count",candidate_count);
   FileWrite(h,"near_tie",(near_tie ? 1 : 0));
   FileWrite(h,"selected_priority",DoubleToString(selected_priority,6));
   FileWrite(h,"runner_up_priority",DoubleToString(runner_up_priority,6));
   FileClose(h);
   return true;
  }

void MbEvaluateCandidateArbitration(
   const string session_profile,
   const string symbol,
   const datetime now,
   const bool paper_mode_active,
   const MbMarketSnapshot &market,
   const MbRuntimeState &state,
   const MbSignalDecision &signal,
   const double lots,
   const double sl_points,
   MbCandidateArbitrationVerdict &out
)
  {
   MbCandidateArbitrationVerdictReset(out);

   string arbitration_group = MbResolveCandidateArbitrationGroup(session_profile);
   out.arbitration_group = arbitration_group;
   if(StringLen(arbitration_group) <= 0)
     {
      out.reason_code = "ARBITRATION_GROUP_UNKNOWN";
      return;
     }

   MbCandidateArbitrationSnapshot own;
   own.ts = now;
   own.symbol = MbCandidateArbitrationSymbolKey(symbol);
   own.arbitration_group = arbitration_group;
   own.valid = true;
   own.paper_mode_active = paper_mode_active;
   own.reason_code = signal.reason_code;
   own.setup_type = signal.setup_type;
   own.side = signal.side;
   own.score = signal.score;
   own.confidence_score = signal.confidence_score;
   own.risk_multiplier = signal.risk_multiplier;
   own.lots = lots;
   own.planned_risk_money = MbEstimateCandidateRiskMoney(market,lots,sl_points);
   own.spread_points = market.spread_points;
   own.market_regime = signal.market_regime;
   own.spread_regime = signal.spread_regime;
   own.execution_regime = signal.execution_regime;
   own.confidence_bucket = signal.confidence_bucket;
   own.priority = MbComputeCandidatePriority(own);
   out.local_priority = own.priority;

   MbSaveCandidateArbitrationSnapshot(arbitration_group,own);

   string symbols[];
   int symbol_count = MbGetCandidateArbitrationSymbols(arbitration_group,symbols);
   if(symbol_count <= 0)
     {
      out.reason_code = "ARBITRATION_SYMBOL_SET_EMPTY";
      return;
     }

   const int stale_sec = 15;
   string best_symbol = "";
   string second_symbol = "";
   double best_priority = -1.0;
   double second_priority = -1.0;
   int candidate_count = 0;

   for(int i = 0; i < symbol_count; ++i)
     {
      MbCandidateArbitrationSnapshot row;
      if(!MbLoadCandidateArbitrationSnapshot(arbitration_group,symbols[i],row))
         continue;
      if(!row.valid || row.ts <= 0)
         continue;
      if((now - row.ts) > stale_sec)
         continue;

      candidate_count++;

      if(row.priority > best_priority)
        {
         second_priority = best_priority;
         second_symbol = best_symbol;
         best_priority = row.priority;
         best_symbol = row.symbol;
        }
      else if(row.priority > second_priority)
        {
         second_priority = row.priority;
         second_symbol = row.symbol;
        }
     }

   out.candidate_count = candidate_count;
   out.selected_priority = MathMax(0.0,best_priority);
   out.runner_up_priority = MathMax(0.0,second_priority);

   if(candidate_count <= 0 || StringLen(best_symbol) <= 0)
     {
      if(paper_mode_active && MbHasStrategyTesterSandbox() && own.valid && own.priority > 0.0)
        {
         out.entry_allowed = true;
         out.selected = true;
         out.reason_code = "TESTER_ISOLATED_LOCAL_ONLY";
         out.candidate_count = 1;
         out.selected_symbol = own.symbol;
         out.selected_priority = own.priority;
         out.runner_up_priority = 0.0;
         MbSaveCandidateArbitrationState(arbitration_group,now,own.symbol,out.reason_code,1,false,own.priority,0.0);
         return;
        }

      out.entry_allowed = false;
      out.selected = false;
      out.reason_code = "NO_ACTIVE_CANDIDATES";
      MbSaveCandidateArbitrationState(arbitration_group,now,"",out.reason_code,candidate_count,false,0.0,0.0);
      return;
     }

   bool near_tie = false;
   bool true_tie = false;
   if(candidate_count >= 2 && best_priority > 0.0 && second_priority >= 0.0)
     {
      double gap_pct = (best_priority - second_priority) / best_priority;
      near_tie = (gap_pct <= 0.03);
      true_tie = (MathAbs(best_priority - second_priority) <= 0.000001);
     }
   out.near_tie = near_tie;

   string selected_symbol = best_symbol;
   string reason_code = "TOP_1_CLEAR";

   if(candidate_count == 1)
      reason_code = "ONLY_CANDIDATE";
   else if(near_tie)
     {
      if(true_tie)
        {
         if(paper_mode_active)
           {
            string last_selected = MbLoadCandidateArbitrationLastSelected(arbitration_group);
            if(MbCandidateArbitrationSymbolKey(last_selected) == MbCandidateArbitrationSymbolKey(best_symbol) && StringLen(second_symbol) > 0)
               selected_symbol = second_symbol;
            else
               selected_symbol = best_symbol;
            reason_code = "TRUE_TIE_ALTERNATE";
           }
         else
           {
            selected_symbol = "";
            reason_code = "TRUE_TIE_SKIP";
           }
        }
      else
        {
         reason_code = "NEAR_TIE_TOP_1";
        }
     }

   MbSaveCandidateArbitrationState(
      arbitration_group,
      now,
      selected_symbol,
      reason_code,
      candidate_count,
      near_tie,
      MathMax(0.0,best_priority),
      MathMax(0.0,second_priority)
   );

   out.selected_symbol = selected_symbol;
   out.reason_code = reason_code;

   if(StringLen(selected_symbol) <= 0)
     {
      out.entry_allowed = false;
      out.selected = false;
      return;
     }

   out.selected = (MbCandidateArbitrationSymbolKey(selected_symbol) == MbCandidateArbitrationSymbolKey(symbol));
   out.entry_allowed = out.selected;
   if(!out.selected)
     out.reason_code = "FAMILY_TOP1_LOST";

   if(!out.entry_allowed)
      return;

   MbCapitalRiskContract contract;
   MbResolveCapitalRiskContract(paper_mode_active,contract);

   double risk_base = MbCapitalRiskResolveRiskBase(paper_mode_active,contract,state,market);
   double max_open_risk_money = risk_base * (contract.max_open_risk_pct / 100.0);
   if(max_open_risk_money <= 0.0 || own.planned_risk_money <= 0.0)
      return;

   double open_risk_money = MbCandidateArbitrationOpenRiskMoney(paper_mode_active);
   if(open_risk_money >= MbCandidateArbitrationGuardSentinel())
     {
      out.entry_allowed = false;
      out.reason_code = "PORTFOLIO_HEAT_UNKNOWN";
      return;
     }

   if((open_risk_money + own.planned_risk_money) > (max_open_risk_money + 0.01))
     {
      if(MbShouldBypassGlobalTeacherLearningCandidateArbitration(symbol,paper_mode_active,"PORTFOLIO_HEAT_BLOCK",own.setup_type,own.score,own.execution_regime,own.spread_regime))
        {
         out.entry_allowed = true;
         out.reason_code = "GLOBAL_TEACHER_IGNORE_PORTFOLIO_HEAT";
         return;
        }

      out.entry_allowed = false;
      out.reason_code = "PORTFOLIO_HEAT_BLOCK";
      return;
     }
  }

#endif
