::  Adapted from Omart's MIT-licensed origin authentication.
/-  *omachan
|%
++  shape
  |=  s=claim
  ^-  ?
  ?&  =(label.body.s 'omarchy')
      (lte (met 3 (jam s)) 2.048)
      (lte (met 0 signature.s) 512)
      (lte (met 0 origin.body.s) 128)
      (gth life.body.s 0)
      (gth revision.body.s 0)
      (lte (met 0 revision.body.s) 128)
      (gth expires.body.s issued.body.s)
      (lte (sub expires.body.s issued.body.s) ~d7)
  ==
++  autograph
  |=  s=claim
  ^-  ?
  =/  checked  (mole |.((safe:as:(com:nu:cric:crypto public-key.s) signature.s (jam body.s))))
  ?~  checked  |
  u.checked
++  authenticate
  |=  [our=ship now=@da s=claim]
  ^-  (unit ?)
  ?.  &((shape s) (autograph s))  `|
  ?:  =(%pawn (clan:title origin.body.s))
    :-  ~
    ?&  =(life.body.s 1)
        =(era.body.s 0)
        =(origin.body.s fig:ex:(com:nu:cric:crypto public-key.s))
    ==
  =/  ego  (scot %p our)
  =/  wen  (scot %da now)
  =/  who  (scot %p origin.body.s)
  =/  rift  .^((unit @ud) %j /[ego]/ryft/[wen]/[who])
  ?~  rift  ~
  ?:  (lth era.body.s u.rift)  `|
  ?:  (gth era.body.s u.rift)  ~
  =/  current  .^((unit @ud) %j /[ego]/lyfe/[wen]/[who])
  ?~  current  ~
  ?:  (lth life.body.s u.current)  `|
  ?:  (gth life.body.s u.current)  ~
  =/  deed
    %-  mole
    |.  .^([life=@ud pub=pass proof=(unit @)] %j /[ego]/deed/[wen]/[who]/(scot %ud life.body.s))
  ?~  deed  ~
  `&(=(life.u.deed life.body.s) =(pub.u.deed public-key.s))
++  seal
  |=  [our=ship now=@da revision=@ud active=? relay-only=?]
  ^-  claim
  =/  ego  (scot %p our)
  =/  wen  (scot %da now)
  =/  life  .^(@ud %j /[ego]/life/[wen]/[ego])
  =/  era  ?:(=(%pawn (clan:title our)) 0 .^(@ud %j /[ego]/rift/[wen]/[ego]))
  =/  sec  .^(ring %j /[ego]/vein/[wen]/(scot %ud life))
  =/  cic  (nol:nu:cric:crypto sec)
  =/  body=statement
    [%omachan-membership-v1 our era life revision now (add now ~d7) active relay-only 'omarchy']
  [body pub:ex:cic (sigh:as:cic (jam body))]
++  newer
  |=  [a=claim b=claim]
  ^-  ?
  ?:  !=(era.body.a era.body.b)  (gth era.body.a era.body.b)
  ?:  !=(life.body.a life.body.b)  (gth life.body.a life.body.b)
  ?:  !=(revision.body.a revision.body.b)  (gth revision.body.a revision.body.b)
  ::  A withdrawal wins if an origin equivocates at the same revision.
  &(!active.body.a active.body.b)
++  fresh
  |=  [now=@da s=claim]
  &((lte issued.body.s (add now ~m5)) (gth expires.body.s now))
--
