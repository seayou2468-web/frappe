import sys

with open('IdeviceViewController.m', 'r') as f:
    content = f.read()

# Fix the method call from my previous script (it was a guess)
content = content.replace('idevice_rsd_checkin_provider(self.currentProvider, &handshake)', 'rsd_handshake_new_from_provider(self.currentProvider, &handshake)')

with open('IdeviceViewController.m', 'w') as f:
    f.write(content)
