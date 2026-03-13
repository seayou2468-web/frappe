import sys

with open("AppManager.m", "r") as f:
    content = f.read()

# Check for ProfileInfo implementation
if "@implementation ProfileInfo" not in content:
    print("Missing ProfileInfo implementation")
    sys.exit(1)

# Check for AppManager methods
methods = [
    "fetchProfilesWithProvider",
    "parseProfilesPlist",
    "installProfileData",
    "removeProfileWithIdentifier"
]

for m in methods:
    if m not in content:
        print(f"Missing method {m} in AppManager.m")
        sys.exit(1)

print("AppManager.m looks good.")
