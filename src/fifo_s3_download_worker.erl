-module(fifo_s3_download_worker).
-behaviour(gen_server).
-behaviour(poolboy_worker).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-export([start_link/1]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-record(state, {data=undefined, part=0}).

start_link(Args) ->
    gen_server:start_link(?MODULE, Args, []).

init(_Args) ->
    {ok, #state{}}.

handle_call(get, _From, State = #state{data=R}) ->
    {reply, R, State#state{data=undefined}};

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({download, _From, P, B, K, Conf, C, Size}, State = #state{data=undefined}) ->
    {Start, End} = start_stop(P, C, Size),
    Range = build_range(Start, End),
    R = try erlcloud_s3:get_object(B, K, [{range, Range}], Conf) of
        Data ->
            case proplists:get_value(content, Data) of
                undefined ->
                    {error, content};
                D ->
                    {ok, D}
            end
    catch
        _:E ->
            {error, E}
    end,
    {noreply, State#state{data=R,part=P}};

handle_cast({download, _From, _P, _, _,_Conf, _C, _Size}, State) ->
    {noreply, State#state{data=undefiend}};

handle_cast(cancle, State) ->
    {noreply, State#state{data=undefiend}};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

build_range(Start, Stop) when Start =< Stop ->
	lists:flatten(io_lib:format("bytes=~p-~p", [Start, Stop])).

start_stop(P, Size, Max) ->
    Start = P*Size,
    End = case (P+1)*Size of
              EndX when EndX > Max ->
                  Max;
              EndX ->
                  EndX
          end,
    {Start, End - 1}.


%%%===================================================================
%%% Tests
%%%===================================================================

-ifdef(TEST).

start_stop_test() ->
    Size = 10,
    Max = 25,
    ?assertEqual({0, 0}, start_stop(0, 1, Max)),
    ?assertEqual({0, 9}, start_stop(0, Size, Max)),
    ?assertEqual({10, 19}, start_stop(1, Size, Max)),
    ?assertEqual({20, 24}, start_stop(2, Size, Max)).

-endif.
