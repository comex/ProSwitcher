#import "PSWApplication.h"

#include <unistd.h>

#import <SpringBoard/SpringBoard.h>
#import <QuartzCore/QuartzCore.h>
#import <CaptainHook/CaptainHook.h>
#import "SpringBoard+Backgrounder.h"

#import "PSWSpringBoardApplication.h"
#import "PSWResources.h"
#import "PSWDisplayStacks.h"
#import "PSWApplicationController.h"
#import "PSWViewController.h"

CHDeclareClass(SpringBoard);
CHDeclareClass(SBUIController);

static CGImageRef springBoardSnapshot = nil;
static PSWSpringBoardApplication *sharedSpringBoardApplication = nil;

@implementation PSWSpringBoardApplication
@synthesize displayName = _displayName;

+ (id)sharedInstance
{
	if (!sharedSpringBoardApplication)
		sharedSpringBoardApplication = [[self alloc] init];
	return sharedSpringBoardApplication;
}

- (id)init
{
	return [super initWithDisplayIdentifier:@"com.apple.springboard"];
}

- (CGImageRef)snapshot
{	
	return springBoardSnapshot;
}

- (BOOL)writeSnapshotToDisk
{
	return NO;
}

- (SBApplicationIcon *)springBoardIcon
{
	return nil;
}

- (UIImage *)themedIcon
{
	return PSWImage(@"springboard");
}

- (UIImage *)unthemedIcon
{
	return [self themedIcon];
}

- (BOOL)hasNativeBackgrounding
{
	return YES;
}

- (void)exit
{
	[(SpringBoard *)[UIApplication sharedApplication] relaunchSpringBoard];
}

- (void)activateWithAnimation:(BOOL)animated
{
	[[PSWViewController sharedInstance] setActive:NO animated:animated];
}

- (SBIconBadge *)badgeView
{
	return nil;
}

- (NSString *)displayName
{
	return @"SpringBoard";
}

@end

#pragma mark SBUIController
CHMethod0(void, SBUIController, finishLaunching)
{
	UIView *sbView = [self contentView];
	CGRect bounds = sbView.bounds;
	bounds.size.height -= 22.0f;
	UIGraphicsBeginImageContext(bounds.size);
	[[UIColor blackColor] set];
	UIRectFill(bounds);
	CGContextRef c = UIGraphicsGetCurrentContext();
	CGContextTranslateCTM(c, 0.0f, -22.0f);
	[sbView.layer renderInContext:c];
	UIImage *viewImage = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	springBoardSnapshot = CGImageRetain([viewImage CGImage]);
	
	CHSuper0(SBUIController, finishLaunching);
}

CHConstructor {
	CHLoadLateClass(SpringBoard);
	CHLoadLateClass(SBUIController);
	CHHook0(SBUIController, finishLaunching);
}

