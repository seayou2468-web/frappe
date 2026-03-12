import sys

with open('IdeviceViewController.m', 'r') as f:
    lines = f.readlines()

new_lines = []
skip_next = False
for i, line in enumerate(lines):
    if skip_next:
        skip_next = False
        continue

    if 'UIButton *simButton = [self createActionButtonWithTitle:@"LOCATION SIMULATION"' in line:
        new_lines.append(line)
        # Check next line
        if i + 1 < len(lines) and '[self.actionStack addArrangedSubview:simButton];' not in lines[i+1]:
             # Find where to add it
             pass
    elif '[self.mainStack addArrangedSubview:appsButton];' in line:
        new_lines.append(line)
        new_lines.append('    [self.mainStack addArrangedSubview:simButton];\n')
    else:
        new_lines.append(line)

with open('IdeviceViewController.m', 'w') as f:
    f.writelines(new_lines)
