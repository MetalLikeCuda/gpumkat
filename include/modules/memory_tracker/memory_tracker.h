#ifndef MEMORY_TRACKER_H
#define MEMORY_TRACKER_H
#include <Metal/Metal.h>
id<MTLBuffer> create_tracked_buffer(id<MTLDevice> device, size_t size,
                                    MTLResourceOptions options);
typedef struct {
  size_t totalAllocated;
  size_t totalFreed;
} MemoryTracker;

static MemoryTracker memoryTracker = {0, 0};
void free_tracked_buffer(id<MTLBuffer> buffer);

// Event Marker System
typedef struct {
  const char *name;
  uint64_t timestamp;
  const char *metadata;
} EventMarker;

#define MAX_MARKERS 1000
static EventMarker eventMarkers[MAX_MARKERS];
static int markerCount = 0;
void add_event_marker(const char *name, const char *metadata);

// Memory Leak Detection
typedef struct {
  void *address;
  size_t size;
  const char *allocation_site;
} MemoryAllocation;

#define MAX_ALLOCATIONS 1000
static MemoryAllocation allocations[MAX_ALLOCATIONS];
static int allocationCount = 0;
void track_allocation(void *ptr, size_t size, const char *site);
void untrack_allocation(void *ptr);

#endif