::  Omachan: explicit, signed discovery; anonymous text among tagged mutuals.
|%
+$  statement
  $:  %omachan-membership-v1
      origin=ship
      era=@ud
      life=@ud
      revision=@ud
      issued=@da
      expires=@da
      active=?
      relay-only=?                              ::  legacy signed slot; ignored
      label=@t
  ==
+$  claim  [body=statement public-key=pass signature=@ux]
+$  announcement  [data=claim distance=@ud via=ship]
+$  claim-wire  [data=claim distance=@ud]
+$  post  [id=@uv when=@da what=@t]
+$  post-entry  [data=post distance=@ud]
::  Keep the legacy role slot for saved-state compatibility; always false.
+$  config  [seed=(unit ship) relay-only=_|]
+$  base-state
  $:  joined=_|
      cfg=config
      revision=@ud
      claims=(map ship announcement)
      posts=(map @uv post-entry)
      dismissed=(set ship)
      links=(set ship)
      tracked=(set ship)
      pending=(list [via=ship received=@da env=claim-wire])
      next=@da
      note=@t
  ==
+$  state-0  [%0 base-state]
+$  handoff  [peer=ship due=@da]
+$  state-1
  $:  %1
      base-state
      shared=(set @uv)
      passes=(map @uv handoff)
      misses=(set ship)
  ==
+$  state
  $:  %2
      base-state
      shared=(set @uv)
      passes=(map @uv handoff)
      misses=(set ship)
      auto-accept=_|
      preferences-set=_|
      bootstrap=(unit ship)
      arrivals=(map @uv @ud)
      sequence=@ud
  ==
--
