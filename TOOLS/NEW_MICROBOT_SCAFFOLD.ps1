param(
    [Parameter(Mandatory = $true)]
    [string]$Symbol,
    [string]$ProjectRoot = "C:\\MAKRO_I_MIKRO_BOT",
    [UInt64]$MagicNumber = 900001,
    [switch]$ExpertOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-SymbolPascal {
    param([string]$Value)
    $upper = $Value.ToUpperInvariant()
    $parts = @()
    for ($i = 0; $i -lt $upper.Length; $i += 3) {
        $chunk = $upper.Substring($i,[Math]::Min(3,$upper.Length - $i)).ToLowerInvariant()
        if ($chunk.Length -gt 0) {
            $parts += ($chunk.Substring(0,1).ToUpperInvariant() + $chunk.Substring(1))
        }
    }
    return ($parts -join "")
}

$symbolUpper = $Symbol.ToUpperInvariant()
$symbolLower = $Symbol.ToLowerInvariant()
$symbolPascal = Get-SymbolPascal -Value $symbolUpper
$expertPath = Join-Path $ProjectRoot ("MQL5\\Experts\\MicroBots\\MicroBot_{0}.mq5" -f $symbolUpper)
$profilePath = Join-Path $ProjectRoot ("MQL5\\Include\\Profiles\\Profile_{0}.mqh" -f $symbolUpper)
$strategyPath = Join-Path $ProjectRoot ("MQL5\\Include\\Strategies\\Strategy_{0}.mqh" -f $symbolUpper)
$presetPath = Join-Path $ProjectRoot ("MQL5\\Presets\\MicroBot_{0}_Live.set" -f $symbolUpper)

if (Test-Path -LiteralPath $expertPath) {
    throw "Expert already exists: $expertPath"
}

$expertContent = @"
#property strict
#property version   "1.00"
#property description "MicroBot $symbolUpper scaffold."

#include <Trade/Trade.mqh>
#include "..\\..\\Include\\Core\\MbRuntimeTypes.mqh"
#include "..\\..\\Include\\Core\\MbRuntimeKernel.mqh"
#include "..\\..\\Include\\Core\\MbStorage.mqh"
#include "..\\..\\Include\\Core\\MbStatusPlane.mqh"
#include "..\\..\\Include\\Core\\MbRuntimeControl.mqh"
#include "..\\..\\Include\\Core\\MbKillSwitchGuard.mqh"
#include "..\\..\\Include\\Core\\MbRateGuard.mqh"
#include "..\\..\\Include\\Core\\MbMarketState.mqh"
#include "..\\..\\Include\\Core\\MbSessionGuard.mqh"
#include "..\\..\\Include\\Core\\MbMarketGuards.mqh"
#include "..\\..\\Include\\Core\\MbLatencyProfile.mqh"
#include "..\\..\\Include\\Core\\MbBrokerProfilePlane.mqh"
#include "..\\..\\Include\\Core\\MbExecutionSummaryPlane.mqh"
#include "..\\..\\Include\\Core\\MbInformationalPolicyPlane.mqh"
#include "..\\..\\Include\\Core\\MbExecutionPrecheck.mqh"
#include "..\\..\\Include\\Core\\MbExecutionSend.mqh"
#include "..\\..\\Include\\Core\\MbExecutionFeedback.mqh"
#include "..\\..\\Include\\Core\\MbExecutionQualityGuard.mqh"
#include "..\\..\\Include\\Core\\MbDecisionJournal.mqh"
#include "..\\..\\Include\\Core\\MbExecutionTelemetry.mqh"
#include "..\\..\\Include\\Core\\MbIncidentJournal.mqh"
#include "..\\..\\Include\\Core\\MbTradeTransactionJournal.mqh"
#include "..\\..\\Include\\Core\\MbClosedDealTracker.mqh"
#include "..\\..\\Include\\Core\\MbPaperTrading.mqh"
#include "..\\..\\Include\\Profiles\\Profile_$symbolUpper.mqh"
#include "..\\..\\Include\\Strategies\\Strategy_$symbolUpper.mqh"

input ulong InpMagic = $MagicNumber;
input uint InpTimerSec = 5;
input bool InpEnableLiveEntries = false;
input bool InpPaperCollectMode = true;
input string InpTradeComment = "MB_$symbolUpper";

CTrade g_trade;
MbRuntimeState g_state;
MbSymbolProfile g_profile;
MbRuntimeControlState g_runtime_control;
MbKillSwitchState g_kill_switch;
MbMarketSnapshot g_market;
MbLatencyProfile g_latency;
string g_decision_log_path = "";
string g_execution_telemetry_path = "";
string g_incident_log_path = "";
string g_latency_log_path = "";
string g_trade_transaction_log_path = "";
MbPaperPositionState g_paper_position;

bool IsLocalPaperModeActive()
  {
   return (InpPaperCollectMode || g_runtime_control.paper_only);
  }

int OnInit()
  {
   MbRuntimeReset(g_state);
   LoadProfile$symbolUpper(g_profile);
   if(!MbVerifyChartSymbol(g_profile.symbol))
      return(INIT_FAILED);
   g_profile.symbol = Symbol();
   g_state.magic = InpMagic;
   g_state.symbol = g_profile.symbol;
   g_state.mode = MB_MODE_READY;
   g_trade.SetExpertMagicNumber((ulong)InpMagic);
   g_trade.SetDeviationInPoints(g_profile.deviation_points);
   g_trade.SetTypeFillingBySymbol(g_profile.symbol);
   if(!MbStorageInit(g_profile.symbol))
      return(INIT_FAILED);
   if(!Strategy${symbolUpper}Init(g_profile))
      return(INIT_FAILED);

   MbLoadRuntimeState(g_state);
   if(!InpEnableLiveEntries || IsLocalPaperModeActive())
     {
      g_state.halt = false;
      g_state.close_only = false;
      g_state.caution_mode = false;
      g_state.mode = MB_MODE_READY;
     }
   MbReadRuntimeControl(g_profile.symbol,g_runtime_control);
   MbApplyRuntimeControl(g_state,g_runtime_control);
   MbKillSwitchEvaluate(g_profile,g_state,g_kill_switch);
   if(IsLocalPaperModeActive())
     {
      g_kill_switch.halt = false;
      g_kill_switch.reason_code = "PAPER_MODE_ACTIVE";
      g_state.halt = false;
      g_state.close_only = false;
      g_state.mode = MB_MODE_READY;
     }
   MbRefreshMarketSnapshot(g_profile,g_market);
   MbLatencyProfileInit(g_latency);
   g_decision_log_path = MbLogFilePath(g_profile.symbol,"decision_events.csv");
   g_execution_telemetry_path = MbLogFilePath(g_profile.symbol,"execution_telemetry.csv");
   g_incident_log_path = MbLogFilePath(g_profile.symbol,"incident_journal.jsonl");
   g_latency_log_path = MbLogFilePath(g_profile.symbol,"latency_profile.csv");
   g_trade_transaction_log_path = MbLogFilePath(g_profile.symbol,"trade_transactions.jsonl");
   MbDecisionJournalInit(g_decision_log_path);
   MbExecutionTelemetryInit(g_execution_telemetry_path);
   MbIncidentJournalInit(g_incident_log_path);
   MbTradeTransactionJournalInit(g_trade_transaction_log_path);
   MbPaperPositionReset(g_paper_position);
   MbLoadPaperPosition(g_profile.symbol,g_paper_position);
   if(g_kill_switch.halt)
      g_state.halt = true;

   EventSetTimer((int)MathMax(1,(int)InpTimerSec));
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   MbDecisionJournalFlush();
   MbExecutionTelemetryFlush();
   MbIncidentJournalFlush();
   MbTradeTransactionJournalFlush();
   MbLatencyProfileFlush(g_latency,g_latency_log_path);
   MbSavePaperPosition(g_profile.symbol,g_paper_position);
   Strategy${symbolUpper}Deinit();
   MbSaveRuntimeState(g_state);
  }

void OnTimer()
  {
   MbReadRuntimeControl(g_profile.symbol,g_runtime_control);
   MbApplyRuntimeControl(g_state,g_runtime_control);
   MbKillSwitchEvaluate(g_profile,g_state,g_kill_switch);
   if(IsLocalPaperModeActive())
     {
      g_kill_switch.halt = false;
      g_kill_switch.reason_code = "PAPER_MODE_ACTIVE";
      g_state.halt = false;
      g_state.close_only = false;
      g_state.mode = MB_MODE_READY;
     }
   MbRefreshMarketSnapshot(g_profile,g_market);
   if(g_kill_switch.halt)
      g_state.halt = true;
   MbRuntimeOnTimer(g_state);
   MbFlushHeartbeat(g_state);
   MbFlushRuntimeStatus(g_state,(g_kill_switch.halt ? g_kill_switch.reason_code : g_runtime_control.reason_code));
   MbFlushInformationalPolicy(g_profile,g_state,g_market,"BOOTSTRAP",(g_kill_switch.halt ? g_kill_switch.reason_code : g_runtime_control.reason_code));
   MbFlushBrokerProfile(g_profile,g_state,g_market);
   MbFlushExecutionSummary(g_profile,g_state,g_market,g_latency,(g_kill_switch.halt ? g_kill_switch.reason_code : g_runtime_control.reason_code));
   MbDecisionJournalFlush();
   MbExecutionTelemetryFlush();
   MbIncidentJournalFlush();
   MbTradeTransactionJournalFlush();
   MbLatencyProfileFlush(g_latency,g_latency_log_path);
   MbSavePaperPosition(g_profile.symbol,g_paper_position);
   MbSaveRuntimeState(g_state);
  }

void OnTick()
  {
   ulong tick_t0_us = GetMicrosecondCount();
   datetime now = TimeCurrent();
   MbMarkPriceProbe(g_state);
   MbRuntimeOnTick(g_state);
   if(IsLocalPaperModeActive())
     {
      g_state.halt = false;
      g_state.close_only = false;
      g_state.mode = MB_MODE_READY;
     }
   MbRefreshTickSnapshot(g_profile,g_market);
   if(IsLocalPaperModeActive())
     {
      double paper_pnl = 0.0;
      string paper_close_reason = "";
      if(MbPaperMaybeClosePosition(g_market,g_paper_position,now,paper_pnl,paper_close_reason))
        {
         MbProcessSyntheticClosedDealFeedback(g_state,paper_pnl,now);
         MbAppendDecisionEvent(
            g_decision_log_path,
            now,
            g_state.symbol,
            "PAPER_CLOSE",
            (paper_pnl >= 0.0 ? "OK" : "LOSS"),
            paper_close_reason,
            g_market.spread_points,
            0.0,
            paper_pnl,
            0
         );
         MbSavePaperPosition(g_profile.symbol,g_paper_position);
        }
     }
   Manage${symbolUpper}OpenPosition(g_trade,g_state,g_profile,g_market);
   MbRateGuardState rate_guard;
   MbRateGuardEvaluate(g_profile,g_state,rate_guard);
   if(rate_guard.halt)
     {
      g_state.halt = true;
      MbIncidentNoteGuard(g_incident_log_path,g_state.symbol,"rate_guard",rate_guard.reason_code,"ERROR","broker_policy");
      return;
     }
   if(rate_guard.caution_mode)
      g_state.caution_mode = true;

   string guard_reason = "OK";
   MbGuardVerdict market_guard = MbEvaluateMarketEntryGuards(g_profile,g_market,g_state,guard_reason);
   if(IsLocalPaperModeActive() && (guard_reason == "OUTSIDE_TRADE_WINDOW" || guard_reason == "MARGIN_FREE_LOW" || guard_reason == "SPREAD_CAP_EXCEEDED"))
     {
      MbAppendDecisionEvent(
         g_decision_log_path,
         now,
         g_state.symbol,
         "MARKET",
         "BYPASS",
         ("PAPER_IGNORE_" + guard_reason),
         g_market.spread_points,
         0.0,
         0.0,
         0
      );
      if(guard_reason == "MARGIN_FREE_LOW")
         g_state.halt = false;
      market_guard = MB_GUARD_OK;
      guard_reason = "OK";
     }
   if(market_guard != MB_GUARD_OK)
     {
      if(market_guard == MB_GUARD_HALT)
         g_state.halt = true;
      MbIncidentNoteGuard(
         g_incident_log_path,
         g_state.symbol,
         "market_guard",
         guard_reason,
         (market_guard == MB_GUARD_HALT ? "ERROR" : "WARN"),
         (market_guard == MB_GUARD_HALT ? "risk" : "guard")
      );
      MbAppendDecisionEvent(
         g_decision_log_path,
         now,
         g_state.symbol,
         "MARKET",
         "SKIP",
         guard_reason,
         g_market.spread_points,
         0.0,
         0.0,
         0
      );
      return;
     }

   MbGuardVerdict exec_quality_guard = MbEvaluateExecutionQualityGuard(g_profile,g_state,g_latency,guard_reason);
   if(exec_quality_guard != MB_GUARD_OK)
     {
      MbIncidentNoteGuard(
         g_incident_log_path,
         g_state.symbol,
         "execution_quality_guard",
         guard_reason,
         "WARN",
         "execution"
      );
      MbAppendDecisionEvent(
         g_decision_log_path,
         now,
         g_state.symbol,
         "EXEC_QUALITY",
         (exec_quality_guard == MB_GUARD_BLOCK ? "SKIP" : "CAUTION"),
         guard_reason,
         g_market.spread_points,
         0.0,
         0.0,
         0
      );
      if(exec_quality_guard == MB_GUARD_BLOCK)
         return;
     }

   MbSignalDecision signal;
   if(IsLocalPaperModeActive())
     {
      g_state.halt = false;
      g_state.close_only = false;
      g_state.mode = MB_MODE_READY;
     }
   Evaluate${symbolUpper}Strategy(g_state,g_profile,signal);
   if(IsLocalPaperModeActive() && !signal.valid && signal.reason_code == "SCORE_BELOW_TRIGGER" && MathAbs(signal.score) >= 0.20)
     {
      signal.valid = true;
      signal.side = (signal.score >= 0.0 ? MB_SIGNAL_BUY : MB_SIGNAL_SELL);
      signal.reason_code = "PAPER_SCORE_GATE";
     }
   ${symbolPascal}LocalRiskPlan risk_plan;
   Build${symbolUpper}RiskPlan(g_state,g_market,risk_plan);
   if(IsLocalPaperModeActive() && signal.valid && !risk_plan.allowed && risk_plan.reason_code == "MARGIN_GUARD")
     {
      risk_plan.allowed = true;
      risk_plan.reason_code = "PAPER_IGNORE_MARGIN_GUARD";
      risk_plan.lots = MathMax(g_market.vol_min,g_market.vol_step);
     }
   if(MbHasPosition(g_state.symbol,g_state.magic) || (IsLocalPaperModeActive() && MbPaperHasOpenPosition(g_paper_position)))
     {
      MbAppendDecisionEvent(
         g_decision_log_path,
         now,
         g_state.symbol,
         "POSITION",
         "SKIP",
         "POSITION_ALREADY_OPEN",
         g_market.spread_points,
         signal.score,
         0.0,
         0
      );
      return;
     }
   if(signal.valid && !risk_plan.allowed)
     {
      MbAppendDecisionEvent(
         g_decision_log_path,
         now,
         g_state.symbol,
         "SIZE",
         "SKIP",
         risk_plan.reason_code,
         g_market.spread_points,
         signal.score,
         0.0,
         0
      );
      return;
     }

   if(signal.valid)
     {
      double entry_price = (signal.side == MB_SIGNAL_BUY ? g_market.ask : g_market.bid);
      double sl_price = 0.0;
      double tp_price = 0.0;
      if(signal.side == MB_SIGNAL_BUY)
        {
         sl_price = entry_price - (risk_plan.sl_points * _Point);
         tp_price = entry_price + (risk_plan.tp_points * _Point);
        }
      else if(signal.side == MB_SIGNAL_SELL)
        {
         sl_price = entry_price + (risk_plan.sl_points * _Point);
         tp_price = entry_price - (risk_plan.tp_points * _Point);
        }

      MbExecutionCheck exec_check = MbBuildExecutionCheck(
         g_profile,
         g_market,
         signal.side,
         risk_plan.lots,
         entry_price,
         sl_price,
         tp_price
      );
      if(!exec_check.allowed)
        {
         if(exec_check.order_check_retcode > 0)
            MbIncidentNoteRetcode(
               g_incident_log_path,
               g_state.symbol,
               "order_check",
               exec_check.order_check_retcode,
               MbClassifyRetcode(exec_check.order_check_retcode),
               1
            );
         MbAppendDecisionEvent(
            g_decision_log_path,
            now,
            g_state.symbol,
            "EXEC_PRECHECK",
            "BLOCK",
            exec_check.reason,
            g_market.spread_points,
            signal.score,
            risk_plan.lots,
            exec_check.order_check_retcode
         );
         return;
        }
      MbAppendDecisionEvent(
         g_decision_log_path,
         now,
         g_state.symbol,
         "EXEC_PRECHECK",
         "READY",
         "PRECHECK_OK",
         g_market.spread_points,
         signal.score,
         risk_plan.lots,
         0
      );
      if(!InpEnableLiveEntries || IsLocalPaperModeActive())
        {
         if(IsLocalPaperModeActive())
           {
            MbMarkOrderSend(g_state);
            MbLatencyProfileRecordExecution(g_latency,true,0,0.0);
            MbPaperOpenPosition(
               g_paper_position,
               signal.side,
               risk_plan.lots,
               entry_price,
               sl_price,
               tp_price,
               g_market.spread_points,
               now,
               300,
               signal.reason_code
            );
            MbSavePaperPosition(g_profile.symbol,g_paper_position);
            MbAppendDecisionEvent(
               g_decision_log_path,
               now,
               g_state.symbol,
               "PAPER_OPEN",
               "OK",
               "PAPER_POSITION_OPENED",
               g_market.spread_points,
               signal.score,
               risk_plan.lots,
               0
            );
         }
         MbAppendDecisionEvent(
            g_decision_log_path,
            now,
            g_state.symbol,
            "EXEC_SEND",
            "SKIP",
            "LIVE_SEND_DISABLED",
            g_market.spread_points,
            signal.score,
            risk_plan.lots,
            0
         );
        }
      else
        {
         MbMarkOrderSend(g_state);
         MbExecutionResult exec_result = MbExecuteMarketOrder(
            g_trade,
            g_profile,
            signal.side,
            risk_plan.lots,
            entry_price,
            sl_price,
            tp_price,
            InpTradeComment
         );
         MbFinalizeExecutionAttempt(
            g_execution_telemetry_path,
            g_incident_log_path,
            g_market,
            g_state,
            (long)(GetMicrosecondCount() - tick_t0_us),
            "EXEC_SEND",
            exec_result
         );
         MbLatencyProfileRecordExecution(
            g_latency,
            exec_result.ok,
            exec_result.retries_used,
            exec_result.slippage_points
         );
         MbAppendDecisionEvent(
            g_decision_log_path,
            now,
            g_state.symbol,
            "EXEC_SEND",
            (exec_result.ok ? "OK" : "ERROR"),
            exec_result.reason,
            g_market.spread_points,
            signal.score,
            risk_plan.lots,
            exec_result.retcode
         );
         if(exec_result.ok)
            return;
        }
     }

   long local_latency_us = (long)(GetMicrosecondCount() - tick_t0_us);
   MbLatencyProfileRecord(g_latency,local_latency_us,0);
   MbAppendDecisionEvent(
      g_decision_log_path,
      now,
      g_state.symbol,
      "SCAN",
      (signal.valid ? "READY" : "SKIP"),
      signal.reason_code,
      g_market.spread_points,
      signal.score,
      (signal.valid ? risk_plan.lots : 0.0),
      0
   );
  }

void OnTradeTransaction(
   const MqlTradeTransaction &trans,
   const MqlTradeRequest &request,
   const MqlTradeResult &result
)
  {
   if(!MbTransactionMatchesLocalBot(g_state.symbol,g_state.magic,trans,request))
      return;

   MbAppendTradeTransactionEvent(
      g_trade_transaction_log_path,
      g_state.symbol,
      g_state.magic,
      trans,
      request,
      result
   );

   if(trans.deal > 0)
      MbProcessClosedDealFeedback(g_state.symbol,g_state.magic,(ulong)trans.deal,g_state);
  }
"@

$profileContent = @"
#ifndef PROFILE_${symbolUpper}_INCLUDED
#define PROFILE_${symbolUpper}_INCLUDED

#include "..\\Core\\MbRuntimeTypes.mqh"

void LoadProfile${symbolUpper}(MbSymbolProfile &out)
  {
   MbSymbolProfileReset(out);
   out.symbol = "$symbolUpper";
   out.trade_tf = PERIOD_M5;
   out.max_spread_points = 25.0;
   out.caution_spread_points = 18.0;
   out.deviation_points = 20;
   out.quotes_tolerance_pct = 0.10;
   out.max_tick_age_sec = 5;
   out.min_margin_free_pct = 120.0;
   out.hard_daily_loss_pct = 2.0;
   out.hard_session_loss_pct = 1.0;
   out.min_seconds_between_entries = 60;
   out.session_profile = "UNSPECIFIED";
   out.trade_window_start_hour = 0;
   out.trade_window_end_hour = 23;
   out.friday_cutoff_enabled = true;
   out.friday_cutoff_hour = 16;
   out.kill_switch_required = true;
   out.kill_switch_token_name = "oandakey_$symbolLower.token";
   out.kill_switch_max_age_sec = 120;
  }

#endif
"@

$strategyContent = @"
#ifndef STRATEGY_${symbolUpper}_INCLUDED
#define STRATEGY_${symbolUpper}_INCLUDED

#include <Trade/Trade.mqh>
#include "..\\Core\\MbRuntimeTypes.mqh"

bool Strategy${symbolUpper}Init(const MbSymbolProfile &profile)
  {
   return true;
  }

void Strategy${symbolUpper}Deinit()
  {
  }

struct ${symbolPascal}LocalRiskPlan
  {
   bool allowed;
   double lots;
   double sl_points;
   double tp_points;
   string reason_code;
  };

void Build${symbolUpper}RiskPlan(
   const MbRuntimeState &state,
   const MbMarketSnapshot &snapshot,
   ${symbolPascal}LocalRiskPlan &out
)
  {
   out.allowed = false;
   out.lots = 0.0;
   out.sl_points = 0.0;
   out.tp_points = 0.0;
   out.reason_code = "SCAFFOLD_ONLY";
  }

void Manage${symbolUpper}OpenPosition(
   CTrade &trade,
   MbRuntimeState &state,
   const MbSymbolProfile &profile,
   const MbMarketSnapshot &snapshot
)
  {
  }

void Evaluate${symbolUpper}Strategy(const MbRuntimeState &state,const MbSymbolProfile &profile,MbSignalDecision &out)
  {
   MbSignalDecisionReset(out);
   out.reason_code = "SCAFFOLD_ONLY";
  }

#endif
"@

$presetContent = @"
InpMagic=$MagicNumber
InpTimerSec=5
InpEnableLiveEntries=false
"@

Set-Content -LiteralPath $expertPath -Value $expertContent -Encoding ASCII
if (-not $ExpertOnly) {
    Set-Content -LiteralPath $profilePath -Value $profileContent -Encoding ASCII
    Set-Content -LiteralPath $strategyPath -Value $strategyContent -Encoding ASCII
    Set-Content -LiteralPath $presetPath -Value $presetContent -Encoding ASCII
}

Write-Host "Created scaffold for $symbolUpper"
