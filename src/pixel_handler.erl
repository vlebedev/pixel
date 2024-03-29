-module(pixel_handler).
-author("wal").

-behavior(cowboy_http_handler).

-export([init/3]).
-export([handle/2]).
-export([handle_request/2]).
-export([terminate/3]).

-define(TENYEARS, 10*365*24*60*60).
-define(PIXEL_PNG, "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAAl21bKAAAAA1BMVEUAAACnej3aAAAAAXRSTlMAQObYZgAAAApJREFUCNdjYAAAAAIAAeIhvDMAAAAASUVORK5CYII=").

init(_Type, Req, _Opts) ->
    State = base64:decode(?PIXEL_PNG),
    {ok, Req, State}.

handle(Req, State) ->
    {ok, Eflame} = application:get_env(pixel, eflame),
    case Eflame of
        true ->
            try eflame:apply(pixel_handler, handle_request, [Req, State]) of
                R -> R
            catch
                _Err:_Reason ->
                    {ok, Req, State}
            end;
        false ->
            handle_request(Req, State)
    end.


terminate(_Reason, _Req, _State) ->
    ok.

handle_request(Req, State) ->
    Start = util:jstime_micro(os:timestamp()),
    %% Get headers and other properties from incoming request
    {Query, Req2}       = cowboy_req:qs(Req),
    {Headers, Req3}     = cowboy_req:headers(Req2),
    {{IP, Port}, Req4}  = cowboy_req:peer(Req3),
    {Host, Req5}        = cowboy_req:host(Req4),
    {HostPort, Req6}    = cowboy_req:port(Req5),
    {Path, Req7}        = cowboy_req:path(Req6),
    {Pid, Req8}         = cowboy_req:qs_val(<<"pid">>, Req7, <<"">>),
    {URL, Req10}        = cowboy_req:url(Req8),
    %% Read the cookie (set it to generated UUID if absent) and set the cookie in our response
    UUID = base64:encode(uuid:uuid4()),
    {Cookie, Req11} = get_cookie_safe(<<"sberlabspx">>, Req10, UUID),
    Req12 = cowboy_req:set_resp_cookie(<<"sberlabspx">>, Cookie, [{max_age, ?TENYEARS}], Req11),
    %% Prepare request data to be published to subscribers
    Data = {[
             {<<"ts">>, Start div 1000},
             {<<"client">>, {[
                        {<<"ip">>, util:addr_to_string(IP)},
                        {<<"port">>, Port}
                       ]}},
             {<<"resource">>, {[
                          {<<"url">>, URL},
                          {<<"host">>, Host},
                          {<<"port">>, HostPort},
                          {<<"path">>, Path},
                          {<<"q">>, Query}
                         ]}},
            {<<"cookie">>, Cookie},
            {<<"pid">>, Pid},
            {<<"headers">>, {Headers}}
            ]},
    %% Publish data to pixel_data process group
    gproc_ps:publish(g, pixel_data, Data),
    %% Reply to original request, serve invisible tracking pixel
    {ok, Req13} = cowboy_req:reply(200, [
                                         {<<"content-type">>, <<"image/png">>},
                                         {<<"connection">>, <<"close">>}
                                        ], State, Req12),
    Finish = util:jstime_micro(os:timestamp()),
    folsom_metrics:notify({{pixel, cowboy, p_img_request}, Finish - Start}),
    {ok, Req13, State}.

get_cookie_safe(Name, Req, DefVal) ->
    case catch cowboy_req:cookie(Name, Req, DefVal) of
        {'EXIT', _} ->
            %% Handle malformed 'cookie' header on some mobile devices/browsers
            {DefVal, Req};
        {Cookie, Req1} ->
            {Cookie, Req1}
    end.
    








