::  Suite's 50/50 private pass or public release; private passes spend no hops.
/-  *omachan
/+  network=omachan-network
|_  [=bowl:gall st=state]
+*  net  ~(. network bowl st)
+$  card  card:agent:gall
++  valid
  |=  p=post
  ^-  ?
  ?&  (lte (met 0 id.p) 256)
      (gth (met 3 what.p) 0)
      (lte (met 3 what.p) 1.024)
      (lte when.p (add now.bowl ~m5))
      (gth when.p (sub now.bowl ~d14))
  ==
++  remember
  |=  id=@uv
  ^-  state
  ?:  (~(has by arrivals.st) id)  st
  st(sequence +(sequence.st), arrivals (~(put by arrivals.st) id +(sequence.st)))
++  pass-wire
  |=  [id=@uv attempt=handoff]
  /pass/(scot %p peer.attempt)/(scot %uv id)/(scot %da due.attempt)
++  cancel
  |=  id=@uv
  ^-  (quip card state)
  ?~  p=(~(get by passes.st) id)  [~ st]
  :_  st(passes (~(del by passes.st) id))
  [%pass (pass-wire id u.p) %arvo %b %rest due.u.p]~
++  release
  |=  p=post
  ^-  (quip card state)
  =^  cards  st  (cancel id.p)
  =.  shared.st  (~(put in shared.st) id.p)
  [(weld cards (broadcast-post:net [p 0] our.bowl)) st]
++  emit
  |=  p=post
  ^-  (quip card state)
  ::  As in Suite, the author's first decision is also a coin flip.
  ?:  =((~(rad og eny.bowl) 2) 1)  (release p)
  =/  aides
    ~(tap in (~(dif in (~(del in board-peers:net) src.bowl)) misses.st))
  ?:  =(~ aides)  (release p)
  =/  who  (snag (~(rad og +(eny.bowl)) (lent aides)) aides)
  =/  attempt=handoff  [who (add now.bowl ~s30)]
  =^  cards  st  (cancel id.p)
  =.  passes.st  (~(put by passes.st) id.p attempt)
  =/  wire  (pass-wire id.p attempt)
  =/  more=(list card)
    :~  [%pass wire %agent [who dap.bowl] %poke %omachan-pass !>(p)]
        [%pass wire %arvo %b %wait due.attempt]
    ==
  [(weld cards more) st]
++  receive-pass
  |=  p=post
  ^-  (quip card state)
  ?>  (board-allowed:net src.bowl)
  ?>  (valid p)
  =.  misses.st  (~(del in misses.st) src.bowl)
  ::  A repeated private pass is acknowledged, as in Suite, without replaying it.
  ?^  old=(~(get by posts.st) id.p)
    ?>  =(p data.u.old)
    [~ st]
  =.  st  (remember id.p)
  =.  posts.st  (~(put by posts.st) id.p [p 0])
  (emit p)
++  receive-posts
  |=  [via=ship rows=(list post-entry)]
  ^-  (quip card state)
  =.  misses.st  (~(del in misses.st) via)
  =|  cards=(list card)
  |-
  ?~  rows  [cards st]
  =/  row  i.rows
  =/  p  data.row
  ?.  &((gte distance.row 1) (lte distance.row 2) (valid p))  $(rows t.rows)
  ?^  old=(~(get by posts.st) id.p)
    ?.  =(p data.u.old)  $(rows t.rows)
    ?:  &((~(has in shared.st) id.p) (gte distance.row distance.u.old))  $(rows t.rows)
    $(posts.st (~(del by posts.st) id.p))
  =^  stops  st  (cancel id.p)
  =.  st  (remember id.p)
  =.  posts.st  (~(put by posts.st) id.p row)
  =.  shared.st  (~(put in shared.st) id.p)
  =/  more  (broadcast-post:net row via)
  $(rows t.rows, cards :(weld cards stops more))
++  ack
  |=  [id=@uv attempt=handoff ok=?]
  ^-  (quip card state)
  ?.  =(`attempt (~(get by passes.st) id))  [~ st]
  =^  cards  st  (cancel id)
  ?:  ok  [cards st(misses (~(del in misses.st) peer.attempt))]
  =.  misses.st  (~(put in misses.st) peer.attempt)
  ?~  p=(~(get by posts.st) id)  [cards st]
  =^  more  st  (emit data.u.p)
  [(weld cards more) st]
++  timeout
  |=  [id=@uv attempt=handoff]
  ^-  (quip card state)
  ?:  (lth now.bowl due.attempt)  [~ st]
  (ack id attempt |)
++  maintain
  ^-  (quip card state)
  =/  rows
    %+  sort
      (skim ~(val by posts.st) |=(p=post-entry (gth when.data.p (sub now.bowl ~d14))))
    |=  [a=post-entry b=post-entry]
    (gth (~(gut by arrivals.st) id.data.a 0) (~(gut by arrivals.st) id.data.b 0))
  =.  posts.st
    (~(gas by *(map @uv post-entry)) (turn (scag 500 rows) |=(p=post-entry [id.data.p p])))
  =.  arrivals.st  (~(gas by *(map @uv @ud)) (skim ~(tap by arrivals.st) |=([id=@uv order=@ud] (~(has by posts.st) id))))
  =.  shared.st  (~(int in shared.st) ~(key by posts.st))
  =.  misses.st  (~(int in misses.st) board-peers:net)
  =/  attempts  ~(tap by passes.st)
  =|  cards=(list card)
  |-
  ?~  attempts  [cards st]
  =/  id  p.i.attempts
  =/  attempt  q.i.attempts
  =^  more  st
    ?:  !(~(has by posts.st) id)  (cancel id)
    ?:  !(board-allowed:net peer.attempt)  (ack id attempt |)
    (timeout id attempt)
  $(attempts t.attempts, cards (weld cards more))
--
