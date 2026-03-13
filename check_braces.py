import sys

def check_braces(filename):
    with open(filename, 'r') as f:
        content = f.read()

    stack = []
    line_num = 1
    col_num = 0

    for char in content:
        if char == '\n':
            line_num += 1
            col_num = 0
        else:
            col_num += 1

        if char == '{':
            stack.append(('{', line_num, col_num))
        elif char == '}':
            if not stack:
                print(f"Error: Unmatched '}}' at {filename}:{line_num}:{col_num}")
                return False
            stack.pop()

    if stack:
        for b, l, c in stack:
            print(f"Error: Unmatched '{{' at {filename}:{l}:{c}")
        return False

    print(f"Braces match in {filename}")
    return True

files = ['AppManager.m', 'ProfileManagerViewController.m', 'IdeviceViewController.m', 'FileBrowserViewController.m']
all_ok = True
for f in files:
    if not check_braces(f):
        all_ok = False

if not all_ok:
    sys.exit(1)
