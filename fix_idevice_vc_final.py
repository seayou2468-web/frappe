import sys

with open("IdeviceViewController.m", "r") as f:
    content = f.read()

# Fix showProfileManager to use proper error logging
content = content.replace('[self log:@"ERROR: NO_ACTIVE_LINK"]', '[self log:@"Active link required."]')

with open("IdeviceViewController.m", "w") as f:
    f.write(content)
