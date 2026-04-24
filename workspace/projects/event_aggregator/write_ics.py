import sys, os
filename = sys.argv[1]
content = sys.stdin.read()
path = f'/home/eric/000_inbox/downloads/events/{filename}'
with open(path, 'w') as f:
    f.write(content)
print(f'Wrote: {path}')
