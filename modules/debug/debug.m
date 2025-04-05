#include "expose_to_debug.h"

void profile_command_buffer(id<MTLCommandBuffer> commandBuffer,
                            const char *name) {
  // Start profiling
  NSDate *startTime = [NSDate date];

  [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
    NSDate *endTime = [NSDate date];
    NSTimeInterval elapsed = [endTime timeIntervalSinceDate:startTime];

    if (buffer.error) {
      NSLog(@"Error in command buffer '%s': %@", name, buffer.error);
      return;
    }

    NSLog(@"Command Buffer '%s' execution time: %.6f seconds", name, elapsed);
  }];

  [commandBuffer commit];
}

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
  float fillrate_reduction;        // 0.0-1.0 (percentage of reduction)
  float texture_quality_reduction; // 0.0-1.0 (percentage of reduction)
  bool reduce_draw_distance;       // Whether to simulate reduced draw distance
  float draw_distance_factor; // 0.0-1.0 (percentage of normal draw distance)
} RenderingSimulation;

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

  RenderingSimulation rendering;
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

void debug_pause(const char *message) {
  printf("\n[DEBUG PAUSE] %s\nPress Enter to continue...", message);
  getchar();
}

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

typedef struct {
  const char *name;
  const char *image_path;
  size_t width;     // Can be 0 for auto-detection
  size_t height;    // Can be 0 for auto-detection
  const char *type; // Type of buffer (e.g., "float")
} ImageBufferConfig;

void print_buffer_state(id<MTLBuffer> buffer, const char *name, size_t size) {
  float *data = (float *)[buffer contents];
  printf("\nBuffer State - %s:\n", name);
  printf("Address: %p\n", (void *)buffer);
  printf("Size: %zu bytes\n", size);
  printf("First 10 elements: ");
  for (int i = 0; i < MIN(10, size / sizeof(float)); i++) {
    printf("%.2f ", data[i]);
  }
  printf("\n");
}

void check_breakpoints(DebugConfig *debug, const char *stage) {
  if (!debug->enabled || !debug->breakpoint_count)
    return;

  for (size_t i = 0; i < debug->breakpoint_count; i++) {
    Breakpoint *bp = &debug->breakpoints[i];
    if (strcmp(bp->condition, stage) == 0) {
      NSLog(@"[BREAKPOINT] Hit breakpoint: %s", bp->description);
      debug_pause("Paused at breakpoint");
    }
  }
}

void init_error_collector(ErrorCollector *collector, size_t initial_capacity) {
  collector->errors = malloc(sizeof(ErrorRecord) * initial_capacity);
  collector->error_count = 0;
  collector->capacity = initial_capacity;
}

// Record an error
void record_error(DebugConfig *debug, ErrorSeverity severity,
                  ErrorCategory category, const char *message,
                  const char *location) {
  if (!debug->enabled || severity < debug->error_config.min_severity) {
    return;
  }

  ErrorCollector *collector = &debug->error_collector;

  // Expand capacity if needed
  if (collector->error_count >= collector->capacity) {
    size_t new_capacity = collector->capacity * 2;
    ErrorRecord *new_errors =
        realloc(collector->errors, sizeof(ErrorRecord) * new_capacity);
    if (!new_errors) {
      NSLog(@"Failed to expand error collector capacity");
      return;
    }
    collector->errors = new_errors;
    collector->capacity = new_capacity;
  }

  // Record the error
  ErrorRecord *record = &collector->errors[collector->error_count++];
  record->severity = severity;
  record->category = category;
  record->message = strdup(message);
  record->location = strdup(location);
  record->timestamp = get_time();

  // Log error based on verbosity
  if (debug->verbosity_level > 0) {
    NSLog(@"[%s] %s: %s",
          severity == ERROR_SEVERITY_WARNING ? "WARNING" : "ERROR", location,
          message);
  }

  // Break if configured
  if (debug->error_config.break_on_error && severity >= ERROR_SEVERITY_ERROR) {
    debug_pause("Execution paused due to error");
  }
}

void load_error_config(DebugConfig *debug, NSDictionary *debugConfig) {
  NSDictionary *errorConfig = debugConfig[@"error_handling"];
  if (errorConfig) {
    debug->error_config.catch_warnings =
        [errorConfig[@"catch_warnings"] boolValue];
    debug->error_config.catch_memory_errors =
        [errorConfig[@"catch_memory_errors"] boolValue];
    debug->error_config.catch_shader_errors =
        [errorConfig[@"catch_shader_errors"] boolValue];
    debug->error_config.catch_validation_errors =
        [errorConfig[@"catch_validation_errors"] boolValue];
    debug->error_config.break_on_error =
        [errorConfig[@"break_on_error"] boolValue];
    debug->error_config.max_error_count =
        [errorConfig[@"max_error_count"] intValue];
    debug->error_config.min_severity = [errorConfig[@"min_severity"] intValue];
  } else {
    // Default error handling settings
    debug->error_config.catch_warnings = true;
    debug->error_config.catch_memory_errors = true;
    debug->error_config.catch_shader_errors = true;
    debug->error_config.catch_validation_errors = true;
    debug->error_config.break_on_error = false;
    debug->error_config.max_error_count = 100;
    debug->error_config.min_severity = ERROR_SEVERITY_WARNING;
  }

  // Initialize error collector
  init_error_collector(&debug->error_collector,
                       debug->error_config.max_error_count);
}

void cleanup_error_collector(ErrorCollector *collector) {
  for (size_t i = 0; i < collector->error_count; i++) {
    free((void *)collector->errors[i].message);
    free((void *)collector->errors[i].location);
  }
  free(collector->errors);
  collector->errors = NULL;
  collector->error_count = 0;
  collector->capacity = 0;
}

void print_error_summary(DebugConfig *debug) {
  if (!debug->enabled)
    return;

  ErrorCollector *collector = &debug->error_collector;

  NSLog(@"\n=== Error Summary ===");
  NSLog(@"Total Errors: %zu", collector->error_count);

  int warnings = 0, errors = 0, fatal = 0;
  for (size_t i = 0; i < collector->error_count; i++) {
    switch (collector->errors[i].severity) {
    case ERROR_SEVERITY_WARNING:
      warnings++;
      break;
    case ERROR_SEVERITY_ERROR:
      errors++;
      break;
    case ERROR_SEVERITY_FATAL:
      fatal++;
      break;
    default:
      break;
    }
  }

  NSLog(@"Warnings: %d", warnings);
  NSLog(@"Errors: %d", errors);
  NSLog(@"Fatal Errors: %d", fatal);
}

void inject_memory_transfer_errors(MemoryTransfer *transfer,
                                   LowEndGpuSimulation *sim) {
  if (!sim->memory.memory_error_rate)
    return;

  // Probabilistic error injection
  float error_probability = ((float)rand() / RAND_MAX);
  if (error_probability < sim->memory.memory_error_rate) {
    // Simulate partial data corruption
    size_t corruption_start = rand() % transfer->transfer_size;
    size_t corruption_length =
        rand() % (transfer->transfer_size - corruption_start);

    uint8_t *buffer = (uint8_t *)transfer->destination_buffer;
    for (size_t i = corruption_start; i < corruption_start + corruption_length;
         i++) {
      buffer[i] = rand() % 256; // Random byte
    }

    transfer->transfer_quality *= (1.0 - sim->memory.memory_error_rate);

    NSLog(@"[LOW-END GPU SIM] Memory Transfer Error Injected: %zu bytes "
          @"corrupted",
          corruption_length);
  }
}

size_t simulate_bandwidth_limited_transfer(void *source, void *destination,
                                           size_t total_size,
                                           LowEndGpuSimulation *sim) {
  if (!sim->memory.bandwidth_reduction)
    return total_size;

  // Calculate effective bandwidth
  size_t max_transfer_size =
      (size_t)(total_size * (1.0 - sim->memory.bandwidth_reduction));

  // Simulate transfer with latency
  struct timespec transfer_delay;
  transfer_delay.tv_sec = 0;
  transfer_delay.tv_nsec =
      (long)(sim->memory.latency_multiplier * 10000000); // Base 10ms latency

  nanosleep(&transfer_delay, NULL);

  // Partial transfer simulation
  memcpy(destination, source, max_transfer_size);

  MemoryTransfer transfer = {.source_buffer = source,
                             .destination_buffer = destination,
                             .transfer_size = max_transfer_size,
                             .transfer_completed = true,
                             .transfer_quality = 1.0};

  // Potentially inject transfer errors
  inject_memory_transfer_errors(&transfer, sim);

  NSLog(@"[LOW-END GPU SIM] Bandwidth Limited Transfer: %zu of %zu bytes "
        @"(Quality: %.2f)",
        max_transfer_size, total_size, transfer.transfer_quality);

  return max_transfer_size;
}

bool is_compute_unit_available(LowEndGpuSimulation *sim, int unit_index) {
  // Probabilistic compute unit availability
  float availability = sim->compute.processing_units_availability;
  float random_check = ((float)rand() / RAND_MAX);

  // Simulate specific compute unit failures
  if (unit_index < sim->compute.compute_unit_failures) {
    return false;
  }

  return random_check <= availability;
}

void simulate_low_end_gpu(LowEndGpuSimulation *sim,
                          id<MTLComputeCommandEncoder> encoder,
                          MTLSize *gridSize, MTLSize *threadGroupSize) {
  if (!sim->enabled)
    return;

  NSLog(@"\n=== Advanced Low-End GPU Simulation ===");

  MTLSize originalGridSize = *gridSize;
  MTLSize simulatedThreadGroupSize = *threadGroupSize;
  MTLSize simulatedGridSize = *gridSize;

  float execution_delay_factor = 1.0;

  simulatedGridSize.width =
      MAX(1, (NSUInteger)(originalGridSize.width *
                          sim->compute.processing_units_availability));
  simulatedGridSize.height =
      MAX(1, (NSUInteger)(originalGridSize.height *
                          sim->compute.processing_units_availability));
  simulatedGridSize.depth =
      MAX(1, (NSUInteger)(originalGridSize.depth *
                          sim->compute.processing_units_availability));

  NSUInteger pass_count_width =
      ceil((float)originalGridSize.width / simulatedGridSize.width);
  NSUInteger pass_count_height =
      ceil((float)originalGridSize.height / simulatedGridSize.height);
  NSUInteger pass_count_depth =
      ceil((float)originalGridSize.depth / simulatedGridSize.depth);
  NSUInteger total_passes =
      pass_count_width * pass_count_height * pass_count_depth;

  if (sim->compute.clock_speed_reduction > 0) {
    execution_delay_factor *= (1.0 + sim->compute.clock_speed_reduction);
    NSLog(@"Clock Speed Reduced: %.2f%% (Delay Factor: %.2fx)",
          sim->compute.clock_speed_reduction * 100, execution_delay_factor);
  }

  if (sim->memory.bandwidth_reduction > 0) {
    execution_delay_factor *=
        (1.0 + sim->memory.bandwidth_reduction *
                   1.5); // 1.5x multiplier for compounding effects
    NSLog(@"Memory Bandwidth Reduced: %.2f%%",
          sim->memory.bandwidth_reduction * 100);
  }

  if (sim->thermal.enable_thermal_simulation) {
    float workload_factor = (originalGridSize.width * originalGridSize.height *
                             originalGridSize.depth) /
                            (1000000.0); // Normalize to reasonable number

    float simulated_temperature =
        60.0 + (workload_factor * 20.0) + (rand() % 10);

    if (simulated_temperature >= sim->thermal.thermal_throttling_threshold) {
      float throttle_factor =
          1.0 +
          ((simulated_temperature - sim->thermal.thermal_throttling_threshold) /
           10.0);

      execution_delay_factor *= throttle_factor;

      NSLog(@"Thermal Throttling Activated at %.1f°C (Throttle Factor: %.2fx)",
            simulated_temperature, throttle_factor);
    }
  }

  if (sim->logging.detailed_logging) {
    FILE *log_file = fopen(sim->logging.log_file_path, "a");
    if (log_file) {
      fprintf(log_file, "Simulation Details:\n");
      fprintf(log_file, "Original Grid Size: %lu x %lu x %lu\n",
              (unsigned long)originalGridSize.width,
              (unsigned long)originalGridSize.height,
              (unsigned long)originalGridSize.depth);
      fprintf(log_file, "Simulated Grid Size: %lu x %lu x %lu\n",
              (unsigned long)simulatedGridSize.width,
              (unsigned long)simulatedGridSize.height,
              (unsigned long)simulatedGridSize.depth);
      fprintf(log_file, "Total Passes Required: %lu\n",
              (unsigned long)total_passes);
      fprintf(log_file, "Execution Delay Factor: %.2fx\n",
              execution_delay_factor);
      fclose(log_file);
    }
  }

  for (NSUInteger pass = 0; pass < total_passes; pass++) {
    if (execution_delay_factor > 1.0) {
      uint64_t delay_microseconds = (uint64_t)(1000 * execution_delay_factor);
      usleep(delay_microseconds); // Actually insert delay proportional to
                                  // simulation factors
    }

    // Dispatch with simulated constraints
    [encoder dispatchThreads:simulatedGridSize
        threadsPerThreadgroup:simulatedThreadGroupSize];
  }

  NSLog(@"Simulation Complete - Total Impact Factor: %.2fx slower",
        execution_delay_factor * total_passes);
}

void simulate_low_end_gpu_rendering(LowEndGpuSimulation *sim,
                                    id<MTLRenderCommandEncoder> encoder,
                                    NSUInteger vertexCount,
                                    NSUInteger instanceCount) {
  if (!sim->enabled)
    return;

  NSLog(@"\n=== Advanced Low-End GPU Rendering Simulation ===");

  // Original rendering parameters
  NSUInteger originalVertexCount = vertexCount;
  NSUInteger originalInstanceCount = instanceCount;

  // Simulated rendering parameters
  NSUInteger simulatedInstanceCount = instanceCount;
  NSUInteger simulatedVertexCount = vertexCount;

  // Calculate actual execution delay factor
  float execution_delay_factor = 1.0;

  float processing_capacity = sim->compute.processing_units_availability;
  simulatedInstanceCount =
      MAX(1, (NSUInteger)(originalInstanceCount * processing_capacity));

  // Calculate how many passes we need to cover the original work
  NSUInteger total_instance_passes =
      ceil((float)originalInstanceCount / simulatedInstanceCount);

  if (sim->compute.clock_speed_reduction > 0) {
    execution_delay_factor *= (1.0 + sim->compute.clock_speed_reduction);
    NSLog(@"Shader Clock Speed Reduced: %.2f%% (Delay Factor: %.2fx)",
          sim->compute.clock_speed_reduction * 100, execution_delay_factor);
  }

  if (sim->memory.bandwidth_reduction > 0) {
    // Texture sampling is heavily affected by memory bandwidth
    execution_delay_factor *= (1.0 + sim->memory.bandwidth_reduction * 2.0);
    NSLog(@"Texture Bandwidth Reduced: %.2f%%",
          sim->memory.bandwidth_reduction * 100);
  }

  if (sim->rendering.fillrate_reduction > 0) {
    execution_delay_factor *= (1.0 + sim->rendering.fillrate_reduction);
    NSLog(@"Fillrate Reduced: %.2f%%", sim->rendering.fillrate_reduction * 100);
  }

  if (sim->thermal.enable_thermal_simulation) {
    // Base temperature + workload factor + randomness for realism
    float workload_factor = (originalVertexCount * originalInstanceCount) /
                            (100000.0); // Normalize to reasonable number

    float simulated_temperature =
        60.0 + (workload_factor * 20.0) + (rand() % 10);

    if (simulated_temperature >= sim->thermal.thermal_throttling_threshold) {
      float throttle_factor =
          1.0 +
          ((simulated_temperature - sim->thermal.thermal_throttling_threshold) /
           10.0);

      execution_delay_factor *= throttle_factor;

      // In extreme thermal conditions, also reduce vertex detail
      if (simulated_temperature >
          sim->thermal.thermal_throttling_threshold + 15.0) {
        // Reduce vertex count (simulating LOD reduction under thermal stress)
        simulatedVertexCount =
            MAX(4, (NSUInteger)(simulatedVertexCount * 0.75));
        NSLog(@"Thermal Emergency: Vertex count reduced to %.0f%%",
              ((float)simulatedVertexCount / originalVertexCount) * 100);
      }

      NSLog(@"Thermal Throttling Activated at %.1f°C (Throttle Factor: %.2fx)",
            simulated_temperature, throttle_factor);
    }
  }

  if (sim->logging.detailed_logging) {
    FILE *log_file = fopen(sim->logging.log_file_path, "a");
    if (log_file) {
      fprintf(log_file, "Rendering Simulation Details:\n");
      fprintf(log_file, "Original Instance Count: %lu\n",
              (unsigned long)originalInstanceCount);
      fprintf(log_file, "Original Vertex Count: %lu\n",
              (unsigned long)originalVertexCount);
      fprintf(log_file, "Simulated Instance Count: %lu\n",
              (unsigned long)simulatedInstanceCount);
      fprintf(log_file, "Simulated Vertex Count: %lu\n",
              (unsigned long)simulatedVertexCount);
      fprintf(log_file, "Total Instance Passes Required: %lu\n",
              (unsigned long)total_instance_passes);
      fprintf(log_file, "Execution Delay Factor: %.2fx\n",
              execution_delay_factor);
      fclose(log_file);
    }
  }

  for (NSUInteger pass = 0; pass < total_instance_passes; pass++) {
    NSUInteger instance_offset = pass * simulatedInstanceCount;
    NSUInteger instances_this_pass =
        MIN(simulatedInstanceCount, originalInstanceCount - instance_offset);

    if (execution_delay_factor > 1.0) {
      uint64_t delay_microseconds = (uint64_t)(1000 * execution_delay_factor);
      usleep(delay_microseconds);
    }

    [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                vertexStart:0
                vertexCount:simulatedVertexCount
              instanceCount:instances_this_pass];
  }

  NSLog(@"Rendering Simulation Complete - Total Impact Factor: %.2fx slower",
        execution_delay_factor * total_instance_passes);
}

void track_async_command(AsyncCommandDebugExtension *ext,
                         id<MTLCommandBuffer> commandBuffer, const char *name) {
  if (!ext->config.enable_async_tracking ||
      ext->command_count >= MAX_ASYNC_COMMANDS) {
    return;
  }

  AsyncCommandTracker *tracker = &ext->commands[ext->command_count++];
  tracker->command_buffer = commandBuffer;
  tracker->submission_time = [NSDate date];
  tracker->name = strdup(name);
  tracker->is_completed = false;
  tracker->has_errors = false;

  [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
    tracker->completion_time = [NSDate date];
    tracker->is_completed = true;
    tracker->execution_time = [tracker->completion_time
        timeIntervalSinceDate:tracker->submission_time];
    tracker->has_errors = (buffer.error != nil);

    // Log long-running commands
    if (ext->config.detect_long_running_commands &&
        tracker->execution_time > ext->config.long_command_threshold) {
      NSLog(@"[ASYNC DEBUG] Long-running command detected: %s", tracker->name);
      NSLog(@"Execution Time: %.4f seconds", tracker->execution_time);
    }

    // Log command status if enabled
    if (ext->config.log_command_status) {
      NSLog(@"[ASYNC DEBUG] Command '%s' status:", tracker->name);
      NSLog(@"  Completed: %@", tracker->is_completed ? @"Yes" : @"No");
      NSLog(@"  Errors: %@", tracker->has_errors ? @"Yes" : @"No");
      NSLog(@"  Execution Time: %.4f seconds", tracker->execution_time);
    }
  }];
}

void generate_async_command_timeline(AsyncCommandDebugExtension *ext) {
  if (!ext->config.generate_async_timeline)
    return;

  FILE *timeline_file = fopen("async_command_timeline.json", "w");
  if (!timeline_file) {
    NSLog(@"Failed to create async command timeline file");
    return;
  }

  fprintf(timeline_file, "[\n");
  for (size_t i = 0; i < ext->command_count; i++) {
    AsyncCommandTracker *cmd = &ext->commands[i];
    fprintf(timeline_file,
            "{\"name\": \"%s\", \"start\": %.6f, \"end\": %.6f, \"duration\": "
            "%.6f, "
            "\"completed\": %s, \"errors\": %s}%s\n",
            cmd->name, [cmd->submission_time timeIntervalSince1970],
            [cmd->completion_time timeIntervalSince1970], cmd -> execution_time,
            cmd -> is_completed ? "true" : "false",
            cmd->has_errors ? "true" : "false",
            (i < ext->command_count - 1) ? "," : "");
  }
  fprintf(timeline_file, "]\n");
  fclose(timeline_file);
}

void configure_thread_execution(id<MTLComputeCommandEncoder> encoder,
                                DebugConfig *debug, MTLSize *originalGridSize,
                                MTLSize *originalThreadGroupSize) {
  if (!debug->enabled || !debug->thread_control.enable_thread_debugging) {
    [encoder dispatchThreads:*originalGridSize
        threadsPerThreadgroup:*originalThreadGroupSize];
    return;
  }

  MTLSize gridSize = *originalGridSize;
  MTLSize threadGroupSize = *originalThreadGroupSize;

  // Apply custom sizes if specified
  if (debug->thread_control.custom_thread_group_size[0] > 0) {
    threadGroupSize =
        MTLSizeMake(debug->thread_control.custom_thread_group_size[0],
                    debug->thread_control.custom_thread_group_size[1],
                    debug->thread_control.custom_thread_group_size[2]);
  }

  if (debug->thread_control.custom_grid_size[0] > 0) {
    gridSize = MTLSizeMake(debug->thread_control.custom_grid_size[0],
                           debug->thread_control.custom_grid_size[1],
                           debug->thread_control.custom_grid_size[2]);
  }

  // Log configuration if enabled
  if (debug->thread_control.log_thread_execution) {
    NSLog(@"Thread Control Configuration:");
    NSLog(@"  Dispatch Mode: %d", debug->thread_control.dispatch_mode);
    NSLog(@"  Grid Size: %lux%lux%lu", gridSize.width, gridSize.height,
          gridSize.depth);
    NSLog(@"  ThreadGroup Size: %lux%lux%lu", threadGroupSize.width,
          threadGroupSize.height, threadGroupSize.depth);
  }

  // Dispatch based on selected mode
  switch (debug->thread_control.dispatch_mode) {
  case THREAD_DISPATCH_DEFAULT:
    [encoder dispatchThreads:gridSize threadsPerThreadgroup:threadGroupSize];
    break;

  case THREAD_DISPATCH_LINEAR: {
    // Linear dispatch by splitting into smaller groups
    NSUInteger totalThreads = gridSize.width * gridSize.height * gridSize.depth;
    NSUInteger threadsPerDispatch =
        threadGroupSize.width * threadGroupSize.height * threadGroupSize.depth;

    for (NSUInteger i = 0; i < totalThreads; i += threadsPerDispatch) {
      NSUInteger remaining = totalThreads - i;
      NSUInteger thisDispatch = MIN(remaining, threadsPerDispatch);

      MTLSize linearGrid = MTLSizeMake(thisDispatch, 1, 1);
      [encoder dispatchThreads:linearGrid
          threadsPerThreadgroup:threadGroupSize];

      if (debug->thread_control.log_thread_execution) {
        NSLog(@"Dispatched linear group %lu-%lu", i, i + thisDispatch - 1);
      }
    }
    break;
  }

  case THREAD_DISPATCH_REVERSE: {
    // Reverse dispatch by splitting into smaller groups
    NSUInteger totalThreads = gridSize.width * gridSize.height * gridSize.depth;
    NSUInteger threadsPerDispatch =
        threadGroupSize.width * threadGroupSize.height * threadGroupSize.depth;

    for (NSUInteger i = totalThreads; i > 0; i -= MIN(i, threadsPerDispatch)) {
      NSUInteger start = i > threadsPerDispatch ? i - threadsPerDispatch : 0;
      NSUInteger count = i > threadsPerDispatch ? threadsPerDispatch : i;

      MTLSize reverseGrid = MTLSizeMake(count, 1, 1);
      [encoder dispatchThreads:reverseGrid
          threadsPerThreadgroup:threadGroupSize];

      if (debug->thread_control.log_thread_execution) {
        NSLog(@"Dispatched reverse group %lu-%lu", start, start + count - 1);
      }
    }
    break;
  }

  case THREAD_DISPATCH_RANDOM: {
    // Random dispatch by shuffling threadgroup order
    NSUInteger xGroups =
        (gridSize.width + threadGroupSize.width - 1) / threadGroupSize.width;
    NSUInteger yGroups =
        (gridSize.height + threadGroupSize.height - 1) / threadGroupSize.height;
    NSUInteger zGroups =
        (gridSize.depth + threadGroupSize.depth - 1) / threadGroupSize.depth;
    NSUInteger totalGroups = xGroups * yGroups * zGroups;

    // Create and shuffle group indices
    NSUInteger *groupIndices = malloc(totalGroups * sizeof(NSUInteger));
    for (NSUInteger i = 0; i < totalGroups; i++) {
      groupIndices[i] = i;
    }

    // Fisher-Yates shuffle
    for (NSUInteger i = totalGroups - 1; i > 0; i--) {
      NSUInteger j = arc4random_uniform((uint32_t)(i + 1));
      NSUInteger temp = groupIndices[i];
      groupIndices[i] = groupIndices[j];
      groupIndices[j] = temp;
    }

    // Dispatch in random order
    for (NSUInteger g = 0; g < totalGroups; g++) {
      NSUInteger groupIdx = groupIndices[g];
      NSUInteger z = groupIdx / (xGroups * yGroups);
      NSUInteger y = (groupIdx % (xGroups * yGroups)) / xGroups;
      NSUInteger x = groupIdx % xGroups;

      MTLSize groupOrigin =
          MTLSizeMake(x * threadGroupSize.width, y * threadGroupSize.height,
                      z * threadGroupSize.depth);

      MTLSize groupSize = MTLSizeMake(
          MIN(threadGroupSize.width, gridSize.width - groupOrigin.width),
          MIN(threadGroupSize.height, gridSize.height - groupOrigin.height),
          MIN(threadGroupSize.depth, gridSize.depth - groupOrigin.depth));

      [encoder dispatchThreadgroups:MTLSizeMake(1, 1, 1)
              threadsPerThreadgroup:groupSize];

      if (debug->thread_control.log_thread_execution) {
        NSLog(@"Dispatched random group %lu at (%lu,%lu,%lu)", groupIdx, x, y,
              z);
      }
    }

    free(groupIndices);
    break;
  }

  case THREAD_DISPATCH_ALTERNATING: {
    // Alternating pattern (even/odd)
    NSUInteger totalThreads = gridSize.width * gridSize.height * gridSize.depth;
    NSUInteger threadsPerDispatch =
        threadGroupSize.width * threadGroupSize.height * threadGroupSize.depth;

    // First pass: even groups
    for (NSUInteger i = 0; i < totalThreads; i += threadsPerDispatch * 2) {
      NSUInteger remaining = totalThreads - i;
      NSUInteger thisDispatch = MIN(remaining, threadsPerDispatch);

      MTLSize evenGrid = MTLSizeMake(thisDispatch, 1, 1);
      [encoder dispatchThreads:evenGrid threadsPerThreadgroup:threadGroupSize];

      if (debug->thread_control.log_thread_execution) {
        NSLog(@"Dispatched even group %lu-%lu", i, i + thisDispatch - 1);
      }
    }

    // Second pass: odd groups
    for (NSUInteger i = threadsPerDispatch; i < totalThreads;
         i += threadsPerDispatch * 2) {
      NSUInteger remaining = totalThreads - i;
      NSUInteger thisDispatch = MIN(remaining, threadsPerDispatch);

      MTLSize oddGrid = MTLSizeMake(thisDispatch, 1, 1);
      [encoder dispatchThreads:oddGrid threadsPerThreadgroup:threadGroupSize];

      if (debug->thread_control.log_thread_execution) {
        NSLog(@"Dispatched odd group %lu-%lu", i, i + thisDispatch - 1);
      }
    }
    break;
  }

  case THREAD_DISPATCH_CUSTOM:
    if (debug->thread_control.thread_order_file) {
      FILE *file = fopen(debug->thread_control.thread_order_file, "r");
      if (file) {
        char line[256];
        int lineNum = 0;

        // First count lines to allocate memory
        int totalDispatches = 0;
        while (fgets(line, sizeof(line), file)) {
          if (strlen(line) > 1)
            totalDispatches++;
        }
        rewind(file);

        // Allocate dispatch info array
        typedef struct {
          uint32_t x, y, z;
          uint32_t count;
        } DispatchInfo;

        DispatchInfo *dispatches =
            malloc(totalDispatches * sizeof(DispatchInfo));
        int dispatchIndex = 0;

        // Parse file
        while (fgets(line, sizeof(line), file)) {
          lineNum++;
          if (strlen(line) <= 1)
            continue; // Skip empty lines

          DispatchInfo di = {0};
          int parsed =
              sscanf(line, "%u,%u,%u,%u", &di.x, &di.y, &di.z, &di.count);

          if (parsed == 4) {
            // Validate coordinates
            if (di.x >= gridSize.width || di.y >= gridSize.height ||
                di.z >= gridSize.depth) {
              NSLog(@"Warning: Line %d coordinates (%u,%u,%u) exceed grid size",
                    lineNum, di.x, di.y, di.z);
              continue;
            }

            // Validate count
            if (di.count == 0 || di.count > threadGroupSize.width *
                                                threadGroupSize.height *
                                                threadGroupSize.depth) {
              NSLog(@"Warning: Line %d count %u exceeds threadgroup size",
                    lineNum, di.count);
              di.count = threadGroupSize.width; // Default to threadgroup width
            }

            dispatches[dispatchIndex++] = di;
          } else {
            NSLog(@"Error parsing line %d: %s", lineNum, line);
          }
        }
        fclose(file);

        // Execute dispatches in file order
        for (int i = 0; i < dispatchIndex; i++) {
          DispatchInfo di = dispatches[i];

          // Calculate actual threads to dispatch (don't exceed grid bounds)
          uint32_t actualCount = MIN(di.count, gridSize.width - di.x);
          if (actualCount == 0)
            continue;

          MTLSize customGrid = MTLSizeMake(actualCount, 1, 1);
          MTLSize customGroup =
              MTLSizeMake(MIN(threadGroupSize.width, actualCount),
                          threadGroupSize.height, threadGroupSize.depth);

          // Set thread position if shader expects it
          uint32_t threadPosition[3] = {di.x, di.y, di.z};
          [encoder setBytes:threadPosition
                     length:sizeof(threadPosition)
                    atIndex:14];

          [encoder dispatchThreads:customGrid
              threadsPerThreadgroup:customGroup];

          if (debug->thread_control.log_thread_execution) {
            NSLog(@"Dispatched custom group %d: (%u,%u,%u) count %u", i, di.x,
                  di.y, di.z, actualCount);
          }
        }

        free(dispatches);
      } else {
        NSLog(@"Failed to open thread order file: %s",
              debug->thread_control.thread_order_file);
        [encoder dispatchThreads:gridSize
            threadsPerThreadgroup:threadGroupSize];
      }
    } else {
      [encoder dispatchThreads:gridSize threadsPerThreadgroup:threadGroupSize];
    }
    break;
  }
}

void load_thread_control_config(DebugConfig *debug, NSDictionary *debugConfig) {
  NSDictionary *threadConfig = debugConfig[@"thread_control"];
  if (threadConfig) {
    debug->thread_control.enable_thread_debugging =
        [threadConfig[@"enable_thread_debugging"] boolValue];
    debug->thread_control.dispatch_mode =
        [threadConfig[@"dispatch_mode"] intValue];
    debug->thread_control.log_thread_execution =
        [threadConfig[@"log_thread_execution"] boolValue];
    debug->thread_control.validate_thread_access =
        [threadConfig[@"validate_thread_access"] boolValue];
    debug->thread_control.simulate_thread_failures =
        [threadConfig[@"simulate_thread_failures"] boolValue];
    debug->thread_control.thread_failure_rate =
        [threadConfig[@"thread_failure_rate"] floatValue];

    // Load custom sizes
    NSArray *customThreadGroup = threadConfig[@"custom_thread_group_size"];
    if (customThreadGroup && customThreadGroup.count == 3) {
      for (int i = 0; i < 3; i++) {
        debug->thread_control.custom_thread_group_size[i] =
            [customThreadGroup[i] intValue];
      }
    }

    NSArray *customGrid = threadConfig[@"custom_grid_size"];
    if (customGrid && customGrid.count == 3) {
      for (int i = 0; i < 3; i++) {
        debug->thread_control.custom_grid_size[i] = [customGrid[i] intValue];
      }
    }

    // Load thread order file path
    NSString *threadOrderFile = threadConfig[@"thread_order_file"];
    if (threadOrderFile) {
      debug->thread_control.thread_order_file =
          strdup([threadOrderFile UTF8String]);
    }
  } else {
    // Default thread control settings
    debug->thread_control.enable_thread_debugging = false;
    debug->thread_control.dispatch_mode = THREAD_DISPATCH_DEFAULT;
    debug->thread_control.log_thread_execution = false;
    debug->thread_control.validate_thread_access = false;
    debug->thread_control.simulate_thread_failures = false;
    debug->thread_control.thread_failure_rate = 0.0;
    memset(debug->thread_control.custom_thread_group_size, 0, sizeof(int) * 3);
    memset(debug->thread_control.custom_grid_size, 0, sizeof(int) * 3);
    debug->thread_control.thread_order_file = NULL;
  }
}

void log_message(ProfilerConfig *config, int level, const char *category,
                 const char *format, ...) {
  if (!config->logging.enabled || level > config->logging.log_level) {
    return;
  }

  FILE *log_file = fopen(config->logging.log_file_path, "a");
  if (!log_file) {
    // If we can't open the log file, fall back to console
    fprintf(stderr, "Warning: Could not open log file %s\n",
            config->logging.log_file_path);
    log_file = stderr;
  }

  char timestamp[64] = "";
  if (config->logging.log_timestamps) {
    time_t now = time(NULL);
    struct tm *timeinfo = localtime(&now);
    strftime(timestamp, sizeof(timestamp), "[%Y-%m-%d %H:%M:%S] ", timeinfo);
  }

  char level_str[10] = "";
  switch (level) {
  case 0:
    strcpy(level_str, "[ERROR] ");
    break;
  case 1:
    strcpy(level_str, "[WARN]  ");
    break;
  case 2:
    strcpy(level_str, "[INFO]  ");
    break;
  case 3:
    strcpy(level_str, "[DEBUG] ");
    break;
  default:
    strcpy(level_str, "[LOG]   ");
    break;
  }

  char category_str[64] = "";
  if (category) {
    snprintf(category_str, sizeof(category_str), "[%s] ", category);
  }

  fprintf(log_file, "%s%s%s", timestamp, level_str, category_str);

  va_list args;
  va_start(args, format);
  vfprintf(log_file, format, args);
  va_end(args);

  fprintf(log_file, "\n");

  if (log_file != stderr) {
    fclose(log_file);
  }
}

void init_log_file(ProfilerConfig *config) {
  if (!config->logging.enabled) {
    return;
  }

  // Create/truncate the log file
  FILE *log_file = fopen(config->logging.log_file_path, "w");
  if (!log_file) {
    fprintf(stderr, "Warning: Could not initialize log file %s\n",
            config->logging.log_file_path);
    return;
  }

  time_t now = time(NULL);
  struct tm *timeinfo = localtime(&now);
  char date_str[64];
  strftime(date_str, sizeof(date_str), "%Y-%m-%d %H:%M:%S", timeinfo);

  fprintf(log_file, "=== gpumkat Profiler Log Started at %s ===\n\n", date_str);
  fclose(log_file);

  log_message(config, 2, "Logging", "Logging initialized to file: %s",
              config->logging.log_file_path);
}

void image_to_buffer(NSString *imagePath, id<MTLBuffer> buffer, size_t width,
                     size_t height) {
  if (!buffer || !imagePath) {
    NSLog(@"Error: Invalid buffer or image path");
    return;
  }

  // Load the image
  NSImage *image = [[NSImage alloc] initWithContentsOfFile:imagePath];
  if (!image) {
    NSLog(@"Error: Failed to load image from path: %@", imagePath);
    return;
  }

  // Get image dimensions if width and height are not specified
  if (width == 0 || height == 0) {
    NSSize imageSize = [image size];
    width = (size_t)imageSize.width;
    height = (size_t)imageSize.height;
  }

  // Ensure buffer is large enough
  size_t required_size = width * height * sizeof(float);
  if (buffer.length < required_size) {
    NSLog(@"Error: Buffer size (%lu) is too small for image data (%lux%lu = "
          @"%lu bytes)",
          (unsigned long)buffer.length, (unsigned long)width,
          (unsigned long)height, (unsigned long)required_size);
    [image release];
    return;
  }

  // Create a bitmap representation of the image
  NSBitmapImageRep *bitmap = nil;
  NSArray *representations = [image representations];
  for (NSImageRep *rep in representations) {
    if ([rep isKindOfClass:[NSBitmapImageRep class]]) {
      bitmap = (NSBitmapImageRep *)rep;
      break;
    }
  }

  // If no bitmap representation was found, create one
  if (!bitmap) {
    NSRect imageRect = NSMakeRect(0, 0, width, height);
    NSImage *resizedImage = [[NSImage alloc] initWithSize:imageRect.size];
    [resizedImage lockFocus];
    [image drawInRect:imageRect
             fromRect:NSZeroRect
            operation:NSCompositingOperationCopy
             fraction:1.0];
    [resizedImage unlockFocus];

    bitmap = [[NSBitmapImageRep alloc]
        initWithData:[resizedImage TIFFRepresentation]];
    [resizedImage release];
  }

  if (!bitmap) {
    NSLog(@"Error: Failed to create bitmap representation of image");
    [image release];
    return;
  }

  // Resize bitmap if necessary
  if ((size_t)[bitmap pixelsWide] != width ||
      (size_t)[bitmap pixelsHigh] != height) {
    NSBitmapImageRep *resizedBitmap =
        [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                pixelsWide:width
                                                pixelsHigh:height
                                             bitsPerSample:8
                                           samplesPerPixel:4
                                                  hasAlpha:YES
                                                  isPlanar:NO
                                            colorSpaceName:NSDeviceRGBColorSpace
                                               bytesPerRow:width * 4
                                              bitsPerPixel:32];

    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext *context =
        [NSGraphicsContext graphicsContextWithBitmapImageRep:resizedBitmap];
    [NSGraphicsContext setCurrentContext:context];

    [bitmap drawInRect:NSMakeRect(0, 0, width, height)];

    [NSGraphicsContext restoreGraphicsState];
    [bitmap release];
    bitmap = resizedBitmap;
  }

  // Get buffer pointer
  float *bufferData = (float *)[buffer contents];

  // Convert image data to float values
  for (size_t y = 0; y < height; y++) {
    for (size_t x = 0; x < width; x++) {
      NSUInteger pixel_index = y * width + x;
      if (pixel_index >= buffer.length / sizeof(float)) {
        continue; // Safety check to avoid buffer overflow
      }

      NSColor *color = [bitmap colorAtX:x y:y];
      if (!color)
        continue;

      // Convert to grayscale using luminance formula
      float grayscale = 0.299 * [color redComponent] +
                        0.587 * [color greenComponent] +
                        0.114 * [color blueComponent];

      bufferData[pixel_index] = grayscale;
    }
  }

  [bitmap release];
  [image release];

  NSLog(@"Image successfully converted to buffer data");
}

void initialize_image_buffers(id<MTLDevice> device, ProfilerConfig *config) {
  if (!device || !config || !config->image_buffers) {
    NSLog(@"Error: Invalid device or config for image buffer initialization");
    return;
  }

  NSLog(@"Initializing %lu image buffers",
        (unsigned long)[config->image_buffers count]);

  for (NSValue *value in config->image_buffers) {
    ImageBufferConfig *imageConfig = [value pointerValue];
    if (!imageConfig || !imageConfig->image_path || !imageConfig->name) {
      NSLog(@"Error: Invalid image buffer configuration");
      continue;
    }

    NSString *imagePath =
        [NSString stringWithUTF8String:imageConfig->image_path];
    NSLog(@"Loading image from %@ for buffer '%s'", imagePath,
          imageConfig->name);

    // Load the image to get dimensions if not specified
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:imagePath];
    if (!image) {
      NSLog(@"Error: Failed to load image from path: %@", imagePath);
      continue;
    }

    // Get image dimensions if width and height are not specified
    size_t width = imageConfig->width;
    size_t height = imageConfig->height;
    if (width == 0 || height == 0) {
      NSSize imageSize = [image size];
      width = (size_t)imageSize.width;
      height = (size_t)imageSize.height;
      NSLog(@"Auto-detected image dimensions: %lux%lu", (unsigned long)width,
            (unsigned long)height);
    }
    [image release];

    // Determine buffer size based on type
    size_t elementSize = 0;
    if (strcmp(imageConfig->type, "float") == 0) {
      elementSize = sizeof(float);
    } else if (strcmp(imageConfig->type, "int") == 0) {
      elementSize = sizeof(int);
    } else if (strcmp(imageConfig->type, "uint") == 0) {
      elementSize = sizeof(unsigned int);
    } else if (strcmp(imageConfig->type, "half") == 0) {
      elementSize = sizeof(short); // Metal half corresponds to 16-bit float
    } else if (strcmp(imageConfig->type, "char") == 0) {
      elementSize = sizeof(char);
    } else if (strcmp(imageConfig->type, "uchar") == 0) {
      elementSize = sizeof(unsigned char);
    } else {
      NSLog(@"Unsupported buffer type: %s, defaulting to float",
            imageConfig->type);
      elementSize = sizeof(float);
    }

    // Calculate buffer size based on image dimensions
    size_t bufferSize = width * height * elementSize;
    NSLog(@"Creating buffer of size %lu bytes for image data",
          (unsigned long)bufferSize);

    // Create a Metal buffer with the appropriate size
    id<MTLBuffer> buffer =
        [device newBufferWithLength:bufferSize
                            options:MTLResourceStorageModeShared];
    if (!buffer) {
      NSLog(@"Error: Failed to create Metal buffer for image");
      continue;
    }

    // Convert image to buffer data
    image_to_buffer(imagePath, buffer, width, height);

    // Create a buffer configuration and add it to the regular buffers array
    BufferConfig *bufferConfig = malloc(sizeof(BufferConfig));
    bufferConfig->name = strdup(imageConfig->name);
    bufferConfig->size = bufferSize;
    bufferConfig->type = strdup(imageConfig->type);
    bufferConfig->contents = @[ buffer ];

    [config->buffers addObject:[NSValue valueWithPointer:bufferConfig]];

    NSLog(@"Successfully initialized image buffer '%s' (%lux%lu)",
          imageConfig->name, (unsigned long)width, (unsigned long)height);
  }

  NSLog(@"Completed image buffer initialization");
}

ProfilerConfig *load_config(const char *config_path) {
  NSError *error = nil;
  NSData *jsonData = [NSData
      dataWithContentsOfFile:[NSString stringWithUTF8String:config_path]];
  if (!jsonData) {
    NSLog(@"Failed to read config file");
    return nil;
  }

  NSDictionary *json = [NSJSONSerialization JSONObjectWithData:jsonData
                                                       options:0
                                                         error:&error];
  if (!json) {
    NSLog(@"Failed to parse JSON: %@", error);
    return nil;
  }

  ProfilerConfig *config = malloc(sizeof(ProfilerConfig));
  config->metallib_path = strdup([json[@"metallib_path"] UTF8String]);
  config->function_name = strdup([json[@"function_name"] UTF8String]);
  config->image_buffers = [[NSMutableArray alloc] init];
  config->buffers = [[NSMutableArray alloc] init];

  // Parse pipeline type - default to compute if not specified
  NSString *pipelineTypeStr = json[@"pipeline_type"];
  if (pipelineTypeStr &&
      [[pipelineTypeStr lowercaseString] isEqualToString:@"renderer"]) {
    config->pipeline_type = PIPELINE_TYPE_RENDERER;
  } else {
    config->pipeline_type = PIPELINE_TYPE_COMPUTE; // Default
  }

  NSDictionary *loggingConfig = json[@"logging"];
  if (loggingConfig) {
    config->logging.enabled = [loggingConfig[@"enabled"] boolValue];

    NSString *logPath = loggingConfig[@"log_file_path"];
    config->logging.log_file_path =
        logPath ? strdup([logPath UTF8String]) : strdup("gpumkat.log");

    config->logging.log_level = [loggingConfig[@"log_level"] intValue];
    config->logging.log_timestamps =
        [loggingConfig[@"log_timestamps"] boolValue];
  } else {
    // Default logging settings
    config->logging.enabled = false;
    config->logging.log_file_path = strdup("gpumkat.log");
    config->logging.log_level = 1; // Warnings and errors by default
    config->logging.log_timestamps = true;
  }

  // Parse debug config
  NSDictionary *debugConfig = json[@"debug"];
  if (debugConfig) {
    config->debug.enabled = [debugConfig[@"enabled"] boolValue];
    config->debug.print_variables = [debugConfig[@"print_variables"] boolValue];
    config->debug.step_by_step = [debugConfig[@"step_by_step"] boolValue];
    config->debug.break_before_dispatch =
        [debugConfig[@"break_before_dispatch"] boolValue];
    config->debug.verbosity_level = [debugConfig[@"verbosity_level"] intValue];
    NSDictionary *timelineConfig = debugConfig[@"timeline"];
    if (timelineConfig) {
      config->debug.timeline.enabled = [timelineConfig[@"enabled"] boolValue];
      config->debug.timeline.track_buffers =
          [timelineConfig[@"track_buffers"] boolValue];
      config->debug.timeline.track_shaders =
          [timelineConfig[@"track_shaders"] boolValue];
      config->debug.timeline.track_performance =
          [timelineConfig[@"track_performance"] boolValue];
      config->debug.timeline.max_events =
          [timelineConfig[@"max_events"] unsignedLongValue];

      // Set default max events if not specified
      if (config->debug.timeline.max_events == 0) {
        config->debug.timeline.max_events = 1000; // Default value
      }

      // Get output file path or use default
      NSString *outputFile = timelineConfig[@"output_file"];
      if (outputFile) {
        config->debug.timeline.output_file = strdup([outputFile UTF8String]);
      } else {
        config->debug.timeline.output_file = strdup("gpumkat_timeline.json");
      }
    } else {
      // Default timeline settings if not specified
      config->debug.timeline.enabled = false;
      config->debug.timeline.track_buffers = false;
      config->debug.timeline.track_shaders = false;
      config->debug.timeline.track_performance = false;
      config->debug.timeline.max_events = 1000;
      config->debug.timeline.output_file = strdup("gpumkat_timeline.json");
    }
  } else {
    // Default debug settings
    config->debug.enabled = false;
    config->debug.print_variables = false;
    config->debug.step_by_step = false;
    config->debug.break_before_dispatch = false;
    config->debug.verbosity_level = 0;
  }

  NSArray *buffersConfig = json[@"buffers"];
  for (NSDictionary *bufferInfo in buffersConfig) {
    BufferConfig *bufferConfig = malloc(sizeof(BufferConfig));
    bufferConfig->name = strdup([bufferInfo[@"name"] UTF8String]);
    bufferConfig->size = [bufferInfo[@"size"] unsignedLongValue];
    bufferConfig->type = strdup([bufferInfo[@"type"] UTF8String]);
    bufferConfig->contents = [bufferInfo[@"contents"] retain];

    [config->buffers addObject:[NSValue valueWithPointer:bufferConfig]];
  }
  NSArray *imageBuffersConfig = json[@"image_buffers"];
  if (imageBuffersConfig) {
    for (NSDictionary *imageBufferInfo in imageBuffersConfig) {
      ImageBufferConfig *imageBufferConfig = malloc(sizeof(ImageBufferConfig));
      imageBufferConfig->name = strdup([imageBufferInfo[@"name"] UTF8String]);
      imageBufferConfig->image_path =
          strdup([imageBufferInfo[@"image_path"] UTF8String]);
      imageBufferConfig->width = [imageBufferInfo[@"width"] unsignedLongValue];
      imageBufferConfig->height =
          [imageBufferInfo[@"height"] unsignedLongValue];
      imageBufferConfig->type = strdup([imageBufferInfo[@"type"] UTF8String]);

      [config->image_buffers
          addObject:[NSValue valueWithPointer:imageBufferConfig]];
    }
  }

  NSArray *breakpointsConfig = debugConfig[@"breakpoints"];
  if (breakpointsConfig) {
    config->debug.breakpoint_count = [breakpointsConfig count];
    config->debug.breakpoints =
        malloc(sizeof(Breakpoint) * config->debug.breakpoint_count);

    for (NSUInteger i = 0; i < config->debug.breakpoint_count; i++) {
      NSDictionary *bpInfo = breakpointsConfig[i];
      config->debug.breakpoints[i].condition =
          strdup([bpInfo[@"condition"] UTF8String]);
      config->debug.breakpoints[i].description =
          strdup([bpInfo[@"description"] UTF8String]);
    }
  } else {
    config->debug.breakpoint_count = 0;
    config->debug.breakpoints = NULL;
  }
  NSDictionary *lowEndGpuConfig = debugConfig[@"low_end_gpu"];
  if (lowEndGpuConfig) {
    // Compute Simulation
    config->debug.low_end_gpu.compute.processing_units_availability =
        [lowEndGpuConfig[@"compute"][@"processing_units_availability"]
            floatValue];
    config->debug.low_end_gpu.compute.clock_speed_reduction =
        [lowEndGpuConfig[@"compute"][@"clock_speed_reduction"] floatValue];
    config->debug.low_end_gpu.compute.compute_unit_failures =
        [lowEndGpuConfig[@"compute"][@"compute_unit_failures"] intValue];

    // Memory Simulation
    config->debug.low_end_gpu.memory.bandwidth_reduction =
        [lowEndGpuConfig[@"memory"][@"bandwidth_reduction"] floatValue];
    config->debug.low_end_gpu.memory.latency_multiplier =
        [lowEndGpuConfig[@"memory"][@"latency_multiplier"] floatValue];
    config->debug.low_end_gpu.memory.available_memory =
        [lowEndGpuConfig[@"memory"][@"available_memory"] unsignedLongValue];
    config->debug.low_end_gpu.memory.memory_error_rate =
        [lowEndGpuConfig[@"memory"][@"memory_error_rate"] floatValue];

    // Thermal Simulation
    config->debug.low_end_gpu.thermal.thermal_throttling_threshold =
        [lowEndGpuConfig[@"thermal"][@"thermal_throttling_threshold"]
            floatValue];
    config->debug.low_end_gpu.thermal.power_limit =
        [lowEndGpuConfig[@"thermal"][@"power_limit"] floatValue];
    config->debug.low_end_gpu.thermal.enable_thermal_simulation =
        [lowEndGpuConfig[@"thermal"][@"enable_thermal_simulation"] boolValue];

    // Logging
    config->debug.low_end_gpu.logging.detailed_logging =
        [lowEndGpuConfig[@"logging"][@"detailed_logging"] boolValue];
    NSString *logPath = lowEndGpuConfig[@"logging"][@"log_file_path"];
    config->debug.low_end_gpu.logging.log_file_path =
        logPath ? strdup([logPath UTF8String]) : strdup("low_end_gpu_sim.log");

    // Rendering Simulation
    config->debug.low_end_gpu.rendering.fillrate_reduction =
        [lowEndGpuConfig[@"rendering"][@"fillrate_reduction"] floatValue];
    config->debug.low_end_gpu.rendering.texture_quality_reduction =
        [lowEndGpuConfig[@"rendering"][@"texture_quality_reduction"]
            floatValue];
    config->debug.low_end_gpu.rendering.reduce_draw_distance =
        [lowEndGpuConfig[@"rendering"][@"reduce_draw_distance"] boolValue];
    config->debug.low_end_gpu.rendering.draw_distance_factor =
        [lowEndGpuConfig[@"rendering"][@"draw_distance_factor"] floatValue];
  } else {
    // Default conservative settings
    config->debug.low_end_gpu.enabled = false;
    config->debug.low_end_gpu.compute.processing_units_availability = 0.7;
    config->debug.low_end_gpu.compute.clock_speed_reduction = 0.3;
    config->debug.low_end_gpu.compute.compute_unit_failures = 1;
    config->debug.low_end_gpu.memory.bandwidth_reduction = 0.5;
    config->debug.low_end_gpu.memory.latency_multiplier = 2.0;
    config->debug.low_end_gpu.memory.memory_error_rate = 0.01;
    config->debug.low_end_gpu.thermal.thermal_throttling_threshold = 90.0;
    config->debug.low_end_gpu.thermal.enable_thermal_simulation = true;
    config->debug.low_end_gpu.logging.detailed_logging = true;
    config->debug.low_end_gpu.rendering.fillrate_reduction = 0.5;
    config->debug.low_end_gpu.rendering.texture_quality_reduction = 0.5;
    config->debug.low_end_gpu.rendering.reduce_draw_distance = true;
    config->debug.low_end_gpu.rendering.draw_distance_factor = 0.5;
  }
  NSDictionary *asyncConfig = debugConfig[@"async_debug"];
  if (asyncConfig) {
    config->debug.async_debug.config.enable_async_tracking =
        [asyncConfig[@"enable_async_tracking"] boolValue];
    config->debug.async_debug.config.log_command_status =
        [asyncConfig[@"log_command_status"] boolValue];
    config->debug.async_debug.config.detect_long_running_commands =
        [asyncConfig[@"detect_long_running_commands"] boolValue];
    config->debug.async_debug.config.long_command_threshold =
        [asyncConfig[@"long_command_threshold"] doubleValue];
    config->debug.async_debug.config.generate_async_timeline =
        [asyncConfig[@"generate_async_timeline"] boolValue];
  } else {
    // Default conservative settings
    config->debug.async_debug.config.enable_async_tracking = false;
    config->debug.async_debug.config.log_command_status = false;
    config->debug.async_debug.config.detect_long_running_commands = false;
    config->debug.async_debug.config.long_command_threshold = 1.0; // 1 second
    config->debug.async_debug.config.generate_async_timeline = false;
  }

  load_error_config(&config->debug, debugConfig);
  load_thread_control_config(&config->debug, debugConfig);

  return config;
}