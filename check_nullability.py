import re
import os

files = [
    'IdeviceViewController.h', 'IdeviceViewController.m',
    'AppListViewController.h', 'AppListViewController.m',
    'AppManager.h', 'AppManager.m',
    'HeartbeatManager.h', 'HeartbeatManager.m',
    'DdiManager.h', 'DdiManager.m'
]

keywords = ['nonnull', 'nullable', '_Nonnull', '_Nullable']
found = False

for f in files:
    if not os.path.exists(f):
        continue
    with open(f, 'r') as file:
        content = file.read()
        for kw in keywords:
            if kw in content:
                print(f"Found {kw} in {f}")
                found = True

if not found:
    print("No nullability keywords found.")
