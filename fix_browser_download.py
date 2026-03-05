import os

file_path = 'WebBrowserViewController.m'
with open(file_path, 'r') as f:
    content = f.read()

old_trigger = """- (void)triggerDownloadWithURL:(NSURL *)url {
    if (!url) return;
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    // Ensure we are using the virtualized Documents path if available
    NSString *downloadsPath = [docs stringByAppendingPathComponent:@"Downloads"];"""

new_trigger = """- (void)triggerDownloadWithURL:(NSURL *)url {
    if (!url) return;
    // Derive download path from the effective home to ensure it's within the virtual sandbox
    NSString *home = [FileManagerCore effectiveHomeDirectory];
    NSString *downloadsPath = [[home stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:@"Downloads"];"""

content = content.replace(old_trigger, new_trigger)

with open(file_path, 'w') as f:
    f.write(content)
