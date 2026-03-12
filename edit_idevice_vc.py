import sys

with open('IdeviceViewController.m', 'r') as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    if '#import "AppListViewController.h"' in line:
        new_lines.append(line)
        new_lines.append('#import "LocationSimulationViewController.h"\n')
    elif 'UIButton *appsButton = [self createActionButtonWithTitle:@"BROWSE APPLICATIONS"' in line:
        new_lines.append(line)
        new_lines.append('    UIButton *simButton = [self createActionButtonWithTitle:@"LOCATION SIMULATION" action:@selector(showLocationSim)];\n')
    elif '[self.actionStack addArrangedSubview:appsButton];' in line:
        new_lines.append(line)
        new_lines.append('    [self.actionStack addArrangedSubview:simButton];\n')
    elif '- (void)showAppList {' in line:
        # Add showLocationSim before showAppList
        new_lines.append('- (void)showLocationSim {\n')
        new_lines.append('    if (!self.currentProvider) { [self log:@"Link required."]; return; }\n')
        new_lines.append('    LocationSimulationViewController *vc = [[LocationSimulationViewController alloc] initWithProvider:self.currentProvider lockdown:self.currentLockdown];\n')
        new_lines.append('    [self.navigationController pushViewController:vc animated:YES];\n')
        new_lines.append('}\n\n')
        new_lines.append(line)
    else:
        new_lines.append(line)

with open('IdeviceViewController.m', 'w') as f:
    f.writelines(new_lines)
