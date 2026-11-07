#!/usr/bin/env python3
"""Print +code for one of this project's three disposable fake ships only."""
import argparse
import re
from dev import conn, PORTS

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('ship',choices=PORTS)
args=parser.parse_args()
result=conn(args.ship,'=/  m  (strand ,vase)  ;<  =bowl:spider  bind:m  get-bowl  '
            '(pure:m !>((scot %p .^(@p %j /(scot %p our.bowl)/code/'
            '(scot %da now.bowl)/(scot %p our.bowl)))))')
print(re.search(r'~[a-z-]+',result)[0][1:])
