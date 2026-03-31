#ifndef MB_LEARNING_OUTCOME_CHAIN_INCLUDED
#define MB_LEARNING_OUTCOME_CHAIN_INCLUDED

#include "MbExecutionTruthFeed.mqh"
#include "MbLearningContext.mqh"
#include "MbMlRuntimeBridge.mqh"
#include "MbPaperTrading.mqh"

struct MbLearningOutcomeOpenResult
  {
   bool paper_opened;
   bool truth_open_written;
   bool paper_saved;
   string candidate_id;
   string request_comment;
   string reason_code;
  };

struct MbLearningOutcomeCloseResult
  {
   bool live_close_processed;
   bool truth_close_written;
   bool lesson_written;
   bool knowledge_written;
   bool knowledge_bridge_enabled;
   string chain_reason;
  };

void MbLearningOutcomeResetOpenResult(MbLearningOutcomeOpenResult &result)
  {
   result.paper_opened = false;
   result.truth_open_written = false;
   result.paper_saved = false;
   result.candidate_id = "";
   result.request_comment = "";
   result.reason_code = "";
  }

void MbLearningOutcomeResetCloseResult(MbLearningOutcomeCloseResult &result)
  {
   result.live_close_processed = false;
   result.truth_close_written = false;
   result.lesson_written = false;
   result.knowledge_written = false;
   result.knowledge_bridge_enabled = false;
   result.chain_reason = "";
  }

string MbLearningOutcomeBuildChainReason(const MbPaperPositionState &closed_paper,const string close_reason)
  {
   string chain_reason = close_reason;
   if(StringLen(closed_paper.candidate_id) > 0)
      chain_reason += "|CID=" + closed_paper.candidate_id;
   return chain_reason;
  }

bool MbLearningOutcomeHandlePaperOpen(
   MbPaperPositionState &paper_position,
   const string symbol_alias,
   const string runtime_symbol,
   const MbSignalDecision &signal,
   const double lots,
   const double entry_price,
   const double sl_price,
   const double tp_price,
   const MbExecutionCheck &exec_check,
   const MbMarketSnapshot &market,
   const datetime now_ts,
   const int hold_seconds,
   const bool enforce_paper_live_scope,
   MbLearningOutcomeOpenResult &result
)
  {
   MbLearningOutcomeResetOpenResult(result);
   result.candidate_id = MbPreTradeTruthBuildCandidateId(symbol_alias,now_ts,signal);
   result.request_comment = MbPreTradeTruthBuildRequestComment(result.candidate_id);

   result.paper_opened = MbPaperOpenPosition(
      paper_position,
      signal.side,
      lots,
      entry_price,
      sl_price,
      tp_price,
      market.spread_points,
      now_ts,
      hold_seconds,
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
      enforce_paper_live_scope,
      symbol_alias
   );

   if(result.paper_opened)
     {
      MbPaperPositionSetTruthContext(paper_position,result.candidate_id,result.request_comment);
      result.truth_open_written = MbExecutionTruthWritePaperOpen(
         "MICROBOT_PAPER",
         symbol_alias,
         runtime_symbol,
         result.candidate_id,
         signal.side,
         lots,
         entry_price,
         paper_position.entry_price,
         market.bid,
         market.ask,
         now_ts,
         result.request_comment
      );
      result.reason_code = "PAPER_POSITION_OPENED";
     }
   else
     {
      result.reason_code = paper_position.entry_reason;
      if(StringLen(result.reason_code) <= 0)
         result.reason_code = "PAPER_OPEN_REJECTED";
     }

   result.paper_saved = MbSavePaperPosition(symbol_alias,paper_position);
   return result.paper_opened;
  }

bool MbLearningOutcomeHandlePaperClose(
   const datetime now_ts,
   const string symbol_alias,
   const string runtime_symbol,
   MbMlRuntimeBridgeState &ml_bridge,
   const MbMarketSnapshot &market,
   const MbPaperPositionState &closed_paper,
   const double paper_pnl,
   const string paper_close_reason,
   MbLearningOutcomeCloseResult &result
)
  {
   MbLearningOutcomeResetCloseResult(result);
   string close_request_comment = closed_paper.request_comment;
   if(StringLen(close_request_comment) <= 0 && StringLen(closed_paper.candidate_id) > 0)
      close_request_comment = MbPreTradeTruthBuildRequestComment(closed_paper.candidate_id);

   result.chain_reason = MbLearningOutcomeBuildChainReason(closed_paper,paper_close_reason);
   result.truth_close_written = MbExecutionTruthWritePaperClose(
      "MICROBOT_PAPER",
      symbol_alias,
      runtime_symbol,
      closed_paper.candidate_id,
      closed_paper.side,
      closed_paper.lots,
      closed_paper.last_mark_price,
      closed_paper.last_mark_price,
      market.bid,
      market.ask,
      now_ts,
      close_request_comment,
      paper_close_reason,
      closed_paper.gross_pln,
      closed_paper.commission_pln,
      closed_paper.swap_pln,
      (closed_paper.slippage_cost_pln + closed_paper.extra_fee_pln),
      closed_paper.net_pln
   );
   result.lesson_written = MbAppendLearningObservationV2(
      symbol_alias,
      now_ts,
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
   result.knowledge_bridge_enabled = ml_bridge.enabled;
   result.knowledge_written = MbMlRuntimeBridgeAppendPaperLedger(
      ml_bridge,
      now_ts,
      symbol_alias,
      closed_paper,
      market,
      paper_pnl,
      paper_close_reason
   );
   return result.truth_close_written || result.lesson_written || result.knowledge_written;
  }

bool MbLearningOutcomeHandleLiveClose(
   MbMlRuntimeBridgeState &ml_bridge,
   const string symbol,
   const ulong magic,
   const ulong deal_ticket,
   MbRuntimeState &runtime_state,
   const bool truth_capture_written,
   MbLearningOutcomeCloseResult &result
)
  {
   MbLearningOutcomeResetCloseResult(result);
   result.live_close_processed = MbProcessClosedDealFeedback(symbol,magic,deal_ticket,runtime_state);
   result.truth_close_written = truth_capture_written;
   result.chain_reason = (truth_capture_written ? "LIVE_DEAL_CLOSE" : "LIVE_TRUTH_CAPTURE_FAIL");
   if(!result.live_close_processed)
      return false;

   result.lesson_written = MbAppendHistoricalLearningObservation(symbol,magic,deal_ticket,runtime_state,"LIVE_DEAL_CLOSE");
   result.knowledge_bridge_enabled = ml_bridge.enabled;
   result.knowledge_written = MbMlRuntimeBridgeAppendLiveDealLedger(ml_bridge,symbol,magic,deal_ticket);
   return true;
  }

#endif
