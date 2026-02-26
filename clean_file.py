import re
import sys

with open('FileBrowserViewController.m', 'r') as f:
    content = f.read()

# Remove the old showOthersMenu method
content = re.sub(r'- \(void\)showOthersMenu \{.*?\}', '', content, flags=re.DOTALL)

# Remove extra @end if any
parts = content.split('@end')
content = '@end'.join(p for p in parts if p.strip()) + '\n@end\n'

with open('FileBrowserViewController.m', 'w') as f:
    f.write(content)
