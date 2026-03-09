import sys

with open('AppManager.m', 'r') as f:
    content = f.read()

# I will attempt to implement a generic app launch using app_service_new if I can get a socket
# But wait, springboard_services is also good.
# Let's check for app_service_connect (without rsd)
