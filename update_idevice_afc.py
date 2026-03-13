import sys

with open('IdeviceViewController.m', 'r') as f:
    content = f.read()

# Add import
if '#import "AfcBrowserViewController.h"' not in content:
    content = content.replace('#import "LocationSimulationViewController.h"',
                              '#import "LocationSimulationViewController.h"\n#import "AfcBrowserViewController.h"')

# Add buttons
if 'UIButton *afcButton = [self createActionButtonWithTitle:@"AFC (MEDIA)"' not in content:
    content = content.replace('UIButton *simButton = [self createActionButtonWithTitle:@"LOCATION SIMULATION" action:@selector(showLocationSim)];',
                              'UIButton *simButton = [self createActionButtonWithTitle:@"LOCATION SIMULATION" action:@selector(showLocationSim)];\n    UIButton *afcButton = [self createActionButtonWithTitle:@"AFC (MEDIA)" action:@selector(showAfc)];\n    UIButton *afc2Button = [self createActionButtonWithTitle:@"AFC2 (ROOT)" action:@selector(showAfc2)];')

if '[self.mainStack addArrangedSubview:afcButton];' not in content:
    content = content.replace('[self.mainStack addArrangedSubview:simButton];',
                              '[self.mainStack addArrangedSubview:simButton];\n    [self.mainStack addArrangedSubview:afcButton];\n    [self.mainStack addArrangedSubview:afc2Button];')

# Add methods
if '- (void)showAfc {' not in content:
    methods = """- (void)showAfc {
    if (!self.currentProvider) { [self log:@"Link required."]; return; }
    AfcBrowserViewController *vc = [[AfcBrowserViewController alloc] initWithProvider:self.currentProvider isAfc2:NO];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showAfc2 {
    if (!self.currentProvider) { [self log:@"Link required."]; return; }
    AfcBrowserViewController *vc = [[AfcBrowserViewController alloc] initWithProvider:self.currentProvider isAfc2:YES];
    [self.navigationController pushViewController:vc animated:YES];
}
"""
    content = content.replace('- (void)showLocationSim {', methods + "\n- (void)showLocationSim {")

with open('IdeviceViewController.m', 'w') as f:
    f.write(content)
