import sys

with open('LocationSimulationViewController.m', 'r') as f:
    content = f.read()

# Fix transport type logic
content = content.replace('req.transportType = (self.transportControl.selectedSegmentIndex == 2) ? MKDirectionsTransportTypeAutomobile : MKDirectionsTransportTypeWalking;',
                          'req.transportType = (self.transportControl.selectedSegmentIndex == 0) ? MKDirectionsTransportTypeWalking : MKDirectionsTransportTypeAutomobile;')

with open('LocationSimulationViewController.m', 'w') as f:
    f.write(content)
