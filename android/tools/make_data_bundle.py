#!/usr/bin/env python3
"""Prepares deduplicated game data for the APK assets.
Usage: make_data_bundle.py <KaM Remake folder> <bundle dir>
Creates <bundle>/kamdata/<path> symlinks for unique files and <bundle>/kamdata.lst lines:
  <size>\\t<game path>\\t<asset path>   (asset path differs from game path for duplicates)
"""
import hashlib, os, shutil, sys

FOLDERS = ['data', 'Campaigns', 'Maps', 'MapsMP', 'Music', 'Sounds', 'Tutorials']
src, out = sys.argv[1], sys.argv[2]
shutil.rmtree(out, ignore_errors=True)
os.makedirs(os.path.join(out, 'kamdata'))

seen = {}
lines = []
saved = 0
for folder in FOLDERS:
    for root, dirs, files in os.walk(os.path.join(src, folder)):
        dirs.sort()
        for name in sorted(files):
            full = os.path.join(root, name)
            rel = os.path.relpath(full, src)
            size = os.path.getsize(full)
            h = hashlib.sha1()
            with open(full, 'rb') as f:
                for chunk in iter(lambda: f.read(1 << 20), b''):
                    h.update(chunk)
            key = (size, h.hexdigest())
            if key in seen:
                saved += size
            else:
                seen[key] = rel
                dst = os.path.join(out, 'kamdata', rel)
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                os.symlink(full, dst)
            lines.append('%d\t%s\t%s' % (size, rel, seen[key]))

with open(os.path.join(out, 'kamdata.lst'), 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines) + '\n')
print('bundle: %d files, %d unique, duplicates skipped: %.1f MB' % (len(lines), len(seen), saved / 1e6))
