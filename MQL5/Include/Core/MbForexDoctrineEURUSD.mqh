#ifndef MB_FOREX_DOCTRINE_EURUSD_INCLUDED
#define MB_FOREX_DOCTRINE_EURUSD_INCLUDED

#include "MbRuntimeTypes.mqh"

struct MbEurUsdForexDoctrine
  {
   string phase_code;
   bool core_liquidity;
   bool thin_liquidity;
   bool transition_risk;
   bool allow_new_experiment;
   double breakout_tax;
   double trend_tax;
   double rejection_tax;
   double confidence_cap;
   double risk_cap;
   string doctrine_code;
   string doctrine_detail;
  };

void MbEurUsdForexDoctrineReset(MbEurUsdForexDoctrine &out)
  {
   out.phase_code = "UNKNOWN";
   out.core_liquidity = false;
   out.thin_liquidity = false;
   out.transition_risk = false;
   out.allow_new_experiment = true;
   out.breakout_tax = 0.0;
   out.trend_tax = 0.0;
   out.rejection_tax = 0.0;
   out.confidence_cap = 1.0;
   out.risk_cap = 1.0;
   out.doctrine_code = "FOREX_NEUTRAL";
   out.doctrine_detail = "neutral";
  }

string MbResolveEURUSDForexPhase(const datetime now_ts)
  {
   MqlDateTime tm;
   TimeToStruct(now_ts,tm);
   int h = tm.hour;

   if(h >= 22 || h <= 0)
      return "ROLLOVER_RISK";
   if(h >= 1 && h <= 6)
      return "ASIA_THIN";
   if(h == 7)
      return "PRE_LONDON";
   if(h == 8)
      return "EUROPE_OPEN";
   if(h >= 9 && h <= 11)
      return "FX_MAIN_CORE";
   if(h >= 12 && h <= 14)
      return "POST_CORE";
   if(h >= 15 && h <= 17)
      return "US_OVERLAP";
   if(h >= 18 && h <= 21)
      return "NY_LATE";

   return "OFF_CORE";
  }

void MbAssessEURUSDForexDoctrine(
   const datetime now_ts,
   const string setup_type,
   const string market_regime,
   const string spread_regime,
   const string execution_regime,
   MbEurUsdForexDoctrine &out
)
  {
   MbEurUsdForexDoctrineReset(out);
   out.phase_code = MbResolveEURUSDForexPhase(now_ts);

   bool trend_like = (setup_type == "SETUP_TREND" || setup_type == "SETUP_PULLBACK");
   bool breakout_like = (setup_type == "SETUP_BREAKOUT");
   bool rejection_like = (setup_type == "SETUP_REJECTION");

   if(out.phase_code == "FX_MAIN_CORE" || out.phase_code == "US_OVERLAP")
      out.core_liquidity = true;

   if(out.phase_code == "ROLLOVER_RISK" || out.phase_code == "ASIA_THIN" || out.phase_code == "OFF_CORE")
      out.thin_liquidity = true;

   if(out.phase_code == "PRE_LONDON" || out.phase_code == "EUROPE_OPEN" || out.phase_code == "POST_CORE" || out.phase_code == "NY_LATE")
      out.transition_risk = true;

   if(spread_regime == "BAD" || execution_regime == "BAD")
     {
      out.allow_new_experiment = false;
      out.breakout_tax = 0.10;
      out.trend_tax = 0.08;
      out.rejection_tax = 0.04;
      out.confidence_cap = 0.82;
      out.risk_cap = 0.78;
      out.doctrine_code = "FOREX_BRUDNA_MIKROSTRUKTURA";
      out.doctrine_detail = "zly spread albo zla egzekucja; nowe strojenie i agresywne wejscia sa nieuczciwe poznawczo";
      return;
     }

   if(out.thin_liquidity)
     {
      out.allow_new_experiment = false;
      out.breakout_tax = 0.10;
      out.trend_tax = 0.08;
      out.rejection_tax = 0.03;
      out.confidence_cap = 0.86;
      out.risk_cap = 0.80;
      out.doctrine_code = "FOREX_CIENKA_PLYNNOSC";
      out.doctrine_detail = "poza rdzeniem EURUSD rynek zbyt latwo tworzy falszywe breakouty i brudne lekcje";
      return;
     }

   if(out.transition_risk)
     {
      out.allow_new_experiment = false;
      out.breakout_tax = 0.06;
      out.trend_tax = 0.04;
      out.rejection_tax = 0.02;
      out.confidence_cap = 0.92;
      out.risk_cap = 0.88;
      out.doctrine_code = "FOREX_OKNO_PRZEJSCIOWE";
      out.doctrine_detail = "faza przejscia sesji; obserwacja jest cenna, ale nowe eksperymenty sa zbyt podatne na szum";
      if(out.phase_code == "EUROPE_OPEN" && breakout_like && market_regime == "BREAKOUT")
        {
         out.allow_new_experiment = true;
         out.breakout_tax = 0.03;
         out.doctrine_code = "FOREX_OTWARCIE_EUROPEJSKIE";
         out.doctrine_detail = "pierwsza godzina po otwarciu Europy jest dopuszczalna, ale wymaga wyzszej dyscypliny";
        }
      return;
     }

   if(out.core_liquidity)
     {
      out.allow_new_experiment = true;
      out.doctrine_code = "FOREX_RDZEN_PLYNNOSCI";
      out.doctrine_detail = "rdzen plynnosci EURUSD; to najlepsze pole do nowych eksperymentow i czystych lekcji";

      if(rejection_like && market_regime == "BREAKOUT")
         out.rejection_tax = 0.05;
      if((trend_like || breakout_like) && market_regime == "CHAOS")
        {
         out.breakout_tax = 0.04;
         out.trend_tax = 0.04;
         out.doctrine_code = "FOREX_RDZEN_ALE_CHAOS";
         out.doctrine_detail = "plynnosc jest dobra, ale sam uklad rynku pozostaje rozchwiany";
        }
      return;
     }

   out.allow_new_experiment = false;
   out.breakout_tax = 0.05;
   out.trend_tax = 0.04;
   out.rejection_tax = 0.02;
   out.confidence_cap = 0.94;
   out.risk_cap = 0.90;
   out.doctrine_code = "FOREX_POZA_RDZENIEM";
   out.doctrine_detail = "rynek nie jest skrajnie zly, ale to nie jest najlepszy moment do nauki nowej polityki";
  }

bool MbCanStartEURUSDForexExperiment(
   const datetime now_ts,
   const MbRuntimeState &state,
   const string focus_setup_type,
   const string focus_market_regime,
   string &out_doctrine_code,
   string &out_doctrine_detail
)
  {
   string setup_type = focus_setup_type;
   string market_regime = focus_market_regime;
   if(setup_type == "" || setup_type == "NONE")
      setup_type = state.last_setup_type;
   if(market_regime == "" || market_regime == "UNKNOWN")
      market_regime = state.market_regime;

   MbEurUsdForexDoctrine doctrine;
   MbAssessEURUSDForexDoctrine(
      now_ts,
      setup_type,
      market_regime,
      state.spread_regime,
      state.execution_regime,
      doctrine
   );

   bool breakout_probe = (setup_type == "SETUP_BREAKOUT" || setup_type == "SETUP_PULLBACK");
   if(!doctrine.allow_new_experiment &&
      state.paper_mode_active &&
      doctrine.phase_code == "POST_CORE" &&
      state.spread_regime == "GOOD" &&
      state.execution_regime == "GOOD" &&
      breakout_probe)
     {
      doctrine.allow_new_experiment = true;
      doctrine.doctrine_code = "FOREX_POST_CORE_PAPER_PROBE";
      doctrine.doctrine_detail = "po rdzeniu Londynu wolno uruchomic tylko waski eksperyment paper dla breakoutu lub pullbacku przy czystej mikrostrukturze";
     }

   out_doctrine_code = doctrine.doctrine_code;
   out_doctrine_detail = StringFormat(
      "faza=%s;rynek=%s;spread=%s;egzekucja=%s;opis=%s",
      doctrine.phase_code,
      state.market_regime,
      state.spread_regime,
      state.execution_regime,
      doctrine.doctrine_detail
   );
   return doctrine.allow_new_experiment;
  }

#endif
