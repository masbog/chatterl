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
-export([start/1,stop/0]).

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
%% @doc
%% Starts the server
%%
%% @spec start(Port) -> {ok,Pid} | ignore | {error,Error}
%% @end
%%--------------------------------------------------------------------
start(Port) ->
  gen_server:start_link({global, ?SERVER}, ?MODULE, [Port], []).

%%--------------------------------------------------------------------
%% @doc
%% Stops the server
%%
%% @spec stop() -> {ok,Pid} | stopped | {error,Error}
%% @end
%%--------------------------------------------------------------------
stop() ->
    gen_server:call({global, ?SERVER}, stop, infinity).

%%====================================================================
%% gen_server callbacks
%%====================================================================
%%--------------------------------------------------------------------
%% @doc
%% Initiates the server
%%
%% Function: init(Port) -> {ok, State} |
%%                         {ok, State, Timeout} |
%%                         ignore               |
%%                         {stop, Reason}

%%--------------------------------------------------------------------
init([Port]) ->
  process_flag(trap_exit, true),
  mochiweb_http:start([{port, Port}, {loop, fun dispatch_requests/1}]),
  erlang:monitor(process,mochiweb_http),
  {ok, #state{}}.

%%--------------------------------------------------------------------
%% @doc
%% Description: Handling call messages
%%
%% @spec handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call(stop, _From, State) ->
    io:format("Processing shut down ~s~n", [?APP]),
    {stop, normal, stopped, State};
handle_call({'POST',Url,ContentType,Post,Req},_From,State) ->
  Reply = handle_response(handle_request('POST',Url,ContentType,Post,Req),ContentType),
  {reply, Reply, State};
handle_call({'GET',Url,ContentType,_Post,Req},_From,State) ->
  Reply = handle_response(handle_request('GET',Url,ContentType,Req),ContentType),
  {reply, Reply, State};
handle_call({_,Url,ContentType,Path,_Req},_From,State) ->
  Reply = send_response(error,{unknown(Url,ContentType),ContentType}),
  {reply, Reply, State};
handle_call(_Request, _From, State) ->
  Reply = ok,
  {reply, Reply, State}.
%%--------------------------------------------------------------------
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info({'DOWN', _Ref, _Process, {mochiweb_http, Host}, Reason}, State) ->
    io:format("Unable to start mochiweb on ~s:~nReason: ~s~n",[Host,Reason]),
    {stop,normal,State};
handle_info(_Info, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @doc
%% Terminates Chatterl Web Interface, making sure to shutdown mochiweb
%% along side it.
%%
%% @spec terminate({node,Reason},State) -> void()
%% @todo Needs a time out for when the port is already in use.
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    io:format("Shutting down ChatterlWeb on: ~s...~n",[node(self())]),
    mochiweb_http:stop(),
    ok.

%%--------------------------------------------------------------------
%% @doc
%%
%% Convert process state when code is changed
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%%
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------
%%--------------------------------------------------------------------
%% @private
%% @doc
%% Dispatches our requests to the relevant handle.
%%
%% Uses clean_path to determine what the action is.
%% @spec dispatch_requests(Request) -> void()
%% @end
%%--------------------------------------------------------------------
dispatch_requests(Req) ->
  [Path|Ext] = string:tokens(Req:get(path),"."),
  Method = Req:get(method),
  Post = Req:parse_post(),
  io:format("~p request for ~p with post: ~p~n", [Method, Path, Post]),
  Response = gen_server:call({global,?MODULE},{Method, Path, get_content_type(Ext), Post, Req}),
  Req:respond(Response).

%%--------------------------------------------------------------------
%% @private
%% @doc
%%
%% Handles CWIGA's requests
%% @spec handle_request('GET', Url, ContentType, _Post) -> HTTPResponse
%%
%% @end
%%--------------------------------------------------------------------
handle_request('GET', Url, ContentType, Req) ->
  case Url of
    "/users/connect/" ++ Client ->
      chatterl_mid_man:connect(ContentType,Client);
    "/users/disconnect/" ++ Client ->
      chatterl_mid_man:disconnect(ContentType,Client);
    "/users/list/" ->
      chatterl_mid_man:user_list(ContentType);
    "/users/list/" ++ Group ->
      chatterl_mid_man:user_list(ContentType,Group);
    "/users/poll/" ++ Client ->
      chatterl_mid_man:user_poll(ContentType,Client);
    "/users/groups/" ++ Client ->
      Fun = fun({CT,U}) ->
                chatterl_mid_man:user_groups(CT,U) end,
      authorise(ContentType,Req,{Fun,{ContentType,Client}});
    "/groups/poll/" ++ Group ->
      Fun = fun({CT,G}) ->
                chatterl_mid_man:group_poll(CT,G) end,
      authorise(ContentType,Req,{Fun,{ContentType,Group}});
    "/groups/list" ->
      Fun = fun(CT) ->
                chatterl_mid_man:group_list(CT) end,
      authorise(ContentType,Req,{Fun,ContentType});
    "/groups/info/" ++ Group ->
      Fun = fun({CT,G}) ->
                chatterl_mid_man:group_info(CT,G) end,
      authorise(ContentType,Req,{Fun,{ContentType,Group}});
    "/status/logged_in/" ->
      Fun = fun(CT) ->
                chatterl_mid_man:logged_in(CT) end,
      authorise(ContentType,Req,{Fun,ContentType});
    _ -> unknown(Url,ContentType)
  end.

handle_request('POST',Url,ContentType,Post,_Req) ->
  case Url of
    "/register/" ++ Nick ->
      [{"name",Name},{"email",Email},{"pass1",Pass1},{"pass2",Pass2}] = Post,
      chatterl_mid_man:register(ContentType,{Nick,{Name,Email,Pass1,Pass2}});
    "/groups/send/" ++ Group ->
      [{"client",Sender},{"msg",Message}] = Post,
      chatterl_mid_man:group_send(ContentType,{Group,Sender,Message});
    "/users/send/" ++ Group ->
      [{"client",Sender},{"msg",Message}] = Post,
      chatterl_mid_man:user_msg(ContentType,{Group,Sender,Message});
    "/groups/join/" ++ Group ->
      [{"client",Client}] = Post,
      chatterl_mid_man:group_join(ContentType,{Group,Client});
    "/groups/leave/" ++ Group ->
      [{"client",Client}] = Post,
      chatterl_mid_man:group_leave(ContentType,{Group,Client});
    "/users/login" ->
      [{"login",Login},{"pass",Pass}] = Post,
      chatterl_mid_man:login(ContentType,{Login,Pass});
    "/users/logout" ->
      [{"client",Client}] = Post,
      chatterl_mid_man:logout(ContentType,Client);
     Url -> unknown(Url,ContentType)
  end.

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

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Wrapper method used for successful responses
%%
%% @spec check_json_response(Json) -> JSONResponse
%% @end
%%--------------------------------------------------------------------
check_json_response(Json) ->
  {struct,[{<<"chatterl">>,
            {struct,[{<<"response">>,{struct,[Response]}}]}}]} =
    mochijson2:decode(Json),
  Response.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Wrapper method used for error responses
%%
%% @spec error(Response,ContentType) -> StatusCode
%% @end
%%--------------------------------------------------------------------
get_status_code(ResponseType) ->
    case ResponseType of
      <<"success">> -> 200;
      <<"failure">> -> 500;
      <<"error">> -> 404;
      <<"unauth">> -> 401
  end.
%%--------------------------------------------------------------------
%% @private
%% @doc
%% Wrapper method used for unknown commands
%%
%% @spec unknown(Url,ContentType) -> HTTPResponse
%% @end
%%--------------------------------------------------------------------
unknown(Url,ContentType) ->
  error("Unknown command: " ++Url, ContentType).


response_message(Type,Message,ContentType) ->
  message_handler:get_response_body(ContentType,
                                    message_handler:build_carrier(Type, Message)).

error(Message,ContentType) ->
  response_message("error", Message,ContentType).
%%--------------------------------------------------------------------
%% @private
%% @doc
%% Wrapper method used for error responses
%%
%% @spec send_response(ResponseType,{Response,ContentType}) -> HTTPResponse
%% @end
%%--------------------------------------------------------------------
send_response(ResponseType,{Response,ContentType}) ->
  StatusCode = get_status_code(ResponseType),
  {StatusCode, [{"Content-Type", ContentType}], list_to_binary(Response)}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Sets up the needed response type for our results.
%%
%% @spec handle_response(Response,ContentType) -> HTTPResponse
%% @end
%%--------------------------------------------------------------------
handle_response(Response,ContentType) ->
  case ContentType of
    ["text/xml"] ->
      send_response(<<"success">>,{Response,ContentType});
    ["text/json"] ->
      case check_json_response(Response) of
        {ResponseType,_} -> send_response(ResponseType,{Response,ContentType})
      end
  end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%%
%% Determines whether the client has successfully authenticated.
%%
%% Need to make this more secure.
%% @spec is_auth(Req) -> {ok,Msg}|{error,Error}
%%
%% @end
%%--------------------------------------------------------------------
is_auth(Req) ->
  case Req:get_header_value("authorization") of
    "Basic "++Base64 ->
      Str = base64:mime_decode_to_string(Base64),
      case string:tokens(Str, ":") of
        [User, Pass] ->
          chatterl_store:auth(User,Pass);
        _ ->
          {error,"Unauthorized authorization."}
      end;
    _ ->
      {error,"Need to authorize"}
  end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%%
%% Authorises a client and then carries out an action.
%%
%% Basic wrapper used to pass parameters to an anonymouse function.
%% @spec is_auth(Req) -> {ok,Msg}|{error,Error}
%%
%% @end
%%--------------------------------------------------------------------
authorise(ContentType,Req,{Fun,Params}) ->
  case is_auth(Req) of
    {error,Error} ->
      response_message('unauth',Error,ContentType);
    {ok,_} ->
      Fun(Params)
  end.
