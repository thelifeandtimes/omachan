::  Executed in ~sev with tagged mutuals ~wes and ~fex, by check-network.py.
::  Cards are inspected, never sent; fixed entropy makes both branches repeatable.
=/  m  (strand ,vase)
;<  b=bowl:spider  bind:m  get-bowl
=/  entropy
  |=  bit=@ud
  =+  n=0
  |-
  ?:  =(bit (~(rad og n) 2))  `@uvJ`n
  $(n +(n))
=/  private  (entropy 0)
=/  public  (entropy 1)
=/  gb  *bowl:gall
=.  gb  gb(our our.b, src our.b, dap %omachan, now now.b, eny private)
=.  sup.gb  (~(put by sup.gb) [/test/wes]~ [~wes /board/v1/~wes])
=.  sup.gb  (~(put by sup.gb) [/test/fex]~ [~fex /board/v1/~fex])
=/  p=post  [0v123 now.b 'controlled proxy test']
=/  initial  *state
=/  s  initial(posts (~(put by posts.initial) id.p [p 0]))
~|  %origin-pass
=/  passed  (emit(bowl gb, st s) p)
=/  ps  +.passed
?>  !(~(has in shared.ps) id.p)
?>  =((lent -.passed) 2)
=/  attempt  (~(got by passes.ps) id.p)
?>  =(due.attempt (add now.b ~s30))
?>  =((snag 0 -.passed) [%pass (pass-wire id.p attempt) %agent [peer.attempt %omachan] %poke %omachan-pass !>(p)])
?>  =(~ ~(board-snapshot ..board-snapshot gb ps))
~|  %origin-release
=/  released  (emit(bowl gb(eny public), st s) p)
=/  rs  +.released
?>  (~(has in shared.rs) id.p)
?>  =(~ passes.rs)
?>  =(~(board-snapshot ..board-snapshot gb rs) [p 1]~)
?>  =((lent -.released) 1)
~|  %repeat-choice-at-proxy
=/  proxied  (receive-pass(bowl gb(src ~wes), st initial) p)
=/  px  +.proxied
?>  =(peer:(~(got by passes.px) id.p) ~fex)
?>  =(distance:(~(got by posts.px) id.p) 0)
?>  =(~ ~(board-snapshot ..board-snapshot gb px))
=/  proxy-release  (receive-pass(bowl gb(src ~wes, eny public), st initial) p)
?>  (~(has in shared.+.proxy-release) id.p)
?>  =(distance:(~(got by posts.+.proxy-release) id.p) 0)
~|  %bootstrap-is-an-ordinary-proxy
=/  excluded  initial(cfg [`~fex |])
=/  fallback  (receive-pass(bowl gb(src ~wes), st excluded) p)
?>  =(peer:(~(got by passes.+.fallback) id.p) ~fex)
~|  %exclude-dismissed-and-missed
=/  excluded  s(dismissed (silt ~[~wes ~fex]))
=/  fallback  (emit(bowl gb, st excluded) p)
?>  (~(has in shared.+.fallback) id.p)
=/  excluded  s(misses (silt ~[~wes ~fex]))
=/  fallback  (emit(bowl gb, st excluded) p)
?>  (~(has in shared.+.fallback) id.p)
~|  %positive-ack-keeps-cache-private
=/  accepted  (ack(bowl gb, st ps) id.p attempt &)
?>  =(~ passes.+.accepted)
?>  =(~ ~(board-snapshot ..board-snapshot gb +.accepted))
?>  =((lent -.accepted) 1)
~|  %nack-retries-another-peer
=/  rejected  (ack(bowl gb, st ps) id.p attempt |)
=/  replacement  (~(got by passes.+.rejected) id.p)
?>  !=(peer.attempt peer.replacement)
?>  (~(has in misses.+.rejected) peer.attempt)
?>  =((lent -.rejected) 3)
~|  %stale-ack-and-wake-cannot-finish-replacement
=/  late  (ack(bowl gb, st +.rejected) id.p attempt &)
?>  =(late [~ +.rejected])
=/  late  (timeout(bowl gb, st +.rejected) id.p attempt(due (sub now.b ~s1)))
?>  =(late [~ +.rejected])
~|  %timeout-respects-deadline-and-retries
=/  early  (timeout(bowl gb, st ps) id.p attempt)
?>  =(early [~ ps])
=/  past  attempt(due (sub now.b ~s1))
=/  overdue  ps(passes (~(put by passes.ps) id.p past))
=/  expired  (timeout(bowl gb, st overdue) id.p past)
?>  !=(peer.attempt peer:(~(got by passes.+.expired) id.p))
?>  =((lent -.expired) 3)
~|  %public-copy-cancels-pass-and-adopts-public-distance
=/  received  (receive-posts(bowl gb, st ps) ~wes [p 1]~)
=/  observed  +.received
?>  =(~ passes.observed)
?>  =(distance:(~(got by posts.observed) id.p) 1)
?>  =(~(board-snapshot ..board-snapshot gb observed) [p 2]~)
?>  =((lent -.received) 2)
=/  farther  (receive-posts(bowl gb, st initial) ~wes [p 2]~)
?>  =(~ -.farther)
?>  =(~ ~(board-snapshot ..board-snapshot gb +.farther))
~|  %duplicate-public-private-and-conflicting-id
=/  duplicate  (receive-posts(bowl gb, st observed) ~wes [p 1]~)
?>  =(duplicate [~ observed])
=/  duplicate  (receive-pass(bowl gb(src ~wes), st px) p)
?>  =(duplicate [~ px])
=/  conflict  (receive-posts(bowl gb, st observed) ~wes [p(what 'conflict') 1]~)
?>  =(conflict [~ observed])
~|  %reload-maintenance-and-legacy-role-is-inert
=/  resumed  maintain(bowl gb, st overdue)
?>  !=(peer.attempt peer:(~(got by passes.+.resumed) id.p))
=/  legacy  ps(cfg [~ &])
=/  kept  maintain(bowl gb, st legacy)
?>  =(passes.+.kept passes.ps)
=/  ordinary  (emit(bowl gb, st s(cfg [~ &])) p)
?>  =(peer:(~(got by passes.+.ordinary) id.p) peer.attempt)
~|  %removed-peer-retries
=/  removed  ps(dismissed (silt [peer.attempt]~))
=/  rerouted  maintain(bowl gb, st removed)
?>  !=(peer.attempt peer:(~(got by passes.+.rerouted) id.p))
~|  %arrival-order-independent-of-authored-time
=/  first  (receive-posts(bowl gb, st initial) ~wes [p 1]~)
=/  later  p(id 0v124, when (sub now.b ~d1))
=/  second  (receive-posts(bowl gb, st +.first) ~wes [later 1]~)
?>  (gth (~(got by arrivals.+.second) id.later) (~(got by arrivals.+.second) id.p))
=/  repeated  (receive-posts(bowl gb, st +.second) ~wes [p 1]~)
?>  =(arrivals.+.second arrivals.+.repeated)
~|  %cache-eviction-cancels-retry
=/  aged  p(when (sub now.b ~d15))
=/  old  ps(posts (~(put by posts.ps) id.p [aged 0]))
=/  pruned  maintain(bowl gb, st old)
?>  =(~ posts.+.pruned)
?>  =(~ passes.+.pruned)
(pure:m !>(%ok))
