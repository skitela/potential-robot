#ifndef MB_RUNTIME_KERNEL_INCLUDED
#define MB_RUNTIME_KERNEL_INCLUDED

#include "MbRuntimeTypes.mqh"

string MbCanonicalSymbol(const string value)
  {
   string out = value;
   StringTrimLeft(out);
   StringTrimRight(out);
   StringToUpper(out);
   int dot_pos = StringFind(out,".");
   if(dot_pos > 0)
      out = StringSubstr(out,0,dot_pos);
   return out;
  }

MbRuntimeMode MbResolveRuntimeMode(const MbRuntimeState &state)
  {
   if(state.halt)
      return MB_MODE_BLOCKED;
   if(state.close_only)
      return MB_MODE_CLOSE_ONLY;
   if(state.caution_mode)
      return MB_MODE_CAUTION;
   return MB_MODE_READY;
  }

void MbRuntimeOnTimer(MbRuntimeState &state)
  {
   state.last_timer_at = TimeCurrent();
   state.timer_cycles++;
   state.mode = MbResolveRuntimeMode(state);
  }

void MbRuntimeOnTick(MbRuntimeState &state)
  {
   state.last_tick_at = TimeCurrent();
   state.ticks_seen++;
   state.mode = MbResolveRuntimeMode(state);
  }

bool MbVerifyChartSymbol(const string expected_symbol)
  {
   string chart_symbol = Symbol();
   string expected_canonical = MbCanonicalSymbol(expected_symbol);
   string chart_canonical = MbCanonicalSymbol(chart_symbol);
   if(chart_canonical == expected_canonical)
      return true;

   string chart_upper = chart_symbol;
   StringToUpper(chart_upper);
   string qdm_prefix = expected_canonical + "_QDM_";
   if(StringFind(chart_upper,qdm_prefix) == 0)
      return true;

   return false;
  }

#endif
