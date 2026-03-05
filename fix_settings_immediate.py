import os

file_path = 'SettingsViewController.m'
with open(file_path, 'r') as f:
    content = f.read()

# Add notification post to confirmDeleteToggled
old_toggle = """- (void)confirmDeleteToggled:(UISwitch *)sender { [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:@"ConfirmDeletion"]; }"""
new_toggle = """- (void)confirmDeleteToggled:(UISwitch *)sender { [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:@"ConfirmDeletion"]; [[NSNotificationCenter defaultCenter] postNotificationName:@"SettingsChanged" object:nil]; }"""
content = content.replace(old_toggle, new_toggle)

with open(file_path, 'w') as f:
    f.write(content)
