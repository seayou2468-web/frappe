import sys

with open('IdeviceViewController.m', 'r') as f:
    content = f.read()

# Add self.mobileConfig = nil to cleanupHandles
content = content.replace('if (self.currentPairingFile) { idevice_pairing_file_free(self.currentPairingFile); self.currentPairingFile = NULL; }',
                          'if (self.currentPairingFile) { idevice_pairing_file_free(self.currentPairingFile); self.currentPairingFile = NULL; }\n    self.mobileConfig = nil;')

with open('IdeviceViewController.m', 'w') as f:
    f.write(content)
