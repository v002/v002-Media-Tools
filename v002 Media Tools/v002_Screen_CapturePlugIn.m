//
//  v002_Screen_CapturePlugIn.m
//  v002 Media Tools
//
//  Created by vade on 7/16/12.
//  Copyright (c) 2012 v002. All rights reserved.
//

#import <OpenGL/CGLMacro.h>
#import <IOKit/graphics/IOGraphicsLib.h>
#import "v002_Screen_CapturePlugIn.h"
#import "v002IOSurfaceImageProvider.h"

#define	kQCPlugIn_Name				@"v002 Screen Capture 2.0"
#define	kQCPlugIn_Description		@"10.8 Only Screen Capture, based off of CGDisplayStream"

@interface v002_Screen_CapturePlugIn (Private)
- (IOSurfaceRef)copyNewFrame;
- (void)emitNewFrame:(IOSurfaceRef)frame;

@end
@implementation v002_Screen_CapturePlugIn

// ports
@dynamic inputDisplayID;
@dynamic inputShowCursor;
@dynamic inputRetina;
//@dynamic inputOriginX;
//@dynamic inputOriginY;
//@dynamic inputWidth;
//@dynamic inputHeight;

@dynamic outputImage;


+ (NSDictionary *)attributes
{
    return @{QCPlugInAttributeNameKey:kQCPlugIn_Name, QCPlugInAttributeDescriptionKey:kQCPlugIn_Description};
}

+ (NSDictionary *)attributesForPropertyPortWithKey:(NSString *)key
{
//    CGDirectDisplayID mainDisplay = CGMainDisplayID();
//    CGRect mainDisplayRect = CGDisplayBounds(mainDisplay);
    
    NSMutableArray* screens = [NSMutableArray arrayWithCapacity:[NSScreen screens].count];
    
    for(NSScreen* screen in [NSScreen screens])
    {
        NSLog(@"%@", [screen deviceDescription]);
        
        [screens addObject:[[self class] productNameForScreen:screen]];
    }
    
    
    if([key isEqualToString:@"inputDisplayID"])
        return  @{QCPortAttributeNameKey : @"Display",
                  QCPortAttributeMenuItemsKey : screens,
                  QCPortAttributeMinimumValueKey : @(0),
                  QCPortAttributeMaximumValueKey : @(screens.count - 1),
                  QCPortAttributeDefaultValueKey : @(0),
                  };
    
    if([key isEqualToString:@"inputShowCursor"])
        return  @{QCPortAttributeNameKey:@"Show Cursor", QCPortAttributeDefaultValueKey:[NSNumber numberWithBool:NO]};
    
    if([key isEqualToString:@"inputRetina"])
    {
        return @{QCPortAttributeNameKey : @"High DPI Capture" , QCPortAttributeDefaultValueKey : @NO};
    }
    
//    if([key isEqualToString:@"inputOriginX"])
//        return  @{QCPortAttributeNameKey : @"X Origin",
//                QCPortAttributeMinimumValueKey : [NSNumber numberWithUnsignedInteger:0],
//                QCPortAttributeDefaultValueKey : [NSNumber numberWithUnsignedInteger:0]};
//
//    if([key isEqualToString:@"inputOriginY"])
//        return  @{QCPortAttributeNameKey : @"Y Origin",
//        QCPortAttributeMinimumValueKey : [NSNumber numberWithUnsignedInteger:0],
//        QCPortAttributeDefaultValueKey : [NSNumber numberWithUnsignedInteger:0]};
//
//    if([key isEqualToString:@"inputWidth"])
//        return  @{QCPortAttributeNameKey : @"Width",
//        QCPortAttributeMinimumValueKey : [NSNumber numberWithUnsignedInteger:0],
//        QCPortAttributeDefaultValueKey : [NSNumber numberWithUnsignedInteger:mainDisplayRect.size.width]};
//
//    if([key isEqualToString:@"inputHeight"])
//        return  @{QCPortAttributeNameKey : @"Height",
//        QCPortAttributeMinimumValueKey : [NSNumber numberWithUnsignedInteger:0],
//        QCPortAttributeDefaultValueKey : [NSNumber numberWithUnsignedInteger:mainDisplayRect.size.height]};

    if([key isEqualToString:@"outputImage"])
        return  @{QCPortAttributeNameKey : @"Image"};

      
	return nil;
}

+ (NSArray*) sortedPropertyPortKeys
{
	return @[@"inputDisplayID",
             @"inputShowCursor",
             @"inputRetina",
             ];
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
        colorspaceForDisplayID = NULL;
    }
	
	return self;
}

- (void) dealloc
{
    dispatch_release(displayQueue);
    if (displayStream) CFRelease(displayStream);
    
    if(colorspaceForDisplayID)
        CGColorSpaceRelease(colorspaceForDisplayID);
    
    [super dealloc];
}

- (IOSurfaceRef)getAndSetFrame:(IOSurfaceRef)new
{
    bool success = false;
    IOSurfaceRef old;
    do {
        old = updatedSurface;
        success = OSAtomicCompareAndSwapPtrBarrier(old, new, (void * volatile *)&updatedSurface);
    } while (!success);
    return old;
}

- (IOSurfaceRef)copyNewFrame
{
    return [self getAndSetFrame:NULL];
}

- (void)emitNewFrame:(IOSurfaceRef)frame
{
    CFRetain(frame);
    [self getAndSetFrame:frame];
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
    if([self didValueForInputKeyChange:@"inputDisplayID"] || [self didValueForInputKeyChange:@"inputShowCursor"] || [self didValueForInputKeyChange:@"inputRetina"])
    {
        NSLog(@"new Display ID");
        
        // Cleanup existing CGDisplayStream;
        
        if(displayStream)
        {
            CFRelease(displayStream);
            displayStream = NULL;
        }
        
        // create a new CGDisplayStream
        
        // we need to get the display ID from our product name
        // theoretically, the list of displays hasnt changed.
        // this is likely a bad assumption but for now we use the index of our product name menu as an index into the NSScreen.
        NSScreen* screen = [[NSScreen screens] objectAtIndex:self.inputDisplayID];
        
        if(screen)
        {
            NSDictionary* screenDictionary = [screen deviceDescription];
            NSNumber* screenID = [screenDictionary objectForKey:@"NSScreenNumber"];
            CGDirectDisplayID screenDisplayID = [screenID unsignedIntValue];

            if(screenDisplayID)
            {
                // release if we have..
                if(colorspaceForDisplayID)
                {
                    CGColorSpaceRelease(colorspaceForDisplayID);
                    colorspaceForDisplayID = NULL;
                }
                colorspaceForDisplayID = CGColorSpaceRetain([screen colorSpace].CGColorSpace);
            }
            
            CGDisplayModeRef mode = CGDisplayCopyDisplayMode(screenDisplayID);
            
            size_t pixelWidth = CGDisplayModeGetPixelWidth(mode);
            size_t pixelHeight = CGDisplayModeGetPixelHeight(mode);
            
            if(!self.inputRetina)
            {
                pixelWidth /= 2;
                pixelHeight /= 2;
            }
            
            CGDisplayModeRelease(mode);
            
            
            NSDictionary* options = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool: self.inputShowCursor] forKey:(NSString*)kCGDisplayStreamShowCursor];
            
            displayStream = CGDisplayStreamCreateWithDispatchQueue(screenDisplayID,
                                                                   pixelWidth,
                                                                   pixelHeight,
                                                                   'BGRA',
                                                                   (CFDictionaryRef)options,
                                                                   displayQueue,
                                                                   ^(CGDisplayStreamFrameStatus status, uint64_t displayTime, IOSurfaceRef frameSurface, CGDisplayStreamUpdateRef updateRef)
                                                                   {
                                                                       if(status == kCGDisplayStreamFrameStatusFrameComplete && frameSurface)
                                                                       {
                                                                           // As per CGDisplayStreams header
                                                                           IOSurfaceIncrementUseCount(frameSurface);
                                                                           // -emitNewFrame: retains the frame
                                                                           [self emitNewFrame:frameSurface];
                                                                       }
                                                                   });
            
            CGDisplayStreamStart(displayStream);

        }
        
    }
    
    IOSurfaceRef frameSurface = [self copyNewFrame];
    if (frameSurface)
    {
        v002IOSurfaceImageProvider *output = [[v002IOSurfaceImageProvider alloc] initWithSurface:frameSurface isFlipped:YES colorSpace:colorspaceForDisplayID shouldColorMatch:YES];
        
        // v002IOSurfaceImageProvider has retained the surface and marked it as in use, so we can unmark it and release it now
        IOSurfaceDecrementUseCount(frameSurface);
        CFRelease(frameSurface);
        
        self.outputImage = output;
        
        [output release];
    }
    
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


#pragma mark - Helper Methods

static io_service_t IOServicePortFromCGDisplayID(CGDirectDisplayID displayID)
{
    io_iterator_t iter;
    io_service_t serv, servicePort = 0;
    
    CFMutableDictionaryRef matching = IOServiceMatching("IODisplayConnect");
    
    // releases matching for us
    kern_return_t err = IOServiceGetMatchingServices(kIOMasterPortDefault,
                                                     matching,
                                                     &iter);
    if (err)
    {
        return 0;
    }
    
    while ((serv = IOIteratorNext(iter)) != 0)
    {
        CFDictionaryRef info;
        CFIndex vendorID, productID;
        CFNumberRef vendorIDRef, productIDRef;
        Boolean success;
        
        info = IODisplayCreateInfoDictionary(serv,kIODisplayOnlyPreferredName);
        
        vendorIDRef = CFDictionaryGetValue(info, CFSTR(kDisplayVendorID));
        productIDRef = CFDictionaryGetValue(info, CFSTR(kDisplayProductID));
        
        success = CFNumberGetValue(vendorIDRef, kCFNumberCFIndexType,
                                   &vendorID);
        success &= CFNumberGetValue(productIDRef, kCFNumberCFIndexType,
                                    &productID);
        
        if (!success)
        {
            CFRelease(info);
            continue;
        }
        
        if (CGDisplayVendorNumber(displayID) != vendorID ||
            CGDisplayModelNumber(displayID) != productID)
        {
            CFRelease(info);
            continue;
        }
        
        // we're a match
        servicePort = serv;
        CFRelease(info);
        break;
    }
    
    IOObjectRelease(iter);
    return servicePort;
}

+ (NSString*)productNameForScreen:(NSScreen*)screen
{
    NSString *screenName = nil;
    
    NSNumber* screenNumber = [screen deviceDescription][@"NSScreenNumber"];
    
    CGDirectDisplayID displayID = [screenNumber unsignedIntValue];
    
    io_service_t displayServicePort = IOServicePortFromCGDisplayID(displayID);
    NSDictionary *deviceInfo = (NSDictionary *)IODisplayCreateInfoDictionary(displayServicePort, kIODisplayOnlyPreferredName);
    NSDictionary *localizedNames = [deviceInfo objectForKey:[NSString stringWithUTF8String:kDisplayProductName]];
    
    if(displayServicePort)
        CFRelease(displayServicePort);
    
    if ([localizedNames count] > 0)
    {
        screenName = [[localizedNames objectForKey:[[localizedNames allKeys] objectAtIndex:0]] retain];
    }
    
    [deviceInfo release];
    return [screenName autorelease];
}


@end
