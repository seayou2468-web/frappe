import sys

with open("AppManager.m", "r") as f:
    content = f.read()

# Fix redefinition and cleanup multiple declarations
content = content.replace("struct CoreDeviceProxyHandle *proxy = NULL;\n        proxy = NULL;", "struct CoreDeviceProxyHandle *proxy = NULL;")

with open("AppManager.m", "w") as f:
    f.write(content)
