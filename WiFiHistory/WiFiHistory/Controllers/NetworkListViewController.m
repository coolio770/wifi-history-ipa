#import "NetworkListViewController.h"
#import "WiFiHistoryManager.h"
#import "WiFiNetworkRecord.h"

static NSString * const kCellReuseID = @"WiFiNetworkCell";

@interface NetworkListViewController ()
@property (nonatomic, copy) NSArray<WiFiNetworkRecord *> *networks;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@end

@implementation NetworkListViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"WiFi History";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 72.0;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kCellReuseID];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                           target:self
                                                                                           action:@selector(refreshNetworks)];

    self.dateFormatter = [[NSDateFormatter alloc] init];
    self.dateFormatter.dateStyle = NSDateFormatterMediumStyle;
    self.dateFormatter.timeStyle = NSDateFormatterShortStyle;

    self.emptyLabel = [[UILabel alloc] init];
    self.emptyLabel.text = @"No networks loaded.\nPull to refresh after signing with jailbreak entitlements.";
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.textColor = [UIColor darkGrayColor];
    self.emptyLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.tableView.backgroundView = self.emptyLabel;

    [self refreshNetworks];
}

- (void)refreshNetworks {
    self.navigationItem.rightBarButtonItem.enabled = NO;
    [[WiFiHistoryManager sharedManager] loadNetworkHistoryWithCompletion:^(NSArray<WiFiNetworkRecord *> *networks, NSError *error) {
        self.navigationItem.rightBarButtonItem.enabled = YES;
        self.networks = networks;
        self.tableView.backgroundView = networks.count > 0 ? nil : self.emptyLabel;
        [self.tableView reloadData];

        if (error && networks.count == 0) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Load Failed"
                                                                           message:error.localizedDescription
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.networks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellReuseID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kCellReuseID];
    }
    WiFiNetworkRecord *record = self.networks[indexPath.row];

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (record.lastConnected) {
        [parts addObject:[self.dateFormatter stringFromDate:record.lastConnected]];
    }
    if (record.securityType.length > 0) {
        [parts addObject:record.securityType];
    }
    if (record.isHidden) {
        [parts addObject:@"Hidden"];
    }

    cell.textLabel.text = record.ssid;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];

    NSString *password = record.password.length > 0 ? record.password : @"(password unavailable)";
    NSString *subtitle = parts.count > 0
        ? [NSString stringWithFormat:@"%@ — %@", [parts componentsJoinedByString:@" · "], password]
        : password;
    cell.detailTextLabel.text = subtitle;
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.textColor = record.password.length > 0 ? [UIColor grayColor] : [UIColor orangeColor];
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    return cell;
}

@end
