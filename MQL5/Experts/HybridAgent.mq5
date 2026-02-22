//+------------------------------------------------------------------+
//|                                                  HybridAgent.mq5 |
//|                                     Agent wykonawczy dla MQL5    |
//|                                     https://github.com/gemini    |
//+------------------------------------------------------------------+
#property copyright "Gemini"
#property link      "https://github.com/gemini"
#property version   "1.10"
#property description "Agent hybrydowy - część wykonawcza w MQL5. Komunikuje się z mózgiem w Pythonie."

// Dołączamy nasz most komunikacyjny ZMQ
#include <zeromq_bridge.mqh>

/*
 KRYTYCZNA ZALEŻNOŚĆ: PONIŻSZA BIBLIOTEKA MUSI ZOSTAĆ POBRANA RĘCZNIE
 Link: https://github.com/xefino/mql5-json
 Plik 'Json.mqh' należy umieścić w katalogu 'MQL5/Include/Json/'.
*/
#include <Json/Json.mqh>


// --- Parametry wejściowe Experta ---
input string InpPythonHost = "127.0.0.1"; // Adres IP, na którym działa serwer Pythona
input int    InpDataPort   = 5555;        // Port do wysyłania danych do Pythona
input int    InpCmdPort    = 5556;        // Port do odbierania komend od Pythona
input uint   InpTimerSec   = 1;           // Interwał timera w sekundach (P0: EventSetTimer uses seconds)

// Zmienna globalna do przechowywania nazwy symbolu
string G_Symbol;

//+------------------------------------------------------------------+
//| Funkcja inicjalizacji Experta                                    |
//+------------------------------------------------------------------+
int OnInit()
{
  Print("Inicjalizacja Agenta Hybrydowego...");
  
  // 1. Inicjalizuj most ZMQ
  if(!Zmq_Init(InpPythonHost, InpDataPort, InpCmdPort))
  {
    Alert("BŁĄD KRYTYCZNY: Nie udało się zainicjalizować mostu ZMQ. Sprawdź logi.");
    return(INIT_FAILED);
  }
  
  // 2. Ustaw timer (P0: EventSetTimer uses seconds)
  if(!EventSetTimer(InpTimerSec))
  {
     Alert("BŁĄD KRYTYCZNY: Nie udało się ustawić timera. Agent nie będzie działać.");
     Zmq_Deinit(); // Posprzątaj po ZMQ
     return(INIT_FAILED);
  }
  
  // 3. Zapisz nazwę symbolu
  G_Symbol = _Symbol;
  
  Print("Agent Hybrydowy zainicjalizowany pomyślnie na symbolu ", G_Symbol);
  Print("Timer ustawiony na ", InpTimerSec, " s.");
  return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Funkcja deinicjalizacji Experta                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
  Print("Deinicjalizacja Agenta Hybrydowego, powód: ", reason);
  
  // 1. Wyłącz timer
  EventKillTimer();
  
  // 2. Zamknij most ZMQ
  Zmq_Deinit();
  
  Print("Zasoby zwolnione.");
}

//+------------------------------------------------------------------+
//| Funkcja obsługi zdarzeń timera                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
  // --- Krok 1: Wysyłanie danych do Pythona ---
  SendTickData();
  SendBarData();
  
  // --- Krok 2: Odbieranie i przetwarzanie komend z Pythona ---
  ProcessCommands();
}

//+------------------------------------------------------------------+
//| Wysyła dane o ostatnim zamkniętym barze M5 do Pythona            |
//+------------------------------------------------------------------+
void SendBarData()
{
  static datetime last_bar_time = 0;
  MqlRates rates[];
  
  // Pobieramy ostatni zamknięty bar (indeks 1)
  if(CopyRates(G_Symbol, PERIOD_M5, 1, 1, rates) > 0)
  {
    if(rates[0].time > last_bar_time)
    {
      string json = StringFormat(
        "{\"type\":\"BAR\", \"symbol\":\"%s\", \"timeframe\":\"M5\", \"time\":%d, \"open\":%.5f, \"high\":%.5f, \"low\":%.5f, \"close\":%.5f, \"volume\":%d}",
        G_Symbol,
        rates[0].time,
        rates[0].open,
        rates[0].high,
        rates[0].low,
        rates[0].close,
        (int)rates[0].tick_volume
      );
      
      if(Zmq_SendData(json))
      {
        last_bar_time = rates[0].time;
      }
    }
  }
}

//+------------------------------------------------------------------+
//| Wysyła ostatni tick do Pythona                                   |
//+------------------------------------------------------------------+
void SendTickData()
{
  MqlTick tick;
  if(SymbolInfoTick(G_Symbol, tick))
  {
    // Budujemy string JSON
    string json = StringFormat(
      "{\"type\":\"TICK\", \"symbol\":\"%s\", \"timestamp_ms\":%d, \"bid\":%.5f, \"ask\":%.5f, \"volume\":%d}",
      G_Symbol,
      tick.time_msc,
      tick.bid,
      tick.ask,
      (int)tick.volume
    );
    
    // Wysyłamy dane przez most
    if(!Zmq_SendData(json))
    {
      // Logujemy błąd tylko raz na jakiś czas, aby nie zalać logów
      static ulong last_error_time = 0;
      if(GetTickCount() - last_error_time > 5000)
      {
        Print("Błąd wysyłania danych tick do Pythona.");
        last_error_time = GetTickCount();
      }
    }
  }
}

//+------------------------------------------------------------------+
//| Odbiera i przetwarza komendy z Pythona                           |
//+------------------------------------------------------------------+
void ProcessCommands()
{
  string command_json;
  // Sprawdzamy, czy w kolejce jest jakaś komenda
  if(Zmq_ReceiveCommand(command_json))
  {
    Print("Odebrano komendę z Pythona: ", command_json);
    
    // Parsujemy otrzymany JSON
    Json json;
    if(json.Parse(command_json))
    {
      string action = json.Get("action");
      if(action == "TRADE")
      {
        Json payload = json.GetNode("payload");
        if(payload.IsObject())
        {
          string signal = payload.Get("signal");
          string symbol = payload.Get("symbol");
          double volume = payload.Get("volume");
          double sl_price = payload.Get("sl_price");
          double tp_price = payload.Get("tp_price");
          long   magic = payload.Get("magic");
          string comment = payload.Get("comment");

          ExecuteTrade(signal, symbol, volume, sl_price, tp_price, (int)magic, comment);
        }
      }
    }
    else
    {
      Print("Błąd parsowania komendy JSON: ", command_json);
    }
  }
}

//+------------------------------------------------------------------+
//| Wykonuje zlecenie transakcyjne na podstawie komendy              |
//+------------------------------------------------------------------+
void ExecuteTrade(string signal, string symbol, double volume, double sl_price, double tp_price, int magic, string comment)
{
  // Sprawdzenie poprawności symbolu (czy na pewno ten, na którym działa EA)
  if(symbol != G_Symbol)
  {
    Print("Odebrano komendę dla innego symbolu: ", symbol, ". Agent działa na: ", G_Symbol);
    return;
  }

  MqlTradeRequest request={0};
  MqlTradeResult  result={0};
  
  ENUM_ORDER_TYPE order_type;
  double price;

  // Ustawienie typu zlecenia i ceny
  if(signal == "BUY")
  {
    order_type = ORDER_TYPE_BUY;
    price = SymbolInfoDouble(symbol, SYMBOL_ASK);
  }
  else if(signal == "SELL")
  {
    order_type = ORDER_TYPE_SELL;
    price = SymbolInfoDouble(symbol, SYMBOL_BID);
  }
  else
  {
    Print("Nieznany typ sygnału w komendzie: ", signal);
    return;
  }
  
  if(price <= 0)
  {
    Print("Nie udało się pobrać aktualnej ceny dla ", symbol);
    return;
  }

  // Wypełnienie struktury zlecenia
  request.action   = TRADE_ACTION_DEAL;
  request.symbol   = symbol;
  request.volume   = volume;
  request.price    = price;
  request.sl       = sl_price;
  request.tp       = tp_price;
  request.magic    = magic;
  request.comment  = comment;
  request.type     = order_type;
  request.type_filling = ORDER_FILLING_FOK; // Fill or Kill
  request.deviation  = 10; // Slippage w punktach

  Print("Wysyłanie zlecenia: ", signal, " ", volume, " lota ", symbol, " @ ", price, " SL:", sl_price, " TP:", tp_price);

  // Wysłanie zlecenia
  if(!OrderSend(request, result))
  {
    Print("Błąd wysyłania zlecenia: ", GetLastError(), " - ", result.comment);
  }
  else
  {
    Print("Zlecenie wysłane pomyślnie. Ticket: ", result.order);
  }
}

//+------------------------------------------------------------------+
// Funkcja OnTick() jest celowo pusta. Cała logika jest w OnTimer(),
// aby uniknąć nadmiernego obciążenia przy bardzo dużej liczbie ticków
// i zapewnić stały, regularny rytm pracy agenta.
//+------------------------------------------------------------------+
void OnTick()
{
}
//+------------------------------------------------------------------+
