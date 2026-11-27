#import "MKSProfileEditorController.h"
#import "../common/MKSProfile.h"

@interface MKSProfileEditorController ()
@property NSInteger major;
@property(strong) NSDictionary *previewProfile;
@property(copy) BOOL (^applyProfile)(NSDictionary *profile);
@end

@implementation MKSProfileEditorController
- (instancetype)initWithProfile:(NSDictionary *)profile apply:(BOOL (^)(NSDictionary *))apply {
    if((self=[super initWithStyle:UITableViewStyleInsetGrouped])) {
        if([NSFileManager.defaultManager fileExistsAtPath:MKSGenerationSettingsPath()]) {
            NSDictionary *configured=MKSGenerateProfileUsingSettings(MKSGenerationSettingsPath(),NULL);
            if(configured)profile=configured;
        }
        NSInteger major=[profile[@"values"][@"ProductVersion"] integerValue];
        self.major=major>=16 && major<=18?major:17;self.applyProfile=apply;
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"自定义 iOS 大版本";
    self.tableView.accessibilityIdentifier=@"mks.iosMajorEditor";
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"应用" style:UIBarButtonItemStyleDone target:self action:@selector(applyPreview)];
    [self generatePreview];
}
- (void)message:(NSString *)title body:(NSString *)body {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:body preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)generatePreview {
    NSError *error=nil;self.previewProfile=MKSGenerateProfileForIOSMajor(self.major,&error);
    self.navigationItem.rightBarButtonItem.enabled=self.previewProfile!=nil;
    if(!self.previewProfile) [self message:@"参数生成未通过" body:error.localizedDescription];
    [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section==0?1:section==1?2:4; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"只选 iOS 大版本",@"自动生成结果",@"使用这组规则"][section];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if(section==0) return @"选择 16、17 或 18。小版本、build、机型及其余参数自动生成，不需要手填。";
    if(section==1) return self.previewProfile?@"认证通过（HTML 本地规则）。每条结果均执行字段格式与关联校验；这不是 Apple 账户或购买认证。":@"生成未通过，当前配置保持不变。";
    return @"保存大版本后，后续一键改机和 HTTP 改机都在该大版本内随机生成小版本、匹配 build 及身份参数。“应用”保存本次预览参数并重启桌面。";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.selectionStyle=UITableViewCellSelectionStyleNone;
    if(indexPath.section==0) {
        UISegmentedControl *selector=[[UISegmentedControl alloc] initWithItems:@[@"iOS 16",@"iOS 17",@"iOS 18"]];
        selector.selectedSegmentIndex=self.major-16;selector.accessibilityIdentifier=@"mks.iosMajor";
        [selector addTarget:self action:@selector(majorChanged:) forControlEvents:UIControlEventValueChanged];
        selector.translatesAutoresizingMaskIntoConstraints=NO;[cell.contentView addSubview:selector];
        [NSLayoutConstraint activateConstraints:@[
            [selector.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
            [selector.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
            [selector.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],
            [selector.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12],
            [selector.heightAnchor constraintGreaterThanOrEqualToConstant:44]]];
    } else if(indexPath.section==1 && indexPath.row==0) {
        NSDictionary *v=self.previewProfile[@"values"];
        cell.textLabel.text=self.previewProfile?[NSString stringWithFormat:@"iOS %@ · %@",v[@"ProductVersion"],v[@"BuildVersion"]]:@"尚未生成";
        cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];cell.textLabel.adjustsFontForContentSizeCategory=YES;
        cell.textLabel.numberOfLines=0;
        cell.detailTextLabel.text=@"小版本和 build 自动配套，其余参数自动生成";cell.detailTextLabel.numberOfLines=0;
        cell.detailTextLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];cell.detailTextLabel.adjustsFontForContentSizeCategory=YES;
        cell.accessibilityIdentifier=@"mks.generatedVersion";
    } else if(indexPath.section==1) {
        UITextView *text=[UITextView new];text.text=MKSProfileHTMLParameters(self.previewProfile) ?: @"";
        text.editable=NO;text.selectable=YES;text.backgroundColor=UIColor.clearColor;text.textColor=UIColor.labelColor;
        text.font=[UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];text.adjustsFontForContentSizeCategory=YES;
        text.accessibilityLabel=@"自动生成的 14 段参数";text.accessibilityIdentifier=@"mks.generatedParameters";
        text.translatesAutoresizingMaskIntoConstraints=NO;[cell.contentView addSubview:text];
        [NSLayoutConstraint activateConstraints:@[
            [text.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
            [text.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
            [text.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:8],
            [text.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8],
            [text.heightAnchor constraintEqualToConstant:160]]];
    } else {
        cell.textLabel.text=@[@"保存大版本供后续改机使用",@"重新随机生成",@"复制 14 段参数",@"恢复默认生成方式"][indexPath.row];
        cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];cell.textLabel.adjustsFontForContentSizeCategory=YES;
        cell.textLabel.numberOfLines=0;cell.textLabel.textColor=indexPath.row==3?UIColor.systemRedColor:UIColor.systemBlueColor;
        cell.selectionStyle=UITableViewCellSelectionStyleDefault;
        cell.isAccessibilityElement=YES;cell.accessibilityLabel=cell.textLabel.text;cell.accessibilityTraits=UIAccessibilityTraitButton;
        cell.accessibilityIdentifier=[@"mks.iosMajorAction." stringByAppendingFormat:@"%ld",(long)indexPath.row];
    }
    return cell;
}
- (void)majorChanged:(UISegmentedControl *)sender { self.major=sender.selectedSegmentIndex+16;[self generatePreview]; }
- (BOOL)saveMajor {
    NSError *error=nil;
    if(!MKSSaveIOSMajor(self.major,MKSGenerationSettingsPath(),&error)) { [self message:@"大版本保存失败" body:error.localizedDescription];return NO; }
    return YES;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];if(indexPath.section!=2)return;
    if(indexPath.row==0) {
        if([self saveMajor]) [self message:@"已保存" body:[NSString stringWithFormat:@"后续一键改机和 HTTP 改机使用 iOS %ld，完整参数每次自动生成并校验。当前生效参数未改变。",(long)self.major]];
    } else if(indexPath.row==1) [self generatePreview];
    else if(indexPath.row==2) {
        if(self.previewProfile) { UIPasteboard.generalPasteboard.string=MKSProfileHTMLParameters(self.previewProfile);[self message:@"已复制" body:@"14 段参数已复制。"];}
    } else {
        NSError *error=nil;NSString *path=MKSGenerationSettingsPath();
        if([NSFileManager.defaultManager fileExistsAtPath:path] && ![NSFileManager.defaultManager removeItemAtPath:path error:&error]) { [self message:@"恢复失败" body:error.localizedDescription];return; }
        [self message:@"已恢复默认生成方式" body:@"后续一键改机使用安装包默认规则，当前生效参数未改变。"];
    }
}
- (void)applyPreview {
    if(!self.previewProfile || MKSProfileHTMLRuleErrors(self.previewProfile).count) { [self message:@"校验未通过" body:@"请重新生成。当前配置未改变。"] ;return; }
    NSDictionary *profile=self.previewProfile;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"应用本次参数？" message:[NSString stringWithFormat:@"iOS %@ · %@\nHTML 规则校验通过。保存完整参数、记住大版本并重启桌面。",profile[@"values"][@"ProductVersion"],profile[@"values"][@"BuildVersion"]] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存并应用" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if(![self saveMajor])return;
        [self.navigationController popViewControllerAnimated:YES];
        if(self.applyProfile)self.applyProfile(profile);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
