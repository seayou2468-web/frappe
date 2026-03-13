import sys

with open("AppManager.m", "r") as f:
    content = f.read()

# Check for robust connection loop
if "for (int i = 0; i < 8; i++)" not in content:
    print("Robust connection loop missing.")
    sys.exit(1)

if "HeartbeatManager sharedManager] pause" not in content:
    print("Heartbeat pause missing.")
    sys.exit(1)

print("AppManager.m looks good (v7).")
