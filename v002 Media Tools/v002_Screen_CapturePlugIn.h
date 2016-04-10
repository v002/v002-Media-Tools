//
//  v002_Screen_CapturePlugIn.h
//  v002 Media Tools
//
//  Created by vade on 7/16/12.
//  Copyright (c) 2012 v002. All rights reserved.
//

#import <Quartz/Quartz.h>

@interface v002_Screen_CapturePlugIn : QCPlugIn
{
    CGDisplayStreamRef  displayStream;
    dispatch_queue_t displayQueue;
    IOSurfaceRef updatedSurface;
    CGColorSpaceRef colorspaceForDisplayID;
}
// Ports
@property (assign) NSUInteger inputDisplayID;
@property (assign) BOOL inputShowCursor;
@property (assign) BOOL inputRetina;
//@property (assign) double inputOriginX;
//@property (assign) double inputOriginY;
//@property (assign) double inputWidth;
//@property (assign) double inputHeight;

@property (assign) id<QCPlugInOutputImageProvider> outputImage;
//@property (assign)

+ (NSString*)productNameForScreen:(NSScreen*)screen;

@end
