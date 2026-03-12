import sys

with open('IdeviceViewController.m', 'r') as f:
    content = f.read()

# Add erase device logic
erase_logic = """\n
- (void)eraseDevice {\n
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Erase Device" message:@"Are you sure? This will wipe the device." preferredStyle:UIAlertControllerStyleAlert];\n
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];\n
    [alert addAction:[UIAlertAction actionWithTitle:@"ERASE" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {\n
        [self ensureMobileConfig:^(BOOL success) {\n
            if (!success) return;\n
            [self.mobileConfig eraseDeviceWithPreserveDataPlan:NO disallowProximity:NO completion:^(BOOL s, id res, NSString *err) {\n
                dispatch_async(dispatch_get_main_queue(), ^{\n
                    if (s) [self log:@"Erase command sent"];\n
                    else [self log:[NSString stringWithFormat:@"Erase failed: %@", err]];\n
                });\n
            }];\n
        }];\n
    }]];\n
    [self presentViewController:alert animated:YES completion:nil];\n
}\n
"""

# Append before the last @end
last_end_index = content.rfind('@end')
content = content[:last_end_index] + erase_logic + content[last_end_index:]

# Add Erase button to UI
content = content.replace('    [mcCard.heightAnchor constraintEqualToConstant:130].active = YES;',
                          '    UIButton *eraseBtn = [UIButton buttonWithType:UIButtonTypeSystem];\n    [eraseBtn setTitle:@"ERASE DEVICE" forState:UIControlStateNormal];\n    eraseBtn.frame = CGRectMake(150, 85, 120, 35);\n    [eraseBtn addTarget:self action:@selector(eraseDevice) forControlEvents:UIControlEventTouchUpInside];\n    [mcCard addSubview:eraseBtn];\n\n    [mcCard.heightAnchor constraintEqualToConstant:130].active = YES;')

with open('IdeviceViewController.m', 'w') as f:
    f.write(content)
