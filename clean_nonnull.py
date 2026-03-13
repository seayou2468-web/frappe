import sys

files = ['ProfileManagerViewController.m', 'FileBrowserViewController.m']
for f in files:
    with open(f, 'r') as file:
        content = file.read()

    new_content = content.replace('_Nonnull', '').replace('nonnull', '')

    with open(f, 'w') as file:
        file.write(new_content)
    print(f"Cleaned {f}")
