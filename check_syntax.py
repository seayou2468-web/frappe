import sys
import subprocess

def check_file(filename):
    # Just a very basic check for brackets and such since we don't have a real compiler here that works
    with open(filename, 'r') as f:
        content = f.read()

    if content.count('{') != content.count('}'):
        print(f"Brace mismatch in {filename}: {{ {content.count('{')} vs }} {content.count('}')}")
        return False
    if content.count('[') != content.count(']'):
        print(f"Bracket mismatch in {filename}: [ {content.count('[')} vs ] {content.count(']')}")
        return False
    if content.count('(') != content.count(')'):
        print(f"Parenthesis mismatch in {filename}: ( {content.count('(')} vs ) {content.count(')')}")
        return False
    return True

files = ['MobileConfigService.h', 'MobileConfigService.m', 'IdeviceViewController.m']
for f in files:
    if not check_file(f):
        sys.exit(1)
print("Basic syntax check passed")
