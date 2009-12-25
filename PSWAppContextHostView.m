//
//  PSWAppContextHostView.m
//  ProSwitcher
//
//  Created by Nicholas Allegra on 12/23/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "PSWAppContextHostView.h"
#import <SpringBoard/SBAppContextHostView.h>
#import "PSWViewController.h"

NSMutableSet *safeIds;

static void setUnsafe(SBAppContextHostView *view)
{
	unsigned int contextId = sceneContextId(view);
	[safeIds removeObject:[NSNumber numberWithUnsignedInt:contextId]];
	[[PSWViewController sharedInstance] refreshSafety];	
}

static void setSafe(SBAppContextHostView *view)
{
	unsigned int contextId = sceneContextId(view);
	[safeIds addObject:[NSNumber numberWithUnsignedInt:contextId]];
	[[PSWViewController sharedInstance] refreshSafetySoon];	
}

CHDeclareClass(SBAppContextHostView);

CHMethod1(void, SBAppContextHostView, setHidden, BOOL, hidden)
{	
	NSLog(@"sethidden ==> %d", hidden);
	if(!hidden) {
		setUnsafe(self);
	}
	CHSuper1(SBAppContextHostView, setHidden, hidden);
	if(hidden) {
		setSafe(self);
	}
	NSLog(@"I am %@", self);
}

CHMethod1(void, SBAppContextHostView, setHostingEnabled, BOOL, hostingEnabled)
{
	NSLog(@"sethostingenabled ==> %d", hostingEnabled);
	setUnsafe(self);
/*	if(hostingEnabled) {
		setUnsafe(self);
	}*/
	CHSuper1(SBAppContextHostView, setHostingEnabled, hostingEnabled);
/*	if(!hostingEnabled) {
		setSafe(self);
	}*/
}

CHConstructor {
	safeIds = [[NSMutableSet alloc] init];
	CHLoadLateClass(SBAppContextHostView);
	CHHook1(SBAppContextHostView, setHidden);
	CHHook1(SBAppContextHostView, setHostingEnabled);
}

BOOL sceneIsSafe(unsigned int contextId)
{
	if(contextId == UINT_MAX) {
		return NO;
	}
	return [safeIds containsObject:[NSNumber numberWithUnsignedInt:contextId]];
}

unsigned int sceneContextId(SBAppContextHostView *contextHostView)
{
	if(!contextHostView) return UINT_MAX;
	NSMutableArray *contexts = (NSMutableArray *) *(((int *) contextHostView) + 36/4);
	if(contexts.count > 0) {
		return [[contexts objectAtIndex:0] contextId];
	}
	return UINT_MAX;
}