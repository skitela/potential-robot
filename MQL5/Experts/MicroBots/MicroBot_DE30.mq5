#property strict
#property version   "1.00"
#property description "MicroBot DE30 scaffold."

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
#include "..\\..\\Include\\Core\\MbTesterTelemetry.mqh"
#include "..\\..\\Include\\Core\\MbInformationalPolicyPlane.mqh"
#include "..\\..\\Include\\Core\\MbExecutionPrecheck.mqh"
#include "..\\..\\Include\\Core\\MbPreTradeTruth.mqh"
#include "..\\..\\Include\\Core\\MbExecutionSend.mqh"
#include "..\\..\\Include\\Core\\MbExecutionFeedback.mqh"
#include "..\\..\\Include\\Core\\MbExecutionTruthFeed.mqh"
#include "..\\..\\Include\\Core\\MbExecutionQualityGuard.mqh"
#include "..\\..\\Include\\Core\\MbContextPolicy.mqh"
#include "..\\..\\Include\\Core\\MbCandleAdvisory.mqh"
#include "..\\..\\Include\\Core\\MbRenkoAdvisory.mqh"
#include "..\\..\\Include\\Core\\MbAuxSignalFusion.mqh"
#include "..\\..\\Include\\Core\\MbDecisionJournal.mqh"
#include "..\\..\\Include\\Core\\MbCandidateSignalJournal.mqh"
#include "..\\..\\Include\\Core\\MbCandidateArbitration.mqh"
#include "..\\..\\Include\\Core\\MbExecutionTelemetry.mqh"
#include "..\\..\\Include\\Core\\MbIncidentJournal.mqh"
#include "..\\..\\Include\\Core\\MbTradeTransactionJournal.mqh"
#include "..\\..\\Include\\Core\\MbClosedDealTracker.mqh"
#include "..\\..\\Include\\Core\\MbLearningContext.mqh"
#include "..\\..\\Include\\Core\\MbPaperTrading.mqh"
#include "..\\..\\Include\\Core\\MbTuningLocalAgent.mqh"
#include "..\\..\\Include\\Core\\MbTuningHierarchyBridge.mqh"
#include "..\\..\\Include\\Core\\MbOnnxPilotObservation.mqh"
#include "..\\..\\Include\\Core\\MbMlRuntimeBridge.mqh"
#include "..\\..\\Include\\Core\\MbGlobalTeacherLearningDiagnostic.mqh"
#include "..\\..\\Include\\Profiles\\Profile_DE30.mqh"
#include "..\\..\\Include\\Strategies\\Strategy_DE30.mqh"

input ulong InpMagic = 930301;
input uint InpTimerSec = 5;
input bool InpEnableLiveEntries = false;
input bool InpPaperCollectMode = true;
input bool InpEnableOnnxObservation = true;
input bool InpEnableMlRuntimeBridge = true;
input bool InpEnableStudentDecisionGate = false;
input string InpTradeComment = "MB_DE30";
input bool InpEnableStrategyTesterSandbox = true;
input string InpStrategyTesterSandboxTag = "DE30_AGENT";

CTrade g_trade;
MbRuntimeState g_state;
MbSymbolProfile g_profile;
MbRuntimeControlState g_runtime_control;
MbKillSwitchState g_kill_switch;
MbMarketSnapshot g_market;
MbLatencyProfile g_latency;
string g_decision_log_path = "";
string g_candidate_log_path = "";
string g_execution_telemetry_path = "";
string g_incident_log_path = "";
string g_latency_log_path = "";
string g_trade_transaction_log_path = "";
MbPaperPositionState g_paper_position;
MbTuningLocalPolicy g_DE30_local_tuning_policy;
MbTuningLocalPolicy g_DE30_effective_tuning_policy;
MbTuningFamilyPolicy g_DE30_family_tuning_policy;
MbTuningCoordinatorState g_tuning_coordinator_state;
string g_throttled_decision_keys[];
datetime g_throttled_decision_times[];
string g_last_aux_event_key = "";
datetime g_last_aux_event_ts = 0;
string g_tuning_action_log_path = "";
string g_tuning_deckhand_log_path = "";
string g_onnx_observation_log_path = "";
string g_onnx_observation_state_path = "";
MbMlRuntimeBridgeState g_ml_bridge;

bool ShouldRunDE30TuningCycle(const datetime now)
  {
   const int tuning_service_interval_sec = 300;

   if(!g_DE30_local_tuning_policy.enabled)
      return false;

   if(g_DE30_local_tuning_policy.last_eval_at <= 0)
      return true;

   if(StringLen(g_tuning_deckhand_log_path) > 0 && !FileIsExist(g_tuning_deckhand_log_path,FILE_COMMON))
      return true;

   if(g_state.learning_sample_count != g_DE30_local_tuning_policy.last_learning_sample_count)
      return true;

   return ((now - g_DE30_local_tuning_policy.last_eval_at) >= tuning_service_interval_sec);
  }

bool IsLocalPaperModeActive()
  {
   return MbIsEffectivePaperRuntimeActive(InpEnableLiveEntries,InpPaperCollectMode,g_runtime_control);
  }

void ConfigureDE30StrategyTesterSandbox()
  {
   if(!InpEnableStrategyTesterSandbox || !MbIsStrategyTesterRuntime())
      return;

   string sandbox_tag = MbCanonicalSymbol(g_profile.symbol);
   string custom_tag = MbStoragePathSanitizeToken(InpStrategyTesterSandboxTag);
   if(custom_tag != "" && custom_tag != "DEFAULT")
      sandbox_tag += "_" + custom_tag;

   MbEnableStrategyTesterSandbox(sandbox_tag);
  }

void NormalizeDE30MarketPermissions()
  {
   MbNormalizePaperRuntimeState(g_state,g_market,IsLocalPaperModeActive());
  }

void AppendDE30DecisionEvent(
   const datetime ts,
   const string phase,
   const string verdict,
   const string reason,
   const double spread_points,
   const double score,
   const double lots,
   const long retcode,
   const bool throttle_repeat = false,
   const int throttle_sec = 30
)
  {
   if(throttle_repeat)
     {
      string key = phase + "|" + verdict + "|" + reason;
      for(int i = 0; i < ArraySize(g_throttled_decision_keys); ++i)
        {
         if(g_throttled_decision_keys[i] != key)
            continue;
         if(g_throttled_decision_times[i] > 0 && (ts - g_throttled_decision_times[i]) < throttle_sec)
            return;
         g_throttled_decision_times[i] = ts;
         key = "";
         break;
        }
      if(StringLen(key) > 0)
        {
         int next = ArraySize(g_throttled_decision_keys);
         ArrayResize(g_throttled_decision_keys,next + 1);
         ArrayResize(g_throttled_decision_times,next + 1);
         g_throttled_decision_keys[next] = key;
         g_throttled_decision_times[next] = ts;
        }
     }

   MbAppendDecisionEvent(
      g_decision_log_path,
      ts,
      g_state.symbol,
      phase,
      verdict,
      reason,
      spread_points,
      score,
      lots,
      retcode
   );
  }

void AppendDE30CandidateEvent(
   const datetime ts,
   const string stage,
   const bool accepted,
   const string reason,
   const MbSignalDecision &signal,
   const double lots
)
  {
   if(signal.setup_type == "NONE")
      return;

   MbAppendCandidateSignal(
      g_candidate_log_path,
      ts,
      g_state.symbol,
      stage,
      accepted,
      reason,
      signal,
      g_market.spread_points,
      lots
   );
  }

void AppendDE30AuxDecisionEvent(const datetime ts,const MbSignalDecision &signal,const MbSignalSide intended_side)
  {
   if(signal.setup_type == "NONE")
      return;

   string verdict = "NEUTRAL";
   string reason = "AUX_INCONCLUSIVE";
   double candle_score = signal.candle_score;
   double renko_score = signal.renko_score;
   bool candle_actionable = (signal.candle_quality_grade != "POOR" && candle_score >= 0.35);
   bool renko_actionable = (signal.renko_quality_grade != "POOR" && renko_score >= 0.45);

   bool candle_support = ((intended_side == MB_SIGNAL_BUY && signal.candle_bias == "UP") || (intended_side == MB_SIGNAL_SELL && signal.candle_bias == "DOWN"));
   bool renko_support = ((intended_side == MB_SIGNAL_BUY && signal.renko_bias == "UP") || (intended_side == MB_SIGNAL_SELL && signal.renko_bias == "DOWN"));
   bool candle_conflict = ((intended_side == MB_SIGNAL_BUY && signal.candle_bias == "DOWN") || (intended_side == MB_SIGNAL_SELL && signal.candle_bias == "UP"));
   bool renko_conflict = ((intended_side == MB_SIGNAL_BUY && signal.renko_bias == "DOWN") || (intended_side == MB_SIGNAL_SELL && signal.renko_bias == "UP"));

   if(signal.reason_code == "AUX_CONFLICT_BLOCK")
     {
      verdict = "BLOCK";
      reason = "AUX_CONFLICT_BLOCK";
     }
   else if(candle_actionable && renko_actionable && candle_support && renko_support)
     {
      verdict = "SUPPORT";
      reason = "AUX_ALIGNMENT_GOOD";
     }
   else if((candle_actionable && candle_conflict) || (renko_actionable && renko_conflict))
     {
      verdict = "CAUTION";
      reason = "AUX_CONFLICT_CAUTION";
     }
   else if((candle_actionable && candle_support) || (renko_actionable && renko_support))
     {
      verdict = "SUPPORT";
      reason = "AUX_ALIGNMENT_LIGHT";
     }
   else if(candle_actionable || renko_actionable)
     {
      verdict = "NEUTRAL";
      reason = "AUX_MIXED";
     }

   // Ignore low-value neutral advisory noise; it does not help post-run diagnosis.
   if(verdict == "NEUTRAL")
     {
      if(reason == "AUX_INCONCLUSIVE")
         return;
      if(reason == "AUX_MIXED" && MathAbs(signal.score) < 0.30)
         return;
     }

   string aux_key = verdict + "|" + reason;
   if(g_last_aux_event_key == aux_key && g_last_aux_event_ts > 0 && (ts - g_last_aux_event_ts) < 120)
      return;

   g_last_aux_event_key = aux_key;
   g_last_aux_event_ts = ts;
   AppendDE30DecisionEvent(ts,"AUX",verdict,reason,g_market.spread_points,signal.score,0.0,0,false);
  }

double MbApplyRiskMultiplierToLots(const MbMarketSnapshot &snapshot,const double base_lots,const double multiplier)
  {
   if(base_lots <= 0.0 || snapshot.vol_step <= 0.0)
      return 0.0;
   double effective_multiplier = MbClampRiskMultiplierToContract(snapshot.paper_runtime_override_active,multiplier);
   if(effective_multiplier <= 0.0)
      return 0.0;
   double scaled = MathFloor((base_lots * effective_multiplier) / snapshot.vol_step) * snapshot.vol_step;
   if(scaled < snapshot.vol_min)
      return 0.0;
   return MathMin(snapshot.vol_max,scaled);
  }

int ResolveDE30PaperHoldSeconds(const MbSignalDecision &signal)
  {
   int hold_seconds = 300;

   if(signal.setup_type == "SETUP_BREAKOUT")
     {
      if(signal.reason_code == "PAPER_SCORE_GATE" || signal.confidence_bucket == "LOW")
         hold_seconds = 150;
      else if(signal.market_regime == "CHAOS" || signal.market_regime == "RANGE")
         hold_seconds = 210;
      else if(signal.confidence_bucket == "HIGH" && !signal.renko_reversal_flag && signal.renko_run_length >= 3)
         hold_seconds = 360;
      else
         hold_seconds = 240;
     }
   else if(signal.setup_type == "SETUP_RANGE" && (signal.market_regime == "TREND" || signal.market_regime == "CHAOS"))
     {
      hold_seconds = (signal.confidence_bucket == "LOW" ? 150 : 180);
     }
   else if(signal.setup_type == "SETUP_REJECTION" && signal.market_regime == "RANGE" && signal.confidence_bucket != "LOW")
      hold_seconds = 360;

   return hold_seconds;
  }

int OnInit()
  {
   MbRuntimeReset(g_state);
   LoadProfileDE30(g_profile);
   if(!MbVerifyChartSymbol(g_profile.symbol))
      return(INIT_FAILED);
   g_profile.symbol = Symbol();
   ConfigureDE30StrategyTesterSandbox();
   g_state.magic = InpMagic;
   g_state.symbol = g_profile.symbol;
   g_state.mode = MB_MODE_READY;
   g_trade.SetExpertMagicNumber((ulong)InpMagic);
   g_trade.SetDeviationInPoints(g_profile.deviation_points);
   g_trade.SetTypeFillingBySymbol(g_profile.symbol);
   if(!MbStorageInit(g_profile.symbol))
      return(INIT_FAILED);
   if(!StrategyDE30Init(g_profile))
      return(INIT_FAILED);

   MbLoadRuntimeState(g_state);
   MbNormalizePaperRuntimeState(g_state,IsLocalPaperModeActive());
   MbReadRuntimeControl(g_profile.symbol,g_profile.session_profile,g_runtime_control);
   MbApplyRuntimeControl(g_state,g_runtime_control);
   MbKillSwitchEvaluate(g_profile,g_state,g_kill_switch);
   MbApplyPaperRuntimeOverride(g_state,g_market,g_kill_switch,IsLocalPaperModeActive());
   MbRefreshMarketSnapshot(g_profile,g_market);
   NormalizeDE30MarketPermissions();
   MbLatencyProfileInit(g_latency);
   g_decision_log_path = MbLogFilePath(g_profile.symbol,"decision_events.csv");
   g_candidate_log_path = MbLogFilePath(g_profile.symbol,"candidate_signals.csv");
   g_execution_telemetry_path = MbLogFilePath(g_profile.symbol,"execution_telemetry.csv");
   g_incident_log_path = MbLogFilePath(g_profile.symbol,"incident_journal.jsonl");
   g_latency_log_path = MbLogFilePath(g_profile.symbol,"latency_profile.csv");
   g_trade_transaction_log_path = MbLogFilePath(g_profile.symbol,"trade_transactions.jsonl");
   g_tuning_action_log_path = MbLogFilePath(g_profile.symbol,"tuning_actions.csv");
   g_tuning_deckhand_log_path = MbLogFilePath(g_profile.symbol,"tuning_deckhand.csv");
   g_onnx_observation_log_path = MbLogFilePath(g_profile.symbol,"onnx_observations.csv");
   g_onnx_observation_state_path = MbStateFilePath(g_profile.symbol,"onnx_observation_latest.json");
   MbDecisionJournalInit(g_decision_log_path);
   MbCandidateSignalJournalInit(g_candidate_log_path);
   MbExecutionTelemetryInit(g_execution_telemetry_path);
   MbIncidentJournalInit(g_incident_log_path);
   MbTradeTransactionJournalInit(g_trade_transaction_log_path);
   MbPaperPositionReset(g_paper_position);
   MbLoadPaperPosition(g_profile.symbol,g_paper_position);
   ArrayResize(g_throttled_decision_keys,0);
   ArrayResize(g_throttled_decision_times,0);
   g_last_aux_event_key = "";
   g_last_aux_event_ts = 0;
   MbTuningLocalPolicyReset(g_DE30_local_tuning_policy);
   MbLoadTuningLocalPolicy(g_profile.symbol,g_DE30_local_tuning_policy);
   MbTuningLocalPolicyReset(g_DE30_effective_tuning_policy);
   MbTuningFamilyPolicyReset(g_DE30_family_tuning_policy);
   MbTuningCoordinatorStateReset(g_tuning_coordinator_state);
   MbBuildEffectiveTuningPolicy(g_profile.session_profile,g_DE30_local_tuning_policy,g_DE30_effective_tuning_policy,g_DE30_family_tuning_policy,g_tuning_coordinator_state);
   StrategyDE30SetTuningPolicy(g_DE30_effective_tuning_policy);
   MbSaveEffectiveTuningLocalPolicy(g_profile.symbol,g_DE30_effective_tuning_policy);
   bool onnx_ready = MbOnnxObservationInit(
      g_profile.symbol,
      InpEnableOnnxObservation,
      g_onnx_observation_log_path,
      g_onnx_observation_state_path
   );
   PrintFormat(
      "MB_DE30_ONNX_OBSERVATION enabled=%s ready=%s symbol=%s",
      (InpEnableOnnxObservation ? "true" : "false"),
      (onnx_ready ? "true" : "false"),
      g_profile.symbol
   );
   MbMlRuntimeBridgeInit(
      g_ml_bridge,
      g_profile.symbol,
      InpEnableMlRuntimeBridge,
      InpEnableStudentDecisionGate
   );
   MbMlRuntimeBridgeFlushSnapshot(g_ml_bridge,g_profile,g_market,g_latency);
   if(g_kill_switch.halt)
      g_state.halt = true;

   EventSetTimer((int)MathMax(1,(int)InpTimerSec));
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   MbDecisionJournalFlush();
   MbCandidateSignalJournalFlush();
   MbExecutionTelemetryFlush();
   MbIncidentJournalFlush();
   MbTradeTransactionJournalFlush();
   MbTesterTelemetryFinalizeSingleRun(g_profile,g_state,g_market,g_DE30_effective_tuning_policy,g_latency);
   MbLatencyProfileFlush(g_latency,g_latency_log_path);
   MbSavePaperPosition(g_profile.symbol,g_paper_position);
   MbOnnxObservationShutdown();
   MbMlRuntimeBridgeShutdown(g_ml_bridge);
            MbClearCandidateArbitrationSnapshot(g_profile.session_profile,g_profile.symbol);
   MbSaveTuningLocalPolicy(g_profile.symbol,g_DE30_local_tuning_policy);
   MbSaveEffectiveTuningLocalPolicy(g_profile.symbol,g_DE30_effective_tuning_policy);
   StrategyDE30Deinit();
   MbSaveRuntimeState(g_state);
  }

void OnTimer()
  {
   datetime now = TimeCurrent();
   MbReadRuntimeControl(g_profile.symbol,g_profile.session_profile,g_runtime_control);
   MbApplyRuntimeControl(g_state,g_runtime_control);
   MbKillSwitchEvaluate(g_profile,g_state,g_kill_switch);
   MbApplyPaperRuntimeOverride(g_state,g_market,g_kill_switch,IsLocalPaperModeActive());
   MbRefreshMarketSnapshot(g_profile,g_market);
   NormalizeDE30MarketPermissions();
   if(g_kill_switch.halt)
      g_state.halt = true;
   MbRuntimeOnTimer(g_state);
   MbOnnxObservationResult timer_onnx_result;
   MbOnnxObservationEmitTimerShadow(now,g_profile.symbol,(IsLocalPaperModeActive() ? "PAPER" : "LIVE"),g_market.spread_points,timer_onnx_result);
   MbFlushHeartbeat(g_state);
   MbFlushRuntimeStatus(g_state,(g_kill_switch.halt ? g_kill_switch.reason_code : g_runtime_control.reason_code));
   MbFlushInformationalPolicy(g_profile,g_state,g_market,g_DE30_local_tuning_policy,"BOOTSTRAP",(g_kill_switch.halt ? g_kill_switch.reason_code : g_runtime_control.reason_code));
   MbFlushBrokerProfile(g_profile,g_state,g_market);
   MbFlushExecutionSummary(g_profile,g_state,g_market,g_DE30_local_tuning_policy,g_latency,(g_kill_switch.halt ? g_kill_switch.reason_code : g_runtime_control.reason_code));
   MbMlRuntimeBridgeFlushSnapshot(g_ml_bridge,g_profile,g_market,g_latency);
   MbDecisionJournalFlush();
   MbCandidateSignalJournalFlush();
   MbExecutionTelemetryFlush();
   MbIncidentJournalFlush();
   MbTradeTransactionJournalFlush();
   MbLatencyProfileFlush(g_latency,g_latency_log_path);

   if(ShouldRunDE30TuningCycle(now))
     {
      string family_symbols[];
      string families[];
      string family_reason = "";
      string coordinator_reason = "";
      bool family_changed = false;
      bool coordinator_changed = false;

      if(MbGetTuningFamilySymbols(g_profile.session_profile,family_symbols) > 0)
        {
         MbLoadTuningFamilyPolicy(g_profile.session_profile,g_DE30_family_tuning_policy);
         family_changed = MbRunTuningFamilyAgent(g_profile.session_profile,family_symbols,g_DE30_family_tuning_policy,family_reason);
        }

      if(MbGetAllTuningFamilies(families) > 0)
        {
         MbLoadTuningCoordinatorState(g_tuning_coordinator_state);
         coordinator_changed = MbRunTuningCoordinator(families,g_tuning_coordinator_state,coordinator_reason);
        }

      MbTuningDeckhandReport tuning_deckhand;
      MbTuningDeckhandReportReset(tuning_deckhand);
      MbRunTuningDeckhand(g_profile.symbol,g_state,g_market,g_tuning_deckhand_log_path,g_DE30_local_tuning_policy,tuning_deckhand);

      string tuning_reason = "";
      string hierarchy_block_reason = "";
      bool hierarchy_blocks = MbTuningHierarchyBlocksLocalChanges(g_DE30_family_tuning_policy,g_tuning_coordinator_state,hierarchy_block_reason);
      if(IsLocalPaperModeActive())
         hierarchy_blocks = false;
      bool tuning_changed = false;
      if(IsLocalPaperModeActive())
         tuning_changed = MbRunLocalTuningAgent(g_profile.symbol,g_state,g_tuning_action_log_path,g_DE30_local_tuning_policy,tuning_deckhand,tuning_reason);
      else if(!hierarchy_blocks)
         tuning_changed = MbRunLocalTuningAgent(g_profile.symbol,g_state,g_tuning_action_log_path,g_DE30_local_tuning_policy,tuning_deckhand,tuning_reason);
      else
         tuning_reason = hierarchy_block_reason;

      MbBuildEffectiveTuningPolicy(g_profile.session_profile,g_DE30_local_tuning_policy,g_DE30_effective_tuning_policy,g_DE30_family_tuning_policy,g_tuning_coordinator_state);
      StrategyDE30SetTuningPolicy(g_DE30_effective_tuning_policy);
      MbSaveTuningLocalPolicy(g_profile.symbol,g_DE30_local_tuning_policy);
      MbSaveEffectiveTuningLocalPolicy(g_profile.symbol,g_DE30_effective_tuning_policy);

      if(family_changed)
         AppendDE30DecisionEvent(now,"TUNING_FAMILY","ADJUST",g_DE30_family_tuning_policy.last_action_code,g_market.spread_points,0.0,0.0,0,true,600);
      else if(g_DE30_family_tuning_policy.freeze_new_changes)
         AppendDE30DecisionEvent(now,"TUNING_FAMILY","SKIP",g_DE30_family_tuning_policy.last_action_code,g_market.spread_points,0.0,0.0,0,true,600);

      if(coordinator_changed)
         AppendDE30DecisionEvent(now,"TUNING_FLEET","ADJUST",g_tuning_coordinator_state.last_action_code,g_market.spread_points,0.0,0.0,0,true,600);
      else if(g_tuning_coordinator_state.freeze_new_changes)
         AppendDE30DecisionEvent(now,"TUNING_FLEET","SKIP",g_tuning_coordinator_state.last_action_code,g_market.spread_points,0.0,0.0,0,true,600);

      if(tuning_changed)
         AppendDE30DecisionEvent(now,"TUNING","ADJUST",g_DE30_local_tuning_policy.last_action_code,g_market.spread_points,0.0,0.0,0,true,300);
      else if(hierarchy_blocks)
         AppendDE30DecisionEvent(now,"TUNING","SKIP",tuning_reason,g_market.spread_points,0.0,0.0,0,true,300);
      else if(!g_DE30_local_tuning_policy.trusted_data)
         AppendDE30DecisionEvent(now,"TUNING","SKIP",g_DE30_local_tuning_policy.trust_reason,g_market.spread_points,0.0,0.0,0,true,300);
     }

   MbSavePaperPosition(g_profile.symbol,g_paper_position);
            MbClearCandidateArbitrationSnapshot(g_profile.session_profile,g_profile.symbol);
   MbSaveRuntimeState(g_state);
  }

int OnTesterInit()
  {
   return MbTesterTelemetryOnInit(g_profile.symbol,(long)InpMagic);
  }

double OnTester()
  {
   return MbTesterTelemetryOnTester(g_profile,g_state,g_market,g_DE30_effective_tuning_policy,g_latency);
  }

void OnTesterPass()
  {
   MbTesterTelemetryOnPass(g_profile.symbol,(long)InpMagic);
  }

void OnTesterDeinit()
  {
   MbTesterTelemetryOnDeinit(g_profile.symbol,(long)InpMagic);
  }

void OnTick()
  {
   ulong tick_t0_us = GetMicrosecondCount();
   datetime now = TimeCurrent();
   if(!IsLocalPaperModeActive())
      MbMarkPriceProbe(g_state);
   MbRuntimeOnTick(g_state);
   MbRefreshPaperTradeRights(g_state,IsLocalPaperModeActive());
   MbRefreshTickSnapshot(g_profile,g_market);
   NormalizeDE30MarketPermissions();
   if(IsLocalPaperModeActive())
     {
      double paper_pnl = 0.0;
      string paper_close_reason = "";
      MbPaperPositionState closed_paper;
      MbPaperPositionReset(closed_paper);
      if(MbPaperMaybeClosePosition(g_market,g_paper_position,now,paper_pnl,paper_close_reason,closed_paper))
        {
         MbProcessSyntheticClosedDealFeedback(g_state,paper_pnl,now);
         MbAppendLearningObservationV2(
            g_state.symbol,
            now,
            closed_paper.setup_type,
            closed_paper.market_regime,
            closed_paper.spread_regime,
            closed_paper.execution_regime,
            closed_paper.confidence_bucket,
            closed_paper.confidence_score,
            closed_paper.candle_bias,
            closed_paper.candle_quality_grade,
            closed_paper.candle_score,
            closed_paper.renko_bias,
            closed_paper.renko_quality_grade,
            closed_paper.renko_score,
            closed_paper.renko_run_length,
            closed_paper.renko_reversal_flag,
            closed_paper.side,
            paper_pnl,
            paper_close_reason
         );
         MbMlRuntimeBridgeAppendPaperLedger(g_ml_bridge,now,g_profile.symbol,closed_paper,g_market,paper_pnl,paper_close_reason);
         AppendDE30DecisionEvent(now,"PAPER_CLOSE",(paper_pnl >= 0.0 ? "OK" : "LOSS"),paper_close_reason,g_market.spread_points,0.0,paper_pnl,0,false);
         MbSavePaperPosition(g_profile.symbol,g_paper_position);
            MbClearCandidateArbitrationSnapshot(g_profile.session_profile,g_profile.symbol);
        }
     }
   ManageDE30OpenPosition(g_trade,g_state,g_profile,g_market);
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

   bool already_has_position = (MbHasPosition(g_state.symbol,g_state.magic) || (IsLocalPaperModeActive() && MbPaperHasOpenPosition(g_paper_position)));
   if(already_has_position)
     {
      AppendDE30DecisionEvent(now,"POSITION","SKIP","POSITION_ALREADY_OPEN",g_market.spread_points,0.0,0.0,0,true,300);
      long local_latency_us_open_position = (long)(GetMicrosecondCount() - tick_t0_us);
      MbLatencyProfileRecord(g_latency,local_latency_us_open_position,0);
      return;
     }

   string guard_reason = "OK";
   MbGuardVerdict market_guard = MbEvaluateMarketEntryGuards(g_profile,g_market,g_state,guard_reason);
   if(MbShouldBypassMarketGuardInPaper(IsLocalPaperModeActive(),guard_reason))
     {
      int market_bypass_throttle = 180;
      if(guard_reason == "OUTSIDE_TRADE_WINDOW" || guard_reason == "TRADE_DISABLED")
         market_bypass_throttle = 300;
      AppendDE30DecisionEvent(now,"MARKET","BYPASS",("PAPER_IGNORE_" + guard_reason),g_market.spread_points,0.0,0.0,0,true,market_bypass_throttle);
      if(MbPaperMarketGuardClearsHalt(guard_reason))
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
      AppendDE30DecisionEvent(now,"MARKET","SKIP",guard_reason,g_market.spread_points,0.0,0.0,0,true,60);
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
      AppendDE30DecisionEvent(now,"EXEC_QUALITY",(exec_quality_guard == MB_GUARD_BLOCK ? "SKIP" : "CAUTION"),guard_reason,g_market.spread_points,0.0,0.0,0,true,30);
      if(exec_quality_guard == MB_GUARD_BLOCK)
         return;
     }

   MbSignalDecision signal;
   MbRefreshPaperTradeRights(g_state,IsLocalPaperModeActive());
   EvaluateDE30Strategy(g_state,g_profile,g_market,signal);
   bool global_teacher_diag_active = MbIsGlobalTeacherLearningDiagnosticActive(g_profile.symbol,IsLocalPaperModeActive());
   if(signal.setup_type != "NONE")
     {
      g_state.market_regime = signal.market_regime;
      g_state.spread_regime = signal.spread_regime;
      g_state.execution_regime = signal.execution_regime;
      g_state.confidence_bucket = signal.confidence_bucket;
      g_state.signal_confidence = signal.confidence_score;
      g_state.signal_risk_multiplier = signal.risk_multiplier;
      g_state.last_setup_type = signal.setup_type;
      g_state.candle_bias = signal.candle_bias;
      g_state.candle_quality_grade = signal.candle_quality_grade;
      g_state.candle_score = signal.candle_score;
      g_state.renko_bias = signal.renko_bias;
      g_state.renko_quality_grade = signal.renko_quality_grade;
      g_state.renko_score = signal.renko_score;
      g_state.renko_run_length = signal.renko_run_length;
      g_state.renko_reversal_flag = signal.renko_reversal_flag;
     }
   if(signal.setup_type != "NONE")
      AppendDE30AuxDecisionEvent(now,signal,(signal.score >= 0.0 ? MB_SIGNAL_BUY : MB_SIGNAL_SELL));
   if(IsLocalPaperModeActive() && !signal.valid && MbShouldBypassGlobalTeacherLearningSoftReject(g_profile.symbol,IsLocalPaperModeActive(),signal.setup_type,signal.reason_code))
     {
      double paper_gate_abs = 0.20;
      bool poor_candle = (signal.candle_quality_grade == "POOR" || signal.candle_quality_grade == "UNKNOWN");
      bool poor_renko = (signal.renko_quality_grade == "POOR" || signal.renko_quality_grade == "UNKNOWN");
      bool weak_candle = (signal.candle_quality_grade != "GOOD");
      bool blocked_by_tuning_gate = false;
      bool blocked_by_de30_range_chaos_foreground_gate = false;
      if(signal.setup_type == "SETUP_TREND" && g_DE30_effective_tuning_policy.require_non_poor_candle_for_trend && poor_candle)
         blocked_by_tuning_gate = true;
      if(signal.setup_type == "SETUP_BREAKOUT" && g_DE30_effective_tuning_policy.require_non_poor_candle_for_breakout && poor_candle)
         blocked_by_tuning_gate = true;
      if(signal.setup_type == "SETUP_BREAKOUT" && g_DE30_effective_tuning_policy.require_non_poor_renko_for_breakout && poor_renko)
         blocked_by_tuning_gate = true;
      if(signal.setup_type == "SETUP_RANGE" && g_DE30_effective_tuning_policy.require_non_poor_candle_for_range && poor_candle)
         blocked_by_tuning_gate = true;
      if(signal.setup_type == "SETUP_RANGE" && g_DE30_effective_tuning_policy.require_non_poor_renko_for_range && poor_renko)
         blocked_by_tuning_gate = true;
      if(signal.setup_type == "SETUP_RANGE" && g_DE30_effective_tuning_policy.range_confidence_floor > 0.0 && signal.confidence_score < g_DE30_effective_tuning_policy.range_confidence_floor)
         blocked_by_tuning_gate = true;
      if(signal.setup_type == "SETUP_PULLBACK" && signal.market_regime == "CHAOS" && (poor_candle || poor_renko))
         blocked_by_tuning_gate = true;
      if(signal.setup_type == "SETUP_PULLBACK" && signal.renko_reversal_flag && poor_candle)
         blocked_by_tuning_gate = true;
      if(signal.setup_type == "SETUP_RANGE" && signal.market_regime == "TREND" && signal.confidence_bucket == "LOW")
         blocked_by_tuning_gate = true;
      if(signal.setup_type == "SETUP_RANGE" && signal.market_regime == "TREND" && (poor_candle || poor_renko))
         blocked_by_tuning_gate = true;
      if(signal.setup_type == "SETUP_RANGE" && signal.market_regime == "CHAOS" && signal.confidence_bucket == "LOW" && (poor_candle || poor_renko))
         blocked_by_tuning_gate = true;
      if(
         signal.setup_type == "SETUP_RANGE" &&
         signal.market_regime == "CHAOS" &&
         signal.confidence_bucket == "LOW" &&
         weak_candle &&
         (signal.spread_regime == "BAD" || poor_renko)
      )
         blocked_by_de30_range_chaos_foreground_gate = true;
      if(signal.setup_type == "SETUP_BREAKOUT")
        {
         paper_gate_abs = 0.60;
         if(signal.market_regime == "CHAOS" || signal.market_regime == "RANGE" || signal.confidence_bucket == "LOW")
            paper_gate_abs = 0.70;
         if(poor_candle)
            paper_gate_abs = MathMax(paper_gate_abs,0.82);
        }
      else if(signal.setup_type == "SETUP_PULLBACK")
        {
         if(signal.market_regime == "CHAOS")
            paper_gate_abs = 0.42;
        }
      else if(signal.setup_type == "SETUP_RANGE")
        {
         if(signal.market_regime == "TREND")
            paper_gate_abs = 0.46;
         else if(signal.market_regime == "CHAOS")
            paper_gate_abs = 0.48;
         if(signal.market_regime == "CHAOS" && signal.confidence_bucket == "LOW" && weak_candle)
            paper_gate_abs = MathMax(paper_gate_abs,0.54);
        }
      else if(signal.setup_type == "SETUP_REJECTION")
         paper_gate_abs = 0.18;

      paper_gate_abs = MbResolveGlobalTeacherLearningGateAbs(g_profile.symbol,signal.setup_type,IsLocalPaperModeActive(),paper_gate_abs);
      if(MbShouldRelaxGlobalTeacherLearningTuningGate(g_profile.symbol,IsLocalPaperModeActive()))
         blocked_by_tuning_gate = false;
      if(MbShouldRelaxGlobalTeacherLearningCostGate(g_profile.symbol,IsLocalPaperModeActive()))
         blocked_by_de30_range_chaos_foreground_gate = false;

      if(!blocked_by_tuning_gate && !blocked_by_de30_range_chaos_foreground_gate && (global_teacher_diag_active || MathAbs(signal.score) >= paper_gate_abs))
        {
         signal.valid = true;
         signal.side = (signal.score >= 0.0 ? MB_SIGNAL_BUY : MB_SIGNAL_SELL);
         signal.reason_code = (global_teacher_diag_active ? "GLOBAL_TEACHER_SCORE_GATE_DIAGNOSTIC" : "PAPER_SCORE_GATE");
        }
      else if(blocked_by_de30_range_chaos_foreground_gate)
         signal.reason_code = "DE30_RANGE_CHAOS_LOW_CONFIDENCE_CANDLE_BLOCK";
     }
   MbOnnxObservationResult onnx_result;
   MbOnnxObservationEvaluateShadowAware(
      now,
      "EVALUATED",
      g_profile.symbol,
      (IsLocalPaperModeActive() ? "PAPER" : "LIVE"),
      signal,
      g_market.spread_points,
      onnx_result
   );
   AppendDE30CandidateEvent(now,"EVALUATED",signal.valid,signal.reason_code,signal,0.0);
   if(!signal.valid)
      MbClearCandidateArbitrationSnapshot(g_profile.session_profile,g_profile.symbol);
   DE30LocalRiskPlan risk_plan;
   BuildDE30RiskPlan(g_state,g_market,risk_plan);
   MbApplyPaperRiskMarginGuardBypass(
      IsLocalPaperModeActive(),
      signal,
      g_market,
      risk_plan.allowed,
      risk_plan.reason_code,
      risk_plan.lots
   );
   if(signal.valid)
      risk_plan.lots = MbApplyRiskMultiplierToLots(g_market,risk_plan.lots,signal.risk_multiplier);
   MbApplyPaperMinLotFloor(
      IsLocalPaperModeActive(),
      signal,
      g_market,
      risk_plan.allowed,
      risk_plan.reason_code,
      risk_plan.lots
   );
   MbNormalizeRiskContractBlockAfterSizing(signal,risk_plan.allowed,risk_plan.reason_code,risk_plan.lots);
   if(signal.valid)
      MbMlRuntimeBridgeApplyStudentGate(g_ml_bridge,now,g_profile,g_market,g_latency,g_state,signal,onnx_result,risk_plan.lots);
   if(signal.valid && !risk_plan.allowed)
     {
      AppendDE30CandidateEvent(now,"SIZE_BLOCK",false,risk_plan.reason_code,signal,0.0);
      AppendDE30DecisionEvent(now,"SIZE","SKIP",risk_plan.reason_code,g_market.spread_points,signal.score,0.0,0,true,30);
      MbClearCandidateArbitrationSnapshot(g_profile.session_profile,g_profile.symbol);
      return;
     }

   if(signal.valid)
     {
      MbCandidateArbitrationVerdict arbitration_verdict;
      MbEvaluateCandidateArbitration(
         g_profile.session_profile,
         g_profile.symbol,
         now,
         IsLocalPaperModeActive(),
         g_market,
         g_state,
         signal,
         risk_plan.lots,
         risk_plan.sl_points,
         arbitration_verdict
      );
      if(!arbitration_verdict.entry_allowed)
        {
         MbAppendCandidateSignal(
            g_candidate_log_path,
            now,
            g_state.symbol,
            "ARBITRATION_BLOCK",
            false,
            arbitration_verdict.reason_code,
            signal,
            g_market.spread_points,
            risk_plan.lots
         );
         MbAppendDecisionEvent(
            g_decision_log_path,
            now,
            g_state.symbol,
            "ARBITRATION",
            "SKIP",
            arbitration_verdict.reason_code,
            g_market.spread_points,
            signal.score,
            risk_plan.lots,
            0
         );
         return;
        }
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
      if(IsLocalPaperModeActive() && signal.valid && !exec_check.allowed)
        {
         if(MbShouldBypassExecutionPrecheckInPaper(exec_check.reason))
           {
            AppendDE30DecisionEvent(
               now,
               "EXEC_PRECHECK",
               "BYPASS",
               ("PAPER_IGNORE_" + exec_check.reason),
               g_market.spread_points,
               signal.score,
               risk_plan.lots,
               exec_check.order_check_retcode,
               true,
               30
            );
            MbMarkExecutionPrecheckBypassedForPaper(exec_check);
         }
        }
      if(!exec_check.allowed)
        {
         AppendDE30CandidateEvent(now,"PRECHECK_BLOCK",false,exec_check.reason,signal,risk_plan.lots);
         if(exec_check.order_check_retcode > 0)
            MbIncidentNoteRetcode(
               g_incident_log_path,
               g_state.symbol,
               "order_check",
               exec_check.order_check_retcode,
               MbClassifyRetcode(exec_check.order_check_retcode),
               1
            );
         AppendDE30DecisionEvent(now,"EXEC_PRECHECK","BLOCK",exec_check.reason,g_market.spread_points,signal.score,risk_plan.lots,exec_check.order_check_retcode,true,30);
         MbClearCandidateArbitrationSnapshot(g_profile.session_profile,g_profile.symbol);
         return;
        }
      AppendDE30DecisionEvent(now,"EXEC_PRECHECK","READY","PRECHECK_OK",g_market.spread_points,signal.score,risk_plan.lots,0,false);
      if(IsLocalPaperModeActive())
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
               ResolveDE30PaperHoldSeconds(signal),
               signal.reason_code,
               signal.setup_type,
               signal.market_regime,
               signal.spread_regime,
               signal.execution_regime,
               signal.confidence_bucket,
               signal.confidence_score,
               signal.risk_multiplier,
               signal.candle_bias,
               signal.candle_quality_grade,
               signal.candle_score,
               signal.renko_bias,
               signal.renko_quality_grade,
               signal.renko_score,
               signal.renko_run_length,
               signal.renko_reversal_flag,
               exec_check.modeled_slippage_points,
               exec_check.modeled_commission_points,
               InpEnableLiveEntries
            );
            MbSavePaperPosition(g_profile.symbol,g_paper_position);
            MbClearCandidateArbitrationSnapshot(g_profile.session_profile,g_profile.symbol);
            AppendDE30CandidateEvent(now,"PAPER_OPEN",true,"PAPER_POSITION_OPENED",signal,risk_plan.lots);
            AppendDE30DecisionEvent(now,"PAPER_OPEN","OK","PAPER_POSITION_OPENED",g_market.spread_points,signal.score,risk_plan.lots,0,false);
         }
         AppendDE30DecisionEvent(now,"EXEC_SEND","SKIP","LIVE_SEND_DISABLED",g_market.spread_points,signal.score,risk_plan.lots,0,true,30);
        }
      else
        {
         string pretrade_candidate_id = MbPreTradeTruthBuildCandidateId(g_state.symbol,now,signal);
         string pretrade_comment = MbPreTradeTruthBuildRequestComment(pretrade_candidate_id);
         MqlTradeRequest pretrade_request;
         MbPreTradeTruthPrepareMarketRequest(
            g_profile,
            g_state.magic,
            signal.side,
            risk_plan.lots,
            entry_price,
            sl_price,
            tp_price,
            pretrade_comment,
            pretrade_request
         );
         MbPreTradeTruthRecord pretrade_record;
         MbPreTradeTruthEvaluateAndWrite("MICROBOT",g_state.symbol,pretrade_candidate_id,pretrade_request,pretrade_record);
         MbMarkOrderSend(g_state);
         MbExecutionResult exec_result = MbExecuteMarketOrder(
            g_trade,
            g_profile,
            signal.side,
            risk_plan.lots,
            entry_price,
            sl_price,
            tp_price,
            pretrade_comment
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
         AppendDE30CandidateEvent(now,(exec_result.ok ? "EXEC_SEND_OK" : "EXEC_SEND_ERROR"),exec_result.ok,exec_result.reason,signal,risk_plan.lots);
         AppendDE30DecisionEvent(now,"EXEC_SEND",(exec_result.ok ? "OK" : "ERROR"),exec_result.reason,g_market.spread_points,signal.score,risk_plan.lots,exec_result.retcode,false);
         MbClearCandidateArbitrationSnapshot(g_profile.session_profile,g_profile.symbol);
         if(exec_result.ok)
            return;
        }
     }

   long local_latency_us = (long)(GetMicrosecondCount() - tick_t0_us);
   MbLatencyProfileRecord(g_latency,local_latency_us,0);
   bool throttle_scan = (!signal.valid && (signal.reason_code == "WAIT_NEW_BAR" || signal.reason_code == "SCORE_BELOW_TRIGGER" || StringFind(signal.reason_code,"PAPER_IGNORE_") == 0));
   AppendDE30DecisionEvent(now,"SCAN",(signal.valid ? "READY" : "SKIP"),signal.reason_code,g_market.spread_points,signal.score,(signal.valid ? risk_plan.lots : 0.0),0,throttle_scan,60);
  }

void OnTradeTransaction(
   const MqlTradeTransaction &trans,
   const MqlTradeRequest &request,
   const MqlTradeResult &result
)
  {
   if(!MbTransactionMatchesLocalBot(g_state.symbol,g_state.magic,trans,request))
      return;

   MbExecutionTruthCapture("MICROBOT",g_state.symbol,trans,request,result);

   MbAppendTradeTransactionEvent(
      g_trade_transaction_log_path,
      g_state.symbol,
      g_state.magic,
      trans,
      request,
      result
   );

   if(trans.deal > 0)
     {
      if(MbProcessClosedDealFeedback(g_state.symbol,g_state.magic,(ulong)trans.deal,g_state))
         MbAppendHistoricalLearningObservation(g_state.symbol,g_state.magic,(ulong)trans.deal,g_state,"LIVE_DEAL_CLOSE");
      MbMlRuntimeBridgeAppendLiveDealLedger(g_ml_bridge,g_state.symbol,g_state.magic,(ulong)trans.deal);
     }
  }
