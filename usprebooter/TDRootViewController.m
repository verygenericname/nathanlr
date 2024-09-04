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
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshNotify:) name:@"refreshNotify" object:nil];
}

- (void)refreshNotify:(NSNotification *)notification {
    [self refreshApps:self.refreshControl];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)refreshApps:(UIRefreshControl *)refreshControl {
    NSArray *newApps = appList();
    self.apps = newApps;

    if (self.isSearching) {
        [self updateSearchResultsForSearchController:self.navigationItem.searchController];
    } else {
        self.filteredApps = self.apps;
    }
    
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

    if (strcmp([(NSString *)app[@"injected"] UTF8String], " • Injected✅") == 0) {
        alert = [UIAlertController alertControllerWithTitle:@"Inject" message:[NSString stringWithFormat:@"Disable Tweaks on %@?", app[@"name"]] preferredStyle:UIAlertControllerStyleAlert];
    } else {
        alert = [UIAlertController alertControllerWithTitle:@"Inject" message:[NSString stringWithFormat:@"Enable Tweaks on %@?", app[@"name"]] preferredStyle:UIAlertControllerStyleAlert];
    }

    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    UIAlertAction *decrypt = [UIAlertAction actionWithTitle:@"Yes" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        decryptApp(app);
    }];
    
    UIAlertAction *decrypt2 = [UIAlertAction actionWithTitle:@"Reinject" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            decryptApp2(app);
    }];
    
    [alert addAction:decrypt];
    if (strcmp([(NSString *)app[@"injected"] UTF8String], " • Injected✅") == 0 && strstr([(NSString *)app[@"bundleID"] UTF8String], "com.apple.") == NULL) {
        [alert addAction:decrypt2];
    }
    [alert addAction:cancel];

    [self presentViewController:alert animated:YES completion:nil];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *searchText = searchController.searchBar.text.lowercaseString;
    self.isSearching = (searchText.length > 0);
    
    if (self.isSearching) {
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *app, NSDictionary *bindings) {
            NSString *appName = app[@"name"];
            return [appName.lowercaseString containsString:searchText];
        }];
        self.filteredApps = [self.apps filteredArrayUsingPredicate:predicate];
    } else {
        self.filteredApps = self.apps;
    }
    
    [self.tableView reloadData];
}

@end
