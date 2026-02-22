//+------------------------------------------------------------------+
//|                                               zeromq_bridge.mqh |
//|                      Komponent mostu komunikacyjnego dla MQL5 |
//|                                     https://github.com/gemini |
//+------------------------------------------------------------------+
/*
  OPIS:
  Ten plik nagłówkowy stanowi warstwę pośredniczącą do komunikacji z backendem w Pythonie
  przy użyciu biblioteki ZeroMQ. Upraszcza on proces wysyłania danych rynkowych
  i odbierania komend transakcyjnych.

  KRYTYCZNA ZALEŻNOŚĆ:
  Ten kod wymaga zewnętrznej biblioteki ZeroMQ dla MQL5. Należy ją pobrać i zainstalować
  zanim spróbujesz skompilować lub uruchomić ten kod.
  
  Rekomendowana biblioteka: dingmaotu/mql-zmq
  Link: https://github.com/dingmaotu/mql-zmq

  INSTRUKCJA INSTALACJI BIBLIOTEKI (dingmaotu/mql-zmq):
  1. Pobierz najnowszą wersję z podanego linku (zakładka "Releases").
  2. Rozpakuj archiwum.
  3. Skopiuj zawartość katalogu 'MQL5/Include' z archiwum do katalogu 'MQL5/Include'
     Twojego terminala MetaTrader 5 (dostęp przez: Plik -> Otwórz Folder Danych).
  4. Skopiuj plik 'libzmq.dll' z katalogu 'MQL5/Libraries' z archiwum do katalogu
     'MQL5/Libraries' Twojego terminala.

  UPEWNIJ SIĘ, że w opcjach Expert Advisora w terminalu MT5 (Narzędzia -> Opcje -> Expert Advisors)
  zaznaczona jest opcja "Zezwalaj na import DLL".
*/
#property copyright "Gemini"
#property link      "https://github.com/gemini"

#include <Zmq/Zmq.mqh> // Dołączamy główny plik biblioteki ZMQ

// --- Zmienne globalne dla kontekstu i gniazd ZMQ ---
int G_ZmqContext = -1; // Uchwyt do kontekstu ZMQ
int G_PushSocket = -1; // Uchwyt do gniazda PUSH (wysyłanie danych do Pythona)
int G_PullSocket = -1; // Uchwyt do gniazda PULL (odbieranie komend z Pythona)

//+------------------------------------------------------------------+
//| Inicjalizuje most ZMQ                                            |
//+------------------------------------------------------------------+
bool Zmq_Init(string python_host = "127.0.0.1", int data_port = 5555, int command_port = 5556)
{
  // 1. Utwórz kontekst ZMQ
  G_ZmqContext = ZmqContextNew();
  if(G_ZmqContext < 0)
  {
    Print("Błąd: Nie udało się utworzyć kontekstu ZMQ.");
    return(false);
  }
  Print("Kontekst ZMQ utworzony pomyślnie.");

  // 2. Utwórz gniazdo PUSH do wysyłania danych do Pythona
  G_PushSocket = ZmqSocketNew(G_ZmqContext, ZMQ_PUSH);
  if(G_PushSocket < 0)
  {
    Print("Błąd: Nie udało się utworzyć gniazda PUSH.");
    ZmqContextDestroy(G_ZmqContext);
    return(false);
  }
  Print("Gniazdo PUSH utworzone pomyślnie.");

  // 3. Połącz gniazdo PUSH z serwerem Pythona
  string push_address = "tcp://" + python_host + ":" + IntegerToString(data_port);
  if(!ZmqConnect(G_PushSocket, push_address))
  {
    Print("Błąd: Nie udało się połączyć gniazda PUSH z adresem ", push_address);
    ZmqSocketClose(G_PushSocket);
    ZmqContextDestroy(G_ZmqContext);
    return(false);
  }
  Print("Gniazdo PUSH połączone z ", push_address);

  // 4. Utwórz gniazdo PULL do odbierania komend od Pythona
  G_PullSocket = ZmqSocketNew(G_ZmqContext, ZMQ_PULL);
  if(G_PullSocket < 0)
  {
    Print("Błąd: Nie udało się utworzyć gniazda PULL.");
    ZmqSocketClose(G_PushSocket);
    ZmqContextDestroy(G_ZmqContext);
    return(false);
  }
  Print("Gniazdo PULL utworzone pomyślnie.");
  
  // 5. Połącz gniazdo PULL z serwerem Pythona
  string pull_address = "tcp://" + python_host + ":" + IntegerToString(command_port);
  if(!ZmqConnect(G_PullSocket, pull_address))
  {
    Print("Błąd: Nie udało się połączyć gniazda PULL z adresem ", pull_address);
    ZmqSocketClose(G_PushSocket);
    ZmqSocketClose(G_PullSocket);
    ZmqContextDestroy(G_ZmqContext);
    return(false);
  }
  Print("Gniazdo PULL połączone z ", pull_address);

  Print("Most komunikacyjny ZMQ zainicjalizowany pomyślnie.");
  return(true);
}

//+------------------------------------------------------------------+
//| Zamyka most ZMQ i zwalnia zasoby                                 |
//+------------------------------------------------------------------+
void Zmq_Deinit()
{
  Print("Rozpoczynanie zamykania mostu ZMQ...");
  // Zamknij gniazda
  if(G_PushSocket >= 0)
  {
    ZmqSocketClose(G_PushSocket);
    G_PushSocket = -1;
    Print("Gniazdo PUSH zamknięte.");
  }
  if(G_PullSocket >= 0)
  {
    ZmqSocketClose(G_PullSocket);
    G_PullSocket = -1;
    Print("Gniazdo PULL zamknięte.");
  }
  // Zniszcz kontekst
  if(G_ZmqContext >= 0)
  {
    ZmqContextDestroy(G_ZmqContext);
    G_ZmqContext = -1;
    Print("Kontekst ZMQ zniszczony.");
  }
  Print("Most ZMQ zamknięty.");
}

//+------------------------------------------------------------------+
//| Wysyła dane (jako string JSON) do Pythona                        |
//+------------------------------------------------------------------+
bool Zmq_SendData(string &data_json)
{
  if(G_PushSocket < 0)
  {
    Print("Błąd wysyłania: Gniazdo PUSH nie jest zainicjalizowane.");
    return(false);
  }

  // Używamy ZMQ_DONTWAIT, aby uniknąć blokowania, jeśli kolejka jest pełna
  return(ZmqSend(G_PushSocket, data_json, ZMQ_DONTWAIT));
}

//+------------------------------------------------------------------+
//| Odbiera komendę (jako string JSON) od Pythona                    |
//+------------------------------------------------------------------+
bool Zmq_ReceiveCommand(string &result_json)
{
  if(G_PullSocket < 0)
  {
    Print("Błąd odbioru: Gniazdo PULL nie jest zainicjalizowane.");
    result_json = "";
    return(false);
  }

  // Używamy ZMQ_DONTWAIT, aby Expert Advisor nigdy nie był blokowany
  // podczas oczekiwania na komendę.
  if(ZmqRecv(G_PullSocket, result_json, ZMQ_DONTWAIT))
  {
    // Wiadomość została odebrana
    return(true);
  }
  
  // Brak wiadomości w kolejce
  result_json = "";
  return(false);
}
//+------------------------------------------------------------------+

