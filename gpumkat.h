#ifndef GPUmkat_h
#define GPUmkat_h

#include "modules/debug/expose_from_debug.h"
#include "modules/lsp_server/lsp_integration.h"
#include "modules/memory_tracker/memory_tracker.h"
#include "modules/pipeline_statistics/pipeline_statistics.h"
#include "modules/plugin_manager/plugin_manager.h"
#include "modules/testing/testing.h"
#include "modules/update/update.h"
#include "modules/visualization/visualization.h"
#include <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <dirent.h>
#import <mach/mach_time.h>
#include <pthread.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>

#define VERSION "v1.2"
#define MAX_PATH_LEN 256

// -------------------- Hot Reloading --------------------
typedef struct {
  id<MTLDevice> device;
  NSString *metallibPath;
  id<MTLLibrary> *currentLibrary;
  pthread_mutex_t library_mutex;
  volatile bool should_stop;
} HotReloadContext;

void *watch_metallib_changes(void *arg);
pthread_t start_hot_reload(id<MTLDevice> device, NSString *metallibPath,
                           id<MTLLibrary> *currentLibrary);

// -------------------- Timer Utilities --------------------
typedef struct {
  uint64_t start_time;
  uint64_t end_time;
} Timer;

uint64_t get_time(void);
double convert_time_to_seconds(uint64_t elapsed_time);

// -------------------- Visualization --------------------
typedef struct {
  char *name;
  double start_time;
  double end_time;
} TraceEvent;

void write_trace_event(const char *filename, TraceEvent *events, size_t count);

// -------------------- Initialization --------------------
void initialize_buffer(id<MTLBuffer> buffer, BufferConfig *config);
id<MTLBuffer> create_buffer_with_error_checking(id<MTLDevice> device,
                                                BufferConfig *config,
                                                DebugConfig *debug);

// -------------------- Signal Handling --------------------
void handle_sigint(int sig);

#endif /* gpumkat.h */
