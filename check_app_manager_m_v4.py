import sys

with open("AppManager.m", "r") as f:
    content = f.read()

# Check for fixed names and simplified logic
if "mcinstall_core_device_client_new_from_stream" in content:
    print("mcinstall_core_device_client_new_from_stream still exists, simplification failed.")
    sys.exit(1)

if "mcinstall_connect" not in content:
    print("mcinstall_connect missing.")
    sys.exit(1)

print("AppManager.m looks good (v4).")
