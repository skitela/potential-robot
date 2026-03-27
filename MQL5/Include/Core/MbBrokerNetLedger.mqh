#pragma once

struct MbBrokerNetLedgerRow
{
   string symbol_alias;
   long   ts;
   string side;
   double lots;

   double entry_price;
   double exit_price;

   double spread_points_entry;
   double spread_points_exit;
   double slippage_points;

   double gross_pln;
   double spread_cost_pln;
   double slippage_cost_pln;
   double commission_pln;
   double swap_pln;
   double extra_fee_pln;
   double net_pln;
};

bool MbBrokerNetOutcomeReady(const MbBrokerNetLedgerRow &row)
{
   return(MathIsValidNumber(row.net_pln));
}
