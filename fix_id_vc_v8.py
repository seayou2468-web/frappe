import sys

with open('IdeviceViewController.m', 'r') as f:
    content = f.read()

# Remove the duplicate @property (nonatomic, assign) struct LockdowndClientHandle *currentLockdown; if any
# Actually it was just an insert.

# Ensure all needed imports are present
if '#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>' not in content:
    content = content.replace('#import "LocationSimulationViewController.h"', '#import "LocationSimulationViewController.h"\n#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>')

with open('IdeviceViewController.m', 'w') as f:
    f.write(content)
