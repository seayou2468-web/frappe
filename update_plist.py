import sys

with open('Config/Project.plist', 'r') as f:
    content = f.read()

# Add CoreLocation framework and NSLocation Usage Description
if '<string>CoreLocation</string>' not in content:
    content = content.replace('<string>UIKit</string>', '<string>UIKit</string>\n\t\t<string>CoreLocation</string>\n\t\t<string>MapKit</string>')

if 'NSLocationWhenInUseUsageDescription' not in content:
    desc = """\t<key>NSLocationWhenInUseUsageDescription</key>\n\t<string>Location is required for simulation and original position recovery.</string>"""
    content = content.replace('<key>LDEBundleShortVersion</key>', desc + "\n\t<key>LDEBundleShortVersion</key>")

with open('Config/Project.plist', 'w') as f:
    f.write(content)
