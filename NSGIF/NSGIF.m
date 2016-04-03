//
//  NSGIF.m
//  
//  Created by Sebastian Dobrincu
//

#import "NSGIF.h"

// Declare constants
#define defaultStaticFileName     @"NSGIF.gif"
#define timeInterval @(600)
#define tolerance    @(0.01)

typedef NS_ENUM(NSInteger, GIFSize) {
    GIFSizeVeryLow  = 2,
    GIFSizeLow      = 3,
    GIFSizeMedium   = 5,
    GIFSizeHigh     = 7,
    GIFSizeOriginal = 10
};


@implementation NSGIFRequest
- (NSURL *)destinationVideo {
    if(_destinationVideo){
        return _destinationVideo;
    }
    NSAssert(self.sourceVideo, @"URL of a source video required if didn't provide destination url.");
    NSString *temporaryFile = [NSTemporaryDirectory() stringByAppendingString:defaultStaticFileName];
    return [NSURL fileURLWithPath:temporaryFile];
}

- (void)assert{
    NSParameterAssert(self.sourceVideo);
    NSAssert(self.framesPerSecond>0, @"framesPerSecond must be higer than 0.");
}

+ (NSGIFRequest *__nonnull)requestForOptimizedDefaults:(NSURL *__nullable)urlForSourceVideo
                                           destination:(NSURL *__nullable)videoFileURL {

    NSGIFRequest * request = [[NSGIFRequest alloc] init];
    request.sourceVideo = urlForSourceVideo;
    request.destinationVideo = videoFileURL;
    request.delayTime = 0.13f;
    request.framesPerSecond = 4;
    return request;
}

+ (NSGIFRequest *__nonnull)requestForLivePhoto:(NSURL *__nullable)urlForSourceVideo
                                   destination:(NSURL *__nullable)videoFileURL {

    NSGIFRequest * request = [self requestForOptimizedDefaults:urlForSourceVideo destination:videoFileURL];
    request.maxVideoLength = 3;
    return request;
}

@end

@implementation NSGIF

#pragma mark - Public methods
+ (void)optimalGIFfromURL:(NSGIFRequest *)request completion:(void (^)(NSURL *))completionBlock {
    [request assert];

    // Create properties dictionaries
    NSDictionary *fileProperties = [self filePropertiesWithLoopCount:request.loopCount];
    NSDictionary *frameProperties = [self framePropertiesWithDelayTime:request.delayTime];

    AVURLAsset *asset = [AVURLAsset assetWithURL:request.sourceVideo];

    CGFloat videoWidth = [[asset tracksWithMediaType:AVMediaTypeVideo][0] naturalSize].width;
    CGFloat videoHeight = [[asset tracksWithMediaType:AVMediaTypeVideo][0] naturalSize].height;

    GIFSize optimalSize = GIFSizeMedium;
    if (videoWidth >= 1200 || videoHeight >= 1200)
        optimalSize = GIFSizeVeryLow;
    else if (videoWidth >= 800 || videoHeight >= 800)
        optimalSize = GIFSizeLow;
    else if (videoWidth >= 400 || videoHeight >= 400)
        optimalSize = GIFSizeMedium;
    else if (videoWidth < 400|| videoHeight < 400)
        optimalSize = GIFSizeHigh;

    // Get the length of the video in seconds
    CGFloat videoLength = (CGFloat)asset.duration.value/asset.duration.timescale;
    NSUInteger frameCount = (NSUInteger) (videoLength * request.framesPerSecond);

    // How far along the video track we want to move, in seconds.
    CGFloat increment = (CGFloat)videoLength/frameCount;

    // Add frames to the buffer
    NSMutableArray *timePoints = [NSMutableArray array];
    for (int currentFrame = 0; currentFrame<frameCount; ++currentFrame) {
        CGFloat seconds = (CGFloat)increment * currentFrame;
        CMTime time = CMTimeMakeWithSeconds(seconds, [timeInterval intValue]);
        [timePoints addObject:[NSValue valueWithCMTime:time]];
    }

    // Prepare group for firing completion block
    dispatch_group_t gifQueue = dispatch_group_create();
    dispatch_group_enter(gifQueue);

    __block NSURL *gifURL;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        gifURL = [self createGIFforTimePoints:timePoints fromURL:request.sourceVideo toURL:request.destinationVideo fileProperties:fileProperties frameProperties:frameProperties frameCount:frameCount gifSize:optimalSize];

        dispatch_group_leave(gifQueue);
    });

    dispatch_group_notify(gifQueue, dispatch_get_main_queue(), ^{
        // Return GIF URL
        completionBlock(gifURL);
    });
}

+ (void)createGIFfromURL:(NSGIFRequest *__nullable)request completion:(void (^ __nullable)(NSURL *__nullable GifURL))completionBlock {
    [request assert];

    // Create properties dictionaries
    NSDictionary *fileProperties = [self filePropertiesWithLoopCount:request.loopCount];
    NSDictionary *frameProperties = [self framePropertiesWithDelayTime:request.delayTime];

    AVURLAsset *asset = [AVURLAsset assetWithURL:request.sourceVideo];

    // Get the length of the video in seconds
    CGFloat videoLength = (CGFloat)asset.duration.value/asset.duration.timescale;

    // How far along the video track we want to move, in seconds.
    CGFloat increment = (CGFloat)videoLength/request.frameCount;

    // Add frames to the buffer
    NSMutableArray *timePoints = [NSMutableArray array];
    for (int currentFrame = 0; currentFrame<request.frameCount; ++currentFrame) {
        CGFloat seconds = (CGFloat)increment * currentFrame;
        CMTime time = CMTimeMakeWithSeconds(seconds, [timeInterval intValue]);
        [timePoints addObject:[NSValue valueWithCMTime:time]];
    }

    // Prepare group for firing completion block
    dispatch_group_t gifQueue = dispatch_group_create();
    dispatch_group_enter(gifQueue);

    __block NSURL *gifURL;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        gifURL = [self createGIFforTimePoints:timePoints fromURL:request.sourceVideo toURL:request.destinationVideo fileProperties:fileProperties frameProperties:frameProperties frameCount:request.frameCount gifSize:GIFSizeMedium];

        dispatch_group_leave(gifQueue);
    });

    dispatch_group_notify(gifQueue, dispatch_get_main_queue(), ^{
        // Return GIF URL
        completionBlock(gifURL);
    });
}

#pragma mark - Base methods

+ (NSURL *)createGIFforTimePoints:(NSArray *)timePoints fromURL:(NSURL *)url toURL:(NSURL *)destFileURL fileProperties:(NSDictionary *)fileProperties frameProperties:(NSDictionary *)frameProperties frameCount:(int)frameCount gifSize:(GIFSize)gifSize{
    NSParameterAssert(timePoints);
    NSParameterAssert(url);
    NSParameterAssert(destFileURL);
    NSParameterAssert(fileProperties);
    NSParameterAssert(frameProperties);

    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)destFileURL, kUTTypeGIF , frameCount, NULL);

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    
    CMTime tol = CMTimeMakeWithSeconds([tolerance floatValue], [timeInterval intValue]);
    generator.requestedTimeToleranceBefore = tol;
    generator.requestedTimeToleranceAfter = tol;
    
    NSError *error = nil;
    CGImageRef previousImageRefCopy = nil;
    for (NSValue *time in timePoints) {
        CGImageRef imageRef;
        
        #if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
            imageRef = (CGFloat)gifSize/10 != 1 ? createImageWithScale([generator copyCGImageAtTime:[time CMTimeValue] actualTime:nil error:&error], (CGFloat)gifSize/10) : [generator copyCGImageAtTime:[time CMTimeValue] actualTime:nil error:&error];
        #elif TARGET_OS_MAC
            imageRef = [generator copyCGImageAtTime:[time CMTimeValue] actualTime:nil error:&error];
        #endif
        
        if (error) {
            NSLog(@"Error copying image: %@", error);
        }
        if (imageRef) {
            CGImageRelease(previousImageRefCopy);
            previousImageRefCopy = CGImageCreateCopy(imageRef);
        } else if (previousImageRefCopy) {
            imageRef = CGImageCreateCopy(previousImageRefCopy);
        } else {
            NSLog(@"Error copying image and no previous frames to duplicate");
            return nil;
        }
        CGImageDestinationAddImage(destination, imageRef, (CFDictionaryRef)frameProperties);
        CGImageRelease(imageRef);
        NSLog(@"%@ %d, %d",time, [timePoints indexOfObject:time], timePoints.count);
    }
    CGImageRelease(previousImageRefCopy);
    
    CGImageDestinationSetProperties(destination, (CFDictionaryRef)fileProperties);
    // Finalize the GIF
    if (!CGImageDestinationFinalize(destination)) {
        NSLog(@"Failed to finalize GIF destination: %@", error);
        if (destination != nil) {
            CFRelease(destination);
        }
        return nil;
    }
    CFRelease(destination);
    
    return destFileURL;
}

#pragma mark - Helpers

CGImageRef createImageWithScale(CGImageRef imageRef, CGFloat scale) {
    
    #if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
    CGSize newSize = CGSizeMake(CGImageGetWidth(imageRef)*scale, CGImageGetHeight(imageRef)*scale);
    CGRect newRect = CGRectIntegral(CGRectMake(0, 0, newSize.width, newSize.height));
    
    UIGraphicsBeginImageContextWithOptions(newSize, NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) {
        return nil;
    }
    
    // Set the quality level to use when rescaling
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGAffineTransform flipVertical = CGAffineTransformMake(1, 0, 0, -1, 0, newSize.height);
    
    CGContextConcatCTM(context, flipVertical);
    // Draw into the context; this scales the image
    CGContextDrawImage(context, newRect, imageRef);
    
    //Release old image
    CFRelease(imageRef);
    // Get the resized image from the context and a UIImage
    imageRef = CGBitmapContextCreateImage(context);
    
    UIGraphicsEndImageContext();
    #endif
    
    return imageRef;
}

#pragma mark - Properties

+ (NSDictionary *)filePropertiesWithLoopCount:(int)loopCount {
    return @{(NSString *)kCGImagePropertyGIFDictionary:
                @{(NSString *)kCGImagePropertyGIFLoopCount: @(loopCount)}
             };
}

+ (NSDictionary *)framePropertiesWithDelayTime:(CGFloat)delayTime {

    return @{(NSString *)kCGImagePropertyGIFDictionary:
                @{(NSString *)kCGImagePropertyGIFDelayTime: @(delayTime)},
                (NSString *)kCGImagePropertyColorModel:(NSString *)kCGImagePropertyColorModelRGB
            };
}
@end
