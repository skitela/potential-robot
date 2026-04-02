#ifndef MB_LEARNING_POLICY_INCLUDED
#define MB_LEARNING_POLICY_INCLUDED

double MbLearningConfidenceFromSamples(const int samples)
  {
   if(samples <= 0)
      return 0.0;
   return MathMax(0.0,MathMin(1.0,(double)samples / 12.0));
  }

int MbLearningMinSamplesForBias()
  {
   return 3;
  }

int MbLearningMinSamplesForRisk()
  {
   return 5;
  }

double MbLearningBiasWinStep(const double confidence)
  {
   return 0.012 * MathMax(0.25,confidence);
  }

double MbLearningBiasLossStep(const double confidence)
  {
   return 0.016 * MathMax(0.25,confidence);
  }

double MbLearningRiskWinStep(const double confidence)
  {
   return 0.008 * MathMax(0.25,confidence);
  }

double MbLearningRiskLossStep(const double confidence)
  {
   return 0.012 * MathMax(0.25,confidence);
  }

#endif
