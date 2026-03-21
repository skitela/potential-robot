#ifndef MB_EXECUTION_COMMON_INCLUDED
#define MB_EXECUTION_COMMON_INCLUDED

#include "MbRuntimeTypes.mqh"

double MbClamp(const double value,const double lo,const double hi)
  {
   return MathMax(lo,MathMin(hi,value));
  }

string MbClassifyRetcode(const long retcode)
  {
   switch((int)retcode)
     {
      case 10004: return "TRADE_RETCODE_REQUOTE";
      case 10006: return "TRADE_RETCODE_REJECT";
      case 10008: return "TRADE_RETCODE_PLACED";
      case 10009: return "TRADE_RETCODE_DONE";
      case 10010: return "TRADE_RETCODE_DONE_PARTIAL";
      case 10014: return "TRADE_RETCODE_INVALID_VOLUME";
      case 10015: return "TRADE_RETCODE_INVALID_PRICE";
      case 10016: return "TRADE_RETCODE_INVALID_STOPS";
      case 10017: return "TRADE_RETCODE_TRADE_DISABLED";
      case 10018: return "TRADE_RETCODE_MARKET_CLOSED";
      case 10019: return "TRADE_RETCODE_NO_MONEY";
      case 10020: return "TRADE_RETCODE_PRICE_CHANGED";
      case 10021: return "TRADE_RETCODE_PRICE_OFF";
      case 10024: return "TRADE_RETCODE_TOO_MANY_REQUESTS";
      case 10028: return "TRADE_RETCODE_LOCKED";
      case 10031: return "TRADE_RETCODE_CONNECTION";
     }
   if(retcode <= 0)
      return "LOCAL_ERROR";
   return "TRADE_RETCODE_OTHER";
  }

string MbRetcodeClass(const long retcode)
  {
   switch((int)retcode)
     {
      case 10008:
      case 10009:
      case 10010:
         return "SUCCESS";
      case 10004:
      case 10020:
      case 10021:
      case 10028:
         return "RECOVERABLE";
      case 10016:
      case 10017:
      case 10018:
      case 10019:
      case 10024:
      case 10031:
         return "CRITICAL";
     }
   return "ERROR";
  }

bool MbShouldRetryRetcode(const long retcode)
  {
   return (retcode == 10004 || retcode == 10020 || retcode == 10021 || retcode == 10028);
  }

int MbRetryDelayMs(const long retcode)
  {
   switch((int)retcode)
     {
      case 10004: return 5;
      case 10020: return 5;
      case 10021: return 10;
      case 10028: return 15;
     }
   return 0;
  }

ENUM_ORDER_TYPE_FILLING MbResolveFilling(const string symbol)
  {
   long fill_mask = (long)SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);
   if((fill_mask & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;
   if((fill_mask & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
  }

string MbIncidentClassFromRetcode(const long retcode_num,const string retcode_name="")
  {
   string name = retcode_name;
   StringToUpper(name);
   int n = (int)retcode_num;
   if(n == 10008 || n == 10009 || n == 10010)
      return "ok";
   if(n == 10019 || StringFind(name,"NO_MONEY") >= 0)
      return "risk";
   if(n == 10017 || n == 10026 || n == 10027 || n == 10042 || n == 10043 || n == 10044 || n == 10045 || n == 10046)
      return "broker_policy";
   if(n == 10012 || n == 10031 || n == 10011)
      return "system";
   if(n <= 0)
      return "system";
   return "execution";
  }

string MbIncidentSeverityFromRetcode(const long retcode_num,const string retcode_name="")
  {
   string name = retcode_name;
   StringToUpper(name);
   int n = (int)retcode_num;
   if(n == 10008 || n == 10009 || n == 10010)
      return "INFO";
   if(n == 10019 || StringFind(name,"NO_MONEY") >= 0)
      return "CRITICAL";
   if(n == 10012 || n == 10031 || n == 10011 || n == 10017 || n == 10026 || n == 10027 || n == 10028 || n == 10029)
      return "ERROR";
   if(n <= 0)
      return "ERROR";
  return "WARN";
  }

double MbResolvePaperRiskLotsFloor(const MbMarketSnapshot &snapshot)
  {
   return MathMax(snapshot.vol_min,snapshot.vol_step);
  }

bool MbShouldBypassRiskMarginGuardInPaper(
   const bool paper_mode_active,
   const MbSignalDecision &signal,
   const bool risk_allowed,
   const string reason_code
)
  {
   return (paper_mode_active && signal.valid && !risk_allowed && reason_code == "MARGIN_GUARD");
  }

void MbApplyPaperRiskMarginGuardBypass(
   const bool paper_mode_active,
   const MbSignalDecision &signal,
   const MbMarketSnapshot &snapshot,
   bool &risk_allowed,
   string &reason_code,
   double &lots
)
  {
   if(!MbShouldBypassRiskMarginGuardInPaper(paper_mode_active,signal,risk_allowed,reason_code))
      return;

   risk_allowed = true;
   reason_code = "PAPER_IGNORE_MARGIN_GUARD";
   lots = MbResolvePaperRiskLotsFloor(snapshot);
  }

bool MbShouldBypassMinLotBlockInPaper(
   const bool paper_mode_active,
   const MbSignalDecision &signal,
   const bool risk_allowed,
   const double lots
)
  {
   return (paper_mode_active && signal.valid && !risk_allowed && lots <= 0.0);
  }

void MbApplyPaperMinLotBlockBypass(
   const bool paper_mode_active,
   const MbSignalDecision &signal,
   const MbMarketSnapshot &snapshot,
   bool &risk_allowed,
   string &reason_code,
   double &lots
)
  {
   if(!MbShouldBypassMinLotBlockInPaper(paper_mode_active,signal,risk_allowed,lots))
      return;

   risk_allowed = true;
   reason_code = "PAPER_IGNORE_MIN_LOT_BLOCK";
   lots = MbResolvePaperRiskLotsFloor(snapshot);
  }

bool MbShouldApplyPaperMinLotFloor(
   const bool paper_mode_active,
   const MbSignalDecision &signal,
   const bool risk_allowed,
   const double lots
)
  {
   return (paper_mode_active && signal.valid && risk_allowed && lots <= 0.0);
  }

void MbApplyPaperMinLotFloor(
   const bool paper_mode_active,
   const MbSignalDecision &signal,
   const MbMarketSnapshot &snapshot,
   const bool risk_allowed,
   string &reason_code,
   double &lots
)
  {
   if(!MbShouldApplyPaperMinLotFloor(paper_mode_active,signal,risk_allowed,lots))
      return;

   lots = MbResolvePaperRiskLotsFloor(snapshot);
   reason_code = "PAPER_IGNORE_MIN_LOT_FLOOR";
  }

void MbNormalizeRiskContractBlockAfterSizing(
   const MbSignalDecision &signal,
   bool &risk_allowed,
   string &reason_code,
   const double lots
)
  {
   if(!signal.valid || lots > 0.0)
      return;

   risk_allowed = false;
   reason_code = "RISK_CONTRACT_BLOCK";
  }

#endif
