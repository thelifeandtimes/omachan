::  Derived from Fang's rumors; signed discovery reuses Omart's crypto pattern.
/-  *omachan
/+  default-agent, dbug, pals, server, crypto=omachan-crypto,
    network=omachan-network, board=omachan-board, web=omachan-http, defaults=omachan-config
|%
+$  card  card:agent:gall
++  helpers
  |_  [bowl=bowl:gall st=state]
  +*  net  ~(. network bowl st)
      gossip  ~(. board bowl st)
      pal  ~(. pals bowl)
  ++  own-claim
    |=  active=?
    ^-  (quip card state)
    =.  revision.st  (max +(revision.st) now.bowl)
    =/  data  (seal:crypto our.bowl now.bowl revision.st active |)
    =/  a=announcement  [data 0 our.bowl]
    =.  claims.st  (~(put by claims.st) our.bowl a)
    [(broadcast-claim:net a our.bowl) st]
  ++  receive-claim
    |=  [via=ship env=claim-wire]
    ^-  (quip card state)
    ?.  &((gte distance.env 1) (lte distance.env 2) (fresh:crypto now.bowl data.env))  [~ st]
    =/  who  origin.body.data.env
    =/  auth  (authenticate:crypto our.bowl now.bowl data.env)
    ?~  auth
      ?.  &((shape:crypto data.env) (autograph:crypto data.env))  [~ st]
      ?:  (gte (lent pending.st) 128)  [~ st]
      =.  pending.st  [[via now.bowl env] pending.st]
      ?:  |((~(has in tracked.st) who) (gte ~(wyt in tracked.st) 512))  [~ st]
      =.  tracked.st  (~(put in tracked.st) who)
      :_  st
      [%pass /keys/(scot %p who) %arvo %j %public-keys (silt ~[who])]~
    ?.  u.auth  [~ st]
    ?^  old=(~(get by claims.st) who)
      ?.  (newer:crypto data.env data.u.old)
        ?.  &(=(data.env data.u.old) (lth distance.env distance.u.old))  [~ st]
        =/  a=announcement  [data.env distance.env via]
        =.  claims.st  (~(put by claims.st) who a)
        [(broadcast-claim:net a via) st]
      $(claims.st (~(del by claims.st) who))
    ?:  (gte ~(wyt by claims.st) 512)  [~ st]
    =/  a=announcement  [data.env distance.env via]
    =.  claims.st  (~(put by claims.st) who a)
    =/  cards  (broadcast-claim:net a via)
    ?:  |(=(who our.bowl) =(%pawn (clan:title who)) (~(has in tracked.st) who) (gte ~(wyt in tracked.st) 512))
      [cards st]
    =.  tracked.st  (~(put in tracked.st) who)
    [[[%pass /keys/(scot %p who) %arvo %j %public-keys (silt ~[who])] cards] st]
  ++  receive-claims
    |=  [via=ship rows=(list claim-wire)]
    ^-  (quip card state)
    =|  cards=(list card)
    |-
    ?~  rows  [cards st]
    =^  more  st  (receive-claim via i.rows)
    $(rows t.rows, cards (weld cards more))
  ++  retry-pending
    ^-  (quip card state)
    =/  rows  pending.st
    =.  pending.st  ~
    =|  cards=(list card)
    |-
    ?~  rows  [cards st]
    =/  row  i.rows
    ?:  (lth received.row (sub now.bowl ~m10))  $(rows t.rows)
    ?~  auth=(authenticate:crypto our.bowl now.bowl data.env.row)
      $(rows t.rows, pending.st [row pending.st])
    =^  more  st  (receive-claim via.row env.row)
    $(rows t.rows, cards (weld cards more))
  ++  accept-peers
    ^-  (list card)
    ?.  &(auto-accept.st joined.st running:pal)  ~
    =/  candidates
      %+  skim  ~(tap by claims.st)
      |=  [who=ship a=announcement]
      ?&  !=(who our.bowl)
          active.body.data.a
          (claim-live:net data.a)
          !(~(has in dismissed.st) who)
          !(target:pal ~.omarchy who)
      ==
    %+  turn  (scag 32 candidates)
    |=  [who=ship a=announcement]
    =/  command  [%meet who (silt ~[~.omarchy])]
    [%pass /auto/(scot %p who) %agent [our.bowl %pals] %poke %pals-command !>(command)]
  ++  refresh
    ^-  (quip card state)
    =^  cards  st  retry-pending
    =^  cleanup  st  maintain:gossip
    =.  claims.st
      %-  ~(gas by *(map ship announcement))
      %+  skim  ~(tap by claims.st)
      |=  [who=ship a=announcement]
      |(=(who our.bowl) (gth expires.body.data.a now.bowl))
    =^  renew  st
      ?.  enabled:net  [~ st]
      ?^  a=(~(get by claims.st) our.bowl)
        ?:  &((claim-live:net data.u.a) (gth expires.body.data.u.a (add now.bowl ~d1)))  [~ st]
        (own-claim &)
      (own-claim &)
    =/  hellos=(list card)
      ?.  enabled:net  *(list card)
      (zing (turn ~(tap in discovery-peers:net) hello:net))
    [:(weld cards cleanup renew hellos accept-peers reconcile:net) st]

  ++  startup
    ^-  (quip card state)
    =.  next.st  (add now.bowl ~s30)
    =^  cards  st  refresh
    =/  extra=(list card)
      :~  [%pass /eyre/connect %arvo %e %connect [~ /omachan] dap.bowl]
          [%pass /eyre/apps %arvo %e %connect [~ /apps/omachan] dap.bowl]
          [%pass /timer/(scot %da next.st) %arvo %b %wait next.st]
          [%pass /keys/(scot %p our.bowl) %arvo %j %public-keys (silt ~[our.bowl])]
      ==
    [(weld cards extra) st]
  ++  act
    |=  jon=json
    ^-  (each (quip card state) @t)
    =/  action  (str:web jon 'action')
    ?+  action  [%| 'Unknown action']
        %join
      =.  joined.st  &
      =^  cards  st  (own-claim &)
      =^  more  st  refresh
      [%& (weld cards more) st(note 'Your signed claim is being shared.')]
        %leave
      =^  cards  st  (own-claim |)
      [%& cards st(joined |, note 'Discovery withdrawn. Existing pals are unchanged.')]
        %config
      =/  name  (str:web jon 'seed')
      =/  seed=(unit ship)  ?~(name ~ (slaw %p name))
      ?:  &(!=(name '') ?=(~ seed))  [%| 'Invalid bootstrap ship']
      ?:  =(`our.bowl seed)  [%| 'Bootstrap ship must be another ship']
      =.  cfg.st  [seed |]
      =^  cards  st  ?.  enabled:net  [~ st]  (own-claim &)
      =^  more  st  refresh
      [%& (weld cards more) st(note 'Connection settings saved.')]
        %preferences
      =.  auto-accept.st  (flag:web jon 'autoAccept' auto-accept.st)
      =.  preferences-set.st  &
      [%& accept-peers st(note 'Peer preferences saved.')]
        %bootstrap
      ?.  running:pal  [%| '%pals is not running']
      =/  name  (str:web jon 'ship')
      =/  who=(unit ship)  ?:  =(name '')  `(fall seed.cfg.st hub:defaults)  (slaw %p name)
      ?~  who  [%| 'Invalid discovery hub']
      ?:  =(u.who our.bowl)  [%| 'Choose another ship as your first pal']
      =.  seed.cfg.st  who
      =.  bootstrap.st  who
      =.  dismissed.st  (~(del in dismissed.st) u.who)
      =/  command  [%meet u.who (silt ~[~.omarchy])]
      :+  %&
        [%pass /bootstrap/(scot %p u.who) %agent [our.bowl %pals] %poke %pals-command !>(command)]~
      st(note 'Adding your first pal before announcing discovery.')
        %retry
      =^  cards  st  refresh
      [%& cards st(note 'Connections refreshed.')]
        %add
      ?.  running:pal  [%| '%pals is not running']
      ?.  joined.st  [%| 'Join discovery before exchanging peers']
      ?~  who=(slaw %p (str:web jon 'ship'))  [%| 'Invalid ship']
      ?:  =(u.who our.bowl)  [%| 'Cannot add yourself']
      ?~  a=(~(get by claims.st) u.who)  [%| 'No signed claim for this ship']
      ?.  &((claim-live:net data.u.a) active.body.data.u.a)  [%| 'Claim expired, withdrawn, or awaiting key verification']
      =.  dismissed.st  (~(del in dismissed.st) u.who)
      =.  links.st  (~(put in links.st) u.who)
      =/  command  [%meet u.who (silt ~[~.omarchy])]
      :+  %&
        [[%pass /pals-command %agent [our.bowl %pals] %poke %pals-command !>(command)] (hello:net u.who)]
      st(note 'Added with omarchy tag. The other ship must add/tag you back.')
        %dismiss
      ?~  who=(slaw %p (str:web jon 'ship'))  [%| 'Invalid ship']
      [%& ~ st(dismissed (~(put in dismissed.st) u.who), links (~(del in links.st) u.who), note 'Suggestion hidden. You can restore it in Peers.')]
        %restore
      ?~  who=(slaw %p (str:web jon 'ship'))  [%| 'Invalid ship']
      [%& ~ st(dismissed (~(del in dismissed.st) u.who), note 'Suggestion restored. Your auto-accept preference applies.')]
        %remove
      ?.  running:pal  [%| '%pals is not running']
      ?~  who=(slaw %p (str:web jon 'ship'))  [%| 'Invalid ship']
      =.  dismissed.st  (~(put in dismissed.st) u.who)
      =.  links.st  (~(del in links.st) u.who)
      =/  command  [%part u.who (silt ~[~.omarchy])]
      :+  %&
        [[%pass /pals-command %agent [our.bowl %pals] %poke %pals-command !>(command)] reconcile:net]
      st(note 'Disconnected your side by removing your omarchy tag. Their friendship and tags of you are unchanged.')
        %post
      ?.  running:pal  [%| '%pals is not running']
      =/  text  (str:web jon 'text')
      ?.  &((gth (met 3 text) 0) (lte (met 3 text) 1.024))  [%| 'Posts must contain 1 to 1024 UTF-8 bytes']
      =/  p=post  [(sham [now.bowl eny.bowl text]) now.bowl text]
      =/  e=post-entry  [p 0]
      =.  st  (remember:gossip id.p)
      =.  posts.st  (~(put by posts.st) id.p e)
      =^  cards  st  (emit:gossip p)
      =^  more  st  maintain:gossip
      :+  %&  (weld cards more)
      st(note 'Posted. Delivery depends on your connected tagged mutuals.')
    ==
  --
--
=|  st=state
%-  agent:dbug
^-  agent:gall
|_  =bowl:gall
+*  this  .
    def  ~(. (default-agent this %|) bowl)
    net  ~(. network bowl st)
    up   ~(. helpers bowl st)
    gossip  ~(. board bowl st)
++  on-init
  ^-  (quip card _this)
  ::  The desk recommends the hub; the install source need not participate.
  =.  seed.cfg.st  ?:  =(our.bowl hub:defaults)  ~  `hub:defaults
  =^  cards  st  startup:up
  [cards this]
++  on-save  !>(st)
++  on-load
  |=  old=vase
  ^-  (quip card _this)
  =.  st
    ?+  -.q.old  !!
      %0  =/  prior  !<(state-0 old)
          [%2 +.prior ~(key by posts.prior) ~ ~ | | ~ ~ 0]
      %1  =/  prior  !<(state-1 old)
          [%2 +<.prior shared.prior passes.prior misses.prior | | ~ ~ 0]
      %2  !<(state old)
    ==
  ::  Legacy posts retain their old order; subsequent arrivals use local order.
  =/  legacy
    %+  sort  ~(val by posts.st)
    |=  [a=post-entry b=post-entry]
    (lth when.data.a when.data.b)
  =.  st
    |-
    ?~  legacy  st
    =.  st  (remember:gossip id.data.i.legacy)
    $(legacy t.legacy)
  ::  Old discovery-only settings no longer restrict participation.
  =.  relay-only.cfg.st  |
  =^  cards  st  startup:up
  [cards this]
++  on-poke
  |=  [=mark =vase]
  ^-  (quip card _this)
  ?+  mark  (on-poke:def mark vase)
      %omachan-pass
    =^  cards  st  (receive-pass:gossip !<(post vase))
    =^  more  st  maintain:gossip
    [(weld cards more) this]
      %omachan-hello
    ?>  enabled:net
    =/  c  !<(claim vase)
    ?>  =(origin.body.c src.bowl)
    ?>  &((fresh:crypto now.bowl c) active.body.c)
    ?>  !(~(has in dismissed.st) src.bowl)
    =^  cards  st  (receive-claim:up src.bowl [c 1])
    ?.  =(`& (authenticate:crypto our.bowl now.bowl c))  [cards this]
    ?:  (gte ~(wyt in links.st) 256)  [cards this]
    =.  links.st  (~(put in links.st) src.bowl)
    [:(weld cards accept-peers:up (send-claims:net src.bowl claims-for-wire:net)) this]
      %omachan-claims
    ?>  (discovery-allowed:net src.bowl)
    =/  rows  !<((list claim-wire) vase)
    ?>  (lte (lent rows) 16)
    =^  cards  st  (receive-claims:up src.bowl rows)
    [(weld cards accept-peers:up) this]
      %handle-http-request
    =+  !<([eyre-id=@ta req=inbound-request:eyre] vase)
    =/  sit  site:(parse-request-line:server url.request.req)
    =/  tail  ?~(sit %$ (rear sit))
    =/  method  method.request.req
    ?:  =(method %'GET')
      :_  this
      %+  give-simple-payload:app:server  eyre-id
      ?:  =(tail %state)
        ?.  &(=(src our):bowl authenticated.req)  (error:web 401 'Sign in to your ship')
        (response:web 200 (view:web bowl st))
      ?:  =(tail %app)  (static:web bowl 'text/javascript' /web/app/js)
      ?:  =(tail %style)  (static:web bowl 'text/css' /web/style/css)
      (static:web bowl 'text/html' /web/index/html)
    ?.  &(=(method %'POST') =(tail %action))
      [(give-simple-payload:app:server eyre-id (error:web 404 'Unknown endpoint')) this]
    ?.  &(=(src our):bowl authenticated.req (csrf:web req))
      [(give-simple-payload:app:server eyre-id (error:web 403 'Sign in and use a same-origin request')) this]
    ?~  body.request.req
      [(give-simple-payload:app:server eyre-id (error:web 400 'Missing JSON body')) this]
    ?:  (gth p.u.body.request.req 8.192)
      [(give-simple-payload:app:server eyre-id (error:web 413 'Request too large')) this]
    ?~  jon=(de:json:html q.u.body.request.req)
      [(give-simple-payload:app:server eyre-id (error:web 400 'Invalid JSON')) this]
    =/  result  (act:up u.jon)
    ?-  -.result
      %|  [(give-simple-payload:app:server eyre-id (error:web 400 p.result)) this]
      %&  =.  st  +.p.result
          [(weld -.p.result (give-simple-payload:app:server eyre-id (response:web 200 (view:web bowl st)))) this]
    ==
      %json
    ?>  =(src our):bowl
    =/  result  (act:up !<(json vase))
    ?>  ?=(%& -.result)
    [-.p.result this(st +.p.result)]
  ==
++  on-watch
  |=  =path
  ^-  (quip card _this)
  ?:  ?=([%http-response *] path)
    [~ this]
  ?>  ?=([%board %v1 @ ~] path)
  ?>  =(i.t.t.path (scot %p src.bowl))
  ?>  (board-allowed:net src.bowl)
  [(board-cards:net ~ board-snapshot:net) this]
++  on-agent
  |=  [=wire =sign:agent:gall]
  ^-  (quip card _this)
  ?:  ?=([%pass @ @ @ ~] wire)
    ?>  =(i.t.wire (scot %p src.bowl))
    ?.  ?=(%poke-ack -.sign)  [~ this]
    =/  id  (need (slaw %uv i.t.t.wire))
    =/  due  (need (slaw %da i.t.t.t.wire))
    =^  cards  st  (ack:gossip id [src.bowl due] ?=(~ p.sign))
    [cards this]
  ?:  ?=([%board @ ~] wire)
    ?>  =(i.t.wire (scot %p src.bowl))
    ?.  ?=(%fact -.sign)  [~ this]
    ?.  (board-allowed:net src.bowl)  [reconcile:net this]
    ?>  =(%omachan-posts p.cage.sign)
    =/  rows  !<((list post-entry) q.cage.sign)
    ?>  (lte (lent rows) 16)
    =^  cards  st  (receive-posts:gossip src.bowl rows)
    =^  more  st  maintain:gossip
    [(weld cards more) this]
  ?:  ?=([%bootstrap @ ~] wire)
    ?.  ?=(%poke-ack -.sign)  [~ this]
    =/  who  (need (slaw %p i.t.wire))
    ?.  =(`who bootstrap.st)  [~ this]
    =.  bootstrap.st  ~
    ?^  p.sign  [~ this(note.st 'Could not add your first pal. Check %pals and try again.')]
    =.  joined.st  &
    =^  cards  st  (own-claim:up &)
    =^  more  st  refresh:up
    [(weld cards more) this(note.st 'First pal added. Your discovery claim is now being shared.')]
  ?:  ?=([%auto @ ~] wire)
    ?.  ?=(%poke-ack -.sign)  [~ this]
    ?^  p.sign  [~ this(note.st 'Auto-accept could not update %pals; it will retry.')]
    [(weld reconcile:net (hello:net (need (slaw %p i.t.wire)))) this]
  ?:  ?=([%pals @ ~] wire)  [reconcile:net this]
  ?:  =(/pals-command wire)
    ?.  ?=(%poke-ack -.sign)  [~ this]
    ?^  p.sign  [~ this(note.st 'Pals rejected the change; verify that %pals is running.')]
    [reconcile:net this]
  ?:  |(?=([%claims @ ~] wire) ?=([%hello @ ~] wire))  [~ this]
  (on-agent:def wire sign)
++  on-arvo
  |=  [=wire =sign-arvo]
  ^-  (quip card _this)
  ?:  ?=([%pass @ @ @ ~] wire)
    ?.  ?=([%behn %wake *] sign-arvo)  [~ this]
    =/  who  (need (slaw %p i.t.wire))
    =/  id  (need (slaw %uv i.t.t.wire))
    =/  due  (need (slaw %da i.t.t.t.wire))
    =^  cards  st  (timeout:gossip id [who due])
    [cards this]
  ?:  ?=([%timer @ ~] wire)
    ?.  =(i.t.wire (scot %da next.st))  [~ this]
    =.  next.st  (add now.bowl ~s30)
    =^  cards  st  refresh:up
    [[[%pass /timer/(scot %da next.st) %arvo %b %wait next.st] cards] this]
  ?:  ?=([%keys @ ~] wire)
    =^  cards  st  refresh:up
    [cards this]
  ?:  ?=([%eyre *] wire)  [~ this]
  (on-arvo:def wire sign-arvo)
++  on-peek
  |=  =path
  ^-  (unit (unit cage))
  ?>  =(src our):bowl
  ?+  path  [~ ~]
    [%x %state ~]  ``json+!>((view:web bowl st))
    [%x %raw ~]    ``noun+!>(st)
  ==
++  on-leave  on-leave:def
++  on-fail   on-fail:def
--
