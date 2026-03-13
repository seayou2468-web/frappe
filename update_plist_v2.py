import sys

with open('Config/Project.plist', 'r') as f:
    content = f.read()

# Add MapKit framework if missing (CoreLocation added in previous run)
if '<string>MapKit</string>' not in content:
    content = content.replace('<string>UIKit</string>', '<string>UIKit</string>\n\t\t<string>CoreLocation</string>\n\t\t<string>MapKit</string>')

# Add NSLocationWhenInUseUsageDescription to LDEBundleInfo instead of root
if 'NSLocationWhenInUseUsageDescription' not in content:
    desc = """\t\t<key>NSLocationWhenInUseUsageDescription</key>\n\t\t<string>Location is required for simulation and original position recovery.</string>"""
    content = content.replace('<key>UIApplicationSceneManifest</key>', desc + "\n\t\t<key>UIApplicationSceneManifest</key>")

with open('Config/Project.plist', 'w') as f:
    f.write(content)
