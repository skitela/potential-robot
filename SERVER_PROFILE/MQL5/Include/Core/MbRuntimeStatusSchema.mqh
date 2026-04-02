#ifndef MB_RUNTIME_STATUS_SCHEMA_INCLUDED
#define MB_RUNTIME_STATUS_SCHEMA_INCLUDED

#define MB_STATUS_RUNNING_LEARNING "MB_STATUS_RUNNING_LEARNING"
#define MB_STATUS_RUNNING_OBSERVING "MB_STATUS_RUNNING_OBSERVING"
#define MB_STATUS_LEARNING_STALLED "MB_STATUS_LEARNING_STALLED"
#define MB_STATUS_MODEL_MISSING "MB_STATUS_MODEL_MISSING"
#define MB_STATUS_CONTRACT_MISSING "MB_STATUS_CONTRACT_MISSING"
#define MB_STATUS_MARKET_IDLE "MB_STATUS_MARKET_IDLE"
#define MB_STATUS_PAPER_POSITION_STUCK "MB_STATUS_PAPER_POSITION_STUCK"
#define MB_STATUS_RUNTIME_DOWN "MB_STATUS_RUNTIME_DOWN"

string MbNormalizeRuntimeStatus(const string raw_status)
  {
   if(raw_status == MB_STATUS_RUNNING_LEARNING ||
      raw_status == MB_STATUS_RUNNING_OBSERVING ||
      raw_status == MB_STATUS_LEARNING_STALLED ||
      raw_status == MB_STATUS_MODEL_MISSING ||
      raw_status == MB_STATUS_CONTRACT_MISSING ||
      raw_status == MB_STATUS_MARKET_IDLE ||
      raw_status == MB_STATUS_PAPER_POSITION_STUCK ||
      raw_status == MB_STATUS_RUNTIME_DOWN)
      return raw_status;

   return MB_STATUS_RUNNING_OBSERVING;
  }

string MbResolveRuntimeStatus(
   const string last_stage,
   const string last_reason_code,
   const bool contract_present,
   const bool local_model_available,
   const bool paper_position_open
)
  {
   if(!contract_present)
      return MB_STATUS_CONTRACT_MISSING;

   if(!local_model_available)
      return MB_STATUS_MODEL_MISSING;

   if(last_stage == "LESSON_WRITE" || last_stage == "KNOWLEDGE_WRITE" || last_stage == "EXECUTION_TRUTH_CLOSE")
      return MB_STATUS_RUNNING_LEARNING;

   if(paper_position_open)
      return MB_STATUS_PAPER_POSITION_STUCK;

   if(last_reason_code == "WAIT_NEW_BAR" ||
      last_reason_code == "MARKET_IDLE" ||
      last_reason_code == "OUTSIDE_TRADE_WINDOW")
      return MB_STATUS_MARKET_IDLE;

   if(last_reason_code == "SCORE_BELOW_TRIGGER" ||
      last_reason_code == "LOW_CONFIDENCE" ||
      last_reason_code == "CONTEXT_LOW_CONFIDENCE" ||
      last_reason_code == "ML_STUDENT_GATE_BLOCK")
      return MB_STATUS_LEARNING_STALLED;

   if(last_stage == "BOOTSTRAP" || last_stage == "TIMER" || last_stage == "SCAN" || last_stage == "EVALUATED")
      return MB_STATUS_RUNNING_OBSERVING;

   return MB_STATUS_RUNNING_OBSERVING;
  }

#endif
