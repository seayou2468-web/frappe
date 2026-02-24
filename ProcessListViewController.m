#import "ProcessListViewController.h"
#import "extends/JITEnableContext.h"

@interface ProcessListViewController () <UITableViewDelegate, UITableViewDataSource>
@property (strong, nonatomic) UITableView *tableView;
@property (strong, nonatomic) NSArray<NSDictionary *> *processes;
@end

@implementation ProcessListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = @"Processes";

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];

    [self loadProcesses];
}

- (void)loadProcesses {
    NSError *error;
    self.processes = [[JITEnableContext shared] fetchProcessListWithError:&error];
    if (error) {
        NSLog(@"Process list error: %@", error);
    }
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.processes.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"ProcessCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
    }

    NSDictionary *proc = self.processes[indexPath.row];
    cell.textLabel.text = [NSString stringWithFormat:@"PID: %@ - %@", proc[@"pid"], [proc[@"path"] lastPathComponent]];
    cell.detailTextLabel.text = proc[@"path"];

    return cell;
}

@end
