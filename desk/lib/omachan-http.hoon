/-  *omachan
/+  server, pals, net=omachan-network, crypto=omachan-crypto, defaults=omachan-config
|%
++  str
  |=  [j=json key=@t]
  ^-  @t
  ?.  ?=(%o -.j)  ''
  ?~  v=(~(get by p.j) key)  ''
  ?.  ?=(%s -.u.v)  ''
  p.u.v
++  flag
  |=  [j=json key=@t fallback=?]
  ^-  ?
  ?.  ?=(%o -.j)  fallback
  ?~  v=(~(get by p.j) key)  fallback
  ?.  ?=(%b -.u.v)  fallback
  p.u.v
++  header
  |=  [key=@t heads=header-list:http]
  ^-  (unit @t)
  ?~  heads  ~
  ?:  =((cass (trip key)) (cass (trip key.i.heads)))  `value.i.heads
  $(heads t.heads)
++  csrf
  |=  req=inbound-request:eyre
  ^-  ?
  =/  heads  header-list.request.req
  ?.  =(`'1' (header 'x-omachan' heads))  |
  ?~  host=(header 'host' heads)  |
  ?~  origin=(header 'origin' heads)  |
  |(=(u.origin (cat 3 'http://' u.host)) =(u.origin (cat 3 'https://' u.host)))
++  response
  |=  [code=@ud jon=json]
  ^-  simple-payload:http
  [[code ~[['content-type' 'application/json'] ['cache-control' 'no-store']]] `(as-octs:mimes:html (en:json:html jon))]
++  error
  |=  [code=@ud msg=@t]
  (response code (pairs:enjs:format ~[error+s+msg]))
++  static
  |=  [bowl=bowl:gall ct=@t pax=path]
  ^-  simple-payload:http
  =/  dat=@  .^(@ %cx :(weld /(scot %p our.bowl)/[dap.bowl]/(scot %da now.bowl) pax))
  [[200 ~[['content-type' ct] ['cache-control' 'no-store'] ['x-content-type-options' 'nosniff']]] `[(met 3 dat) dat]]
++  timestamp
  |=  t=@da
  ^-  json
  (numb:enjs:format (div (sub t ~1970.1.1) ~s1))
++  distributor
  |=  bowl=bowl:gall
  ^-  ship
  =/  sources  .^((map desk [ship desk]) %gx /(scot %p our.bowl)/hood/(scot %da now.bowl)/kiln/sources/noun)
  ?~  source=(~(get by sources) dap.bowl)  distributor:defaults
  ?:  =(our.bowl -.u.source)  distributor:defaults
  -.u.source
++  view
  |=  [bowl=bowl:gall st=state]
  ^-  json
  =/  network  ~(. net bowl st)
  =/  pal  ~(. pals bowl)
  =/  all  (~(uni in ~(key by claims.st)) (~(uni in (targets:pal ~.)) leeches:pal))
  =/  peers=json
    :-  %a
    %+  turn  ~(tap in (~(del in all) our.bowl))
    |=  who=ship
    =/  a  (~(get by claims.st) who)
    =/  verified=?  ?~(a | (claim-live:network data.u.a))
    =/  current=?  ?~(a | &(verified active.body.data.u.a))
    =/  sub  (~(get by wex.bowl) [/board/(scot %p who) who dap.bowl])
    =,  enjs:format
    %-  pairs
    :~  ship+s+(scot %p who)
        verified+b+verified
        active+b+current
        via+?~(a ~ s+(scot %p via.u.a))
        expires+?~(a ~ (timestamp expires.body.data.u.a))
        hop+?~(a ~ (numb distance.u.a))
        target+b+(target:pal ~. who)
        incoming+b+(leeche:pal who)
        tagged+b+(~(has in (targets:pal ~.omarchy)) who)
        mutual+b+(mutual:pal ~. who)
        ignored+b+(~(has in dismissed.st) who)
        eligible+b+(board-allowed:network who)
        connected+b+&((board-allowed:network who) ?~(sub | -.u.sub))
    ==
  =/  rows=json
    :-  %a
    %+  turn
      %+  sort  ~(val by posts.st)
      |=  [a=post-entry b=post-entry]
      (gth (~(gut by arrivals.st) id.data.a 0) (~(gut by arrivals.st) id.data.b 0))
    |=  p=post-entry
    (pairs:enjs:format ~[id+s+(scot %uv id.data.p) when+(timestamp when.data.p) text+s+what.data.p order+(numb:enjs:format (~(gut by arrivals.st) id.data.p 0))])
  (pairs:enjs:format ~[our+s+(scot %p our.bowl) joined+b+joined.st 'autoAccept'^b+auto-accept.st 'preferencesSet'^b+preferences-set.st 'bootstrapping'^b+?=(^ bootstrap.st) distributor+s+(scot %p (distributor bowl)) hub+s+(scot %p (fall seed.cfg.st hub:defaults)) seed+?~(seed.cfg.st ~ s+(scot %p u.seed.cfg.st)) 'palsRunning'^b+running:pal peers+peers posts+rows note+s+note.st])
--
