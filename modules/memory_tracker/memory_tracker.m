#include <Metal/Metal.h>
#include <mach/mach_time.h>
#include "../debug/expose_from_debug.h"

typedef struct {
  size_t totalAllocated;
  size_t totalFreed;
} MemoryTracker;

static MemoryTracker memoryTracker = {0, 0};

id<MTLBuffer> create_tracked_buffer(id<MTLDevice> device, size_t size,
                                    MTLResourceOptions options) {
  memoryTracker.totalAllocated += size;
  log_printf(2, "Memory", "Buffer allocated: %zu bytes (Total: %zu bytes)", size,
        memoryTracker.totalAllocated);
  return [device newBufferWithLength:size options:options];
}

void free_tracked_buffer(id<MTLBuffer> buffer) {
  size_t size = buffer.length;
  memoryTracker.totalFreed += size;
  log_printf(2, "Memory", "Buffer freed: %zu bytes (Total freed: %zu bytes)", size,
        memoryTracker.totalFreed);
}

typedef struct {
  const char *name;
  uint64_t timestamp;
  const char *metadata;
} EventMarker;

#define MAX_MARKERS 1000
static EventMarker eventMarkers[MAX_MARKERS];
static int markerCount = 0;

void add_event_marker(const char *name, const char *metadata) {
  if (markerCount < MAX_MARKERS) {
    eventMarkers[markerCount].name = name;
    eventMarkers[markerCount].timestamp = mach_absolute_time();
    eventMarkers[markerCount].metadata = metadata;
    markerCount++;
  }
}

typedef struct {
  void *address;
  size_t size;
  const char *allocation_site;
} MemoryAllocation;

#define MAX_ALLOCATIONS 1000
static MemoryAllocation allocations[MAX_ALLOCATIONS];
static int allocationCount = 0;

void track_allocation(void *ptr, size_t size, const char *site) {
  if (allocationCount < MAX_ALLOCATIONS) {
    allocations[allocationCount].address = ptr;
    allocations[allocationCount].size = size;
    allocations[allocationCount].allocation_site = site;
    allocationCount++;
  }
}

void untrack_allocation(void *ptr) {
  for (int i = 0; i < allocationCount; i++) {
    if (allocations[i].address == ptr) {
      // Remove by shifting remaining elements
      memmove(&allocations[i], &allocations[i + 1],
              (allocationCount - i - 1) * sizeof(MemoryAllocation));
      allocationCount--;
      break;
    }
  }
}