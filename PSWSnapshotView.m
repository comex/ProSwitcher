#import "PSWSnapshotView.h"

#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <SpringBoard/SpringBoard.h>
#import <SpringBoard/SBAppContextHostView.h>
#import <QuartzCore/CALayer.h>
#import <CaptainHook/CaptainHook.h>

#import "PSWApplication.h"
#import "PSWResources.h"
#import "PSWAppContextHostView.h"

#define kSwipeThreshold 30.0f

@implementation PSWSnapshotView

@synthesize application = _application;
@synthesize delegate = _delegate;
@synthesize allowsSwipeToClose = _allowsSwipeToClose;
@synthesize allowsZoom = _allowsZoom;
@synthesize screenView = screen;

- (void)snapshot:(UIButton *)snapshot touchUpInside:(UIEvent *)event
{
	if ([_delegate respondsToSelector:@selector(snapshotViewTapped:withCount:)]) {
		UITouch *touch = [[event allTouches] anyObject];
		[_delegate snapshotViewTapped:self withCount:[touch tapCount]];
	}
}

- (void)snapshot:(UIButton *)theSnapshot didStartDrag:(UIEvent *)event
{
	UITouch *touch = [[event allTouches] anyObject];
	touchDownPoint = [touch locationInView:[self superview]];
	wasSwipedAway = NO;
	wasSwipedUp = NO;
	wasEverSwipedUp = NO;
	isInDrag = NO;
}

- (void)snapshot:(UIButton *)theSnapshot didDrag:(UIEvent *)event
{
	if (_allowsSwipeToClose) {
		UITouch *touch = [[event allTouches] anyObject];
		CGRect frame = [theSnapshot frame];
		
		NSInteger vert = touchDownPoint.y - [touch locationInView:[self superview]].y;
		if (vert > 0.0f) {
			wasSwipedAway = (vert > kSwipeThreshold);
			wasSwipedUp = YES;
			wasEverSwipedUp = YES;
			frame.origin.y = screenY - vert;
			CGFloat alpha = 1.0f - (vert / 300.0f);
			screen.alpha = (alpha > 0.0f) ? alpha:0.0f;
		} else {
			wasSwipedAway = NO;
			frame.origin.y = screenY;
			screen.alpha = 1.0f;
		}		
		[screen setFrame:frame];
		if (!isInDrag) {
			[UIView beginAnimations:nil context:NULL];
			[UIView setAnimationDuration:0.33f];
			[UIView setAnimationBeginsFromCurrentState:YES];
			_closeButton.alpha = 0.0f;
			_titleView.alpha = 0.0f;
			_iconView.alpha = 0.0f;
			_iconBadge.opacity = 0.0f;
			[UIView commitAnimations];
			isInDrag = YES;
		}
	}
}

- (void)snapshot:(UIButton *)theSnapshot didEndDrag:(UIEvent *)event
{
	if (wasSwipedAway) {
		wasSwipedAway = NO;
		if ([_delegate respondsToSelector:@selector(snapshotViewClosed:)])
			[_delegate snapshotViewClosed:self];
	} else {
		[UIView beginAnimations:nil context:NULL];
		[UIView setAnimationDuration:0.33f];
		CGRect frame = [theSnapshot frame]; 
		frame.origin.y = screenY;
		[theSnapshot setFrame:frame];
		theSnapshot.alpha = 1.0f;
		_closeButton.alpha = 1.0f;
		_titleView.alpha = 1.0f;
		_iconView.alpha = 1.0f;
		_iconBadge.opacity = 1.0f;
		[UIView commitAnimations];
		UITouch *touch = [[event allTouches] anyObject];
		if (!wasEverSwipedUp && [touch locationInView:[self superview]].y - touchDownPoint.y > kSwipeThreshold) {
			if ([_delegate respondsToSelector:@selector(snapshotViewDidSwipeOut:)])
				[_delegate snapshotViewDidSwipeOut:self];
		}
	}
}

- (void)_relayoutViews
{
	CGImageRef snapshot = [_application snapshot];
	CGSize imageSize;
	imageSize.width = (CGFloat)CGImageGetWidth(snapshot);
	imageSize.height = (CGFloat)CGImageGetHeight(snapshot);
	
	CGRect frame = [self frame];
	CGSize boundingSize;
	if (isZoomed) {
		boundingSize.width = frame.size.width;
		boundingSize.height = frame.size.height - 45.0f;
	} else {
		boundingSize.width = frame.size.width - 30.0f;
		boundingSize.height = frame.size.height - 60.0f;
	}
		
	CGFloat ratioW = boundingSize.width  / imageSize.width;
	CGFloat ratioH = boundingSize.height / imageSize.height;
	CGFloat properRatio = (ratioW < ratioH)?ratioW:ratioH;
	
	CGRect screenFrame;	
	screenFrame.size.width = properRatio * imageSize.width;
	screenFrame.size.height = properRatio * imageSize.height;
	screenFrame.origin.x = (NSInteger)((frame.size.width - screenFrame.size.width) / 2.0f);
	screenFrame.origin.y = (NSInteger)((frame.size.height - screenFrame.size.height) / 2.0f);
	
	if (isZoomed)
		screenFrame.origin.y += 8;
	
	if (_showsTitle)
		screenFrame.origin.y -= 16.0f;
	
	[screen setFrame:screenFrame];
	[_dummy setFrame:screenFrame];

	for(CALayer *sublayer in screen.layer.sublayers) {
		CGAffineTransform transform = CGAffineTransformMakeScale(properRatio, properRatio);
		sublayer.affineTransform = transform;
		sublayer.frame = CGRectMake(0, -12, frame.size.width, frame.size.height);
	}

	screenY = screenFrame.origin.y;
	if (_roundedCornerRadius == 0) {
		[[screen layer] setMask:nil];
	} else {
		CALayer *layer = [CALayer layer];
		[layer setFrame:CGRectMake(0.0f, 0.0f, screenFrame.size.width, screenFrame.size.height)];
		[layer setContents:(id) [PSWGetCachedCornerMaskOfSize(screenFrame.size, _roundedCornerRadius) CGImage]];
		[[screen layer] setMask:layer];
	}
	
	if (_closeButton != nil) {
		[_closeButton removeFromSuperview];
		[_closeButton release];
		_closeButton = nil;
	}
	if (_showsCloseButton) {
		UIImage *closeImage = PSWImage(@"closebox");
		_closeButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
		[_closeButton setBackgroundImage:closeImage forState:UIControlStateNormal];
		[_closeButton addTarget:self action:@selector(_closeButtonWasPushed) forControlEvents:UIControlEventTouchUpInside];
		
		CGSize closeImageSize = [closeImage size];
		CGFloat offsetX = (NSInteger)(closeImageSize.width / 2.0f);
		CGFloat offsetY = (NSInteger)(closeImageSize.height / 2.0f);
		[_closeButton setFrame:CGRectMake(screenFrame.origin.x - offsetX, screenFrame.origin.y - offsetY, closeImageSize.width, closeImageSize.height)];	
		
		[self addSubview:_closeButton];
	}
	
	if (_showsTitle) {
		UIFont *titleFont = [UIFont boldSystemFontOfSize:17.0f];
		NSString *title = [_application displayName];
		CGSize textSize = [title sizeWithFont:titleFont];
		CGRect titleFrame;
		titleFrame.origin.x = (NSInteger)(([self bounds].size.width - textSize.width) / 2.0f) + 18.0f;
		titleFrame.origin.y = screenFrame.origin.y + screenFrame.size.height + 25.0f - (NSInteger)(textSize.height / 2.0f);
		titleFrame.size.width = textSize.width;
		titleFrame.size.height = textSize.height;
		CGRect iconFrame;
		iconFrame.origin.x = titleFrame.origin.x - 36.0f;
		iconFrame.origin.y = screenFrame.origin.y + screenFrame.size.height + 13.0f;
		iconFrame.size.width = 24.0f;
		iconFrame.size.height = 24.0f;
		if (!_titleView) {
			_titleView = [[UILabel alloc] initWithFrame:titleFrame];
			_titleView.font = titleFont;
			_titleView.backgroundColor = [UIColor clearColor];
			_titleView.textColor = [UIColor whiteColor]; 
			_titleView.text = title;
			[self addSubview:_titleView];
		} else {
			[_titleView setFrame:titleFrame];
		}
		if (!_iconView) {
			UIImage *smallIcon;
			if (_themedIcon)
				smallIcon = [_application themedIcon];
			else
				smallIcon = [_application unthemedIcon];
			_iconView = [[UIImageView alloc] initWithFrame:iconFrame];
			[_iconView setImage:smallIcon];
			[self addSubview:_iconView];
		} else {
			[_iconView setFrame:iconFrame];
		}
	} else {
		if (_titleView) {
			[_titleView removeFromSuperview];
			[_titleView release];
			_titleView = nil;
		}
		if (_iconView) {
			[_iconView removeFromSuperview];
			[_iconView release];
			_iconView = nil;
		}
	}
		
	if (_iconBadge != nil) {
		[_iconBadge removeFromSuperlayer];
		[_iconBadge release];
		_iconBadge = nil;
	}
	if (_showsBadge) {
		SBIconBadge *badge = [_application badgeView];
		if (badge) {	
			_iconBadge = [[CALayer layer] retain];
			id badgeContents = [[badge layer] contents];
			[_iconBadge setContents:badgeContents];
			CGRect badgeFrame = [badge frame];
			badgeFrame.origin.x = (NSInteger) (screenFrame.origin.x + screenFrame.size.width - badgeFrame.size.width + (badgeFrame.size.height / 2.0f));
			badgeFrame.origin.y = (NSInteger) (screenFrame.origin.y - (badgeFrame.size.height / 2.0f) + 2.0f);
			[_iconBadge setFrame:badgeFrame];
			[[self layer] addSublayer:_iconBadge];
		}
	}
	
	CGFloat alpha = _focused?1.0f:0.0f;
	[_closeButton setAlpha:alpha];
	[_iconBadge setOpacity:alpha];
	[_titleView setAlpha:alpha];
	[_iconView setAlpha:alpha];
}

- (id)initWithFrame:(CGRect)frame application:(PSWApplication *)application
{
    if (self = [super initWithFrame:frame]) {
		_application = [application retain];
		_application.delegate = self;
		self.userInteractionEnabled = YES;
		self.opaque = NO;
		
		// Add Snapshot layer
		screen = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 0)];
		//CGImageRef snapshot = 
		[application snapshot];
		[screen setClipsToBounds:YES];
		[self reloadSnapshot];
		screen.hidden = NO;
		
		[self addSubview:screen];
		
		_dummy = [UIButton buttonWithType:UIButtonTypeCustom];
		[_dummy addTarget:self action:@selector(snapshot:touchUpInside:) forControlEvents:UIControlEventTouchUpInside];
		[_dummy addTarget:self action:@selector(snapshot:didStartDrag:) forControlEvents:UIControlEventTouchDown];
		[_dummy addTarget:self action:@selector(snapshot:didDrag:) forControlEvents:UIControlEventTouchDragInside | UIControlEventTouchDragOutside];
		[_dummy addTarget:self action:@selector(snapshot:didEndDrag:) forControlEvents:UIControlEventTouchCancel | UIControlEventTouchDragExit | UIControlEventTouchUpOutside | UIControlEventTouchUpInside];
		
		_dummy.backgroundColor = [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.01];
		[self addSubview:_dummy];
		
		[self _relayoutViews];
	}
    return self;
}

- (void)dealloc
{
	_application.delegate = nil;
	[_titleView release];
	[_iconView release];
	[_closeButton release];
	[_iconBadge release];
	[_application release];
	[screen release];
	[_dummy release];
	
    [super dealloc];
}

- (void)reloadSnapshotIfNecessary
{
	BOOL wasLive = screen.layer.sublayers.count > 0;
	BOOL shouldBeLive = _focused && sceneIsSafe([_application contextId]);
	//NSLog(@"(%@) rsin: wasLive=%d shouldBeLive=%d", [_application displayName], wasLive, shouldBeLive);
	if(shouldBeLive != wasLive) {
		if(wasLive) {
			[_application loadSnapshotFromLayer:[screen.layer.sublayers objectAtIndex:0]];
			//[_application loadSnapshotFromDefaultSurface];
		}		
		[self reloadSnapshot:shouldBeLive];
	}
	[self setNeedsDisplay];
}

- (void)reloadSnapshot:(BOOL)shouldBeLive
{
	CALayer *screenLayer = [screen layer];

	for(CALayer *sublayer in [screenLayer sublayers]) {
		[sublayer removeFromSuperlayer];
	}

	CALayer *liveLayer = shouldBeLive ? [_application liveLayer] : nil;
	if(liveLayer) {
		[screenLayer addSublayer:liveLayer];
		[liveLayer release];
	} else {
		[screenLayer setContents:(id)[_application snapshot]];
	}
	if(shouldBeLive) [self _relayoutViews];	
}

- (void)reloadSnapshot
{
	[self reloadSnapshot:(_focused && sceneIsSafe([_application contextId]))];
}

- (void)doneZoomy
{
	[self reloadSnapshot];
	[self _relayoutViews];
}

#pragma mark Properties

- (void)redraw
{
	[self _relayoutViews];
}

- (void)_closeButtonWasPushed
{
	if ([_delegate respondsToSelector:@selector(snapshotViewClosed:)])
		[_delegate snapshotViewClosed:self];
}

- (BOOL)showsCloseButton
{
	return _closeButton != nil;
}

- (void)setShowsCloseButton:(BOOL)showsCloseButton
{
	if (_showsCloseButton != showsCloseButton) {
		_showsCloseButton = showsCloseButton;
		[self _relayoutViews];
	}
}

- (BOOL)showsTitle
{
	return _titleView != nil;
}

- (void)setShowsTitle:(BOOL)showsTitle
{
	_showsTitle = showsTitle;
	[self _relayoutViews];
}

- (BOOL)themedIcon
{
	return _themedIcon;
}
- (void)setThemedIcon:(BOOL)themedIcon
{
	_themedIcon = themedIcon;
	
	// Remove icon view so it gets re-created with the new icon
	if (_iconView) {
		[_iconView removeFromSuperview];
		[_iconView release];
		_iconView = nil;
	}
	
	[self _relayoutViews];
}

- (BOOL)showsBadge
{
	return _iconBadge != nil;
}
- (void)setShowsBadge:(BOOL)showsBadge
{
	_showsBadge = showsBadge;
	[self _relayoutViews];
}
  
- (CGFloat)roundedCornerRadius
{
	return _roundedCornerRadius;
}
- (void)setRoundedCornerRadius:(CGFloat)roundedCornerRadius
{
	if (_roundedCornerRadius != roundedCornerRadius) {
		_roundedCornerRadius = roundedCornerRadius;
		[self _relayoutViews];
	}
}

- (BOOL)focused
{
	return _focused;
}
- (void)setFocused:(BOOL)focused animated:(BOOL)animated
{
	_focused = focused;
	if (animated) {
		[UIView beginAnimations:nil context:NULL];
		[UIView setAnimationDuration:0.33f];
	}
	CGFloat alpha = _focused?1.0f:0.0f;
	[_closeButton setAlpha:alpha];
	[_titleView setAlpha:alpha];
	[_iconView setAlpha:alpha];
	[_iconBadge setOpacity:alpha];
	if (animated) {
		[UIView commitAnimations];
	}
	[self reloadSnapshotIfNecessary];
}
- (void)setFocused:(BOOL)focused
{
	[self setFocused:focused animated:YES];
}

- (void)setFrame:(CGRect)frame
{
	if (!CGRectEqualToRect([self frame], frame)) {
		[super setFrame:frame];
		[self _relayoutViews];
	}
}

- (void)setZoomed:(BOOL)zoomed
{
	if ((!zoomed && !isZoomed) || (zoomed && isZoomed))
		return;
	if (_allowsZoom) {
		[UIView beginAnimations:nil context:NULL];
		[UIView setAnimationDuration:0.2f];
		isZoomed = zoomed;
		[self _relayoutViews];
		[UIView commitAnimations];
	} else {
		if (isZoomed) {
			[UIView beginAnimations:nil context:NULL];
			[UIView setAnimationDuration:0.2f];
			isZoomed = NO;
			[self _relayoutViews];
			[UIView commitAnimations];
		}
	}
}

#pragma mark PSWApplicationDelegate

- (void)applicationSnapshotDidChange:(PSWApplication *)application
{
	[self reloadSnapshot];
}

- (void)applicationBadgeDidChange:(PSWApplication *)application
{
	[self _relayoutViews];
}

@end
