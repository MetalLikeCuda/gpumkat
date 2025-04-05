#ifndef GPUmkat_h
#define GPUmkat_h

#include "modules/debug/expose_from_debug.h"
#include "modules/memory_tracker/memory_tracker.h"
#include "modules/pipeline_statistics/pipeline_statistics.h"
#include "modules/plugin_manager/plugin_manager.h"
#include "modules/update/update.h"
#include "modules/visualization/visualization.h"
#import <QuartzCore/QuartzCore.h>
#include <dirent.h>
#import <mach/mach_time.h>
#include <pthread.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>

#define VERSION "v1.0"
#define ARCH "arm64"
#define MAX_PATH_LEN 256

// -------------------- Timer Utilities --------------------
typedef struct {
  uint64_t start_time;
  uint64_t end_time;
} Timer;

static uint64_t get_time();
static double convert_time_to_seconds(uint64_t elapsed_time);

// -------------------- Memory Tracker --------------------
typedef struct {
  size_t totalAllocated;
  size_t totalFreed;
} MemoryTracker;

id<MTLBuffer> create_tracked_buffer(id<MTLDevice> device, size_t size,
                                    MTLResourceOptions options);
void free_tracked_buffer(id<MTLBuffer> buffer);

// Event Marker System
typedef struct {
  const char *name;
  uint64_t timestamp;
  const char *metadata;
} EventMarker;

void add_event_marker(const char *name, const char *metadata);

// Memory Leak Detection
typedef struct {
  void *address;
  size_t size;
  const char *allocation_site;
} MemoryAllocation;

void track_allocation(void *ptr, size_t size, const char *site);
void untrack_allocation(void *ptr);

// Pipeline Statistics
typedef struct {
  double gpuTime;
  double cpuUsage;
  uint64_t cpuFrequency;
  uint64_t usedMemory;
  uint64_t virtualMemory;
  uint64_t totalMemory;
  double gpuToCpuTransferTime;
  uint64_t gpuToCpuBandwidth;
  double kernelOccupancy;
  uint64_t activeWarps;
  uint64_t maxWarps;
  uint64_t threadBlockSize;
  uint64_t gridSize;
  CFTimeInterval lastFrameTime;
  double currentFPS;
  CFTimeInterval totalTime;
  double actualFPS;
} PipelineStats;

typedef struct {
  uint64_t cacheHits;
  uint64_t cacheMisses;
  float threadExecutionEfficiency;
  uint64_t instructionsExecuted;
  float gpuPower;
  float peakPower;
  float averagePower;
} SampleData;

bool setup_power_metrics(id<MTLDevice> device);
void sample_power_metrics(id<MTLCommandBuffer> commandBuffer);
void update_power_metrics();
void cleanup_counters();
void resolve_power_metrics();

PipelineStats
collect_pipeline_statistics(id<MTLCommandBuffer> commandBuffer,
                            id<MTLComputePipelineState> pipelineState);

// -------------------- Visualization --------------------
typedef struct {
  char *name;
  double start_time;
  double end_time;
} TraceEvent;

void write_trace_event(const char *filename, TraceEvent *events, size_t count);

// -------------------- Multithreading Support --------------------
void init_profiling_queue();
void profile_multithreaded_work(id<MTLCommandBuffer> commandBuffer,
                                const char *name);

// -------------------- Command Buffer Profiling and Debugging
// --------------------
void profile_command_buffer(id<MTLCommandBuffer> commandBuffer,
                            const char *name);

void print_buffer_state(id<MTLBuffer> buffer, const char *name, size_t size);
typedef struct {
  const char *name;
  size_t size;
  const char *type;
  NSArray *contents;
} BufferConfig;

typedef struct {
  const char *condition;   // Expression or condition to evaluate
  const char *description; // Description of the breakpoint
} Breakpoint;

// Error severity levels
typedef enum {
  ERROR_SEVERITY_INFO = 0,
  ERROR_SEVERITY_WARNING = 1,
  ERROR_SEVERITY_ERROR = 2,
  ERROR_SEVERITY_FATAL = 3
} ErrorSeverity;

// Error categories
typedef enum {
  ERROR_CATEGORY_MEMORY = 0,
  ERROR_CATEGORY_SHADER = 1,
  ERROR_CATEGORY_PIPELINE = 2,
  ERROR_CATEGORY_BUFFER = 3,
  ERROR_CATEGORY_RUNTIME = 4,
  ERROR_CATEGORY_VALIDATION = 5,
  ERROR_CATEGORY_LIBRARY = 6,
  ERROR_CATEGORY_COMMAND_QUEUE = 7,
  ERROR_CATEGORY_COMMAND_BUFFER = 8,
  ERROR_CATEGORY_COMMAND_ENCODER = 9
} ErrorCategory;

// Error structure
typedef struct {
  ErrorSeverity severity;
  ErrorCategory category;
  const char *message;
  const char *location;
  uint64_t timestamp;
} ErrorRecord;

// Error handling configuration
typedef struct {
  bool catch_warnings;          // Whether to catch and log warnings
  bool catch_memory_errors;     // Track memory-related issues
  bool catch_shader_errors;     // Track shader compilation/execution issues
  bool catch_validation_errors; // Track data validation issues
  bool break_on_error;          // Whether to pause execution on errors
  int max_error_count;          // Maximum number of errors to store
  ErrorSeverity min_severity;   // Minimum severity level to track
} ErrorHandlingConfig;

// Error collector
typedef struct {
  ErrorRecord *errors;
  size_t error_count;
  size_t capacity;
} ErrorCollector;

typedef struct {
  char *event_name;
  char *event_type;
  char *details;
  uint64_t timestamp;
  size_t depth; // For tracking nested events
} TimelineEvent;

// Timeline configuration
typedef struct {
  bool enabled;
  char *output_file;
  bool track_buffers;
  bool track_shaders;
  bool track_performance;
  size_t max_events;
} TimelineConfig;

typedef struct {
  bool enabled;

  // Compute Simulation
  struct {
    float processing_units_availability; // 0.0 - 1.0 (% of compute units
                                         // available)
    float clock_speed_reduction;         // 0.0 - 1.0 (reduction in clock speed)
    int compute_unit_failures; // Number of simulated compute unit failures
  } compute;

  // Memory Simulation
  struct {
    float bandwidth_reduction; // 0.0 - 1.0 (% of bandwidth reduction)
    float latency_multiplier;  // 1.0+ (increased latency)
    size_t available_memory;   // Simulated available memory in bytes
    float
        memory_error_rate; // 0.0 - 1.0 (probability of memory transfer errors)
  } memory;

  // Thermal and Power Simulation
  struct {
    float thermal_throttling_threshold; // Temperature at which performance
                                        // degrades
    float power_limit;                  // Maximum power consumption
    bool enable_thermal_simulation;
  } thermal;

  // Performance Logging
  struct {
    bool detailed_logging;
    char *log_file_path;
  } logging;
} LowEndGpuSimulation;

typedef struct {
  void *source_buffer;
  void *destination_buffer;
  size_t transfer_size;
  bool transfer_completed;
  float transfer_quality; // 0.0 - 1.0 representing transfer integrity
} MemoryTransfer;

typedef struct {
  bool enable_async_tracking;
  bool log_command_status;
  bool detect_long_running_commands;
  double long_command_threshold; // in seconds
  bool generate_async_timeline;
} AsyncCommandDebugConfig;

typedef struct {
  id<MTLCommandBuffer> command_buffer;
  NSDate *submission_time;
  NSDate *completion_time;
  const char *name;
  bool is_completed;
  bool has_errors;
  double execution_time;
} AsyncCommandTracker;

// Maximum number of async commands to track
#define MAX_ASYNC_COMMANDS 100

typedef struct {
  AsyncCommandDebugConfig config;
  AsyncCommandTracker commands[MAX_ASYNC_COMMANDS];
  size_t command_count;
} AsyncCommandDebugExtension;

typedef enum {
  THREAD_DISPATCH_DEFAULT = 0, // Default Metal thread dispatch
  THREAD_DISPATCH_LINEAR,      // Execute threads in linear order
  THREAD_DISPATCH_REVERSE,     // Execute threads in reverse order
  THREAD_DISPATCH_RANDOM,      // Execute threads in random order
  THREAD_DISPATCH_ALTERNATING, // Execute threads in alternating pattern
  THREAD_DISPATCH_CUSTOM       // Custom execution pattern
} ThreadDispatchMode;

typedef struct {
  ThreadDispatchMode dispatch_mode; // How to dispatch threads
  bool enable_thread_debugging;     // Enable detailed thread debugging
  bool log_thread_execution;        // Log thread execution order
  bool validate_thread_access;      // Validate thread memory access
  bool simulate_thread_failures;    // Simulate random thread failures
  float thread_failure_rate;        // Probability of thread failure (0.0-1.0)
  int custom_thread_group_size[3];  // Custom threadgroup size
                                    // [width,height,depth]
  int custom_grid_size[3];          // Custom grid size [width,height,depth]
  const char *thread_order_file;    // File specifying custom thread order
} ThreadControlConfig;

typedef struct {
  bool enabled;
  bool print_variables;
  bool step_by_step;
  bool break_before_dispatch;
  int verbosity_level;
  size_t breakpoint_count;
  Breakpoint *breakpoints;
  ErrorHandlingConfig error_config;
  ErrorCollector error_collector;
  TimelineConfig timeline;
  TimelineEvent *events;
  size_t event_count;
  LowEndGpuSimulation low_end_gpu;
  AsyncCommandDebugExtension async_debug;
  ThreadControlConfig thread_control;
} DebugConfig;

typedef enum {
  PIPELINE_TYPE_COMPUTE, // Default
  PIPELINE_TYPE_RENDERER // Graphics pipeline
} PipelineType;

typedef struct {
  const char *metallib_path;
  const char *function_name;
  NSMutableArray *buffers;
  NSMutableArray *image_buffers; // New field for image buffers
  DebugConfig debug;
  struct {
    bool enabled;
    const char *log_file_path;
    int log_level; // 0=errors only, 1=warnings, 2=info, 3=debug
    bool log_timestamps;
  } logging;
  PipelineType pipeline_type;
} ProfilerConfig;

void print_error_summary(DebugConfig *debug);
void record_error(DebugConfig *debug, ErrorSeverity severity,
                  ErrorCategory category, const char *message,
                  const char *location);
void cleanup_error_collector(ErrorCollector *collector);
void init_error_collector(ErrorCollector *collector, size_t initial_capacity);
void check_breakpoints(DebugConfig *debug, const char *stage);
void print_buffer_state(id<MTLBuffer> buffer, const char *name, size_t size);
void load_error_config(DebugConfig *debug, NSDictionary *debugConfig);
size_t write_callback(void *contents, size_t size, size_t nmemb, void *userp);
id<MTLBuffer> create_buffer_with_error_checking(id<MTLDevice> device,
                                                BufferConfig *config,
                                                DebugConfig *debug);
void load_thread_control_config(DebugConfig *debug, NSDictionary *debugConfig);

void configure_thread_execution(id<MTLComputeCommandEncoder> encoder,
                                DebugConfig *debug, MTLSize *originalGridSize,
                                MTLSize *originalThreadGroupSize);
void generate_async_command_timeline(AsyncCommandDebugExtension *ext);
void track_async_command(AsyncCommandDebugExtension *ext,
                         id<MTLCommandBuffer> commandBuffer, const char *name);
void simulate_advanced_low_end_gpu(LowEndGpuSimulation *sim,
                                   id<MTLComputeCommandEncoder> encoder,
                                   MTLSize *gridSize, MTLSize *threadGroupSize);
size_t simulate_bandwidth_limited_transfer(void *source, void *destination,
                                           size_t total_size,
                                           LowEndGpuSimulation *sim);
bool is_compute_unit_available(LowEndGpuSimulation *sim, int unit_index);
size_t simulate_bandwidth_limited_transfer(void *source, void *destination,
                                           size_t total_size,
                                           LowEndGpuSimulation *sim);
void inject_memory_transfer_errors(MemoryTransfer *transfer,
                                   LowEndGpuSimulation *sim);

ProfilerConfig *load_config(const char *config_path);
void initialize_buffer(id<MTLBuffer> buffer, BufferConfig *config);
int compare_versions(const char *version1, const char *version2);
char *fetch_latest_version(void);
static double getProgramCPUUsage(void);
static NSString *getStackTrace();
static void getProgramMemoryUsage(uint64_t *residentMemory,
                                  uint64_t *virtualMemory);
void getKernelStats(id<MTLComputePipelineState> pipelineState,
                    uint64_t *activeWarps, uint64_t *threadBlockSize);
int remove_plugin(const char *plugin_name);
int add_plugin(const char *plugin_source);
void init_log_file(ProfilerConfig *config);
void log_message(ProfilerConfig *config, int level, const char *category,
                 const char *format, ...);
void initialize_image_buffers(id<MTLDevice> device, ProfilerConfig *config);
void image_to_buffer(NSString *imagePath, id<MTLBuffer> buffer, size_t width,
                     size_t height);
void simulate_low_end_gpu_rendering(LowEndGpuSimulation *sim,
                                    id<MTLRenderCommandEncoder> encoder,
                                    NSUInteger vertexCount,
                                    NSUInteger instanceCount);
void generate_buffer_heatmap(id<MTLBuffer> buffer, const char *buffer_name,
                             bool before_execution);
bool can_visualize_as_image(id<MTLBuffer> buffer, size_t width, size_t height);
void generate_buffer_image(id<MTLBuffer> buffer, const char *buffer_name,
                           bool before_execution, size_t width, size_t height);
void generate_buffer_surface_plot(id<MTLBuffer> buffer, const char *buffer_name,
                                  bool before_execution, size_t width,
                                  size_t height);
void generate_buffer_histogram(id<MTLBuffer> buffer, const char *buffer_name,
                               bool before_execution);
void generate_all_buffer_visualizations(id<MTLBuffer> buffer,
                                        const char *buffer_name,
                                        bool before_execution);
RenderPipelineStats collect_render_pipeline_statistics(
    id<MTLCommandBuffer> commandBuffer,
    id<MTLRenderPipelineState> pipelineState,
    MTLRenderPassDescriptor *renderPassDescriptor, NSUInteger vertexCount,
    NSUInteger instanceCount, NSUInteger drawCallCount);
#endif /* gpumkat.h */