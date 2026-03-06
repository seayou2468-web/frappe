import sys
import os

def check_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    braces = {'(': 0, '{': 0, '[': 0}
    pairs = {'(': ')', '{': '}', '[': ']'}

    for char in content:
        if char in braces:
            braces[char] += 1
        elif char in pairs.values():
            for opening, closing in pairs.items():
                if char == closing:
                    braces[opening] -= 1
                    if braces[opening] < 0:
                        return False, f"Unexpected closing brace: {char}"

    for char, count in braces.items():
        if count != 0:
            return False, f"Unbalanced brace: {char} (count: {count})"

    return True, "OK"

files = ['IdeviceManager.m']
for f in files:
    if os.path.exists(f):
        ok, msg = check_file(f)
        print(f"{f}: {msg}")
