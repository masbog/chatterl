%%----------------------------------------------------------------
%%% @author  Yomi Colledge <yomi@boodah.net>
%%% @doc Web interface for Chatterl
%%%
%%% Chatterl Web Gateway, allowing Web based clients to interact
%%% with Chatterl over a RESTful API.
%%%
%%% Allows Chatterl to interface with any web-based interface
%%% Using JSON and XML, sending the requests off to the chatterl_serv
%%% module.
%%%
%%% All calls to CWIGA will only be allowed via a specified IP, which
%%% will be defined with the configuration file.
%%% @end
%%% @copyright 2008-2009 Yomi Colledge
%%%---------------------------------------------------------------
-module(cwiga).

-behaviour(gen_server).

%% API
-export([start_link/1,stop/0]).

-define(APP, "CWIGA").
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-record(state, {}).

%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start_link() -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the server
%%--------------------------------------------------------------------
start_link(Port) ->
  gen_server:start_link({global, ?SERVER}, ?MODULE, [Port], []).

stop() ->
    gen_server:call({global, ?SERVER}, stop, infinity).

dispatch_requests(Req) ->
  [Path|Ext] = string:tokens(Req:get(path),"."),
  Method = Req:get(method),
  Post = Req:parse_post(),
  io:format("~p request for ~p with post: ~p~n", [Method, Path, Post]),
  Response = handle(Method, Path, get_content_type(Ext), Post),
  Req:respond(Response).

handle('POST',"/groups/send/" ++ Group,ContentType,Post) ->
  [{"client",Sender},{"msg",Message}] = Post,
  Response = chatterl_mid_man:group_send(ContentType,{Group,Sender,Message}),
  handle_response(Response,ContentType);
handle('POST',"/groups/join/" ++ Group,ContentType,Post) ->
  [{"client",Client}] = Post,
  Response = chatterl_mid_man:group_join(ContentType,{Group,Client}),
  handle_response(Response,ContentType);
handle('POST',"/groups/leave/" ++ Group,ContentType,Post) ->
  [{"client",Client}] = Post,
  Response = chatterl_mid_man:group_leave(ContentType,{Group,Client}),
  handle_response(Response,ContentType);
handle('GET',"/users/connect/" ++ Client,ContentType,_Post) ->
  handle_response(chatterl_mid_man:connect(ContentType,Client),ContentType);
handle('GET',"/users/disconnect/" ++ Client,ContentType,_Post) ->
  handle_response(chatterl_mid_man:disconnect(ContentType,Client),ContentType);
handle('GET',"/users/list/" ++ Group,ContentType,_Post) ->
  handle_response(chatterl_mid_man:user_list(ContentType,Group),ContentType);
handle('GET',"/users/list",ContentType,_Post) ->
  handle_response(chatterl_mid_man:user_list(ContentType),ContentType);
handle('GET',"/users/poll/" ++ Client,ContentType,_Post) ->
  handle_response(chatterl_mid_man:user_poll(ContentType,Client),ContentType);
handle('GET',"/users/groups/" ++ Client,ContentType,_Post) ->
  handle_response(chatterl_mid_man:user_groups(ContentType,Client),ContentType);
handle('GET',"/groups/poll/" ++ Group,ContentType,_Post) ->
  handle_response(chatterl_mid_man:group_poll(ContentType,Group),ContentType);
handle('GET',"/groups/list",ContentType,_Post) ->
  handle_response(chatterl_mid_man:group_list(ContentType),ContentType);
handle('GET',"/groups/info/" ++ Group,ContentType,_Post) ->
  handle_response(chatterl_mid_man:group_info(ContentType,Group),ContentType);
handle(_,Path,ContentType,_) ->
  Response = message_handler:get_response_body(ContentType,
                                               message_handler:build_carrier("error", "Unknown command: " ++Path)),
  error(Response,ContentType).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% Function: init(Args) -> {ok, State} |
%%                         {ok, State, Timeout} |
%%                         ignore               |
%%                         {stop, Reason}
%% Description: Initiates the server
%%--------------------------------------------------------------------
init([Port]) ->
  process_flag(trap_exit, true),
  mochiweb_http:start([{port, Port}, {loop, fun dispatch_requests/1}]),
  erlang:monitor(process,mochiweb_http),
  {ok, #state{}}.

%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%--------------------------------------------------------------------
handle_call(stop, _From, State) ->
    io:format("Processing shut down ~s~n", [?APP]),
    {stop, normal, stopped, State};
handle_call(_Request, _From, State) ->
  Reply = ok,
  {reply, Reply, State}.

%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% Function: handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% Description: Handling all non call/cast messages
%%--------------------------------------------------------------------
handle_info({'DOWN', _Ref, _Process, {mochiweb_http, Host}, Reason}, State) ->
    io:format("Unable to start mochiweb on ~s:~nReason: ~s~n",[Host,Reason]),
    {stop,normal,State};
handle_info(_Info, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% Function: terminate(Reason, State) -> void()
%% Description: This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    io:format("Shutting down ChatterlWeb on: ~s...~n",[node(self())]),
    mochiweb_http:stop(),
    ok.

%%--------------------------------------------------------------------
%% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
%% Description: Convert process state when code is changed
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @private
%% @doc
%%
%% Gets the content type, used to help CWIGA to determine what format
%% to respond in.
%% @spec get_content_type(Type) -> string()
%%
%% @end
%%--------------------------------------------------------------------
get_content_type(Type) ->
    case Type of
	["json"] ->
	    ["text/json"];
	["xml"] ->
	    ["text/xml"];
	_ -> ["text/json"]
    end.

check_json_response(Json) ->
  {struct,[{<<"chatterl">>,{struct,[{<<"response">>,{struct,[Response]}}]}}]} = mochijson2:decode(Json),
  Response.

error(Response,ContentType) ->
  {404, [{"Content-Type", ContentType}], list_to_binary(Response)}.

failure(Response,ContentType) ->
  {501, [{"Content-Type", ContentType}], list_to_binary(Response)}.

success(Response,ContentType) ->
  {200, [{"Content-Type", ContentType}], list_to_binary(Response)}.


handle_response(Response,ContentType) ->
  case check_json_response(Response) of
    {<<"failure">>,_} -> failure(Response,ContentType);
    {<<"success">>,_} -> success(Response,ContentType);
    {<<"error">>,_} -> error(Response,ContentType)
  end.