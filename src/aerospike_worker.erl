-module(aerospike_worker).
-behaviour(poolboy_worker).
-include("aerospike.hrl").
-behaviour(gen_server).

%% API
-export([start_link/1]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link(Args) -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link(Args) ->
    gen_server:start_link(?MODULE, Args, []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([{host, Host}, {port, Port}, {username, Username}, {password, Password}]) ->
    process_flag(trap_exit, true),
    {ok, Handle} = aerospike_nif:new(),
    ok = aerospike_nif:control(Handle, op(connect), [Host, Port, Username, Password]),
    receive
        ok -> {ok, #instance{handle = Handle}};
        {error, Error} -> {stop, Error}
    end.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call({mtouch, Keys, ExpTimesE}, _From, 
            State = #instance{handle = Handle}) ->
    ok = aerospike_nif:control(Handle, op(mtouch), [Keys, ExpTimesE]),
    receive
        Reply -> {reply, Reply, State}
    end;
handle_call({unlock, Key, Cas}, _From, 
            State = #instance{handle = Handle}) ->
    aerospike_nif:control(Handle, op(unlock), [Key, Cas]),
    receive
        Reply -> {reply, Reply, State}
    end;
handle_call({store, Op, Key, Value, TranscoderOpts, Exp, Cas}, _From, 
            State = #instance{handle = Handle, transcoder = Transcoder}) ->
    StoreValue = Transcoder:encode_value(TranscoderOpts, Value), 
    ok = aerospike_nif:control(Handle, op(store), [operation_value(Op), Key, StoreValue, 
                           Transcoder:flag(TranscoderOpts), Exp, Cas]),
    receive
        Reply -> {reply, Reply, State}
    end;


handle_call({mget, Keys, Exp, Lock, {trans, Flag}}, _From,
    State = #instance{handle = Handle, transcoder = Transcoder}) ->
    ok = aerospike_nif:control(Handle, op(mget), [Keys, Exp, Lock, 0]),
    Reply = receive
                {error, Error} -> {error, Error};
                {ok, Results} ->
                    lists:map(fun(Result) ->
                        case Result of
                            {Cas, _Flag, Key, Value} ->  %% won't use Flag from aerospike bucket
                                DecodedValue = Transcoder:decode_value(Flag, Value),
                                {Key, Cas, DecodedValue};
                            {_Key, {error, _Error}} ->
                                Result
                        end
                    end, Results)
            end,
    {reply, Reply, State};

handle_call({mget, Keys, Exp, Lock, Type}, _From, 
            State = #instance{handle = Handle, transcoder = Transcoder}) ->
    ok = aerospike_nif:control(Handle, op(mget), [Keys, Exp, Lock, Type]),
    Reply = receive
        {error, Error} -> {error, Error};
        {ok, Results} ->
            lists:map(fun(Result) ->
                        case Result of
                            {Cas, Flag, Key, Value} ->
                                        DecodedValue = Transcoder:decode_value(Flag, Value),
                                        {Key, Cas, DecodedValue};
                            {_Key, {error, _Error}} ->
                                Result
                        end
                end, Results)
    end,
    {reply, Reply, State};

handle_call({mget, Keys, Exp, Lock}, _From, 
            State = #instance{handle = Handle, transcoder = Transcoder}) ->
    ok = aerospike_nif:control(Handle, op(mget), [Keys, Exp, Lock, 0]),
    Reply = receive
        {error, Error} -> {error, Error};
        {ok, Results} ->
            lists:map(fun(Result) ->
                        case Result of
                            {Cas, Flag, Key, Value} ->
                                DecodedValue = Transcoder:decode_value(Flag, Value),
                                {Key, Cas, DecodedValue};
                            {_Key, {error, _Error}} ->
                                Result
                        end
                end, Results)
    end,
    {reply, Reply, State};
handle_call({arithmetic, Key, OffSet, Exp, Create, Initial}, _From,
            State = #instance{handle = Handle, transcoder = Transcoder}) ->
    ok = aerospike_nif:control(Handle, op(arithmetic), [Key, OffSet, Exp, Create, Initial]),
    Reply = receive
        {error, Error} -> {error, Error};
        {ok, {Cas, Flag, Value}} ->
            DecodedValue = Transcoder:decode_value(Flag, Value),
            {ok, Cas, DecodedValue}
    end,
    {reply, Reply, State};
handle_call({remove, Key, N}, _From,
            State = #instance{handle = Handle}) ->
    ok = aerospike_nif:control(Handle, op(remove), [Key, N]),
    receive
        Reply -> {reply, Reply, State}
    end;
handle_call({http, Path, Body, ContentType, Method, Chunked}, _From,
            State = #instance{handle = Handle}) ->
    ok = aerospike_nif:control(Handle, op(http), [Path, Body, ContentType, Method, Chunked]),
    receive
        Reply -> {reply, Reply, State}
    end;

handle_call({lset_add, NS, Set, Key, Ldt, Value, Timeout}, 
            _From, 
            State = #instance{handle = Handle}) ->
    ok = aerospike_nif:control(Handle, op(lset_add), [
                NS, Set, Key, Ldt, Value, Timeout]),
    receive
        Reply -> {reply, Reply, State}
    end;

handle_call({lset_remove, NS, Set, Key, Ldt, Value, Timeout}, 
            _From, 
            State = #instance{handle = Handle}) ->
    ok = aerospike_nif:control(Handle, op(lset_remove), [
                NS, Set, Key, Ldt, Value, Timeout]),
    receive
        Reply -> {reply, Reply, State}
    end;

handle_call({lset_get, NS, Set, Key, Ldt, Timeout}, 
            _From, 
            State = #instance{handle = Handle}) ->
    ok = aerospike_nif:control(Handle, op(lset_get), [
                NS, Set, Key, Ldt, Timeout]),
    receive
        Reply -> {reply, Reply, State}
    end;


handle_call({lset_size, NS, Set, Key, Ldt, Timeout}, 
            _From, 
            State = #instance{handle = Handle}) ->
    ok = aerospike_nif:control(Handle, op(lset_size), [
                NS, Set, Key, Ldt, Timeout]),
    receive
        Reply -> {reply, Reply, State}
    end;



handle_call(bucketname, _From, State = #instance{bucketname = BucketName}) ->
    {reply, {ok, BucketName}, State};
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State = #instance{handle = Handle}) ->
    aerospike_nif:destroy(Handle),
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

-spec operation_value(operation_type()) -> integer().
operation_value(add) -> ?'CBE_ADD';
operation_value(replace) -> ?'CBE_REPLACE';
operation_value(set) -> ?'CBE_SET';
operation_value(append) -> ?'CBE_APPEND';
operation_value(prepend) -> ?'CBE_PREPEND';
operation_value(lenqueue) -> ?'CBE_LENQUEUE';
operation_value(lremove) -> ?'CBE_LREMOVE';
operation_value(lset_add) -> ?'LSET_ADD';
operation_value(lset_REMOVE) -> ?'LSET_REMOVE';
operation_value(lset_GET) -> ?'LSET_GET';
operation_value(lset_SIZE) -> ?'LSET_SIZE'.

-spec op(atom()) -> integer().
op(connect) -> ?'CMD_CONNECT';
op(store) -> ?'CMD_STORE';
op(mget) -> ?'CMD_MGET';
op(unlock) -> ?'CMD_UNLOCK';
op(mtouch) -> ?'CMD_MTOUCH';
op(arithmetic) -> ?'CMD_ARITHMETIC';
op(remove) -> ?'CMD_REMOVE';
op(http) -> ?'CMD_HTTP'.

-spec canonical_bucket_name(string()) -> string().
canonical_bucket_name(Name) ->
    case Name of
        [] -> "default";
        BucketName -> BucketName
    end.

-spec binary_to_uint64(binary()) -> integer().
binary_to_uint64(Bin) ->
    case Bin of 
        <<U64:64/unsigned-big-integer>> -> U64
    end.

-spec binary_to_uint64_list(binary()) -> list().
binary_to_uint64_list(Bin) ->
    case Bin of
        <<U64:64/unsigned-big-integer>> -> [U64];
        <<U64:64/unsigned-big-integer, Rest/binary>> -> [U64 | binary_to_uint64_list(Rest)]
    end.