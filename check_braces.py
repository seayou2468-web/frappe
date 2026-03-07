import sys

def check_file(filename):
    with open(filename, 'r') as f:
        content = f.read()

    brace_level = 0
    in_comment = False
    in_string = False

    for i, char in enumerate(content):
        if char == '"' and not in_comment:
            if i > 0 and content[i-1] == '\\':
                pass
            else:
                in_string = not in_string
        if in_string:
            continue

        if content[i:i+2] == '/*':
            in_comment = True
        elif content[i:i+2] == '*/':
            in_comment = False

        if in_comment:
            continue

        if char == '{':
            brace_level += 1
        elif char == '}':
            brace_level -= 1
            if brace_level < 0:
                print(f"Negative brace level at index {i}")
                # Print some context
                start = max(0, i - 40)
                end = min(len(content), i + 40)
                print(f"Context: {content[start:end]}")

    print(f"Final brace level: {brace_level}")

check_file('IdeviceManager.m')
