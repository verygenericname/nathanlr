#import "TDRootViewController.h"
#import "TDUtils.h"
#import "TSPresentationDelegate.h"

@implementation TDRootViewController

- (void)loadView {
    [super loadView];

    self.apps = appList();
    self.filteredApps = self.apps;
    self.title = @"Inject into Apps";
    self.navigationController.navigationBar.prefersLargeTitles = YES;

    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self action:@selector(refreshApps:) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refreshControl;
    TSPresentationDelegate.presentationViewController = self;
    
    UISearchController *searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    searchController.searchResultsUpdater = self;
    searchController.obscuresBackgroundDuringPresentation = NO;
    searchController.searchBar.placeholder = @"Search Apps";
    self.navigationItem.searchController = searchController;
    self.definesPresentationContext = YES;
}

- (void)refreshApps:(UIRefreshControl *)refreshControl {
    self.apps = appList();
    self.filteredApps = self.apps;
    [self.tableView reloadData];
    [refreshControl endRefreshing];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredApps.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"AppCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellIdentifier];
    }
    
    NSDictionary *app = self.filteredApps[indexPath.row];
    cell.textLabel.text = [NSString stringWithFormat:@"%@%@", app[@"name"], app[@"injected"]];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %@", app[@"version"], app[@"bundleID"]];
    cell.imageView.image = [UIImage _applicationIconImageForBundleIdentifier:app[@"bundleID"] format:iconFormat() scale:[UIScreen mainScreen].scale];

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 80.0f;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UIAlertController *alert;
    
    NSDictionary *app = self.filteredApps[indexPath.row];

    alert = [UIAlertController alertControllerWithTitle:@"Inject" message:[NSString stringWithFormat:@"Toggle Tweaks on %@?", app[@"name"]] preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    UIAlertAction *decrypt = [UIAlertAction actionWithTitle:@"Yes" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        decryptApp(app);
    }];

    [alert addAction:decrypt];
    [alert addAction:cancel];

    [self presentViewController:alert animated:YES completion:nil];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *searchText = searchController.searchBar.text.lowercaseString;
    
    if (searchText.length == 0) {
        self.filteredApps = self.apps;
    } else {
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *app, NSDictionary *bindings) {
            NSString *appName = app[@"name"];
            return [appName.lowercaseString containsString:searchText];
        }];
        self.filteredApps = [self.apps filteredArrayUsingPredicate:predicate];
    }
    
    [self.tableView reloadData];
}

@end
