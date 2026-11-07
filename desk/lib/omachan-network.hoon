::  Two independent channels: signed discovery and unattributed board content.
/-  *omachan
/+  pals, crypto=omachan-crypto
|_  [=bowl:gall st=state]
+*  pal  ~(. pals bowl)
+$  card  card:agent:gall
++  enabled  joined.st
++  discovery-peers
  ^-  (set ship)
  =/  live-links
    %-  ~(gas in *(set ship))
    %+  skim  ~(tap in links.st)
    |=  who=ship
    ?~  a=(~(get by claims.st) who)  |
    &((claim-live data.u.a) active.body.data.u.a)
  =/  peers  (~(uni in live-links) (mutuals:pal ~.omarchy))
  =?  peers  ?=(^ seed.cfg.st)  (~(put in peers) u.seed.cfg.st)
  (~(dif in (~(del in peers) our.bowl)) dismissed.st)
++  board-allowed
  |=  who=ship
  ^-  ?
  ?&  !=(who our.bowl)
      !(~(has in dismissed.st) who)
      (mutual:pal ~.omarchy who)
  ==
++  board-peers
  ^-  (set ship)
  %-  ~(gas in *(set ship))
  (skim ~(tap in (mutuals:pal ~.omarchy)) board-allowed)
++  discovery-allowed
  |=  who=ship
  &(enabled (~(has in discovery-peers) who) !(~(has in dismissed.st) who))
++  claim-live
  |=  s=claim
  ^-  ?
  &((fresh:crypto now.bowl s) =(`& (authenticate:crypto our.bowl now.bowl s)))
++  claims-for-wire
  ^-  (list claim-wire)
  %+  murn  ~(val by claims.st)
  |=  a=announcement
  ^-  (unit claim-wire)
  ?.  &((lth distance.a 2) (claim-live data.a))  ~
  `[data.a +(distance.a)]
++  send-claims
  |=  [who=ship rows=(list claim-wire)]
  ^-  (list card)
  ?:  =(~ rows)  ~
  :-  [%pass /claims/(scot %p who) %agent [who dap.bowl] %poke %omachan-claims !>(`(list claim-wire)`(scag 16 rows))]
  $(rows (slag 16 rows))
++  broadcast-claim
  |=  [a=announcement except=ship]
  ^-  (list card)
  ?.  &((lth distance.a 2) (claim-live data.a))  ~
  %-  zing
  %+  turn  ~(tap in (~(del in discovery-peers) except))
  |=  who=ship
  (send-claims who [data.a +(distance.a)]~)
++  hello
  |=  who=ship
  ^-  (list card)
  ?.  enabled  ~
  ?~  own=(~(get by claims.st) our.bowl)  ~
  ?.  (claim-live data.u.own)  ~
  [%pass /hello/(scot %p who) %agent [who dap.bowl] %poke %omachan-hello !>(data.u.own)]~
++  board-snapshot
  ^-  (list post-entry)
  %+  murn  ~(val by posts.st)
  |=  p=post-entry
  ^-  (unit post-entry)
  ?.  &((~(has in shared.st) id.data.p) (lth distance.p 2) (gth when.data.p (sub now.bowl ~d14)))  ~
  `[data.p +(distance.p)]
++  board-cards
  |=  [paths=(list path) rows=(list post-entry)]
  ^-  (list card)
  ?:  =(~ rows)  ~
  :-  [%give %fact paths %omachan-posts !>(`(list post-entry)`(scag 16 rows))]
  $(rows (slag 16 rows))
++  broadcast-post
  |=  [p=post-entry except=ship]
  ^-  (list card)
  ?:  (gte distance.p 2)  ~
  =/  paths=(list path)
    %+  murn  ~(val by sup.bowl)
    |=  [who=ship pax=path]
    ^-  (unit path)
    ?.  ?&  ?=([%board %v1 @ ~] pax)
            !=(who except)
            (board-allowed who)
        ==
      ~
    `pax
  ?~  paths  ~
  (board-cards paths [data.p +(distance.p)]~)
++  reconcile
  ^-  (list card)
  =/  want  board-peers
  =/  old=(list card)
    %+  murn  ~(tap by wex.bowl)
    |=  [[=wire =ship =term] [acked=? =path]]
    ^-  (unit card)
    ?.  ?=([%board @ ~] wire)  ~
    ?:  (~(has in want) ship)  ~
    `[%pass wire %agent [ship term] %leave ~]
  =/  kicks=(list card)
    %+  murn  ~(val by sup.bowl)
    |=  [who=ship pax=path]
    ^-  (unit card)
    ?.  ?=([%board %v1 @ ~] pax)  ~
    ?:  (board-allowed who)  ~
    `[%give %kick [pax]~ `who]
  =/  watches=(list card)
    %+  murn  ~(tap in want)
    |=  who=ship
    ^-  (unit card)
    =/  wire  /board/(scot %p who)
    ?:  (~(has by wex.bowl) [wire who dap.bowl])  ~
    `[%pass wire %agent [who dap.bowl] %watch /board/v1/(scot %p our.bowl)]
  =/  pals-watches=(list card)
    %+  murn  `(list term)`~[%targets %leeches]
    |=  which=term
    ^-  (unit card)
    ?:  (~(has by wex.bowl) [/pals/[which] our.bowl %pals])  ~
    `[%pass /pals/[which] %agent [our.bowl %pals] %watch /[which]]
  ;:  weld  old  kicks  watches  pals-watches  ==
--
