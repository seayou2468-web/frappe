import sys

with open('IdeviceViewController.m', 'r') as f:
    content = f.read()

# Fix imports
if '#import "LocationSimulationViewController.h"' not in content:
    content = content.replace('#import "AppListViewController.h"', '#import "AppListViewController.h"\n#import "LocationSimulationViewController.h"')

# Fix button creation and addition
if 'UIButton *simButton = [self createActionButtonWithTitle:@"LOCATION SIMULATION"' not in content:
    content = content.replace('UIButton *appsButton = [self createActionButtonWithTitle:@"BROWSE APPLICATIONS" action:@selector(showAppList)];',
                              'UIButton *appsButton = [self createActionButtonWithTitle:@"BROWSE APPLICATIONS" action:@selector(showAppList)];\n    UIButton *simButton = [self createActionButtonWithTitle:@"LOCATION SIMULATION" action:@selector(showLocationSim)];')

if '[self.mainStack addArrangedSubview:simButton];' not in content:
    content = content.replace('[self.mainStack addArrangedSubview:appsButton];', '[self.mainStack addArrangedSubview:appsButton];\n    [self.mainStack addArrangedSubview:simButton];')

# showLocationSim method is already there from previous run but let's be sure
if '- (void)showLocationSim {' not in content:
     content = content.replace('- (void)showAppList {',
                               '- (void)showLocationSim {\n    if (!self.currentProvider) { [self log:@"Link required."]; return; }\n    LocationSimulationViewController *vc = [[LocationSimulationViewController alloc] initWithProvider:self.currentProvider lockdown:self.currentLockdown];\n    [self.navigationController pushViewController:vc animated:YES];\n}\n\n- (void)showAppList {')

with open('IdeviceViewController.m', 'w') as f:
    f.write(content)
