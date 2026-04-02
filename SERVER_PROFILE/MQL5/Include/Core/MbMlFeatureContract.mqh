#ifndef MB_ML_FEATURE_CONTRACT_INCLUDED
#define MB_ML_FEATURE_CONTRACT_INCLUDED

#define MB_GLOBAL_FEATURE_COUNT 29
#define MB_LOCAL_FEATURE_COUNT  25

void MbFillGlobalFeatureNames(string &names[])
{
   ArrayResize(names, MB_GLOBAL_FEATURE_COUNT);
   names[0]  = "symbol_alias";
   names[1]  = "setup_type";
   names[2]  = "side_normalized";
   names[3]  = "market_regime";
   names[4]  = "spread_regime";
   names[5]  = "execution_regime";
   names[6]  = "confidence_bucket";
   names[7]  = "score";
   names[8]  = "confidence_score";
   names[9]  = "spread_points";
   names[10] = "risk_multiplier";
   names[11] = "lots";
   names[12] = "candle_score";
   names[13] = "renko_score";
   names[14] = "renko_run_length";
   names[15] = "renko_reversal_flag";
   names[16] = "runtime_latency_us";
   names[17] = "server_operational_ping_ms";
   names[18] = "server_terminal_ping_ms";
   names[19] = "server_local_latency_us_avg";
   names[20] = "server_local_latency_us_max";
   names[21] = "server_ping_contract_enabled";
   names[22] = "qdm_tick_count";
   names[23] = "qdm_spread_mean";
   names[24] = "qdm_spread_max";
   names[25] = "qdm_mid_range_1m";
   names[26] = "qdm_mid_return_1m";
   names[27] = "qdm_data_present";
   names[28] = "pretrade_edge_estimate_pln";
}

void MbFillLocalFeatureNames(string &names[])
{
   ArrayResize(names, MB_LOCAL_FEATURE_COUNT);
   names[0]  = "setup_type";
   names[1]  = "side_normalized";
   names[2]  = "market_regime";
   names[3]  = "spread_regime";
   names[4]  = "execution_regime";
   names[5]  = "confidence_bucket";
   names[6]  = "score";
   names[7]  = "confidence_score";
   names[8]  = "spread_points";
   names[9]  = "risk_multiplier";
   names[10] = "lots";
   names[11] = "candle_score";
   names[12] = "renko_score";
   names[13] = "renko_run_length";
   names[14] = "renko_reversal_flag";
   names[15] = "runtime_latency_us";
   names[16] = "server_operational_ping_ms";
   names[17] = "server_terminal_ping_ms";
   names[18] = "server_local_latency_us_avg";
   names[19] = "server_local_latency_us_max";
   names[20] = "server_ping_contract_enabled";
   names[21] = "qdm_tick_count";
   names[22] = "qdm_spread_mean";
   names[23] = "qdm_spread_max";
   names[24] = "teacher_global_score";
}

#endif
