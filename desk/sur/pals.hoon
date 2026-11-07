::  pals: manual neighboring
::
|%
+$  records
  $:  outgoing=(jug ship @ta)
      incoming=(set ship)
      receipts=(map ship ?)
  ==
+$  gesture
  $%  [%hey ~]
      [%bye ~]
  ==
+$  command
  $%  [%meet =ship in=(set @ta)]
      [%part =ship in=(set @ta)]
  ==
+$  effect
  $%  target-effect
      leeche-effect
  ==
+$  target-effect
  $%  [%meet =ship]
      [%part =ship]
  ==
+$  leeche-effect
  $%  [%near =ship]
      [%away =ship]
  ==
--
