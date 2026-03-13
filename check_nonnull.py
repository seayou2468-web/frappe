import sys
import re

files = ['AppManager.h', 'AppManager.m', 'ProfileManagerViewController.h', 'ProfileManagerViewController.m', 'IdeviceViewController.h', 'IdeviceViewController.m', 'FileBrowserViewController.m']
found_issue = False

for f in files:
    with open(f, 'r') as file:
        content = file.read()
        if 'nonnull' in content.lower():
            print(f"Warning: 'nonnull' found in {f}")
            found_issue = True

if not found_issue:
    print("No 'nonnull' found in modified files.")
