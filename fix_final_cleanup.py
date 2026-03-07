import re

with open('IdeviceManager.m', 'r') as f:
    content = f.read()

# Fix the double if (err) caused by re.sub earlier
content = content.replace('if (err) if (err) idevice_error_free(err);', 'if (err) idevice_error_free(err);')

with open('IdeviceManager.m', 'w') as f:
    f.write(content)
