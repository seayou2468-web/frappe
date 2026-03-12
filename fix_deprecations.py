import sys

with open('LocationSimulationViewController.m', 'r') as f:
    content = f.read()

# Fix cellForRowAtIndexPath deprecations
content = content.replace('cell.detailTextLabel.text = item.placemark.title;',
                          'cell.detailTextLabel.text = item.name;') # Simplified for now

# Fix didSelectRowAtIndexPath deprecations
content = content.replace('[self.mapView setCenterCoordinate:item.placemark.coordinate animated:YES];',
                          '[self.mapView setCenterCoordinate:item.location.coordinate animated:YES];')
content = content.replace('[self.addDestination:item.placemark.coordinate];',
                          '[self.addDestination:item.location.coordinate];')

# Fix calculateRoute deprecations
# MKDirectionsRequest source and destination
content = content.replace('req.destination = [[MKMapItem alloc] initWithPlacemark:[[MKPlacemark alloc] initWithCoordinate:self.destinations.lastObject.coordinate]];',
                          'req.destination = [[MKMapItem alloc] initWithLocation:[[CLLocation alloc] initWithLatitude:self.destinations.lastObject.coordinate.latitude longitude:self.destinations.lastObject.coordinate.longitude] address:nil];')

content = content.replace('req.source = [[MKMapItem alloc] initWithPlacemark:[[MKPlacemark alloc] initWithCoordinate:self.currentSimulatedPos]];',
                          'req.source = [[MKMapItem alloc] initWithLocation:[[CLLocation alloc] initWithLatitude:self.currentSimulatedPos.latitude longitude:self.currentSimulatedPos.longitude] address:nil];')

# Fix overlay renderer cast
content = content.replace('MKPolylineRenderer *r = [[MKPolylineRenderer alloc] initWithPolyline:overlay];',
                          'MKPolylineRenderer *r = [[MKPolylineRenderer alloc] initWithPolyline:(MKPolyline *)overlay];')

with open('LocationSimulationViewController.m', 'w') as f:
    f.write(content)
