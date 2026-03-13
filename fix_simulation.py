import sys

with open('LocationSimulationViewController.m', 'r') as f:
    content = f.read()

# Fix startSimulation re-assignment bug
content = content.replace('self.currentPathPoints = [NSMutableArray array];',
                          '[self.currentPathPoints removeAllObjects];')

# Update calculateRoute to populate the persistent array correctly
import re
new_calc_route_success = """            [self.currentPathPoints removeAllObjects];
            CLLocation *prevL = nil;
            for (NSUInteger i = 0; i < count; i++) {
                CLLocation *currL = [[CLLocation alloc] initWithLatitude:coords[i].latitude longitude:coords[i].longitude];
                if (prevL) { [self interpolateBetween:prevL and:currL into:self.currentPathPoints]; }
                else { [self.currentPathPoints addObject:currL]; }
                prevL = currL;
            }
            free(coords);"""

content = re.sub(r'self\.currentPathPoints = \[NSMutableArray array\];.*?free\(coords\);',
                 new_calc_route_success, content, flags=re.DOTALL)

with open('LocationSimulationViewController.m', 'w') as f:
    f.write(content)
