import sys
import os

def add_dealloc(filepath):
    with open(filepath, 'r') as f:
        lines = f.readlines()

    if any('dealloc' in line for line in lines):
        print(f"{filepath} already has dealloc")
        return

    new_lines = []
    found_end = False
    for line in reversed(lines):
        if not found_end and '@end' in line:
            new_lines.insert(0, line)
            new_lines.insert(0, '- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }\n\n')
            found_end = True
        else:
            new_lines.insert(0, line)

    with open(filepath, 'w') as f:
        f.writelines(new_lines)

add_dealloc('IdeviceViewController.m')
add_dealloc('MainContainerViewController.m')
