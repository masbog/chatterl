-module(chatterl_test).

-include_lib("eunit/include/eunit.hrl").
-include_lib("stdlib/include/qlc.hrl").
-include_lib("chatterl.hrl").

%% Test chatterl_serv functionality
chatterl_serv_test_() ->
  [{setup,
    fun() ->
        ?assertEqual(ok,chatterl:start())
    end,
    fun(_) ->
        chatterl:stop() end,
    [{timeout, 5000,
      fun() ->
         {Group1,Description} = {"anuva","nu room"},
         ?assertEqual([],chatterl_serv:list_groups()),
         ?assertEqual([],chatterl_serv:list_users()),
         ?assertEqual({error,"Group doesn't exist!"},chatterl_serv:list_users(Group1)),
         ?assert(erlang:is_tuple(chatterl_serv:create(Group1,Description))),
         ?assertEqual({error,already_created},chatterl_serv:create(Group1,Description)),
         ?assertEqual([],chatterl_serv:list_users(Group1)),
         ?assertEqual([Group1],chatterl_serv:list_groups())
      end}]}].

chatterl_serv_groups_test_() ->
  {Client1,Group1,Group2,Description} = {"blah","room","anuva","nu room"},
  [{setup,
    fun() ->
        chatterl:start(),
        chatterl_serv:create(Group1,Description),
        chatterl_serv:create(Group2,"anuva room")
    end,
    fun(_) ->
        chatterl:stop() end,
    [fun() ->
         ?assertEqual([Group2,Group1],chatterl_serv:list_groups()),
         ?assertEqual({ok,"connected"},chatterl_serv:connect(Client1)),
         ?assertEqual([Client1],chatterl_serv:list_users()),
         ?assertEqual({error,"blah is unable to connect."},chatterl_serv:connect(Client1)),
         ?assertEqual({error,"Unable to disconnect noone"},chatterl_serv:disconnect("noone")),
         ?assertEqual({ok,"User disconnected: blah"},chatterl_serv:disconnect(Client1)),
         ?assertEqual({error,"Can not find group."},chatterl_serv:group_description("anuva1")),
         ?assertEqual({description,Description},chatterl_serv:group_description(Group1)),
         ?assert(erlang:is_tuple(gen_server:call({global, chatterl_serv}, {get_group, Group1}))),
         ?assertEqual({error,"Can not find blah"},chatterl_serv:drop("blah")),
         ?assertEqual({ok,"Group dropped anuva"},chatterl_serv:drop(Group2)),
         ?assert(erlang:is_list(gen_server:call({global,chatterl_serv},{group_info,Group1})))
     end]}].

chatterl_client_handle_test_() ->
  {Client1,Client2,Group,Description} = {"noobie","blah","anuva1","a nu room"},
  [{setup,
    fun() ->
        start_client(Client1,Group,Description),
        chatterl_client:start(Client2)
    end,
    fun(_) ->
        chatterl:stop() end,
    [{"Can we retrieve client information from a client process",
      fun() ->
          ?assertEqual({name,Client1}, gen_server:call({global,Client1},client_name)),
          ?assert(erlang:is_list(gen_server:call({global,Client1},groups))),
          ?assertEqual([], gen_server:call({global,Client2},groups)),
          ?assertEqual([], gen_server:call({global,Client2},poll_messages))
      end},
      {"Can a client join a group",
       fun() ->
          ?assertEqual({error,"Unknown error!"}, gen_server:call({global,Client2},{join_group,"none"})),
          ?assertEqual({ok,joined_group}, gen_server:call({global,Client1},{join_group,Group})),
          ?assertEqual(["anuva1"],gen_server:call({global,Client1},groups))
      end},
     {"Can a client send private messages",
      fun() ->
          ?assertEqual({ok,msg_sent}, gen_server:call({global,Client1},{private_msg,Client2,"sup"})),
          ?assertEqual({error,"Cannot find user!"}, gen_server:call({global,Client1},{private_msg,"noob","sup"})),
          ?assertEqual({ok,msg_sent}, gen_server:call({global,Client2},{private_msg,Client1,"sup"})),
          ?assertEqual({ok,msg_sent}, chatterl_client:private_msg(Client2,Client1,"sup")),
          ?assert(erlang:is_list(gen_server:call({global,Client1},poll_messages))),
          ?assertEqual({error,"Can not send to self!"}, gen_server:call({global,Client1},{private_msg,Client1,"sup"}))
     end},
     {"Can a client leave a group",
      fun() ->
          ?assertEqual({error,"Not connected"}, gen_server:call({global,Client2},{leave_group,Group})),
          ?assertEqual({ok, drop_group}, gen_server:call({global,Client1},{leave_group,Group})),
          ?assertEqual(stopped,gen_server:call({global,Client2},{stop,"because"}))
      end}]}].

%% Test our groups functionality
chatterl_group_handle_test_() ->
  {Client,Group,Description} = {"boodah","anuva","a nu room"},
  [{setup,
    fun() ->
        start_client(Client,Group,Description)
    end,
    fun(_) ->
        chatterl:stop() end,
   [{"Can retrieve group information",
     fun() ->
         ?assert(erlang:is_tuple(gen_server:call({global, chatterl_serv}, {get_group, Group}, infinity))),
         ?assertEqual({name,Group},gen_server:call({global,Group},name)),
         ?assertEqual({description,"a nu room"}, gen_server:call({global,Group},description)),
         ?assert(erlang:is_tuple(gen_server:call({global,Group},created))),
         ?assertEqual([],gen_server:call({global,Group},list_users)),
         ?assertEqual([],gen_server:call({global,Group},poll_messages))
     end},
    {"Client can join a group",
     fun() ->
         ?assertEqual({ok, "User added"},gen_server:call({global,Group},{join,Client})),
         ?assert(erlang:is_list(gen_server:call({global,Group},list_users))),
         ?assertEqual({error, "Already joined"},gen_server:call({global,Group},{join,Client})),
         ?assertEqual({error, "not connected"},gen_server:call({global,Group},{join,"nonUsers"})),
         ?assertEqual({error, "Invalid user name"},gen_server:call({global,Group},{join,{"nonUsers"}}))
     end},
    {"Client can leave a group",
     fun() ->
         ?assertEqual({ok, dropped}, gen_server:call({global,Group},{leave,Client})),
         ?assertEqual({error, "Not connected"}, gen_server:call({global,Group},{leave,Client})),
         ?assertEqual([],gen_server:call({global,Group},list_users))
     end},
    {"Client can send messages to a group",
     fun() ->
         ?assertEqual({ok, "User added"},gen_server:call({global,Group},{join,Client})),
         ?assertMatch({error, user_not_joined},gen_server:call({global,Group},{send_msg,"blah","hey"})),
         ?assertEqual({ok, msg_sent},gen_server:call({global,Group},{send_msg,Client,"hey"})),
         ?assertEqual({error,already_sent},gen_server:call({global,Group},{send_msg,Client,"heya"})),
         ?assert(erlang:is_list(gen_server:call({global,Group},poll_messages)))
     end}]}].
%% Test all our middle man json response
chatterl_mid_man_basics_test_() ->
  [{setup,
    fun() ->
        chatterl:start()
    end,
    fun(_) ->
        chatterl:stop()
    end,
    [{"Basic CWIGA tests.",
      fun() ->
          ?assertEqual(<<"Illegal content type!">>,
                       check_json(mochijson2:decode(chatterl_mid_man:user_list("text/json")))),
          ?assertEqual({struct,[{<<"clients">>,[]}]},
                       check_json(mochijson2:decode(chatterl_mid_man:user_list(["text/json"]))))
      end}]}].

chatterl_mid_man_message_poll_test_() ->
  {Client1,Client2} = {"baft","boodah"},
  [{setup,
    fun() ->
        chatterl:start(),
        chatterl_serv:create("sum other room","nu room"),
        chatterl_mid_man:connect(["text/json"],Client1),
        chatterl_mid_man:connect(["text/json"],Client2)
    end,
    fun(_) ->
        chatterl:stop()
    end,
    [{"Chatterl Middle Man can retrieve messages",
      fun() ->
          ?assertEqual({struct,[{<<"messages">>,[]}]},
                       check_json(mochijson2:decode(chatterl_mid_man:user_poll(["text/json"],Client1)))),
          ?assertEqual(<<"Sending message to boodah...">>,
                       check_json(mochijson2:decode(chatterl_mid_man:user_msg(["text/json"],{Client1,Client2,"hey"})))),
          ?assertEqual(<<"Client: foobar doesn't exist">>,
                       check_json(mochijson2:decode(chatterl_mid_man:user_poll(["text/json"],"foobar")))),
          ?assertEqual({struct,[{<<"messages">>,[]}]},
                       check_json(mochijson2:decode(chatterl_mid_man:user_poll(["text/json"],Client1)))),
          ?assert({struct,[{<<"messages">>,[]}]} /= mochijson2:decode(chatterl_mid_man:user_poll(["text/json"],Client2)))
      end}]}].

chatterl_mid_man_user_connect_test_() ->
  {Client1,Client2,Client3,Group} = {"baft","boodah","baphled","sum room"},
  [{setup,
    fun() ->
        chatterl:start(),
        chatterl_mid_man:connect(["text/json"],Client2),
        chatterl_serv:create(Group,"nu room")
    end,
    fun(_) ->
        chatterl:stop()
    end,
    [{"CWIGA retrieves client",
      fun() ->
          ?assertEqual({struct,[{<<"clients">>,[{struct,[{<<"client">>,<<"boodah">>}]}]}]},
                       check_json(mochijson2:decode(chatterl_mid_man:user_list(["text/json"]))))
      end},
     {"Clients can connect via CWIGA",
      fun() ->
          ?assertEqual(<<"baphled now connected">>,
                       check_json(mochijson2:decode(chatterl_mid_man:connect(["text/json"],Client3)))),
          ?assertEqual(<<"baphled is already connected">>,
                       check_json(mochijson2:decode(chatterl_mid_man:connect(["text/json"],Client3))))
      end},
     {"Clients can disconnect via CWIGA",
      fun() ->
          ?assertEqual(<<"Not connected">>,
                       check_json(mochijson2:decode(chatterl_mid_man:disconnect(["text/json"],Client1)))),
          ?assertEqual(<<"Disconnected">>,
                       check_json(mochijson2:decode(chatterl_mid_man:disconnect(["text/json"],Client3))))
      end},
     {"CWIGA can list clients",
      fun() ->
          ?assertEqual({struct,[{<<"clients">>,[]}]},
                       check_json(mochijson2:decode(chatterl_mid_man:user_list(["text/json"],Group)))),
          ?assertEqual(<<"Group: nonexistent doesn't exist">>,
                       check_json(mochijson2:decode(chatterl_mid_man:user_list(["text/json"],"nonexistent"))))
      end},
     {"CWIGA doesn't send client messages is not connected",
      fun() ->
          ?assertEqual(<<"blah is not connected!">>,
                       check_json(mochijson2:decode(chatterl_mid_man:user_msg(["text/json"],{"blah",Client2,"hey"})))),
          ?assertEqual(<<"baft is not connected!">>,
                       check_json(mochijson2:decode(chatterl_mid_man:user_msg(["text/json"],{Client1,"blah","hey"}))))
      end},
     {"CWIGA can send messages to connected clients",
      fun() ->
          ?assertEqual(<<"baft now connected">>,
                       check_json(mochijson2:decode(chatterl_mid_man:connect(["text/json"],Client1)))),
          ?assertEqual(<<"Sending message to boodah...">>,
                       check_json(mochijson2:decode(chatterl_mid_man:user_msg(["text/json"],{Client1,Client2,"hey"})))),
          ?assertEqual({struct,[{<<"messages">>,[]}]},
                       check_json(mochijson2:decode(chatterl_mid_man:user_poll(["text/json"],Client1))))
      end}]}].

chatterl_private_messages_test_() ->
  {Client1,Client2,Group} = {"baft","boodah","anuva"},
  [{setup,
    fun() ->
        chatterl:start(),
        chatterl_mid_man:connect(["text/json"],Client1),
        chatterl_mid_man:connect(["text/json"],Client2),
        chatterl_serv:create(Group,"nu room")
    end,
    fun(_) ->
        chatterl_mid_man:disconnect(["text/json"],Client1),
        chatterl_mid_man:disconnect(["text/json"],Client2),
        chatterl_serv:drop(Group),
        chatterl:stop()
    end,
    [{"CWIGA can send private messages & poll them",
      fun() ->
          Result = check_json(mochijson2:decode(chatterl_mid_man:user_poll(["text/json"],Client2))),
          ?assertEqual({struct,[{<<"messages">>,[]}]},Result),
          chatterl_mid_man:user_msg(["text/json"],{Client1,Client2,"hey u"}),
          ?assertEqual({struct,[{<<"messages">>,[]}]},
                       check_json(mochijson2:decode(chatterl_mid_man:user_poll(["text/json"],Client2)))),
          ?assert(Result /= check_json(mochijson2:decode(chatterl_mid_man:user_poll(["text/json"],Client2))))
    end}]}].

chatterl_user_groups_test_() ->
  {Client1,Client2,Group,ContentType} = {"baph","boodah","nu",["text/json"]},
  [{setup,
    fun() ->
        chatterl:start(),
        chatterl_mid_man:connect(ContentType,Client1),
        chatterl_mid_man:connect(ContentType,Client2),
        chatterl_serv:create(Group,"nu room"),
        chatterl_mid_man:group_join(ContentType,{Group,Client2})
    end,
    fun(_) ->
        chatterl:stop()
    end,
    [{"CWIGA allows clients to join groups",
      fun() ->
          ?assertEqual(<<"Group: blah doesn't exist">>,
                       check_json(mochijson2:decode(chatterl_mid_man:group_join(ContentType,{"blah",Client2})))),
          ?assertEqual({struct,[{<<"groups">>,[]}]},
                       check_json(mochijson2:decode(chatterl_mid_man:user_groups(ContentType,Client1)))),
          ?assertEqual(<<"Client: blah doesn't exist">>,
                       check_json(mochijson2:decode(chatterl_mid_man:user_groups(ContentType,"blah"))))
      end},
      {"CWIGA can list clients joined to groups",
       fun() ->
          ?assertEqual([Group],gen_server:call({global,Client2},groups)),
          ?assertEqual({struct,[{<<"groups">>,[{struct,[{<<"group">>,<<"nu">>}]}]}]},
                       check_json(mochijson2:decode(chatterl_mid_man:user_groups(ContentType,Client2)))),
          ?assertEqual({struct,[{<<"groups">>,[{struct,[{<<"group">>,<<"nu">>}]}]}]},
                       check_json(mochijson2:decode(chatterl_mid_man:group_list(ContentType))))
      end},
     {"CWIGA allows clients to leave groups",
      fun() ->
          ?assertEqual(<<"Group: blah doesn't exist">>,
                       check_json(mochijson2:decode(chatterl_mid_man:group_leave(ContentType,{"blah",Client2})))),
          ?assertEqual(<<"User not joined">>,
                      check_json(mochijson2:decode(chatterl_mid_man:group_leave(ContentType,{"blah","blah"})))),
          ?assertEqual(<<"boodah has disconnected from nu">>,
                      check_json(mochijson2:decode(chatterl_mid_man:group_leave(ContentType,{Group,Client2}))))
       end}]}].

chatterl_group_create_test_() ->
  {Room,Description,ContentType} = {"nu","nu room",["text/json"]},
  [{setup, fun() ->
               chatterl:start()
           end,
    fun(_) -> chatterl:stop() end,
    [{timeout, 5000,
      fun() ->
          ?assertEqual({struct,[{<<"groups">>,[]}]},check_json(mochijson2:decode(chatterl_mid_man:group_list(ContentType)))),
          ?assertEqual(<<"Group: nu added">>,
                       check_json(mochijson2:decode(chatterl_mid_man:group_create(ContentType,{Room,Description})))),
          ?assertEqual(<<"Unable to create group: nu">>,
                       check_json(mochijson2:decode(chatterl_mid_man:group_create(ContentType,{Room,Description})))),
          % abit lazy but not sure how to check the creation date dynamically atm.
          ?assert(erlang:is_tuple(check_json(mochijson2:decode(chatterl_mid_man:group_info(ContentType,Room))))),
          ?assertEqual(<<"Group dropped nu">>,
                       check_json(mochijson2:decode(chatterl_mid_man:group_drop(ContentType,Room)))),
          ?assertEqual(<<"Can not find nu">>,
                       check_json(mochijson2:decode(chatterl_mid_man:group_drop(ContentType,Room)))),
          ?assertEqual(<<"Group doesn't exist!">>,
                       check_json(mochijson2:decode(chatterl_mid_man:group_info(ContentType,Room))))
      end}]}].

chatterl_group_messages_test_() ->
  {Client,Group,ContentType} = {"baph","nu",["text/json"]},
  [{setup, fun() ->
               chatterl:start(),
               chatterl_mid_man:connect(ContentType,Client),
               chatterl_serv:create(Group,"nu room"),
               chatterl_mid_man:group_join(ContentType,{Group,Client})
           end,
    fun(_) -> chatterl:stop() end,
    [{timeout, 5000,
      fun() ->
          Result = {struct,[{<<"messages">>,[]}]},
          ?assertEqual(Result,
                       check_json(mochijson2:decode(chatterl_mid_man:group_poll(["text/json"],Group)))),
          ?assertEqual(<<"Unable to send msg!">>,
                       check_json(mochijson2:decode(chatterl_mid_man:group_send(["text/json"],{Group,"blah","hey"})))),
          ?assertEqual(<<"User not joined">>,
                       check_json(mochijson2:decode(chatterl_mid_man:group_send(["text/json"],{"blah",Client,"hey"})))),
          ?assertEqual(<<"Message sent">>,
                       check_json(mochijson2:decode(chatterl_mid_man:group_send(["text/json"],{Group,Client,"hey"})))),
          ?assert(Result /=  check_json(mochijson2:decode(chatterl_mid_man:group_poll(["text/json"],Group)))),
          ?assertEqual(<<"Group: blah doesn't exist!">>,
                       check_json(mochijson2:decode(chatterl_mid_man:group_poll(["text/json"],"blah"))))
           end}]}].

% Basic units to implement the storage client and group processe states
chatterl_store_test_() ->
  {Client,Group,Description} = {"noob","nu","nu room"},
  [{setup,
    fun() ->
        chatterl:start(),
        chatterl_serv:create(Group,Description),
        chatterl_client:start(Client),
        gen_server:call({global,Client},{join_group,Group}),
        chatterl_store:start_link(ram_copies)
    end,
    fun(_) ->
        chatterl_store:stop(),
        mnesia:clear_table(group),
        mnesia:clear_table(client),
        mnesia:clear_table(registered_user),
        chatterl:stop()
    end,
    [{timeout, 5000,
      fun() ->
          ?assertEqual([registered_user,client,group,schema],mnesia:system_info(tables))
      end},
    fun() ->
        GroupState = gen_server:call({global,Group},get_state),
        ?assertEqual(Group,GroupState#group.name),
        ?assertEqual(Description,GroupState#group.description),
        ?assert(erlang:is_tuple(GroupState#group.created)),
        ?assertEqual({0,nil},GroupState#group.messages),
        ?assert(erlang:is_tuple(GroupState#group.users)),
        ?assertEqual({error,"Group doesn't exist"},chatterl_store:group("anuva")),
        ?assertEqual(ok,chatterl_store:group(Group)),
        ?assertEqual([GroupState],chatterl_store:get_group(Group))
    end,
    fun() ->
        ClientState = gen_server:call({global,Client},get_state),
        ?assertEqual(Client,ClientState#client.name),
        ?assertEqual(ok,chatterl_store:user(Client)),
        ?assertEqual({0,nil},ClientState#client.messages),
        ?assertEqual({error,"User doesn't exist"},chatterl_store:user("blah")),
        ?assert(erlang:is_tuple(ClientState#client.groups)),
        ?assertEqual([ClientState],chatterl_store:get_user(Client))
       end]}].

chatterl_store_user_register_test_() ->
  {Nick1,Name1,Email1,Password1} = {"noobie","noobie 1","noobie@noobie.com","blahblah"},
  {Nick2,Name2,Email2,Password2} = {"nerf","nerf 1","nerf@noobie.com","asfdasdf"},
  [{setup,
    fun() ->
        chatterl:start(),
        chatterl_client:start(Nick1),
        chatterl_store:start_link(ram_copies)
    end,
    fun(_) ->
        chatterl_store:stop(),
        mnesia:delete_table(client),
        mnesia:delete_table(group),
        mnesia:clear_table(registered_user),
        chatterl:stop()
    end,
    [fun() ->
          ?assertEqual({ok,"noobie is registered"},chatterl_store:register(Nick1,{Name1,Email1,Password1,Password1})),
          ?assertEqual({ok,"nerf is registered"},chatterl_store:register(Nick2,{Name2,Email2,Password2,Password2})),
          ?assertEqual({error,"noobie's passwords must match"},chatterl_store:register(Nick1,{Name1,Email1,Password1,"blah"}))
     end,
     fun() ->
         ?assertEqual({ok,"noobie Authorized"},chatterl_store:auth(Nick1,Password1)),
         ?assertEqual({error,"Unable to authorise blah"},chatterl_store:auth("blah","blah")),
         ?assertEqual([{Nick2,Name2,Email2},{Nick1,Name1,Email1}], chatterl_store:registered())
     end,
     fun() ->
         ?assertEqual({error,"noobie is already registered"},chatterl_store:register(Nick1,{Name1,Email1,Password1,Password1})),
         ?assert(chatterl_store:is_auth(Nick1,Password1)),
         ?assert(false =:= chatterl_store:is_auth(Nick1,"blah"))
      end]}].

chatterl_registered_user_store_group_test_() ->
  ContentType = ["text/json"],
  {Nick1,Name1,Email1,Password1} = {"noobie","noobie 1","noobie@noobie.com","blahblah"},
  {Nick2,Name2,Email2,Password2} = {"nerf","nerf 1","nerf@noobie.com","asfdasdf"},
  [{setup,
    fun() ->
        chatterl:start(),
        chatterl_store:start_link(ram_copies)
    end,
    fun(_) ->
        chatterl_store:stop(),
        mnesia:clear_table(registered_user),
        chatterl:stop()
    end,
    [{timeout,5000,
      fun() ->
          ?assertEqual({ok,"noobie is registered"},chatterl_store:register(Nick1,{Name1,Email1,Password1,Password1})),
          ?assertEqual([{Nick1,Name1,Email1}],chatterl_store:registered()),
          ?assertEqual({struct,[{<<"registered">>,
                                 {struct,[{<<"client">>,[{struct,[{<<"nick">>,<<"noobie">>}]},
                                                         {struct,[{<<"name">>,<<"noobie 1">>}]},
                                                         {struct,[{<<"email">>,<<"noobie@noobie.com">>}]}]}]}
                                }]},
                       check_json(mochijson2:decode(chatterl_mid_man:registered_list(ContentType))))
      end},
     fun() ->
         ?assertEqual({ok,"nerf is registered"},chatterl_store:register(Nick2,{Name2,Email2,Password2,Password2})),
         ?assertEqual([{Nick2,Name2,Email2},{Nick1,Name1,Email1}],chatterl_store:registered()),
         ?assertEqual({struct,[{<<"registered">>,[
                                                  {struct,[{<<"client">>,[{struct,[{<<"nick">>,<<"nerf">>}]},
                                                                          {struct,[{<<"name">>,<<"nerf 1">>}]},
                                                                          {struct,[{<<"email">>,<<"nerf@noobie.com">>}]}]}]},
                                                  {struct,[{<<"client">>,[{struct,[{<<"nick">>,<<"noobie">>}]},
                                                                          {struct,[{<<"name">>,<<"noobie 1">>}]},
                                                                          {struct,[{<<"email">>,<<"noobie@noobie.com">>}]}]}]}
                                                 ]}]}, check_json(mochijson2:decode(chatterl_mid_man:registered_list(ContentType))))
     end]}].

chatterl_registered_users_can_login_and_out_test_() ->
  {Nick1,Name1,Email1,Password1,Nick2,Password2} = {"noobie","noobie 1","noobie@noobie.com","blahblah","nerf","asdasd"},
  [{setup,
    fun() ->
        chatterl:start(),
        chatterl_store:start_link(ram_copies),
        chatterl_store:register(Nick1,{Name1,Email1,Password1,Password1})
    end,
    fun(_) ->
        chatterl_store:stop(),
        mnesia:delete_table(registered_user),
        chatterl:stop()
    end,
    [{"Do registered client login successfully & unregistered fail",
      fun() ->
          ?assertEqual([],chatterl_store:get_registered(Nick2)),
          ?assertEqual([{registered_user,Nick1,Name1,Email1,erlang:md5(Password1),0,{0,nil}}],chatterl_store:get_registered(Nick1)),
          ?assertEqual({error,"Unable to login"},chatterl_store:login(Nick1,"blah")),
          ?assertEqual({error,"Not Registered"},chatterl_store:login(Nick2,Password2)),
          ?assertEqual({ok,"Logged in"},chatterl_store:login(Nick1,Password1)),
          ?assertEqual([{registered_user,Nick1,Name1,Email1,erlang:md5(Password1),1,{0,nil}}],chatterl_store:get_registered(Nick1)),
          ?assertEqual([Nick1],chatterl_store:get_logged_in())
      end},
     {"What happens when a registered client & an unregistered client try to log out",
       fun() ->
         ?assertEqual(false,chatterl_store:logged_in(Nick2)),
         ?assertEqual({error,"Not logged in"},chatterl_store:logout(Nick2)),
         ?assertEqual(true,chatterl_store:logged_in(Nick1)),
         ?assertEqual([{Nick1,Name1,Email1}],chatterl_store:registered()),
         ?assertEqual({ok,"Logged out"},chatterl_store:logout(Nick1)),
         ?assertEqual(false,chatterl_store:logged_in(Nick1))
     end},
     {"Can our client login using chatterl_serv?",
      fun() ->
         ?assertEqual({error,"Unable to login"},chatterl_serv:login(Nick1,"blah")),
         ?assertEqual({error,"Not Registered"},chatterl_serv:login(Nick2,Password2)),
         ?assertEqual({ok,"noobie is logged in."},chatterl_serv:login(Nick1,Password1)),
         ?assertEqual([Nick1],chatterl_store:get_logged_in())
     end},
     {"Does chatterl handle logins as we expect them to",
      fun() ->
         ?assertEqual(true,gen_server:call({global,chatterl_serv},{user_exists,Nick1})),
         ?assertEqual(false,gen_server:call({global,chatterl_serv},{user_exists,Nick2})),
         ?assertEqual(true,chatterl_store:logged_in(Nick1)),
         ?assertEqual({ok,"noobie is logged out."},chatterl_serv:logout(Nick1)),
         ?assertEqual(false,gen_server:call({global,chatterl_serv},{user_exists,Nick1}))
     end},
     {"Can a client successfully logout",
      fun() ->
         ?assertEqual(false,chatterl_store:logged_in(Nick2)),
         ?assertEqual({error,"Not logged in"},chatterl_serv:logout(Nick2)),
         ?assertEqual(false,chatterl_store:logged_in(Nick1))
      end}]}].

chatterl_registered_users_can_logout_properly_test_() ->
  {Nick1,Name1,Email1,Password1,Nick2,Password2} = {"noobie","noobie 1","noobie@noobie.com","blahblah","nerf","asdasd"},
  {NewName,NewEmail,NewPassword} = {"new name","y@me.com","encrypt"},
  [{setup,
    fun() ->
        chatterl:start(),
        chatterl_store:start_link(ram_copies),
        chatterl_store:register(Nick1,{Name1,Email1,Password1,Password1}),
        chatterl_serv:login(Nick1,Password1)
    end,
    fun(_) ->
        chatterl_store:stop(),
        mnesia:delete_table(registered_user),
        chatterl:stop()
    end,
    [{"Client is able to edit their profiles",
      fun() ->
          ?assertEqual({error,"nerf not logged in"},chatterl_store:edit_profile(Nick2,{firstname,"some name"})),
          ?assertEqual({ok,"Updated profile"},chatterl_store:edit_profile(Nick1,{firstname,NewName})),
          ?assertEqual({error,"Unable to update profile"},chatterl_store:edit_profile(Nick1,{blah,NewName})),
          ?assertEqual([{registered_user,Nick1,NewName,Email1,erlang:md5(Password1),1,{0,nil}}],chatterl_store:get_registered(Nick1)),
          ?assertEqual({ok,"Updated profile"},chatterl_store:edit_profile(Nick1,{email,NewEmail})),
          ?assertEqual([{registered_user,Nick1,NewName,NewEmail,erlang:md5(Password1),1,{0,nil}}],chatterl_store:get_registered(Nick1)),
          ?assertEqual({ok,"Updated profile"},chatterl_store:edit_profile(Nick1,{password,NewPassword})),
          ?assertEqual([{registered_user,Nick1,NewName,NewEmail,erlang:md5(NewPassword),1,{0,nil}}],chatterl_store:get_registered(Nick1))
      end},
     {"Client processes log their selves out on termination",
      fun() ->
          ?assertEqual(true,chatterl_store:logged_in(Nick1)),
          ?assertEqual({ok,"Logged out"},chatterl_client:stop(Nick1)),
          ?assertEqual(false,chatterl_store:logged_in(Nick1)),
          ?assertEqual({ok,"noobie is logged in."},chatterl_serv:login(Nick1,NewPassword))
      end}]}].

%% Helper functions.
start_client(Client,Group,Description) ->
  start_group(Group,Description),
  chatterl_client:start(Client).

start_group(Group,Description) ->
  chatterl:start(),
  chatterl_serv:create(Group,Description).

check_json(Json) ->
  {struct,[{<<"chatterl">>,{struct,[{<<"response">>,{struct,[Response]}}]}}]} = Json,
  case Response of
    {<<"success">>,Result} ->
      Result;
    {<<"failure">>,Result} ->
      Result;
    {<<"error">>,Result} ->
      Result
  end.
