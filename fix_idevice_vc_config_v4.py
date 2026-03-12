import sys

with open('IdeviceViewController.m', 'r') as f:
    content = f.read()

# Add supervised check to the existing connect success block
supervised_check = """
                plist_t supervised = NULL;
                struct IdeviceFfiError *svErr = lockdownd_get_value(self.currentLockdown, "IsSupervised", NULL, &supervised);
                if (!svErr && supervised) {
                    uint8_t b = 0;
                    plist_get_bool_val(supervised, &b);
                    [self log:[NSString stringWithFormat:@"Device Supervised: %s", b ? "YES" : "NO"]];
                    plist_free(supervised);
                }
                if (svErr) idevice_error_free(svErr);
"""

# Find the end of connection success logic
# It usually sets the lockdownd status to connected
target = '[self updateStatusIndicator:self.lockdownIndicator label:self.lockdownLabel status:1];'
content = content.replace(target, target + supervised_check)

with open('IdeviceViewController.m', 'w') as f:
    f.write(content)
