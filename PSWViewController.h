#import <UIKit/UIKit.h>
#import "libactivator.h"
#import "PSWSnapshotPageView.h"
#import "PSWAppContextHostView.h"

@interface PSWViewController : UIViewController<PSWSnapshotPageViewDelegate, LAListener> {
@private
	PSWSnapshotPageView *snapshotPageView;
	PSWApplication *focusedApplication;
	BOOL isActive;
	BOOL isAnimating;
	UIStatusBarStyle formerStatusBarStyle;
}
+ (PSWViewController *)sharedInstance;

- (void)refreshSafety;
- (void)refreshSafetySoon;
@property (nonatomic, assign, getter=isActive) BOOL active;
- (void)setActive:(BOOL)active animated:(BOOL)animated;
@property (nonatomic, readonly) BOOL isAnimating;
@property (nonatomic, readonly) PSWSnapshotPageView *snapshotPageView;

@end
