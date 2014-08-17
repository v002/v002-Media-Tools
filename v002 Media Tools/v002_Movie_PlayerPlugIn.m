//
//  v002_Media_ToolsPlugIn.m
//  v002 Media Tools
//
//  Created by vade on 7/15/12.
//  Copyright (c) 2012 v002. All rights reserved.
//

// It's highly recommended to use CGL macros instead of changing the current context for plug-ins that perform OpenGL rendering
#import <OpenGL/CGLMacro.h>
#import "v002CVPixelBufferImageProvider.h"
#import "v002_Movie_PlayerPlugIn.h"

#define	kQCPlugIn_Name				@"v002 Movie Player 3.0"
#define	kQCPlugIn_Description		@"AVFoundation based movie player - supports only Pro Res and h.264"

@implementation v002_Movie_PlayerPlugIn

@synthesize movieDidEnd;

@dynamic inputPath;
@dynamic inputPlayhead;
@dynamic inputRate;
@dynamic inputPlay;
@dynamic inputLoopMode;
@dynamic inputVolume;
@dynamic inputColorCorrection;

@dynamic outputImage;
@dynamic outputPlayheadPosition;
@dynamic outputDuration;
@dynamic outputMovieTime;
@dynamic outputMovieDidEnd;

+ (NSDictionary *)attributes
{
    return @{QCPlugInAttributeNameKey:kQCPlugIn_Name, QCPlugInAttributeDescriptionKey:kQCPlugIn_Description};
}

+ (NSDictionary *)attributesForPropertyPortWithKey:(NSString *)key
{

    if([key isEqualToString:@"inputPath"])
        return  @{QCPortAttributeNameKey : @"Movie Path"};
    
    if([key isEqualToString:@"inputPlayhead"])
        return  @{QCPortAttributeNameKey : @"Playhead",
                QCPortAttributeMinimumValueKey : [NSNumber numberWithFloat:0.0],
                QCPortAttributeDefaultValueKey : [NSNumber numberWithFloat:0.0],
                QCPortAttributeMaximumValueKey : [NSNumber numberWithFloat:1.0]};

    if([key isEqualToString:@"inputPlay"])
        return  @{QCPortAttributeNameKey:@"Play", QCPortAttributeDefaultValueKey:[NSNumber numberWithBool:YES]};

    if([key isEqualToString:@"inputRate"])
        return  @{QCPortAttributeNameKey:@"Rate", QCPortAttributeDefaultValueKey:[NSNumber numberWithFloat:1.0]};
    
    if([key isEqualToString:@"inputLoopMode"])
		return  @{QCPortAttributeNameKey : @"Loop Mode",
                QCPortAttributeMenuItemsKey : @[@"Loop", @"Palindrome", @"No Loop"],
                QCPortAttributeMinimumValueKey : [NSNumber numberWithUnsignedInteger:0],
                QCPortAttributeDefaultValueKey : [NSNumber numberWithUnsignedInteger:0],
                QCPortAttributeMaximumValueKey : [NSNumber numberWithUnsignedInteger:2]};

    if([key isEqualToString:@"inputVolume"])
        return  @{QCPortAttributeNameKey : @"Volume",
                QCPortAttributeMinimumValueKey : [NSNumber numberWithFloat:0.0],
                QCPortAttributeDefaultValueKey : [NSNumber numberWithFloat:1.0],
                QCPortAttributeMaximumValueKey : [NSNumber numberWithFloat:1.0]};

    if([key isEqualToString:@"inputColorCorrection"])
        return  @{QCPortAttributeNameKey:@"Color Correct", QCPortAttributeDefaultValueKey:[NSNumber numberWithBool:YES]};

    if([key isEqualToString:@"outputImage"])
        return  @{QCPortAttributeNameKey : @"Image"};

    if([key isEqualToString:@"outputPlayheadPosition"])
        return  @{QCPortAttributeNameKey : @"Current Playhead Position"};

    if([key isEqualToString:@"outputDuration"])
        return  @{QCPortAttributeNameKey : @"Duration"};

    if([key isEqualToString:@"outputMovieTime"])
        return  @{QCPortAttributeNameKey : @"Current Time"};

    if([key isEqualToString:@"outputMovieDidEnd"])
        return  @{QCPortAttributeNameKey : @"Movie Finished"};

	return nil;
}

+ (NSArray*) sortedPropertyPortKeys
{
	return @[@"inputPath",
            @"inputPlayhead",
            @"inputPlay",
            @"inputRate",
            @"inputLoopMode",
            @"inputVolume",
            @"inputColorCorrection",
            @"outputImage",
            @"outputPlayheadPosition",
            @"outputMovieTime",
            @"outputDuration",
            @"outputMovieDidEnd"];
}

+ (QCPlugInExecutionMode)executionMode
{
	return kQCPlugInExecutionModeProvider;
}

+ (QCPlugInTimeMode)timeMode
{
	return kQCPlugInTimeModeIdle;
}

- (id)init
{
	self = [super init];
	if (self)
    {
//        playerVideoOutputQueue = dispatch_queue_create(NULL, NULL);

        player = [[AVPlayer alloc] init];

        // kCVPixelFormatType_32ARGB, kCVPixelFormatType_32BGRA, kCVPixelFormatType_422YpCbCr8
        playerItemVideoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kCVPixelFormatType_422YpCbCr8], kCVPixelBufferPixelFormatTypeKey, nil]];
 		if (playerItemVideoOutput)
		{
            playerItemVideoOutput.suppressesPlayerRendering = YES;
//			[playerItemVideoOutput setDelegate:self queue:dispatch_get_main_queue()];
		//	[playerItemVideoOutput requestNotificationOfMediaDataChangeWithAdvanceInterval:ADVANCE_INTERVAL_IN_SECONDS];
        }
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerItemDidPlayToEndTime:) name:AVPlayerItemDidPlayToEndTimeNotification object:nil];

	}
	
	return self;
}

- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    
    [player release];
    player = nil;
    
//    dispatch_sync(playerVideoOutputQueue, ^
//    {
//		[playerItemVideoOutput setDelegate:nil queue:NULL];
//	});
    
    [playerItemVideoOutput release];
    playerItemVideoOutput = nil;
    
    [super dealloc];
}

@end

@implementation v002_Movie_PlayerPlugIn (Execution)

- (BOOL)startExecution:(id <QCPlugInContext>)context
{
    if(self.inputPlay)
        [player play];

	return YES;
}

- (void)enableExecution:(id <QCPlugInContext>)context
{
}

- (BOOL)execute:(id <QCPlugInContext>)context atTime:(NSTimeInterval)time withArguments:(NSDictionary *)arguments
{	
    
    // new file path
    if([self didValueForInputKeyChange:@"inputPath"])
    {
        NSString * path = self.inputPath;
		
		NSURL *pathURL;
		
		// relative to composition ?
		if(![path hasPrefix:@"/"] && ![path hasPrefix:@"http://"] && ![path hasPrefix:@"rtsp://"])
			path =  [NSString pathWithComponents:[NSArray arrayWithObjects:[[[context compositionURL] path]stringByDeletingLastPathComponent], path, nil]];
		
		path = [path stringByStandardizingPath];
		
		if([[NSFileManager defaultManager] fileExistsAtPath:path])
		{
			pathURL = [NSURL fileURLWithPath:path]; // TWB no longer retained
			NSLog(@"%@", pathURL);
		}
		else
		{
			pathURL =  [NSURL URLWithString:[path stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]; 
			NSLog(@"%@", pathURL);
		}
        
        AVPlayerItem* newItem = [AVPlayerItem playerItemWithURL:pathURL];
        
        [player replaceCurrentItemWithPlayerItem:newItem];
        
        [[player currentItem] addOutput:playerItemVideoOutput];
        
        self.outputDuration = CMTimeGetSeconds([[player currentItem] duration]);
        
        [player play];
    }
    
    if([self didValueForInputKeyChange:@"inputPlayhead"])
    {
     	[[player currentItem] seekToTime:CMTimeMultiplyByFloat64([[player currentItem] duration], (Float64) self.inputPlayhead) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    }

    if([self didValueForInputKeyChange:@"inputPlay"])
    {
        if(self.inputPlay)
            [player play];
        else
            [player pause];
    }

    
    if([self didValueForInputKeyChange:@"inputRate"])
    {
        [player setRate:self.inputRate];
    }

    if([self didValueForInputKeyChange:@"inputVolume"])
    {
        [player setVolume:self.inputVolume];
    }
    
    // check our video output for new frames
    CMTime outputItemTime = [playerItemVideoOutput itemTimeForHostTime:CACurrentMediaTime()];
	if ([playerItemVideoOutput hasNewPixelBufferForItemTime:outputItemTime])
	{
		CVPixelBufferRef pixBuff = [playerItemVideoOutput copyPixelBufferForItemTime:outputItemTime itemTimeForDisplay:NULL];
		
        // create new output image provider - retains the pixel buffer for us
        v002CVPixelBufferImageProvider *output = [[v002CVPixelBufferImageProvider alloc] initWithPixelBuffer:pixBuff isFlipped:CVImageBufferIsFlipped(pixBuff) shouldColorMatch:self.inputColorCorrection];
		        
        self.outputImage = output;
        
        [output release];
        CVBufferRelease(pixBuff);

        double currentTime = CMTimeGetSeconds([[player currentItem] currentTime]);
        double duration = CMTimeGetSeconds([[player currentItem] duration]);

        self.outputMovieTime = currentTime;
        self.outputPlayheadPosition = currentTime / duration;
	}

    // output port values
    BOOL end = self.movieDidEnd;
    
	if(end)
	{
		self.outputMovieDidEnd = YES;
		self.movieDidEnd = NO;
		
		// QCPortAttributeMenuItemsKey : @[@"Loop", @"Palindrome", @"No Loop"],
		if (self.inputLoopMode == 0)
		{
			[[player currentItem] seekToTime:kCMTimeZero];
			[player setRate:self.inputRate];
		}
		else if (self.inputLoopMode == 1)
		{
			// Rate is already zero by the time we get here.
			// Don't rely on reversePlaybackEndTime comparison
			if (CMTimeCompare([player currentTime], kCMTimeZero) > 0)
			{
			    [player setRate: -1.0 * fabs(self.inputRate)];
			}
			else
			{
			    [player setRate: fabs(self.inputRate)];
			}
		}
	}
    else
    {
		self.outputMovieDidEnd = NO;
    }
    
	return YES;
}

- (void)disableExecution:(id <QCPlugInContext>)context
{
}

- (void)stopExecution:(id <QCPlugInContext>)context
{
    [player pause];
}

- (void)playerItemDidPlayToEndTime:(NSNotification *)notification
{
	if ([player currentItem] == [notification object])
	{
        self.movieDidEnd = YES;
	}
}

- (void)outputMediaDataWillChange:(AVPlayerItemOutput *)sender NS_AVAILABLE(10_8, TBD)
{
    
}

- (void)outputSequenceWasFlushed:(AVPlayerItemOutput *)output NS_AVAILABLE(10_8, TBD);
{
    
}

@end
