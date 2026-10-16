#!/usr/bin/env python3
"""Exact text replacement preserving line endings: rep.py FILE  (pairs read from stdin separated by lines '=====' and '-----')"""
import sys
p=sys.argv[1]
s=open(p,encoding='latin1',newline='').read()
nl='\r\n' if '\r\n' in s else '\n'
s=s.replace('\r\n','\n')
data=sys.stdin.read()
for block in data.split('\n=====\n'):
    if not block.strip(): continue
    a,b=block.split('\n-----\n')
    if s.count(a)!=1:
        sys.exit('NOT UNIQUE (%d): %s'%(s.count(a),a[:200]))
    s=s.replace(a,b)
open(p,'w',encoding='latin1',newline='').write(s.replace('\n',nl))
