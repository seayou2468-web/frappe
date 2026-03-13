import sys

with open('LocationSimulationViewController.m', 'r') as f:
    lines = f.readlines()

new_lines = []
skip = False
for i, line in enumerate(lines):
    if 'MoveMode mode = (MoveMode)self.modeControl.selectedSegmentIndex;' in line and i + 1 < len(lines) and '[self.currentPathPoints removeAllObjects];' in lines[i+1]:
        new_lines.append(line)
        new_lines.append('    if (mode != MoveModeRoadAuto) { [self.currentPathPoints removeAllObjects]; }\n')
        skip = True
    elif skip:
        skip = False
        continue
    else:
        new_lines.append(line)

with open('LocationSimulationViewController.m', 'w') as f:
    f.writelines(new_lines)
