#import "PSWViewController.h"

#import <QuartzCore/QuartzCore.h>
#import <SpringBoard/SpringBoard.h>
#import <SpringBoard/SBAwayController.h>
#import <SpringBoard/SBIconController.h>
#import <SpringBoard/SBStatusBarController.h>
#import <SpringBoard/SBIconModel.h>
#import <CaptainHook/CaptainHook.h>

#include <dlfcn.h>

#import "PSWDisplayStacks.h"
#import "PSWPreferences.h"
#import "PSWResources.h"
#import "SpringBoard+Backgrounder.h"
#import "SBUIController+CategoriesSB.h"

// Using late binding until we get a simulator build for libactivator :(
CHDeclareClass(LAActivator);

CHDeclareClass(SBAwayController);
CHDeclareClass(SBStatusBarController);
CHDeclareClass(SBApplication);
CHDeclareClass(SBDisplayStack);
CHDeclareClass(SpringBoard);
CHDeclareClass(SBIconListPageControl);
CHDeclareClass(SBUIController);
CHDeclareClass(SBApplicationController);
CHDeclareClass(SBIconModel);
CHDeclareClass(SBIconController);
CHDeclareClass(SBZoomView);
CHDeclareClass(SBStatusBar);
CHDeclareClass(SBSearchView);
CHDeclareClass(SBVoiceControlAlert);

#define SBActive ([SBWActiveDisplayStack topApplication] == nil)
#define SBSharedInstance ((SpringBoard *) [UIApplication sharedApplication])

static NSDictionary *preferences = nil;

static NSUInteger disallowIconListScatter;
static NSUInteger disallowRestoreIconList;
static NSUInteger disallowIconListScroll;
static NSUInteger modifyZoomTransformCountDown;
static NSUInteger ignoreZoomSetAlphaCountDown;

static PSWViewController *mainController;
@implementation PSWViewController
@synthesize snapshotPageView;

+ (PSWViewController *)sharedInstance
{
	if (!mainController)
		mainController = [[PSWViewController alloc] init];
	return mainController;
}

- (BOOL)isActive
{
	return isActive;
}

- (BOOL)isAnimating
{
	return isAnimating;
}

#pragma mark Preferences

- (void)_applyPreferences
{
	UIView *view = [self view];
	view.backgroundColor = GetPreference(PSWDimBackground, BOOL) ? [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.8]:[UIColor clearColor];
	
	if (GetPreference(PSWBackgroundStyle, NSInteger) == 1)
		[[view layer] setContents:(id) [PSWImage(@"Background") CGImage]];
	else
		[[view layer] setContents:nil];
	
	if ([self isActive] && GetPreference(PSWShowPageControl, BOOL))
		[CHSharedInstance(SBIconController) setPageControlVisible:NO];
	
	CGRect frame;
	frame.origin.x = 0.0f;
	frame.origin.y = [[CHClass(SBStatusBarController) sharedStatusBarController] useDoubleHeightSize] ? 40.0f : 20.0f;
	frame.size.width = 320.0f;
	frame.size.height = (GetPreference(PSWShowDock, BOOL) ? 390.0f : 480.0f) - frame.origin.y;
	[snapshotPageView setFrame:frame];
	[snapshotPageView setBackgroundColor:[UIColor clearColor]];
	
	snapshotPageView.allowsSwipeToClose  = GetPreference(PSWSwipeToClose, BOOL);
	snapshotPageView.showsTitles         = GetPreference(PSWShowApplicationTitle, BOOL);
	snapshotPageView.showsCloseButtons   = GetPreference(PSWShowCloseButton, BOOL);
	snapshotPageView.emptyText           = GetPreference(PSWShowEmptyText, BOOL) ? @"No Apps Running" : nil;
	snapshotPageView.roundedCornerRadius = GetPreference(PSWRoundedCornerRadius, float);
	snapshotPageView.tapsToActivate      = GetPreference(PSWTapsToActivate, NSInteger);
	snapshotPageView.snapshotInset       = GetPreference(PSWSnapshotInset, float);
	snapshotPageView.unfocusedAlpha      = GetPreference(PSWUnfocusedAlpha, float);
	snapshotPageView.showsPageControl    = GetPreference(PSWShowPageControl, BOOL);
	snapshotPageView.showsBadges         = GetPreference(PSWShowBadges, BOOL);
	NSMutableArray *ignored = GetPreference(PSWShowDefaultApps, BOOL) ? [[NSMutableArray alloc] init] : [GetPreference(PSWDefaultApps, id) mutableCopy];
	if (GetPreference(PSWSpringBoardCard, BOOL) == NO)
		[ignored addObject:@"com.apple.springboard"];
	snapshotPageView.ignoredDisplayIdentifiers = ignored;
	snapshotPageView.pagingEnabled       = GetPreference(PSWPagingEnabled, BOOL);
	snapshotPageView.themedIcons         = GetPreference(PSWThemedIcons, BOOL);
	snapshotPageView.allowsZoom          = GetPreference(PSWAllowsZoom, BOOL);
}

- (void)_reloadPreferences
{
	[preferences release];
	preferences = [[NSDictionary alloc] initWithContentsOfFile:PSWPreferencesFilePath];
	[self _applyPreferences];
}

#pragma mark View Controller

- (id)init
{
	if ((self = [super init])) {
		preferences = [[NSDictionary alloc] initWithContentsOfFile:PSWPreferencesFilePath];
	}	
	return self;
}

- (void)dealloc 
{
	[preferences release];
	[focusedApplication release];
	[snapshotPageView release];
    [super dealloc];
}

- (void)reparentView
{
	// Find appropriate superview and add as subview
	UIView *buttonBar = [CHSharedInstance(SBIconModel) buttonBar];
	UIView *buttonBarParent = [buttonBar superview];
	UIView *targetSuperview = [buttonBarParent superview];
	if (GetPreference(PSWShowDock, BOOL))
		[targetSuperview insertSubview:self.view belowSubview:buttonBarParent];
	else
		[targetSuperview insertSubview:self.view aboveSubview:buttonBarParent];	
}

- (void)loadView 
{
	UIView *view = [[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
	
	snapshotPageView = [[PSWSnapshotPageView alloc] initWithFrame:CGRectZero applicationController:[PSWApplicationController sharedInstance]];
	[snapshotPageView setDelegate:self];
	[view addSubview:snapshotPageView];
	
	[self setView:view];
	[view release];
	[self _applyPreferences];
}

- (void)viewDidUnload
{
	[snapshotPageView removeFromSuperview];
	[snapshotPageView release];
	snapshotPageView = nil;
	[super viewDidUnload];
}

- (void)didReceiveMemoryWarning
{
	[super didReceiveMemoryWarning];
	[[PSWApplicationController sharedInstance] writeSnapshotsToDisk];
	PSWClearResourceCache();
}

#pragma mark Status Bar

- (void)saveStatusBarStyle
{
	formerStatusBarStyle = [[UIApplication sharedApplication] statusBarStyle];
}

- (void)restoreStatusBarStyle
{
	[[UIApplication sharedApplication] setStatusBarStyle:formerStatusBarStyle animated:NO];
}

#pragma mark Activate

- (void)didFinishActivate:(NSString *)animationID finished:(NSNumber *)finished context:(PSWSnapshotView *)context
{
	NSLog(@"didFinishActivate finished:%@", finished);
	if([finished boolValue]) {
		isAnimating = NO;		
	}
}

- (void)activateWithAnimation:(BOOL)animated
{
	// Always reparent view
	[self reparentView];
	
	// Don't double-activate
	if (isActive)
		return;

	NSLog(@"activateWithAnimation:%d", animated);
		
	// Deactivate CategoriesSB
	if ([CHSharedInstance(SBUIController) respondsToSelector:@selector(categoriesSBCloseAll)])
		[CHSharedInstance(SBUIController) categoriesSBCloseAll];
	
	// Deactivate Keyboard
	[[CHSharedInstance(SBUIController) window] endEditing:YES];
	
	// Setup status bar
	[self saveStatusBarStyle];
	[[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault animated:NO];
	
	// Load View (must be done before we access snapshotPageView)
	UIView *view = [self view];
	
	// Restore focused application
	[snapshotPageView setFocusedApplication:focusedApplication];
	
	CALayer *scrollLayer = [snapshotPageView.scrollView layer];
	if (animated) {
		view.alpha = 0.0f;
		[scrollLayer setTransform:CATransform3DMakeScale(2.0f, 2.0f, 1.0f)];
			
		[UIView beginAnimations:nil context:nil];
		[UIView setAnimationDuration:0.5f];
	}
	
	// Apply preferences
	if (GetPreference(PSWShowPageControl, BOOL))
		[CHSharedInstance(SBIconController) setPageControlVisible:NO];
	[self _applyPreferences];
	
	// Show ProSwitcher
	[scrollLayer setTransform:CATransform3DIdentity];
	view.alpha = 1.0f;
	isActive = YES;
			
	if (animated) {
		isAnimating = YES;
		[UIView setAnimationDelegate:self];
		[UIView setAnimationDidStopSelector:@selector(didFinishActivate:finished:context:)];
		[UIView commitAnimations];
	} else {
		isAnimating = NO;
		//[self performSelector:@selector(doneZoomy) withObject:nil afterDelay:3.0f];
	}
}

#pragma mark Deactivate

- (void)didFinishDeactivate
{
	[[self view] removeFromSuperview];
	isAnimating = NO;
}
- (void)deactivateWithAnimation:(BOOL)animated
{
	// Don't deactivate if we are already deactivated
	if (!isActive)
		return;

	// Save focused applciation
	[focusedApplication release];
	focusedApplication = [snapshotPageView.focusedApplication retain];
		
	CALayer *scrollLayer = [snapshotPageView.scrollView layer];
	[scrollLayer setTransform:CATransform3DIdentity];
		
	if (animated) {
		// Animate deactivation
		[UIView beginAnimations:nil context:nil];
		[UIView setAnimationDuration:0.5f];
		[scrollLayer setTransform:CATransform3DMakeScale(2.0f, 2.0f, 1.0f)];
	}
			
	// Show SpringBoard's page control
	if (GetPreference(PSWShowPageControl, BOOL))
		[CHSharedInstance(SBIconController) setPageControlVisible:YES];
			
	// Hide ProSwitcher
	isActive = NO;
			
	if (animated) {
		self.view.alpha = 0.0f;
		isAnimating = YES;
		[UIView setAnimationDelegate:self];
		[UIView setAnimationDidStopSelector:@selector(didFinishDeactivate)];
		[UIView commitAnimations];
	} else {
		[self didFinishDeactivate];
	}

	
}

- (void)setActive:(BOOL)active animated:(BOOL)animated
{
	NSLog(@"setActive:%d animated:%d", active, animated);
	if (active)
		[self activateWithAnimation:animated];
	else
		[self deactivateWithAnimation:animated];
}

- (void)setActive:(BOOL)active
{
	[self setActive:active animated:GetPreference(PSWAnimateActive, BOOL)];
}

#pragma mark libactivator delegate

- (void)activator:(LAActivator *)activator receiveEvent:(LAEvent *)event
{
	if ([[CHClass(SBAwayController) sharedAwayController] isLocked] || [self isAnimating])
		return;
	
	if (SBActive) {
		// SpringBoard is active, just activate
		BOOL newActive = ![self isActive];
		[self setActive:newActive];
		if (newActive)
			[event setHandled:YES];
	} else {
		SBApplication *application = [SBWActiveDisplayStack topApplication];
		NSString *displayIdentifier = [application displayIdentifier];
		// Top application will be nil when app is loading; do nothing
		if ([displayIdentifier length]) {
			PSWApplication *activeApp = [[PSWApplicationController sharedInstance] applicationWithDisplayIdentifier:displayIdentifier];
			[self setActive:YES animated:NO];
			
			modifyZoomTransformCountDown = 2;
			ignoreZoomSetAlphaCountDown = 2;
			disallowIconListScatter++;
			
			// Background
			if (![activeApp hasNativeBackgrounding]) {
				if ([SBSharedInstance respondsToSelector:@selector(setBackgroundingEnabled:forDisplayIdentifier:)])
					[SBSharedInstance setBackgroundingEnabled:YES forDisplayIdentifier:displayIdentifier];
			}
			
			// Deactivate
			[[activeApp application] setDeactivationSetting:0x2 flag:YES]; // animate
			//[activeApp setDeactivationSetting:0x8 value:[NSNumber numberWithDouble:1]]; // disable animations
			[SBWActiveDisplayStack popDisplay:application];
			[SBWSuspendingDisplayStack pushDisplay:application];
			
			// Show ProSwitcher
			[self reparentView];
			[snapshotPageView setFocusedApplication:activeApp animated:NO];
			[event setHandled:YES];
			
			disallowIconListScatter--;
		}
	}
}

- (void)activator:(LAActivator *)activator abortEvent:(LAEvent *)event
{
	[self setActive:NO animated:NO];
}

#pragma mark PSWSnapshotPageView delegate

- (void)snapshotPageView:(PSWSnapshotPageView *)sspv didSelectApplication:(PSWApplication *)app
{
	disallowIconListScatter++;
	modifyZoomTransformCountDown = 1;
	ignoreZoomSetAlphaCountDown = 1;
	[app activateWithAnimation:YES];
	disallowIconListScatter--;
}

- (void)snapshotPageView:(PSWSnapshotPageView *)sspv didCloseApplication:(PSWApplication *)app
{
	disallowRestoreIconList++;
	[app exit];
	[self reparentView]; // Fix layout
	[snapshotPageView removeViewForApplication:app];
	disallowRestoreIconList--;
}

- (void)snapshotPageViewShouldExit:(PSWSnapshotPageView *)sspv
{
	[self setActive:NO];
}

- (void)_deactivateFromAppActivate
{
	[self setActive:NO animated:NO];
}

- (void)refreshSafety
{
	for(PSWSnapshotView *view in snapshotPageView.snapshotViews) {
		[view reloadSnapshotIfNecessary];
	}
}

- (void)refreshSafetySoon
{
	[self performSelector:@selector(refreshSafety) withObject:nil afterDelay:1.0f]; // wtf
}

@end

#pragma mark Preference Changed Notification
static void PreferenceChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
	[[PSWViewController sharedInstance] _reloadPreferences];
}

#pragma mark SBUIController
CHMethod3(void, SBUIController, animateApplicationActivation, SBApplication *, application, animateDefaultImage, BOOL, animateDefaultImage, scatterIcons, BOOL, scatterIcons)
{
	CHSuper3(SBUIController, animateApplicationActivation, application, animateDefaultImage, animateDefaultImage, scatterIcons, scatterIcons && !disallowIconListScatter);
}

CHMethod1(void, SBUIController, restoreIconList, BOOL, animated)
{
	if (disallowRestoreIconList == 0)
		CHSuper1(SBUIController, restoreIconList, animated && disallowIconListScatter == 0);
}

CHMethod0(void, SBUIController, finishLaunching)
{
	NSMutableDictionary* plistDict = [[NSMutableDictionary alloc] initWithContentsOfFile:PSWPreferencesFilePath];
	
	BOOL value = [[plistDict objectForKey:@"PSWAlert"] boolValue];
	if (!value) {
		UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Welcome to ProSwitcher" message:@"To change settings or to setup launching in *any* app, go to the Settings app. Otherwise, tap the ProSwitcher icon to activate.\n\nProSwitcher is (c) 2009 Ryan Petrich and Grant Paul, released under the LGPL." delegate:nil cancelButtonTitle:nil otherButtonTitles:@"Continue", nil] autorelease];
		[alert show];
		[plistDict setObject:[NSNumber numberWithBool:YES] forKey:@"PSWAlert"];
		PSWWriteBinaryPropertyList(plistDict, PSWPreferencesFilePath);
	}
	[plistDict release];
	
	CHSuper0(SBUIController, finishLaunching);
}

#pragma mark SBDisplayStack
CHMethod1(void, SBDisplayStack, pushDisplay, SBDisplay *, display)
{
	if (self == SBWSuspendingDisplayStack && GetPreference(PSWBecomeHomeScreen, BOOL)) {
		if (CHIsClass(display, SBApplication)) {
			SBApplication *application = (SBApplication *)display;
			PSWApplication *suspendingApp = [[PSWApplicationController sharedInstance] applicationWithDisplayIdentifier:[application displayIdentifier]];
			if (suspendingApp) {
				modifyZoomTransformCountDown = 2;
				ignoreZoomSetAlphaCountDown = 2;
				disallowIconListScatter++;
				CHSuper1(SBDisplayStack, pushDisplay, display);
				PSWViewController *vc = [PSWViewController sharedInstance];
				[vc setActive:YES animated:NO];
				[[vc snapshotPageView] setFocusedApplication:suspendingApp animated:NO];
				disallowIconListScatter--;
				return;
			}
		}
	} else if (self == SBWPreActivateDisplayStack) {
		NSLog(@"WHY HELLO THERE %@ (%d) (%@)", display, CHIsClass(display, SBApplication), CHClass(SBApplication));
		if (CHIsClass(display, SBApplication)) {
			[[PSWViewController sharedInstance] performSelector:@selector(_deactivateFromAppActivate) withObject:nil afterDelay:0.5f];
		}
	}
	CHSuper1(SBDisplayStack, pushDisplay, display);
}

#pragma mark SpringBoard
CHMethod0(void, SpringBoard, _handleMenuButtonEvent)
{
	PSWViewController *vc = [PSWViewController sharedInstance];
	if ([vc isActive]) {
		// Deactivate and suppress SpringBoard list scrolling
		[vc setActive:NO];
		
		disallowIconListScroll++;
		CHSuper0(SpringBoard, _handleMenuButtonEvent);
		disallowIconListScroll--;
		
		return;
	}
	
	CHSuper0(SpringBoard, _handleMenuButtonEvent);
}

#pragma mark SBIconController
CHMethod2(void, SBIconController, scrollToIconListAtIndex, NSInteger, index, animate, BOOL, animate)
{
	if (disallowIconListScroll == 0)
		CHSuper2(SBIconController, scrollToIconListAtIndex, index, animate, animate);
}

CHMethod1(void, SBIconController, setIsEditing, BOOL, isEditing)
{
	// Disable ProSwitcher when editing
	if (isEditing)
		[[PSWViewController sharedInstance] setActive:NO];
	
	CHSuper1(SBIconController, setIsEditing, isEditing);
}

#pragma mark SBZoomView
__attribute__((always_inline))
static CGAffineTransform TransformRectToRect(CGRect sourceRect, CGRect targetRect)
{
	return CGAffineTransformScale(
		CGAffineTransformMakeTranslation(
			targetRect.origin.x - sourceRect.origin.x + (targetRect.size.width - sourceRect.size.width) / 2,
			targetRect.origin.y - sourceRect.origin.y + (targetRect.size.height - sourceRect.size.height) / 2),
		targetRect.size.width / sourceRect.size.width,
		targetRect.size.height / sourceRect.size.height);
}

CHMethod1(void, SBZoomView, setTransform, CGAffineTransform, transform)
{
	switch (modifyZoomTransformCountDown) {
		case 1: {
			modifyZoomTransformCountDown = 0;
			PSWViewController *vc = [PSWViewController sharedInstance];
			PSWSnapshotView *ssv = [[vc snapshotPageView] focusedSnapshotView];
			UIView *screenView = [ssv screenView];
			CGRect translatedDestRect = [screenView convertRect:[screenView bounds] toView:[vc view]];
			CHSuper1(SBZoomView, setTransform, TransformRectToRect([self frame], translatedDestRect));
			break;
		}
		case 0:
			CHSuper1(SBZoomView, setTransform, transform);
			break;
		default:
			modifyZoomTransformCountDown--;
			CHSuper1(SBZoomView, setTransform, transform);
			break;
	}
}

/*CHMethod1(void, SBZoomView, setAlpha, CGFloat, alpha)
{
	if (ignoreZoomSetAlphaCountDown)
		ignoreZoomSetAlphaCountDown--;
	else
		CHSuper1(SBZoomView, setAlpha, alpha);
}*/

#pragma mark SBStatusBar

CHMethod0(CGAffineTransform, SBStatusBar, distantStatusWindowTransform)
{
	if (disallowIconListScatter)
		return CGAffineTransformMakeTranslation(0.0f, -[self frame].size.height);
	else
		return CHSuper0(SBStatusBar, distantStatusWindowTransform);
}

#pragma mark SBSearchView

CHMethod2(void, SBSearchView, setShowsKeyboard, BOOL, visible, animated, BOOL, animated)
{
	// Disable search view's keyboard when ProSwitcher is active
	CHSuper2(SBSearchView, setShowsKeyboard, visible && ![[PSWViewController sharedInstance] isActive], animated, animated);
}

#pragma mark SBVoiceControlAlert

CHMethod0(void, SBVoiceControlAlert, deactivate)
{
	CHSuper0(SBVoiceControlAlert, deactivate);
	
	// Fix display when coming back from VoiceControl
	PSWViewController *vc = [PSWViewController sharedInstance];
	if ([vc isActive])
		[vc setActive:NO animated:NO];
}

CHConstructor
{
	CHAutoreleasePoolForScope();
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, PreferenceChangedCallback, CFSTR(PSWPreferencesChangedNotification), NULL, CFNotificationSuspensionBehaviorCoalesce);
	CHLoadLateClass(SBAwayController);
	CHLoadLateClass(SBStatusBarController);
	CHLoadLateClass(SBIconListPageControl);
	CHLoadLateClass(SBUIController);
	CHHook1(SBUIController, restoreIconList);
	CHHook3(SBUIController, animateApplicationActivation, animateDefaultImage, scatterIcons);
	CHHook0(SBUIController, finishLaunching);
	CHLoadLateClass(SBApplicationController);
	CHLoadLateClass(SBIconModel);
	CHLoadLateClass(SBDisplayStack);
	CHHook1(SBDisplayStack, pushDisplay);
	CHLoadLateClass(SpringBoard);
	CHHook0(SpringBoard, _handleMenuButtonEvent);
	CHLoadLateClass(SBIconController);
	CHHook2(SBIconController, scrollToIconListAtIndex, animate);
	CHHook1(SBIconController, setIsEditing);
	CHLoadLateClass(SBZoomView);
	CHHook1(SBZoomView, setTransform);
	//CHHook1(SBZoomView, setAlpha);
	CHLoadLateClass(SBStatusBar);
	CHHook0(SBStatusBar, distantStatusWindowTransform);
	CHLoadLateClass(SBSearchView);
	CHHook2(SBSearchView, setShowsKeyboard, animated);
	CHLoadLateClass(SBVoiceControlAlert);
	CHHook0(SBVoiceControlAlert, deactivate);
	CHLoadLateClass(SBApplication);
	
	// Using late-binding until we get a simulator build for libactivator :(
	dlopen("/usr/lib/libactivator.dylib", RTLD_LAZY);
	CHLoadLateClass(LAActivator);
	[CHSharedInstance(LAActivator) registerListener:[PSWViewController sharedInstance] forName:@"com.collab.proswitcher"];
}
