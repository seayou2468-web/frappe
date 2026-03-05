import sys

def get_file_lines(path):
    with open(path, 'r') as f:
        return f.readlines()

# Since I don't have the "before" state easily, I'll just describe the changes in the review call.
