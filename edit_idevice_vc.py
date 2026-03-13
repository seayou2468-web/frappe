import sys

with open("IdeviceViewController.m", "r") as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    new_lines.append(line)
    if '#import "LocationSimulationViewController.h"' in line:
        new_lines.append('#import "ProfileManagerViewController.h"\n')

    if 'UIButton *simButton = [self createActionButtonWithTitle:@"LOCATION SIMULATION" action:@selector(showLocationSim)];' in line:
        new_lines.append('    UIButton *profileButton = [self createActionButtonWithTitle:@"CONFIGURATION PROFILES" action:@selector(showProfileManager)];\n')

    if '[self.mainStack addArrangedSubview:simButton];' in line:
        new_lines.append('    [self.mainStack addArrangedSubview:profileButton];\n')

# Add the showProfileManager method
found_show_location_sim = False
for i in range(len(new_lines)):
    if '- (void)showLocationSim {' in new_lines[i]:
        found_show_location_sim = True
        continue
    if found_show_location_sim and new_lines[i].strip() == '}':
        new_lines.insert(i+1, '\n- (void)showProfileManager {\n    if (!self.currentProvider) { [self log:@"ERROR: NO_ACTIVE_LINK"]; return; }\n    ProfileManagerViewController *vc = [[ProfileManagerViewController alloc] initWithProvider:self.currentProvider];\n    [self.navigationController pushViewController:vc animated:YES];\n}\n')
        break

with open("IdeviceViewController.m", "w") as f:
    f.writelines(new_lines)
