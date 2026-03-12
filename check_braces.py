import sys

def check_braces(filename):
    with open(filename, 'r') as f:
        content = f.read()

    open_braces = content.count('{')
    close_braces = content.count('}')

    if open_braces != close_braces:
        print(f"Error in {filename}: Open braces ({open_braces}) != Close braces ({close_braces})")
        return False
    return True

check_braces('LocationSimulationViewController.m')
check_braces('IdeviceViewController.m')
