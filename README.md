# quicer

QUIC protocol erlang library.

[msquic](https://github.com/microsoft/msquic) NIF binding.

Project Status: WIP (actively), POC quality

API: is not stable, might be changed in the future.

![CI](https://github.com/emqx/quic/workflows/ci/badge.svg)

# OS Support
| OS      | Status    |
|---------|-----------|
| Linux   | Supported |
| MACOS   | Supported |
| Windows | TBD       |

# BUILD

## Dependencies

1. OTP22+
1. rebar3
1. cmake3.16+
1. [CLOG](https://github.com/microsoft/CLOG) (required for debug logging only)
1. LTTNG2.12 (required for debug build only)

## With DEBUG

Debug build depedency: [CLOG](https://github.com/microsoft/CLOG) 

``` sh
$ rebar3 compile 
# OR
$ make
```

note, 

To enable logging and release build:

``` sh
export CMAKE_BUILD_TYPE=Debug
export QUIC_ENABLE_LOGGING=ON
export QUICER_USE_LTTNG=1
make
```

## Without DEBUG

``` sh
$ git submodule update --init --recursive
$ cmake -B c_build -DCMAKE_BUILD_TYPE=Release -DQUIC_ENABLE_LOGGING=OFF && make 
```

# Examples

## Ping Pong server and client

### Server

``` erlang
application:ensure_all_started(quicer),
Port = 4567,
LOptions = [ {cert, "cert.pem"}
           , {key,  "key.pem"}
           , {alpn, ["sample"]}
             ],
{ok, L} = quicer:listen(Port, LOptions),
{ok, Conn} = quicer:accept(L, [], 5000),
{ok, Conn} = quicer:handshake(Conn),
{ok, Stm} = quicer:accept_stream(Conn, []),
receive {quic, <<"ping">>, Stm, _, _, _} -> ok end,
{ok, 4} = quicer:send(Stm, <<"pong">>),
quicer:close_listener(L).
```

### Client

``` erlang
application:ensure_all_started(quicer),
Port = 4567,
{ok, Conn} = quicer:connect("localhost", Port, [{alpn, ["sample"]}], 5000),
{ok, Stm} = quicer:start_stream(Conn, []),
{ok, 4} = quicer:send(Stm, <<"ping">>),
receive {quic, <<"pong">>, Stm, _, _, _} -> ok end,
ok = quicer:close_connection(Conn).
```


# TEST

``` sh
$ make test
```

# API

All APIs are exported though API MODULE: quicer.erl

## Terminology
| Term       | Definition                                                       |
|------------|------------------------------------------------------------------|
| server     | listen and accept quic connections from clients                  |
| client     | initiates quic connection                                        |
| listener   | Erlang Process owns listening port                               |
| connection | Quic Connection                                                  |
| stream     | Exchanging app data over a connection                            |
| owner      | 'owner' is a process that receives quic events.                  |
|            | 'connection owner' receive events of a connection                |
|            | 'stream owner' receive application data and events from a stream |
|            | 'listener owner' receive events from listener                    |
|            | When owner is dead, related resources would be released          |
| l_ctx      | listener nif context                                             |
| c_ctx      | connection nif context                                           |
| s_ctx      | stream nif context                                               |
|            |                                                                  |

## Connection API

### Start listener (Server)

Start listener on specific port.

``` erlang
quicer:listen(ListenOn, Options) ->
  {ok, Connection} | {error, any()} | {error, any(), ErrorCode::integer()}.
  
```

note: 
1. port binding is done in NIF context, thus you cannot see it from `inet:i()`.
1. ListenOn can either be integer() for Port or be String for HOST:PORT


### Close listener (Server)

``` erlang
quicer:close_listener(Listener) -> ok.
```

Gracefully close listener.

### Accept Connection (Server) 

Accept connection

``` erlang
quicer:accept(Listener, Options, Timeout) -> 
  {ok, Connection} | {error, any()} | {error, any(), ErrorCode::integer()}.
```

Blocking call to accept new connection.

Caller becomes the owner of new connection.

### TLS Handshake (Server)

``` erlang
quicer:handeshake(Connection) -> {ok, Connection} | {error, any()}.
```

### Start Connection  (Client)

``` erlang
quicer:connection(Hostname, Port, Options, Timeout) -> 
  {ok, Connection} | {error, any()} | {error, any(), ErrorCode::integer()}.
```

### Close_connection

``` erlang
quicer:close_connection(Connection) -> ok.
quicer:close_connection(Connection, Timeout) -> ok.
quicer:close_connection(Connection, Flag, Reason) -> ok.
quicer:close_connection(Connection, Flag, Reason, Timeout) -> ok.

Flag :: ?QUIC_CONNECTION_SHUTDOWN_FLAG_NONE | ?QUIC_CONNECTION_SHUTDOWN_FLAG_SILENT.
```

Shutdown connection with app specific reason, it also implicitly shuts down the streams.

`QUIC_CONNECTION_SHUTDOWN_FLAG_SILENT` is used for lowmem scenarios without sending a connection_close frame to the peer.

## Stream API

### Start stream

``` erlang
quicer:start_stream(Connection, Options) -> 
  {ok, Stream} | {error, any()} | {error, any(), ErrorCode::integer()}.
```

### Accept stream

``` erlang
accept_stream(Connection, Opts, Timeout) -> 
  {ok, Stream} | {error, any()} | {error, any(), ErrorCode::integer()}.
```

Accept stream on a existing connection. 

This is a blocking call.

After this call is returned, the calling process becomes the owner of the stream.

### Send Data over stream

#### Sync Send

Send data over stream and the call get blocked until the send buffer is flushed

``` erlang
quicer:send(Stream, BinaryData) -> 
  {ok, SizeSent::non_neg_integer()} | {error, any()} | {error, any(), ErrorCode::integer()}.
```

#### Async Send

Send data over stream asynchronously without waiting for the buffer get flushed.

``` erlang
quicer:async_send(Stream, BinaryData) -> 
  {ok, SizeSent::non_neg_integer()} | {error, any()} | {error, any(), ErrorCode::integer()}.
```

### Active receive from stream

If the stream option `active` is set to `true`, stream data will be delivered to the stream owner's process message queue as following format

``` erlang
{quic, Data, Stream, AbsOffset, Length, Flag}
when ->
  Data::binary(),
  Stream::stream_handler(),
  AbsOffset::non_neg_integer(),
  Length::non_neg_integer(),
  Flag::integer()
```

### Passive receive from stream

``` erlang
quicer:recv(Stream, Len) -> 
  {ok, binary()} | {error, any()} | {error, any(), ErrorCode::integer()}.
```

Like gen_tcp:recv, passive recv data from stream.

If Len = 0, return all data in buffer if it is not empty.
            if buffer is empty, blocking for a quic msg from stack to arrive and return all data from that msg.
If Len > 0, desired bytes will be returned, other data would be buffered in proc dict.

Suggested to use Len=0 if caller want to buffer or reassemble the data on its own.

note, the requested Len cannot exceeed the stream recv window size of connection opts otherwise {error, stream_recv_window_too_small} will be returned.

### Shutdown stream

``` erlang
quicer:close_stream(Stream) -> ok | {error, any()}.
quicer:close_stream(Stream, Timeout) -> ok | {error, any()}.
quicer:close_stream(Stream, Flags, Reason, Timeout) -> ok | {error, any()}.
```
Shutdown stream with an app specific reason (integer) indicate to the peer as the reason for the shutdown.

Use flags to control of the behavior of shutdown, check ?QUIC_STREAM_SHUTDOWN_FLAG_* in =quicer.hrl= for more.

note, could return error if wrong combination of flags are set.

### Get/Set Connection/Stream Opts

``` erlang
%% Get Opts in binary format
quicer:getopt(Stream | Connection, [Opt]) -> 
  {ok, [{OptName::atom(), OptValue::binary()}]}.
```

``` erlang
%% Get Opts
quicer:getopt(Stream | Connection, [Opt], IsRaw :: boolean) -> 
  {ok, [{OptName::atom(), OptValue::binary() | any()}]}.
```

``` erlang
%% Set Opt
quicer:setopt(Stream | Connection, Opt :: atom(), Value :: any()) -> 
  ok | {error, any()}.
```

Supported Opts:
  | OptName | Suport Set/Get | Type | Description |
  |---------|----------------|------|-------------|
  |         |                |      |             |
| param_conn_settings | Set            | map() | map keys: <br>conn_flow_control_window<br>max_worker_queue_delay_us<br>max_stateless_operations<br>initial_window_packets<br>send_idle_timeout_ms<br>initial_rtt_ms<br>max_ack_delay_ms<br>disconnect_timeout_ms<br>keep_alive_interval_ms<br>peer_bidi_stream_count<br>peer_unidi_stream_count<br>retry_memory_limit<br>load_balancing_mode<br>max_operations_per_drain<br>send_buffering_enabled<br>pacing_enabled<br>migration_enabled<br>datagram_receive_enabled<br>server_resumption_level<br>version_negotiation_ext_enabled<br>desired_versions_list<br>desired_versions_list_length<br> |


### Connection stat

``` erlang
quicer:getstat(Connection, [inet:stat_option()]) -> 
  {ok, [{stat_option(), integer()}] | {error, any()}.
```

**note**, if state's return value is -1 that means it is unsupported.

### Peer name

``` erlang
quicer:peername(Stream | Connection) ->
  {ok, {inet:ip_address(), inet:port_number()}} | {error, any()}.
```

Returns connection Peer's IP and Port

### Sock name

``` erlang
quicer:sockname(Stream | Connection) ->   
  {ok, {inet:ip_address(), inet:port_number()}} | {error, any()}.
```
Returns connection local IP and Port.

# License
Apache License Version 2.0

