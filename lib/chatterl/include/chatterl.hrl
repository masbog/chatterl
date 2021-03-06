%%%-------------------------------------------------------------------
%%% File    : chatterl.hrl
%%% Author  : Yomi Colledge <yomi@boodah.net>
%%% Description : Records associated with Chatterl
%%%
%%% Created : 18 Dec 2008-2009 by Yomi Colledge <yomi@boodah.net>
%%%-------------------------------------------------------------------

%% Records for chatterl_serv, will track the total users & groups.
-record(chatterl, {groups, users}).
%% Records associated with groups
-record(group, {name, description,created, messages, users}).
%% Records associated with users
-record(client, {name, ip, groups, messages}).
%% Stores our registered clients credentials for login.
-record(registered_user, {nick,firstname,email,password,logged_in}).
-record(messages,{recipient,created_on,sender,msg}).
