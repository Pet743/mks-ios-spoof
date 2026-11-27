#import <UIKit/UIKit.h>

@interface MKSProfileEditorController : UITableViewController
- (instancetype)initWithProfile:(NSDictionary *)profile apply:(BOOL (^)(NSDictionary *profile))apply;
@end
