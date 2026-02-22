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
input uint   InpPythonTimeoutSec = 180;   // Po ilu sekundach bez komendy z Pythona aktywować tryb fail-safe

// Zmienna globalna do przechowywania nazwy symbolu
string G_Symbol;

// Zmienne globalne dla mechanizmu fail-safe
ulong  G_LastPythonMessageTime = 0;
bool   G_IsFailSafeActive = false;

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
  
  // 3. Zapisz nazwę symbolu i czas startu
  G_Symbol = _Symbol;
  G_LastPythonMessageTime = GetTickCount(); // Ustawiamy początkowy czas
  
  Print("Agent Hybrydowy zainicjalizowany pomyślnie na symbolu ", G_Symbol);
  Print("Timer ustawiony na ", InpTimerSec, " s.");
  Print("Timeout dla Pythona ustawiony na ", InpPythonTimeoutSec, " s.");
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
  // --- Krok 0: Sprawdzenie trybu Fail-Safe ---
  if(!G_IsFailSafeActive && InpPythonTimeoutSec > 0)
  {
    ulong elapsed_ms = GetTickCount() - G_LastPythonMessageTime;
    if(elapsed_ms > (InpPythonTimeoutSec * 1000))
    {
      G_IsFailSafeActive = true;
      Alert("FAIL-SAFE AKTYWOWANY! Utracono połączenie z Pythonem (timeout > ", (string)InpPythonTimeoutSec, "s). Zamykanie wszystkich pozycji.");
      CloseAllOpenPositionsByMagic((int)PositionGetInteger(POSITION_MAGIC), "FAIL_SAFE_TIMEOUT");
    }
  }

  // --- Krok 1: Wysyłanie danych do Pythona ---
  if(!G_IsFailSafeActive)
  {
    SendTickData();
    SendBarData();
  }
  
  // --- Krok 2: Odbieranie i przetwarzanie komend z Pythona ---
  // W trybie fail-safe nie przetwarzamy nowych komend
  if(!G_IsFailSafeActive)
  {
    ProcessCommands();
  }
}

//+------------------------------------------------------------------+
//| Zamyka wszystkie otwarte pozycje dla danego numeru magic         |
//+------------------------------------------------------------------+
void CloseAllOpenPositionsByMagic(int magic_to_close, string reason)
{
  for(int i = PositionsTotal() - 1; i >= 0; i--)
  {
    ulong pos_ticket = PositionGetTicket(i);
    if(pos_ticket > 0)
    {
      if(PositionGetInteger(POSITION_MAGIC) == magic_to_close)
      {
        MqlTradeRequest request={0};
        MqlTradeResult  result={0};
        
        request.action = TRADE_ACTION_DEAL;
        request.symbol = PositionGetString(POSITION_SYMBOL);
        request.volume = PositionGetDouble(POSITION_VOLUME);
        request.magic = magic_to_close;
        request.comment = reason;
        request.type_filling = ORDER_FILLING_IOC;
        request.deviation = 20; // Większy slippage dla zamknięć awaryjnych

        if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
          request.type = ORDER_TYPE_SELL;
          request.price = SymbolInfoDouble(request.symbol, SYMBOL_BID);
        }
        else
        {
          request.type = ORDER_TYPE_BUY;
          request.price = SymbolInfoDouble(request.symbol, SYMBOL_ASK);
        }
        
        if(request.price > 0)
        {
          Print("FAIL-SAFE: Zamykanie pozycji #", (string)pos_ticket, " ", (string)request.volume, " ", request.symbol);
          OrderSend(request, result);
        }
        else
        {
          Print("FAIL-SAFE: Nie udało się pobrać ceny do zamknięcia pozycji #", (string)pos_ticket);
        }
      }
    }
  }
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
  // Sprawdzamy, czy w kolejce jest jakieś żądanie
  if(Zmq_ReceiveRequest(command_json))
  {
    G_LastPythonMessageTime = GetTickCount(); // Zresetuj czas ostatniej komendy
    // Nie logujemy heartbeatów, żeby nie zaśmiecać logów
    if(StringFind(command_json, "\"action\":\"HEARTBEAT\"") == -1)
    {
      Print("Odebrano żądanie z Pythona: ", command_json);
    }
    
    // Parsujemy otrzymany JSON
    Json json;
    if(json.Parse(command_json))
    {
      string action = json.Get("action");
      string msg_id = json.Get("msg_id"); // Pobieramy ID wiadomości
      string contract_v = json.Get("__v");
      if(contract_v == "")
      {
        Print("WARN: Missing protocol version __v in command msg_id=", msg_id);
      }
      else if(contract_v != "1.0")
      {
        Print("WARN: Protocol version mismatch __v=", contract_v, " expected=1.0 msg_id=", msg_id);
      }
      
      if(action == "HEARTBEAT")
      {
        string reply = StringFormat("{\"status\":\"OK\", \"correlation_id\":\"%s\", \"action\":\"HEARTBEAT_REPLY\"}", msg_id);
        Zmq_SendReply(reply);
      }
      else if(action == "TRADE")
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

          ExecuteTrade(signal, symbol, volume, sl_price, tp_price, (int)magic, comment, msg_id);
        }
        else
        {
          string reply = StringFormat("{\"status\":\"ERROR\", \"correlation_id\":\"%s\", \"error\":\"Payload is not a valid object\"}", msg_id);
          Zmq_SendReply(reply);
        }
      }
      else
      {
         string reply = StringFormat("{\"status\":\"ERROR\", \"correlation_id\":\"%s\", \"error\":\"Unknown action specified\"}", msg_id);
         Zmq_SendReply(reply);
      }
    }
    else
    {
      string bad_reply_msg_id = "unknown";
      int pos = StringFind(command_json, "\"msg_id\":\"");
      if(pos != -1)
      {
        int end_pos = StringFind(command_json, "\"", pos + 10);
        if(end_pos != -1) bad_reply_msg_id = StringSubstr(command_json, pos + 10, end_pos - (pos + 10));
      }
      Print("Błąd parsowania komendy JSON: ", command_json);
      string reply = StringFormat("{\"status\":\"ERROR\", \"correlation_id\":\"%s\", \"error\":\"Failed to parse command JSON\"}", bad_reply_msg_id);
      Zmq_SendReply(reply);
    }
  }
}

//+------------------------------------------------------------------+
//| Wykonuje zlecenie transakcyjne na podstawie komendy              |
//+------------------------------------------------------------------+
void ExecuteTrade(string signal, string symbol, double volume, double sl_price, double tp_price, int magic, string comment, string msg_id)
{
  // --- GUARD: Sprawdź, czy nie jest aktywny tryb fail-safe ---
  if(G_IsFailSafeActive)
  {
    Print("Odrzucono zlecenie (msg_id: ", msg_id, "): Aktywny tryb FAIL-SAFE.");
    string nack_json = StringFormat(
      "{\"status\":\"REJECTED\", \"correlation_id\":\"%s\", \"retcode\":%d, \"retcode_str\":\"%s\", \"comment\":\"Rejected due to active FAIL-SAFE mode.\"}",
      msg_id,
      50002, // Custom retcode for fail-safe active
      "CUSTOM_RETCODE_FAIL_SAFE_ACTIVE"
    );
    Zmq_SendReply(nack_json);
    return;
  }

  // Sprawdzenie poprawności symbolu (czy na pewno ten, na którym działa EA)
  if(symbol != G_Symbol)
  {
    Print("Odebrano komendę dla innego symbolu: ", symbol, ". Agent działa na: ", G_Symbol);
    string nack_json = StringFormat("{\"status\":\"REJECTED\", \"correlation_id\":\"%s\", \"error\":\"Invalid symbol. EA runs on %s, command was for %s.\"}", msg_id, G_Symbol, symbol);
    Zmq_SendReply(nack_json);
    return;
  }

  // --- GUARD: Sprawdź, czy już nie ma pozycji dla tego symbolu i magic ---
  for(int i = PositionsTotal() - 1; i >= 0; i--)
  {
    ulong pos_ticket = PositionGetTicket(i);
    if(pos_ticket > 0)
    {
      if(PositionGetString(POSITION_SYMBOL) == symbol && PositionGetInteger(POSITION_MAGIC) == magic)
      {
        Print("Odrzucono zlecenie (msg_id: ", msg_id, "): Istnieje już pozycja dla ", symbol, " z tym samym numerem magic.");
        string nack_json = StringFormat(
          "{\"status\":\"REJECTED\", \"correlation_id\":\"%s\", \"retcode\":%d, \"retcode_str\":\"%s\", \"comment\":\"Position already exists for this magic number on the specified symbol.\"}",
          msg_id,
          50001, // Custom retcode for duplicate position
          "CUSTOM_RETCODE_DUPLICATE_POSITION"
        );
        Zmq_SendReply(nack_json);
        return; // Zakończ, aby nie otwierać nowej pozycji
      }
    }
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
    string nack_json = StringFormat("{\"status\":\"REJECTED\", \"correlation_id\":\"%s\", \"error\":\"Unknown signal type in command\"}", msg_id);
    Zmq_SendReply(nack_json);
    return;
  }
  
  if(price <= 0)
  {
    Print("Nie udało się pobrać aktualnej ceny dla ", symbol);
    string nack_json = StringFormat("{\"status\":\"REJECTED\", \"correlation_id\":\"%s\", \"error\":\"Could not fetch current price for symbol\"}", msg_id);
    Zmq_SendReply(nack_json);
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

  // Wysłanie zlecenia i obsługa wyniku
  if(!OrderSend(request, result))
  {
    Print("Błąd wysyłania zlecenia: ", GetLastError(), " - ", result.comment);
  }
  
  // --- KROK KRYTYCZNY: Wysłanie potwierdzenia ACK/NACK do Pythona ---
  string ack_json = StringFormat(
    "{\"status\":\"PROCESSED\", \"correlation_id\":\"%s\", \"details\":{\"retcode\":%d, \"retcode_str\":\"%s\", \"order\":%d, \"deal\":%d, \"comment\":\"%s\", \"symbol\":\"%s\"}}",
    msg_id,
    result.retcode,
    GetRetcodeString(result.retcode),
    (int)result.order,
    (int)result.deal,
    result.comment,
    symbol
  );
  
  Zmq_SendReply(ack_json);
}

//+------------------------------------------------------------------+
//| Zwraca tekstową reprezentację kodu wyniku transakcji (retcode)   |
//+------------------------------------------------------------------+
string GetRetcodeString(uint retcode)
{
  switch(retcode)
  {
    case 10004: return "TRADE_RETCODE_REQUOTE";
    case 10006: return "TRADE_RETCODE_REJECT";
    case 10007: return "TRADE_RETCODE_CANCEL";
    case 10008: return "TRADE_RETCODE_PLACED";
    case 10009: return "TRADE_RETCODE_DONE";
    case 10010: return "TRADE_RETCODE_DONE_PARTIAL";
    case 10011: return "TRADE_RETCODE_ERROR";
    case 10012: return "TRADE_RETCODE_TIMEOUT";
    case 10013: return "TRADE_RETCODE_INVALID";
    case 10014: return "TRADE_RETCODE_INVALID_VOLUME";
    case 10015: return "TRADE_RETCODE_INVALID_PRICE";
    case 10016: return "TRADE_RETCODE_INVALID_STOPS";
    case 10017: return "TRADE_RETCODE_TRADE_DISABLED";
    case 10018: return "TRADE_RETCODE_MARKET_CLOSED";
    case 10019: return "TRADE_RETCODE_NO_MONEY";
    case 10020: return "TRADE_RETCODE_PRICE_CHANGED";
    case 10021: return "TRADE_RETCODE_PRICE_OFF";
    case 10022: return "TRADE_RETCODE_INVALID_EXPIRATION";
    case 10023: return "TRADE_RETCODE_ORDER_CHANGED";
    case 10024: return "TRADE_RETCODE_TOO_MANY_REQUESTS";
    case 10025: return "TRADE_RETCODE_NO_CHANGES";
    case 10026: return "TRADE_RETCODE_SERVER_DISABLES_AT";
    case 10027: return "TRADE_RETCODE_CLIENT_DISABLES_AT";
    case 10028: return "TRADE_RETCODE_LOCKED";
    case 10029: return "TRADE_RETCODE_FROZEN";
    case 10030: return "TRADE_RETCODE_INVALID_FILL";
    case 10031: return "TRADE_RETCODE_CONNECTION";
    case 10032: return "TRADE_RETCODE_ONLY_REAL";
    case 10033: return "TRADE_RETCODE_LIMIT_ORDERS";
    case 10034: return "TRADE_RETCODE_LIMIT_VOLUME";
    case 10035: return "TRADE_RETCODE_INVALID_ORDER";
    case 10036: return "TRADE_RETCODE_POSITION_CLOSED";
    case 10038: return "TRADE_RETCODE_INVALID_CLOSE_VOLUME";
    case 10039: return "TRADE_RETCODE_CLOSE_ORDER_EXIST";
    case 10040: return "TRADE_RETCODE_LIMIT_POSITIONS";
    case 10041: return "TRADE_RETCODE_REJECT_CANCEL";
    case 10042: return "TRADE_RETCODE_LONG_ONLY";
    case 10043: return "TRADE_RETCODE_SHORT_ONLY";
    case 10044: return "TRADE_RETCODE_FIFO_CLOSE";
    case 10045: return "TRADE_RETCODE_HEDGE_PROHIBITED";
    default: return "UNKNOWN_RETCODE";
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
