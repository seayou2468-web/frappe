import sys

with open('LocationSimulationViewController.m', 'r') as f:
    content = f.read()

# Fix didSelectRowAtIndexPath deprecations - correcting the typo from previous run
content = content.replace('[self addDestination:item.placemark.coordinate];',
                          '[self addDestination:item.location.coordinate];')

with open('LocationSimulationViewController.m', 'w') as f:
    f.write(content)
