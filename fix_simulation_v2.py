import sys

with open('LocationSimulationViewController.m', 'r') as f:
    content = f.read()

# Fix 1: Use removeAllObjects instead of creating new array in startSimulation
content = content.replace('self.currentPathPoints = [NSMutableArray array];',
                          '[self.currentPathPoints removeAllObjects];')

# Fix 2: populate the persistent array in calculateRoute instead of replacing it
content = content.replace('self.currentPathPoints = interpolated;',
                          '[self.currentPathPoints removeAllObjects];\n            [self.currentPathPoints addObjectsFromArray:interpolated];')

with open('LocationSimulationViewController.m', 'w') as f:
    f.write(content)
