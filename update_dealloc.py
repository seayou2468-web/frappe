import sys

with open('LocationSimulationViewController.m', 'r') as f:
    content = f.read()

# Update dealloc to free RemoteServer if used
if 'remote_server_free(self.remoteServer);' not in content:
    content = content.replace('location_simulation_free(self.simHandle17);',
                              'location_simulation_free(self.simHandle17);\n    if (self.remoteServer) remote_server_free(self.remoteServer);')

with open('LocationSimulationViewController.m', 'w') as f:
    f.write(content)
