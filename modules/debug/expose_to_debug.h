#ifndef EXPOSE_TO_DEBUG_H
#define EXPOSE_TO_DEBUG_H
#import <Metal/Metal.h>
#import <Mach/mach_time.h>
#import <WebKit/WebKit.h>
static uint64_t get_time() { return mach_absolute_time(); }
id<MTLBuffer> create_tracked_buffer(id<MTLDevice> device, size_t size,
                                    MTLResourceOptions options);
#endif