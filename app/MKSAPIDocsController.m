#import "MKSAPIDocsController.h"
#import "../common/MKSHTTP.h"
#include <TargetConditionals.h>

@interface MKSAPIDocsController ()
@property(strong) UITextView *document;
@end
@implementation MKSAPIDocsController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"HTTP 调用文档";
    self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.document=[UITextView new];self.document.translatesAutoresizingMaskIntoConstraints=NO;
    self.document.editable=NO;self.document.selectable=YES;
    self.document.font=[UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    self.document.textColor=UIColor.labelColor;
    self.document.textContainerInset=UIEdgeInsetsMake(16,16,24,16);
    [self.view addSubview:self.document];
    [NSLayoutConstraint activateConstraints:@[
        [self.document.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.document.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [self.document.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.document.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]]];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"复制" style:UIBarButtonItemStylePlain target:self action:@selector(copyDocument)];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSString *token=MKSHTTPToken();
#if TARGET_OS_SIMULATOR
    token=@"SIMULATOR_EXAMPLE_TOKEN";
#endif
    self.document.text=MKSHTTPDocumentation(MKSHTTPBaseURL(),token ?: @"（服务未就绪：安装完整 MKS DEB 后返回重进）");
}
- (void)copyDocument {
    UIPasteboard.generalPasteboard.string=self.document.text;
    self.navigationItem.rightBarButtonItem.title=@"已复制";
}
@end
