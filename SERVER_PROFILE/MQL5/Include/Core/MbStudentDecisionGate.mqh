#ifndef MB_STUDENT_DECISION_GATE_INCLUDED
#define MB_STUDENT_DECISION_GATE_INCLUDED

struct MbDecisionThresholds
{
   double min_gate_probability;
   double min_decision_score_pln;
   double max_spread_points;
   double max_server_ping_ms;
   double max_server_latency_us_avg;
};

void MbSetDefaultDecisionThresholds(MbDecisionThresholds &cfg)
{
   cfg.min_gate_probability      = 0.53;
   cfg.min_decision_score_pln    = 0.00;
   cfg.max_spread_points         = 999.0;
   cfg.max_server_ping_ms        = 35.0;
   cfg.max_server_latency_us_avg = 250000.0;
}

bool MbAllowStudentTrade(
   const double teacher_score,
   const double student_score,
   const double expected_edge_pln,
   const double decision_score_pln,
   const double spread_points,
   const double server_ping_ms,
   const double server_latency_us_avg,
   const bool   outcome_ready,
   const MbDecisionThresholds &cfg
)
{
   if(expected_edge_pln <= 0.0) return(false);
   if(decision_score_pln < cfg.min_decision_score_pln) return(false);
   if(spread_points <= 0.0 || spread_points > cfg.max_spread_points) return(false);
   if(server_ping_ms > cfg.max_server_ping_ms) return(false);
   if(server_latency_us_avg > cfg.max_server_latency_us_avg) return(false);

   // Gdy outcome nie jest jeszcze dojrzały, lokalny student nie może być gorszy od nauczyciela.
   if(!outcome_ready && student_score < teacher_score) return(false);

   return(true);
}

#endif
