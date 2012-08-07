//
//  v002_Screen_CapturePlugIn.m
//  v002 Media Tools
//
//  Created by vade on 7/16/12.
//  Copyright (c) 2012 v002. All rights reserved.
//

#import <OpenGL/CGLMacro.h>

#import "v002_Screen_CapturePlugIn.h"

#define	kQCPlugIn_Name				@"v002 Screen Capture 2.0"
#define	kQCPlugIn_Description		@"10.8 Only Screen Capture, based off of CGDisplayStream"

static  void MyTextureRelease(CGLContextObj cgl_ctx, GLuint name, void* context)
{
    glDeleteTextures(1, &name);
    
    IOSurfaceRef frameSurface = (IOSurfaceRef) context;
    IOSurfaceDecrementUseCount(frameSurface);
    CFRelease(frameSurface);
}


@implementation v002_Screen_CapturePlugIn

@synthesize displayImageProvider;

// ports
@dynamic inputDisplayID;
@dynamic inputShowCursor;
@dynamic inputOriginX;
@dynamic inputOriginY;
@dynamic inputWidth;
@dynamic inputHeight;

@dynamic outputImage;


+ (NSDictionary *)attributes
{
    return @{QCPlugInAttributeNameKey:kQCPlugIn_Name, QCPlugInAttributeDescriptionKey:kQCPlugIn_Description};
}

+ (NSDictionary *)attributesForPropertyPortWithKey:(NSString *)key
{
    CGDirectDisplayID mainDisplay = CGMainDisplayID();
    CGRect mainDisplayRect = CGDisplayBounds(mainDisplay);
    
    
    if([key isEqualToString:@"inputDisplayID"])
        return  @{QCPortAttributeNameKey : @"Display ID", QCPortAttributeDefaultValueKey:[NSNumber numberWithUnsignedInt:mainDisplay]};
    
    if([key isEqualToString:@"inputShowCursor"])
        return  @{QCPortAttributeNameKey:@"Show Cursor", QCPortAttributeDefaultValueKey:[NSNumber numberWithBool:NO]};
    
    
    if([key isEqualToString:@"inputOriginX"])
        return  @{QCPortAttributeNameKey : @"X Origin",
                QCPortAttributeMinimumValueKey : [NSNumber numberWithUnsignedInteger:0],
                QCPortAttributeDefaultValueKey : [NSNumber numberWithUnsignedInteger:0]};

    if([key isEqualToString:@"inputOriginY"])
        return  @{QCPortAttributeNameKey : @"Y Origin",
        QCPortAttributeMinimumValueKey : [NSNumber numberWithUnsignedInteger:0],
        QCPortAttributeDefaultValueKey : [NSNumber numberWithUnsignedInteger:0]};

    if([key isEqualToString:@"inputWidth"])
        return  @{QCPortAttributeNameKey : @"Width",
        QCPortAttributeMinimumValueKey : [NSNumber numberWithUnsignedInteger:0],
        QCPortAttributeDefaultValueKey : [NSNumber numberWithUnsignedInteger:mainDisplayRect.size.width]};

    if([key isEqualToString:@"inputHeight"])
        return  @{QCPortAttributeNameKey : @"Height",
        QCPortAttributeMinimumValueKey : [NSNumber numberWithUnsignedInteger:0],
        QCPortAttributeDefaultValueKey : [NSNumber numberWithUnsignedInteger:mainDisplayRect.size.height]};

      
	return nil;
}

+ (NSArray*) sortedPropertyPortKeys
{
	return @[@"inputPath",
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
        displayQueue = dispatch_queue_create("info.v002.v002ScreenCaptureQueue", DISPATCH_QUEUE_SERIAL);
    }
	
	return self;
}

- (void)finalize
{
    dispatch_release(displayQueue);
    if (displayStream) CFRelease(displayStream);
    [super finalize];
}

- (void) dealloc
{
    dispatch_release(displayQueue);
    if (displayStream) CFRelease(displayStream);
    [super dealloc];
}


@end

@implementation v002_Screen_CapturePlugIn (Execution)

- (BOOL)startExecution:(id <QCPlugInContext>)context
{
    if(displayStream)
        CGDisplayStreamStart(displayStream);
	
    return YES;
}

- (void)enableExecution:(id <QCPlugInContext>)context
{
}

- (BOOL)execute:(id <QCPlugInContext>)context atTime:(NSTimeInterval)time withArguments:(NSDictionary *)arguments
{
    CGLContextObj cgl_ctx = [context CGLContextObj];
    
    // Get the current queue we are on.
    dispatch_queue_t pluginQueue = dispatch_get_current_queue();
    
    if([self didValueForInputKeyChange:@"inputDisplayID"])
    {
        NSLog(@"new Display ID");
        
        // Cleanup existing CGDisplayStream;
        
        if(displayStream)
        {
            CFRelease(displayStream);
            displayStream = NULL;
        }
        
        // create a new CGDisplayStream
        CGDirectDisplayID display = (CGDirectDisplayID) self.inputDisplayID;
        
        CGRect bounds = CGDisplayBounds(display);
        
        displayStream = CGDisplayStreamCreateWithDispatchQueue(display,
                                                               bounds.size.width,
                                                               bounds.size.height,
                                                               'BGRA',
                                                               nil,
                                                               displayQueue,
                                                               ^(CGDisplayStreamFrameStatus status, uint64_t displayTime, IOSurfaceRef frameSurface, CGDisplayStreamUpdateRef updateRef)
                                                               {
                                                                   if(frameSurface)
                                                                   {
                                                                       // As per CGDisplayStreams header
                                                                       CFRetain(frameSurface);
                                                                       IOSurfaceIncrementUseCount(frameSurface);
                                                                       
                                                                       // use the plugins Queue so our GL context is in the correct spot
                                                                       dispatch_sync(pluginQueue, ^{
                                                                           
                                                                           NSUInteger width = IOSurfaceGetWidth(frameSurface);
                                                                           NSUInteger height = IOSurfaceGetHeight(frameSurface);
                                                                           
                                                                           GLuint newTextureForSurface;
                                                                           
                                                                           glPushAttrib(GL_TEXTURE_BIT);
                                                                           
                                                                           glGenTextures(1, &newTextureForSurface);
                                                                           glBindTexture(GL_TEXTURE_RECTANGLE_EXT,newTextureForSurface);
                                                                           
                                                                           CGLTexImageIOSurface2D(cgl_ctx, GL_TEXTURE_RECTANGLE_EXT, GL_RGBA, width, height, GL_BGRA, GL_UNSIGNED_BYTE, frameSurface, 0);
                                                                           
                                                                           glPopAttrib();
                                                                           
                                                                           
                                                                           // make a new
                                                                           id<QCPlugInOutputImageProvider> provider = nil;
                                                                           CGColorSpaceRef cspace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
                                                                           provider = [context outputImageProviderFromTextureWithPixelFormat:QCPlugInPixelFormatBGRA8
                                                                                                                                  pixelsWide:width
                                                                                                                                  pixelsHigh:height
                                                                                                                                        name:newTextureForSurface
                                                                                                                                     flipped:YES
                                                                                                                             releaseCallback:MyTextureRelease
                                                                                                                              releaseContext:frameSurface
                                                                                                                                  colorSpace:cspace
                                                                                                                            shouldColorMatch:YES];
                                                                           
                                                                           CGColorSpaceRelease(cspace);
                                                                           
                                                                           // set immediately on the plugins queue.
                                                                           self.displayImageProvider = provider;
                                                                           
                                                                       });
                                                                   }
                                                               });
        
        CGDisplayStreamStart(displayStream);
        
    }
    
    self.outputImage = self.displayImageProvider;
    
    return YES;
}

- (void)disableExecution:(id <QCPlugInContext>)context
{
}

- (void)stopExecution:(id <QCPlugInContext>)context
{
    if(displayStream)
        CGDisplayStreamStop(displayStream);
}


@end
