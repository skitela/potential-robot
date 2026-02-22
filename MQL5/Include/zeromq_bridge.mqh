//+------------------------------------------------------------------+
//|                                               zeromq_bridge.mqh |
//|            Minimal ZeroMQ C-API bridge for HybridAgent (MQL5)   |
//+------------------------------------------------------------------+
#property strict

#define ZMQ_REQ 3
#define ZMQ_REP 4
#define ZMQ_PUSH 8
#define ZMQ_DONTWAIT 1

#import "libzmq.dll"
long zmq_ctx_new();
int zmq_ctx_term(long context);
long zmq_socket(long context, int type);
int zmq_close(long socket);
int zmq_connect(long socket, const uchar &addr[]);
int zmq_send(long socket, const uchar &buf[], long len, int flags);
int zmq_recv(long socket, uchar &buf[], long len, int flags);
int zmq_errno();
#import

long G_ZmqContext = 0;
long G_PushSocket = 0;
long G_RepSocket = 0;

bool _ZmqConnect(long socket_ref, string address)
{
  uchar addr[];
  int n = StringToCharArray(address, addr, 0, -1, CP_UTF8);
  if(n <= 0)
    return false;
  return (zmq_connect(socket_ref, addr) == 0);
}

bool _ZmqSend(long socket_ref, string payload, bool nonblock)
{
  uchar data[];
  int n = StringToCharArray(payload, data, 0, -1, CP_UTF8);
  if(n <= 0)
    return false;

  long msg_len = (long)(n - 1); // drop null terminator
  int flags = nonblock ? ZMQ_DONTWAIT : 0;
  return (zmq_send(socket_ref, data, msg_len, flags) >= 0);
}

bool _ZmqRecv(long socket_ref, string &payload, bool nonblock)
{
  payload = "";
  uchar data[];
  ArrayResize(data, 65536);

  int flags = nonblock ? ZMQ_DONTWAIT : 0;
  int rc = zmq_recv(socket_ref, data, (long)ArraySize(data), flags);
  if(rc <= 0)
    return false;

  payload = CharArrayToString(data, 0, rc, CP_UTF8);
  return true;
}

bool Zmq_Init(string python_host = "127.0.0.1", int data_port = 5555, int rep_port = 5556)
{
  Zmq_Deinit();

  if(MQLInfoInteger(MQL_DLLS_ALLOWED) == 0)
  {
    Print("ZMQ_INIT_FAIL reason=DLL_IMPORT_DISABLED");
    return false;
  }

  G_ZmqContext = zmq_ctx_new();
  if(G_ZmqContext == 0)
  {
    Print("ZMQ_INIT_FAIL reason=CTX_NEW errno=", zmq_errno());
    return false;
  }

  G_PushSocket = zmq_socket(G_ZmqContext, ZMQ_PUSH);
  if(G_PushSocket == 0)
  {
    Print("ZMQ_INIT_FAIL reason=PUSH_NEW errno=", zmq_errno());
    Zmq_Deinit();
    return false;
  }

  G_RepSocket = zmq_socket(G_ZmqContext, ZMQ_REP);
  if(G_RepSocket == 0)
  {
    Print("ZMQ_INIT_FAIL reason=REP_NEW errno=", zmq_errno());
    Zmq_Deinit();
    return false;
  }

  string push_address = "tcp://" + python_host + ":" + IntegerToString(data_port);
  if(!_ZmqConnect(G_PushSocket, push_address))
  {
    Print("ZMQ_INIT_FAIL reason=PUSH_CONNECT addr=", push_address, " errno=", zmq_errno());
    Zmq_Deinit();
    return false;
  }

  string rep_address = "tcp://" + python_host + ":" + IntegerToString(rep_port);
  if(!_ZmqConnect(G_RepSocket, rep_address))
  {
    Print("ZMQ_INIT_FAIL reason=REP_CONNECT addr=", rep_address, " errno=", zmq_errno());
    Zmq_Deinit();
    return false;
  }

  Print("ZMQ_INIT_OK push=", push_address, " rep=", rep_address);
  return true;
}

void Zmq_Deinit()
{
  if(G_PushSocket != 0)
  {
    zmq_close(G_PushSocket);
    G_PushSocket = 0;
  }

  if(G_RepSocket != 0)
  {
    zmq_close(G_RepSocket);
    G_RepSocket = 0;
  }

  if(G_ZmqContext != 0)
  {
    zmq_ctx_term(G_ZmqContext);
    G_ZmqContext = 0;
  }
}

bool Zmq_SendData(string &data_json)
{
  if(G_PushSocket == 0)
    return false;
  return _ZmqSend(G_PushSocket, data_json, true);
}

bool Zmq_ReceiveRequest(string &result_json)
{
  if(G_RepSocket == 0)
  {
    result_json = "";
    return false;
  }
  return _ZmqRecv(G_RepSocket, result_json, true);
}

bool Zmq_SendReply(string &reply_json)
{
  if(G_RepSocket == 0)
    return false;
  return _ZmqSend(G_RepSocket, reply_json, false);
}
