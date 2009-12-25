#import "PSWApplication.h"

#include <unistd.h>

#import <SpringBoard/SpringBoard.h>
#import <SpringBoard/SBApplication.h>
#import <SpringBoard/SBIconModel.h>
#import <SpringBoard/SBUIController.h>
#import <QuartzCore/QuartzCore.h>
#import <CaptainHook/CaptainHook.h>
#import "SpringBoard+Backgrounder.h"
#import <QuartzCore/CAAnimation.h>

#import "PSWDisplayStacks.h"
#import "PSWApplicationController.h"
#import "PSWResources.h"
#import "PSWAppContextHostView.h"

@interface UIWindow (PrivateStuff)
+ (void *)createIOSurfaceWithContextId:(unsigned)contextId frame:(CGRect)frame;
+(void*)createIOSurfaceWithContextIds:(const unsigned*)contextIds count:(unsigned)count frame:(CGRect)frame;
@end

CHDeclareClass(SBApplicationController);
CHDeclareClass(SBApplicationIcon);
CHDeclareClass(SBIconModel);
CHDeclareClass(SBApplication);
CHDeclareClass(SBUIController);

static NSString *ignoredRelaunchDisplayIdentifier;
static NSUInteger defaultImagePassThrough;

@interface CALayerHost : CALayer {
}
@property(assign) unsigned contextId;
@end

@class CAWindowServer;
@class CAContext;

@implementation PSWApplication

@synthesize displayIdentifier = _displayIdentifier;
@synthesize application = _application;
@synthesize delegate = _delegate;

+ (NSString *)snapshotPath
{
	return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/"];
}

+ (void)clearSnapshotCache
{
	NSString *snapshotPath = [self snapshotPath];
	NSFileManager *fileManager = [NSFileManager defaultManager];
	for (NSString *path in [fileManager contentsOfDirectoryAtPath:snapshotPath error:NULL])
		if ([snapshotPath hasPrefix:@"ProSwitcher-"] && [snapshotPath hasSuffix:@".cache"])
			unlink([[snapshotPath stringByAppendingPathComponent:snapshotPath] UTF8String]);
}

- (id)initWithDisplayIdentifier:(NSString *)displayIdentifier
{
	if ((self = [super init])) {
		_application = [[CHSharedInstance(SBApplicationController) applicationWithDisplayIdentifier:displayIdentifier] retain];
		_displayIdentifier = [displayIdentifier copy];
		_surface = NULL;
	}
	return self;
}

- (id)initWithSBApplication:(SBApplication *)application
{
	if ((self = [super init])) {
		_application = [application retain];
		_displayIdentifier = [[application displayIdentifier] copy];
		_surface = NULL;		
	}
	return self;
}

- (void)dealloc
{
	[_displayIdentifier release];
#ifdef USE_IOSURFACE
	CGImageRelease(_snapshotImage);
	if (_surface) {
		CFRelease(_surface);
		_surface = NULL;
	}
	if (_snapshotFilePath) {
		unlink([_snapshotFilePath UTF8String]);
		[_snapshotFilePath release];
	}
#endif
	[super dealloc];
}

- (NSString *)displayName
{
	return [_application displayName];
}

- (CGImageRef)snapshot
{	
	NSLog(@"I (%@) asked for snapshotImage and it is %x (surface is %x)", [self displayName], _snapshotImage, _surface);
#ifdef USE_IOSURFACE
	if (_snapshotImage)
		return _snapshotImage;
#endif
	defaultImagePassThrough++;
	CGImageRef result = [[_application defaultImage:NULL] CGImage];
	defaultImagePassThrough--;
	return result;
}
extern void lsfl();
#ifdef USE_IOSURFACE
- (void)loadSnapshotFromLayer:(CALayer *)layer	
{
	
	[CATransaction begin];
	[CATransaction setValue:(id)kCFBooleanTrue
				     forKey:kCATransactionDisableActions];
	[layer retain];
	[layer removeFromSuperlayer];
	layer.affineTransform = CGAffineTransformIdentity;
	layer.frame = CGRectMake(0, 0, 320, 480);
	[((UIView *)[CHSharedInstance(SBUIController) contentView]).layer addSublayer:layer];
	[layer setValue:@"TVOut" forKey:@"displayName"];	
	CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
	const CGFloat myColor[] = {0.90625, 0.80, 0.80, 1.0};
	[layer setBackgroundColor:CGColorCreate(rgb, myColor)];
	CGColorSpaceRelease(rgb);
	NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithObject:@"TVOut" forKey:@"displayName"];
    [dict setObject:[NSNumber numberWithInt:8] forKey:@"bitsPerComponentHint"];	
	CAContext *tvBackgroundContext = [[CAContext localContextWithOptions:dict] retain];
	[tvBackgroundContext setLevel:5];
	CALayer *tvBackgroundLayer = [[CALayer layer] retain];
	
	[tvBackgroundContext setLayer:tvBackgroundLayer];
	[tvBackgroundLayer addSublayer:layer];

	//[layer release];
	[CATransaction commit];
	[CATransaction flush];
	
	IOSurfaceRef surf = IOSurfaceCreate([UIWindow _ioSurfacePropertyDictionaryForRect:CGRectMake(0, 0, 320, 480)]);
	NSLog(@"surf=%x", surf);
	CARenderServerRenderDisplay(0, @"TVOut", surf, 0, 0);
	[self loadSnapshotFromSurface:surf cropInsets:_cropInsets];
	CFRelease(surf);

	// Do not remove this part!
	[layer setHidden:YES];
	[layer setValue:@"LCD" forKey:@"displayName"];	
	
	[layer removeFromSuperlayer];
	[tvBackgroundContext release];
	[tvBackgroundLayer release];
	NSLog(@"!");	
	[layer release];
	
}

- (void)loadSnapshotFromSurface:(IOSurfaceRef)surface cropInsets:(PSWCropInsets)cropInsets
{
	NSLog(@"(%@) loadsnapshotFromSurface %x", [self displayName], surface);
	if (surface) {//surface != _surface) {
		if (_surface && _surface != surface)
			CFRelease(_surface);
		if (_snapshotFilePath) {
			unlink([_snapshotFilePath UTF8String]);
			[_snapshotFilePath release];
			_snapshotFilePath = nil;
		}
		if (surface) {
			IOSurfaceLock(surface, kIOSurfaceLockReadOnly, NULL);
			int width = IOSurfaceGetWidth(surface) - cropInsets.left - cropInsets.right;
			int height = IOSurfaceGetHeight(surface) - cropInsets.top - cropInsets.bottom;
			if (width > 0 && height > 0) {
				if(_snapshotImage) CGImageRelease(_snapshotImage);
				NSLog(@"Updating snapshot from surface %x (seed=%x)", surface, IOSurfaceGetSeed(surface));
				uint8_t *baseAddress = IOSurfaceGetBaseAddress(surface);
				size_t stride = IOSurfaceGetBytesPerRow(surface);
				baseAddress += cropInsets.left * 4 + stride * cropInsets.top;
				CGDataProviderRef dataProvider = CGDataProviderCreateWithData(NULL, baseAddress, stride * (height - 1) + width * 4, NULL);
				CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
				_snapshotImage = CGImageCreate(width, height, 8, 32, stride, colorSpace, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little, dataProvider, NULL, false, kCGRenderingIntentDefault);
				CGColorSpaceRelease(colorSpace);
				CGDataProviderRelease(dataProvider);
				if(_surface != surface) {
					CFRetain(surface);
					_surface = surface;
				}
				_cropInsets = cropInsets;				
				IOSurfaceUnlock(surface, kIOSurfaceLockReadOnly, NULL);				
			} else {
				_snapshotImage = NULL;
				_surface = NULL;
			}
		} else {
			_snapshotImage = NULL;
			_surface = NULL;
		}
		if ([_delegate respondsToSelector:@selector(applicationSnapshotDidChange:)])
			[_delegate applicationSnapshotDidChange:self];
	}
}

- (void)loadSnapshotFromSurface:(IOSurfaceRef)surface
{
	PSWCropInsets insets;
	insets.top = 0;
	insets.left = 0;
	insets.bottom = 0;
	insets.right = 0;
	[self loadSnapshotFromSurface:surface cropInsets:insets];
}

#endif

- (unsigned int)contextId
{
	return sceneContextId([_application contextHostView]);
}

- (CALayer *)liveLayer
{
#ifdef USE_IOSURFACE
	if(!_application) return nil;
	unsigned int contextId = [self contextId];
	if(contextId != UINT_MAX) {
		//[_application
		CALayerHost *layerHost = [[CALayerHost alloc] init];
		NSLog(@"My new layerhost is %@", layerHost);
		layerHost.hidden = YES;
		layerHost.frame = [[UIScreen mainScreen] bounds];
		layerHost.contextId = contextId;
		layerHost.hidden = NO;
		//[layerHost autorelease];
		return layerHost;
	}
#endif
	return nil;
}


- (BOOL)writeSnapshotToDisk
{
#ifdef USE_IOSURFACE
	if (_snapshotFilePath || !_surface)
		return NO;
	// Release image
	CGImageRelease(_snapshotImage);
	[_snapshotUIImage release];
	// Generate filename
	CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
	CFStringRef uuidString = CFUUIDCreateString(kCFAllocatorDefault, uuid);
	CFRelease(uuid);
	NSString *fileName = [NSString stringWithFormat:@"ProSwitcher-%@.cache", uuidString];
	CFRelease(uuidString);
	_snapshotFilePath = [[[PSWApplication snapshotPath] stringByAppendingPathComponent:fileName] retain];
	// Write to file
	int width = IOSurfaceGetWidth(_surface) - _cropInsets.left - _cropInsets.right;
	int height = IOSurfaceGetHeight(_surface) - _cropInsets.top - _cropInsets.bottom;
	uint8_t *baseAddress = IOSurfaceGetBaseAddress(_surface);
	size_t stride = IOSurfaceGetBytesPerRow(_surface);
	baseAddress += _cropInsets.left * 4 + stride * _cropInsets.top;
	NSData *tempData = [[NSData alloc] initWithBytesNoCopy:baseAddress length:stride * (height - 1) + width * 4 freeWhenDone:NO];
	[tempData writeToFile:_snapshotFilePath atomically:NO];
	[tempData release];
	// Read back into mapped data
	NSData *mappedData = [[NSData alloc] initWithContentsOfMappedFile:_snapshotFilePath];
	CGDataProviderRef dataProvider = CGDataProviderCreateWithCFData((CFDataRef)mappedData);
	[mappedData release];
	// Create Image
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	_snapshotImage = CGImageCreate(width, height, 8, 32, stride, colorSpace, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little, dataProvider, NULL, false, kCGRenderingIntentDefault);
	CGColorSpaceRelease(colorSpace);
	// Release Surface
	CFRelease(_surface);
	_surface = NULL;
	// Notify delegate
	if ([_delegate respondsToSelector:@selector(applicationSnapshotDidChange:)])
		[_delegate applicationSnapshotDidChange:self];
	return YES;
#else
	return NO;
#endif
}

- (SBApplicationIcon *)springBoardIcon
{
	return (SBApplicationIcon *)[CHSharedInstance(SBIconModel) iconForDisplayIdentifier:_displayIdentifier];
}

- (UIImage *)themedIcon
{
	return [[self springBoardIcon] icon];
}

- (UIImage *)unthemedIcon
{
	return [[self springBoardIcon] smallIcon];
}

- (BOOL)hasNativeBackgrounding
{
	return [_displayIdentifier isEqualToString:@"com.apple.mobilephone"]
		|| [_displayIdentifier isEqualToString:@"com.apple.mobilemail"]
		|| [_displayIdentifier isEqualToString:@"com.apple.mobilesafari"]
		|| [_displayIdentifier hasPrefix:@"com.apple.mobileipod"]
		|| [_displayIdentifier hasPrefix:@"com.bigboss.categories."]
		|| [_displayIdentifier isEqualToString:@"com.googlecode.mobileterminal"];
}

- (void)exit
{
	if ([self hasNativeBackgrounding]) {
		[ignoredRelaunchDisplayIdentifier release];
		ignoredRelaunchDisplayIdentifier = [_displayIdentifier retain];
		[_application kill];
	} else {
		UIApplication *sharedApp = [UIApplication sharedApplication];
		if ([sharedApp respondsToSelector:@selector(setBackgroundingEnabled:forDisplayIdentifier:)])
			[sharedApp setBackgroundingEnabled:NO forDisplayIdentifier:_displayIdentifier];
		if ([SBWActiveDisplayStack containsDisplay:_application]) {
			[_application setDeactivationSetting:0x2 flag:YES]; // animate
			[SBWActiveDisplayStack popDisplay:_application];
		} else {
			[_application setDeactivationSetting:0x2 flag:NO]; // don't animate
		}
		// Deactivate the application
		[_application setActivationSetting:0x2 flag:NO]; // don't animate
		[SBWSuspendingDisplayStack pushDisplay:_application];
	}	
}

- (void)activateWithAnimation:(BOOL)animated
{
	SBApplication *fromApp = [SBWActiveDisplayStack topApplication];
	NSString *fromIdent = fromApp ? [fromApp displayIdentifier] : @"com.apple.springboard";
	if (![fromIdent isEqualToString:_displayIdentifier]) {
		// App to switch to is not the current app
		// NOTE: Save the identifier for later use
		//deactivatingApp = [fromIdent copy];
		
		if ([fromIdent isEqualToString:@"com.apple.springboard"]) {
			// Switching from SpringBoard; simply activate the target app
			[_application setDisplaySetting:0x4 flag:animated]; // animate (or not)
			// Activate the target application
			[SBWPreActivateDisplayStack pushDisplay:_application];
		} else {
			// Switching from another app
			if (![_displayIdentifier isEqualToString:@"com.apple.springboard"]) {
				// Switching to another app; setup app-to-app
				[_application setActivationSetting:0x40 flag:YES]; // animateOthersSuspension
				[_application setActivationSetting:0x20000 flag:YES]; // appToApp
				[_application setDisplaySetting:0x4 flag:animated]; // animate
				
				// Activate the target application (will wait for
				// deactivation of current app)
				[SBWPreActivateDisplayStack pushDisplay:_application];
			}
			
			// Deactivate the current application
			
			// If Backgrounder is installed, enable backgrounding for current application
			UIApplication *sharedApp = [UIApplication sharedApplication];
			if ([sharedApp respondsToSelector:@selector(setBackgroundingEnabled:forDisplayIdentifier:)])
				[sharedApp setBackgroundingEnabled:YES forDisplayIdentifier:fromIdent];
			
			// NOTE: Must set animation flag for deactivation, otherwise
			// application window does not disappear (reason yet unknown)
			[fromApp setDeactivationSetting:0x2 flag:YES]; // animate
			
			// Deactivate by moving from active stack to suspending stack
			[SBWActiveDisplayStack popDisplay:fromApp];
			[SBWSuspendingDisplayStack pushDisplay:fromApp];
		}
	}
}

- (void)activate
{
	[self activateWithAnimation:NO];
}

- (void)_badgeDidChange
{
	if ([_delegate respondsToSelector:@selector(applicationBadgeDidChange:)])
		[_delegate applicationBadgeDidChange:self];
}

- (SBIconBadge *)badgeView
{
	SBIcon *icon = [self springBoardIcon];
	return (icon)?CHIvar(icon, _badge, SBIconBadge *):nil;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%s %p %@>", class_getName([self class]), self, _displayIdentifier];
}

@end

#pragma mark SBApplication

CHMethod1(void, SBApplication, _relaunchAfterAbnormalExit, BOOL, something)
{
	// Method for 3.0.x
	if ([[self displayIdentifier] isEqualToString:ignoredRelaunchDisplayIdentifier]) {
		[ignoredRelaunchDisplayIdentifier release];
		ignoredRelaunchDisplayIdentifier = nil;
	} else {
		CHSuper1(SBApplication, _relaunchAfterAbnormalExit, something);
	}
}

CHMethod0(void, SBApplication, _relaunchAfterExit)
{
	// Method for 3.1.x
	if ([[self displayIdentifier] isEqualToString:ignoredRelaunchDisplayIdentifier]) {
		[ignoredRelaunchDisplayIdentifier release];
		ignoredRelaunchDisplayIdentifier = nil;
	} else {
		CHSuper0(SBApplication, _relaunchAfterExit);
	}
}

CHMethod1(UIImage *, SBApplication, defaultImage, BOOL *, something)
{
	if (defaultImagePassThrough == 0) {
		PSWApplication *app = [[PSWApplicationController sharedInstance] applicationWithDisplayIdentifier:[self displayIdentifier]];
		if (![app hasNativeBackgrounding] ||
			[app.displayIdentifier isEqualToString:@"com.apple.mobilemail"] ||
			[app.displayIdentifier isEqualToString:@"com.apple.mobilesafari"]) {
			CGImageRef cgResult = [app snapshot];
			if (cgResult) {
				if (something)
					*something = YES;
				return [UIImage imageWithCGImage:cgResult];
			}
		}
	}
	return CHSuper1(SBApplication, defaultImage, something);
}

#pragma mark SBApplicationIcon

CHMethod1(void, SBApplicationIcon, setBadge, id, value)
{
	CHSuper1(SBApplicationIcon, setBadge, value);
	PSWApplication *app = [[PSWApplicationController sharedInstance] applicationWithDisplayIdentifier:[self displayIdentifier]];
	[app _badgeDidChange];
}

CHConstructor {
	CHAutoreleasePoolForScope();
	CHLoadLateClass(SBApplicationController);
	CHLoadLateClass(SBApplicationIcon);
	CHLoadLateClass(SBIconModel);
	CHLoadLateClass(SBApplication);
	CHLoadLateClass(SBUIController);
	CHHook1(SBApplication, _relaunchAfterAbnormalExit);
	CHHook0(SBApplication, _relaunchAfterExit);
	CHHook1(SBApplication, defaultImage);
}

