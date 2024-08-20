#import <UIKit/UIKit.h>

@interface TDRootViewController : UITableViewController <UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating>

@property (nonatomic, strong) NSArray *apps;

@property (nonatomic, strong) NSArray *filteredApps;

@end
