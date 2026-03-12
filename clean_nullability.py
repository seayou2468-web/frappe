import os
import re

def clean_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # Remove nonnull, _Nonnull, nullable, _Nullable
    content = re.sub(r'\b(nonnull|_Nonnull|nullable|_Nullable)\b', '', content)

    with open(filepath, 'w') as f:
        f.write(content)

for filename in os.listdir('.'):
    if filename.endswith(('.h', '.m', '.mm')):
        clean_file(filename)
