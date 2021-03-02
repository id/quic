%%--------------------------------------------------------------------
%% Copyright (c) 2020-2021 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(quicer).

-export([ listen/2
        , close_listener/1
        , connect/4
        , accept/3
        , close_connection/1
        ]).

-on_load(init/0).

-type listener_handler() :: reference().

-spec listen(inet:port_number(), proplists:proplists() | map()) ->
        {ok, listener_handler()} | {error, any()}.
listen(Port, Opts) when is_list(Opts)->
  listen(Port, maps:from_list(Opts));
listen(Port, Opts) when is_map(Opts)->
  quicer_nif:listen(Port, Opts).

-spec close_listener(listener_handler()) -> ok.
close_listener(Listener) ->
  quicer_nif:close_listener(Listener).

connect(Addr, Port, Opts, _Timeout) ->
  case quicer_nif:async_connect(Addr, Port, Opts) of
    {ok, _H} ->
      receive
        {quic, connected, Ctx} ->
          %%io:format("erl nif: connected\n"),
          {ok, Ctx}
      end;
    {error, _} = Err ->
      Err
  end.

accept(LSock, Opts, Timeout) ->
  % non-blocking
  {ok, _L} = quicer_nif:async_accept(LSock, Opts),
  receive
    {new_conn, C} ->
      {ok, C}
  after Timeout ->
    {error, timeout}
  end.

close_connection(Conn) ->
  quicer_nif:close_connection(Conn).

init() ->
  quicer_nif:open_lib(),
  quicer_nif:reg_open().

%%%_* Emacs ====================================================================
%%% Local Variables:
%%% allout-layout: t
%%% erlang-indent-level: 2
%%% End: