#define MB_TESTER_OPTIMIZATION_INPUTS_INCLUDED

sinput double InpTesterSafetyMarginScale = 1.00;
sinput double InpTesterEdgeRequirementScale = 1.00;
sinput double InpTesterTimeStopScale = 1.00;

double MbClampTesterOptimizationScale(const double value)
  {
   if(!MathIsValidNumber(value))
      return 1.0;
   return MathMax(0.25,MathMin(3.0,value));
  }

bool MbIsTesterOptimizationInputContext()
  {
   return (MQLInfoInteger(MQL_TESTER) != 0 || MQLInfoInteger(MQL_OPTIMIZATION) != 0);
  }

double MbResolveTesterSafetyMarginScale()
  {
   if(!MbIsTesterOptimizationInputContext())
      return 1.0;
   return MbClampTesterOptimizationScale(InpTesterSafetyMarginScale);
  }

double MbResolveTesterEdgeRequirementScale()
  {
   if(!MbIsTesterOptimizationInputContext())
      return 1.0;
   return MbClampTesterOptimizationScale(InpTesterEdgeRequirementScale);
  }

double MbResolveTesterTimeStopScale()
  {
   if(!MbIsTesterOptimizationInputContext())
      return 1.0;
   return MbClampTesterOptimizationScale(InpTesterTimeStopScale);
  }

bool MbConfigureCommonOptimizationRanges()
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION) == 0)
      return false;

   bool ok = true;
   ResetLastError();
   ok = (ParameterSetRange("InpTesterSafetyMarginScale",true,InpTesterSafetyMarginScale,0.50,0.25,2.00) && ok);
   ok = (ParameterSetRange("InpTesterEdgeRequirementScale",true,InpTesterEdgeRequirementScale,0.75,0.25,2.25) && ok);
   ok = (ParameterSetRange("InpTesterTimeStopScale",true,InpTesterTimeStopScale,0.75,0.25,2.25) && ok);
   return ok;
  }
