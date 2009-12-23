#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <SpringBoard/SpringBoard.h>
#import <SpringBoard/SBIconBadge.h>
#import <CaptainHook/CaptainHook.h>

#import "PSWApplication.h"

@protocol PSWSnapshotViewDelegate;

@interface PSWSnapshotView : UIView<PSWApplicationDelegate> {
@private
	PSWApplication *_application;
	id<PSWSnapshotViewDelegate> _delegate;
	BOOL _allowsSwipeToClose;
	BOOL _showsCloseButton;
	BOOL _showsTitle;
	BOOL _themedIcon;
	BOOL _showsBadge;
	BOOL _focused; 
	BOOL _allowsZoom;
	BOOL mayBeLive;
	UIButton *_closeButton;
	CALayer *_iconBadge;
	UILabel *_titleView;
	UIImageView *_iconView;
	
	BOOL wasSwipedAway;
	BOOL wasEverSwipedUp;
	BOOL wasSwipedUp;
	BOOL isInDrag;
	BOOL isZoomed;
	CGPoint touchDownPoint;
	UIView *screen;
	UIButton *_dummy;
	CGFloat screenY;
	CGFloat _roundedCornerRadius;
}

- (id)initWithFrame:(CGRect)frame application:(PSWApplication *)application;

@property (nonatomic, readonly) PSWApplication *application;
@property (nonatomic, assign) id<PSWSnapshotViewDelegate> delegate;
@property (nonatomic, assign) BOOL showsTitle;
@property (nonatomic, assign) BOOL showsBadge;
@property (nonatomic, assign) BOOL allowsZoom;
- (void)setZoomed:(BOOL)zoomed;
@property (nonatomic, assign) BOOL themedIcon;
@property (nonatomic, assign) BOOL showsCloseButton;
@property (nonatomic, assign) BOOL allowsSwipeToClose;
@property (nonatomic, assign) CGFloat roundedCornerRadius;
@property (nonatomic, assign) BOOL focused;
@property (nonatomic, assign) BOOL mayBeLive;
- (void)setFocused:(BOOL)focused animated:(BOOL)animated;
@property (nonatomic, readonly) UIView *screenView;

- (void)redraw;
- (void)reloadSnapshot;

@end

@protocol PSWSnapshotViewDelegate <NSObject>
@optional
- (void)snapshotViewTapped:(PSWSnapshotView *)snapshotView withCount:(NSInteger)tapCount;
- (void)snapshotViewClosed:(PSWSnapshotView *)snapshotView;
- (void)snapshotViewDidSwipeOut:(PSWSnapshotView *)snapshotView;
@end
