#include "expose_from_debug.h"
#include "expose_to_debug.h"
#include <pthread.h>
#include <stdarg.h>

static FILE *log_file_ptr = NULL;
static pthread_mutex_t log_mutex = PTHREAD_MUTEX_INITIALIZER;
static int log_enabled = 0;
static int log_level_threshold = 1;
static int log_timestamps_enabled = 1;

void profile_command_buffer(id<MTLCommandBuffer> commandBuffer,
                            const char *name) {
  NSDate *startTime = [NSDate date];
  [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
    NSDate *endTime = [NSDate date];
    NSTimeInterval elapsed = [endTime timeIntervalSinceDate:startTime];
    if (buffer.error) {
      log_printf(2, "Profile", "Error in command buffer '%s': %s", name,
                 [[buffer.error description] UTF8String]);
      return;
    }
    log_printf(2, "Profile", "Command Buffer '%s' execution time: %.6f seconds",
               name, elapsed);
  }];
  [commandBuffer commit];
}

void debug_pause(const char *message) {
  printf("\n[DEBUG PAUSE] %s\nPress Enter to continue...", message);
  getchar();
}

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
      log_printf(2, "Breakpoint", "[BREAKPOINT] Hit breakpoint: %s",
                 bp->description);
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
      log_printf(0, "ErrorCollector",
                 "Failed to expand error collector capacity");
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
    log_printf(0, "ErrorCollector", "[%s] %s: %s",
               severity == ERROR_SEVERITY_WARNING ? "WARNING" : "ERROR",
               location, message);
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

  log_printf(2, "ErrorSummary", "\n=== Error Summary ===");
  log_printf(2, "ErrorSummary", "Total Errors: %zu", collector->error_count);

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

  log_printf(2, "ErrorSummary", "Warnings: %d", warnings);
  log_printf(2, "ErrorSummary", "Errors: %d", errors);
  log_printf(2, "ErrorSummary", "Fatal Errors: %d", fatal);
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

    log_printf(1, "Simulation",
               "[LOW-END GPU SIM] Memory Transfer Error Injected: %zu bytes "
               "corrupted",
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

  log_printf(2, "Simulation",
             "[LOW-END GPU SIM] Bandwidth Limited Transfer: %zu of %zu bytes "
             "(Quality: %.2f)",
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

static float get_thermal_throttle_factor(void) {
  NSProcessInfoThermalState state = [[NSProcessInfo processInfo] thermalState];

  switch (state) {
  case NSProcessInfoThermalStateNominal:
    return 1.0f;
  case NSProcessInfoThermalStateFair:
    return 1.15f;
  case NSProcessInfoThermalStateSerious:
    return 1.5f;
  case NSProcessInfoThermalStateCritical:
    return 2.25f;
  default:
    return 1.0f;
  }
}

void simulate_low_end_gpu(LowEndGpuSimulation *sim,
                          id<MTLComputeCommandEncoder> encoder,
                          MTLSize *gridSize, MTLSize *threadGroupSize) {
  if (!sim->enabled)
    return;

  log_printf(2, "Simulation", "\n=== Low-End GPU Simulation ===");

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
    log_printf(
        2, "Simulation", "Clock Speed Reduced: %.2f%% (Delay Factor: %.2fx)",
        sim->compute.clock_speed_reduction * 100, execution_delay_factor);
  }

  if (sim->memory.bandwidth_reduction > 0) {
    execution_delay_factor *=
        (1.0 + sim->memory.bandwidth_reduction *
                   1.5); // 1.5x multiplier for compounding effects
    log_printf(2, "Simulation", "Memory Bandwidth Reduced: %.2f%%",
               sim->memory.bandwidth_reduction * 100);
  }

  if (sim->thermal.enable_thermal_simulation) {
    float throttle_factor = get_thermal_throttle_factor();
    if (throttle_factor > 1.0f) {
      execution_delay_factor *= throttle_factor;
      log_printf(2, "Simulation",
                 "Thermal Throttling Active "
                 "(system state factor: %.2fx)",
                 throttle_factor);
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
      fflush(log_file);
      fclose(log_file);
    }
  }

  for (NSUInteger pass = 0; pass < total_passes; pass++) {
    if (execution_delay_factor > 1.0) {
      uint64_t delay_microseconds = (uint64_t)(1000 * execution_delay_factor);
      usleep(delay_microseconds); // Actually insert delay proportional
                                  // to simulation factors
    }

    // Dispatch with simulated constraints
    [encoder dispatchThreads:simulatedGridSize
        threadsPerThreadgroup:simulatedThreadGroupSize];
  }

  log_printf(2, "Simulation",
             "Simulation Complete - Total Impact Factor: %.2fx slower",
             execution_delay_factor * total_passes);
}

void init_low_end_gpu_log_file(LowEndGpuSimulation *gpu) {
  if (!gpu->enabled || !gpu->logging.detailed_logging) {
    return;
  }
  if (!gpu->logging.log_file_path) {
    return;
  }
  FILE *f = fopen(gpu->logging.log_file_path, "w");
  if (!f) {
    fprintf(stderr,
            "Warning: Could not initialize low-end GPU "
            "log file %s\n",
            gpu->logging.log_file_path);
    return;
  }
  time_t now = time(NULL);
  struct tm *ti = localtime(&now);
  char date_str[64];
  strftime(date_str, sizeof(date_str), "%Y-%m-%d %H:%M:%S", ti);
  fprintf(f,
          "=== Low-End GPU Simulation Log "
          "Started at %s ===\n",
          date_str);
  fprintf(f, "Simulation Settings:\n");
  fprintf(f, "  Processing Units Availability: %.2f\n",
          gpu->compute.processing_units_availability);
  fprintf(f, "  Clock Speed Reduction:         %.2f\n",
          gpu->compute.clock_speed_reduction);
  fprintf(f, "  Compute Unit Failures:         %d\n",
          gpu->compute.compute_unit_failures);
  fprintf(f, "  Bandwidth Reduction:           %.2f\n",
          gpu->memory.bandwidth_reduction);
  fprintf(f, "  Latency Multiplier:            %.2f\n",
          gpu->memory.latency_multiplier);
  fprintf(f, "  Available Memory:              %llu bytes\n",
          (unsigned long long)gpu->memory.available_memory);
  fprintf(f, "  Memory Error Rate:             %.4f\n",
          gpu->memory.memory_error_rate);
  fprintf(f, "  Thermal Simulation Enabled:    %s\n",
          gpu->thermal.enable_thermal_simulation ? "Yes" : "No");
  fprintf(f, "\n");
  fflush(f);
  fclose(f);
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
      log_printf(2, "Async", "[ASYNC DEBUG] Long-running command detected: %s",
                 tracker->name);
      log_printf(2, "Async", "Execution Time: %.4f seconds",
                 tracker->execution_time);
    }

    // Log command status if enabled
    if (ext->config.log_command_status) {
      log_printf(2, "Async",
                 "[ASYNC DEBUG] Command '%s' status:", tracker->name);
      log_printf(2, "Async", "  Completed: %s",
                 tracker->is_completed ? "Yes" : "No");
      log_printf(2, "Async", "  Errors: %s",
                 tracker->has_errors ? "Yes" : "No");
      log_printf(2, "Async", "  Execution Time: %.4f seconds",
                 tracker->execution_time);
    }
  }];
}

void generate_async_command_timeline(AsyncCommandDebugExtension *ext) {
  if (!ext->config.generate_async_timeline)
    return;

  FILE *timeline_file = fopen("async_command_timeline.json", "w");
  if (!timeline_file) {
    log_printf(2, "Async", "Failed to create async command timeline file");
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
  fflush(timeline_file);
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
    log_printf(2, "ThreadControl", "Thread Control Configuration:");
    log_printf(2, "ThreadControl", "  Dispatch Mode: %d",
               debug->thread_control.dispatch_mode);
    log_printf(2, "ThreadControl", "  Grid Size: %lux%lux%lu", gridSize.width,
               gridSize.height, gridSize.depth);
    log_printf(2, "ThreadControl", "  ThreadGroup Size: %lux%lux%lu",
               threadGroupSize.width, threadGroupSize.height,
               threadGroupSize.depth);
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
        log_printf(2, "ThreadControl", "Dispatched linear group %lu-%lu", i,
                   i + thisDispatch - 1);
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
        log_printf(2, "ThreadControl", "Dispatched reverse group %lu-%lu",
                   start, start + count - 1);
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
        log_printf(2, "ThreadControl",
                   "Dispatched random group %lu at (%lu,%lu,%lu)", groupIdx, x,
                   y, z);
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
        log_printf(2, "ThreadControl", "Dispatched even group %lu-%lu", i,
                   i + thisDispatch - 1);
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
        log_printf(2, "ThreadControl", "Dispatched odd group %lu-%lu", i,
                   i + thisDispatch - 1);
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
              log_printf(
                  2, "ThreadControl",
                  "Warning: Line %d coordinates (%u,%u,%u) exceed grid size",
                  lineNum, di.x, di.y, di.z);
              continue;
            }

            // Validate count
            if (di.count == 0 || di.count > threadGroupSize.width *
                                                threadGroupSize.height *
                                                threadGroupSize.depth) {
              log_printf(2, "ThreadControl",
                         "Warning: Line %d count %u exceeds threadgroup size",
                         lineNum, di.count);
              di.count = threadGroupSize.width; // Default to threadgroup width
            }

            dispatches[dispatchIndex++] = di;
          } else {
            log_printf(2, "ThreadControl", "Error parsing line %d: %s", lineNum,
                       line);
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
            log_printf(2, "ThreadControl",
                       "Dispatched custom group %d: (%u,%u,%u) count %u", i,
                       di.x, di.y, di.z, actualCount);
          }
        }

        free(dispatches);
      } else {
        log_printf(2, "ThreadControl", "Failed to open thread order file: %s",
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
  if (!log_enabled || level > log_level_threshold) {
    return;
  }

  pthread_mutex_lock(&log_mutex);
  if (!log_file_ptr) {
    pthread_mutex_unlock(&log_mutex);
    return;
  }

  char timestamp[64] = "";
  if (log_timestamps_enabled) {
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

  fprintf(log_file_ptr, "%s%s%s", timestamp, level_str, category_str);

  va_list args;
  va_start(args, format);
  vfprintf(log_file_ptr, format, args);
  va_end(args);

  fprintf(log_file_ptr, "\n");
  fflush(log_file_ptr);

  pthread_mutex_unlock(&log_mutex);
}

void log_printf(int level, const char *category, const char *format, ...) {
  if (!log_enabled || level > log_level_threshold) {
    return;
  }

  pthread_mutex_lock(&log_mutex);
  if (!log_file_ptr) {
    pthread_mutex_unlock(&log_mutex);
    return;
  }

  char timestamp[64] = "";
  if (log_timestamps_enabled) {
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

  fprintf(log_file_ptr, "%s%s%s", timestamp, level_str, category_str);

  va_list args;
  va_start(args, format);
  vfprintf(log_file_ptr, format, args);
  va_end(args);

  fprintf(log_file_ptr, "\n");
  fflush(log_file_ptr);

  pthread_mutex_unlock(&log_mutex);
}

void init_log_file(ProfilerConfig *config) {
  if (!config->logging.enabled) {
    return;
  }

  pthread_mutex_lock(&log_mutex);

  // Close previous file if still open
  if (log_file_ptr) {
    fclose(log_file_ptr);
  }

  // Create/truncate the log file
  log_file_ptr = fopen(config->logging.log_file_path, "w");
  if (!log_file_ptr) {
    fprintf(stderr, "Warning: Could not initialize log file %s\n",
            config->logging.log_file_path);
    pthread_mutex_unlock(&log_mutex);
    return;
  }

  setvbuf(log_file_ptr, NULL, _IOLBF, 0);

  // Set global state from config
  log_enabled = config->logging.enabled ? 1 : 0;
  log_level_threshold = config->logging.log_level;
  log_timestamps_enabled = config->logging.log_timestamps ? 1 : 0;

  time_t now = time(NULL);
  struct tm *timeinfo = localtime(&now);
  char date_str[64];
  strftime(date_str, sizeof(date_str), "%Y-%m-%d %H:%M:%S", timeinfo);

  fprintf(log_file_ptr, "=== gpumkat Profiler Log Started at %s ===\n\n",
          date_str);
  fflush(log_file_ptr);

  pthread_mutex_unlock(&log_mutex);

  log_message(config, 2, "Logging", "Logging initialized to file: %s",
              config->logging.log_file_path);
}

// String->enum helpers

MTLPixelFormat pixel_format_from_string(const char *str) {
  if (!str)
    return MTLPixelFormatRGBA8Unorm;
  if (strcmp(str, "RGBA8Unorm") == 0)
    return MTLPixelFormatRGBA8Unorm;
  if (strcmp(str, "RGBA8Uint") == 0)
    return MTLPixelFormatRGBA8Uint;
  if (strcmp(str, "RGBA8Sint") == 0)
    return MTLPixelFormatRGBA8Sint;
  if (strcmp(str, "BGRA8Unorm") == 0)
    return MTLPixelFormatBGRA8Unorm;
  if (strcmp(str, "RGBA16Float") == 0)
    return MTLPixelFormatRGBA16Float;
  if (strcmp(str, "R32Float") == 0)
    return MTLPixelFormatR32Float;
  if (strcmp(str, "RGBA32Float") == 0)
    return MTLPixelFormatRGBA32Float;
  if (strcmp(str, "R16Float") == 0)
    return MTLPixelFormatR16Float;
  if (strcmp(str, "R8Unorm") == 0)
    return MTLPixelFormatR8Unorm;
  NSLog(@"Warning: Unknown pixel format '%s', defaulting to RGBA8Unorm", str);
  return MTLPixelFormatRGBA8Unorm;
}

MTLTextureUsage texture_usage_from_string_array(NSArray *array) {
  MTLTextureUsage usage = MTLTextureUsageUnknown;
  for (NSString *s in array) {
    if ([s isEqualToString:@"shader_read"])
      usage |= MTLTextureUsageShaderRead;
    else if ([s isEqualToString:@"shader_write"])
      usage |= MTLTextureUsageShaderWrite;
    else if ([s isEqualToString:@"render_target"])
      usage |= MTLTextureUsageRenderTarget;
    else if ([s isEqualToString:@"pixel_format_view"])
      usage |= MTLTextureUsagePixelFormatView;
  }
  if (usage == MTLTextureUsageUnknown)
    usage = MTLTextureUsageShaderRead;
  return usage;
}

// Shared image decoding

uint8_t *decode_image_to_rgba8(const char *image_path, size_t *out_width,
                               size_t *out_height,
                               ProfilerConfig *profilerConfig) {
  if (!image_path)
    return NULL;
  NSString *path = [NSString stringWithUTF8String:image_path];
  NSURL *url = [NSURL fileURLWithPath:path];
  CGImageSourceRef source =
      CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
  if (!source) {
    if (profilerConfig)
      record_error(&profilerConfig->debug, ERROR_SEVERITY_ERROR,
                   ERROR_CATEGORY_BUFFER, "Cannot open image file", image_path);
    return NULL;
  }
  CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
  CFRelease(source);
  if (!image) {
    if (profilerConfig)
      record_error(&profilerConfig->debug, ERROR_SEVERITY_ERROR,
                   ERROR_CATEGORY_BUFFER, "Failed to decode image", image_path);
    return NULL;
  }
  size_t w = CGImageGetWidth(image);
  size_t h = CGImageGetHeight(image);
  size_t bpr = w * 4;
  uint8_t *tempData = (uint8_t *)malloc(bpr * h);
  if (!tempData) {
    CGImageRelease(image);
    return NULL;
  }
  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  CGContextRef ctx = CGBitmapContextCreate(tempData, w, h, 8, bpr, cs,
                                           kCGImageAlphaPremultipliedLast |
                                               kCGBitmapByteOrder32Big);
  CGColorSpaceRelease(cs);
  if (!ctx) {
    free(tempData);
    CGImageRelease(image);
    return NULL;
  }
  CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), image);
  CGContextRelease(ctx);
  CGImageRelease(image);
  if (out_width)
    *out_width = w;
  if (out_height)
    *out_height = h;
  return tempData;
}

void print_texture_state(id<MTLTexture> texture, const char *name) {
  if (!texture || !name)
    return;
  printf("\nTexture State - %s:\n", name);
  printf("  Size: %lux%lu\n", (unsigned long)texture.width,
         (unsigned long)texture.height);
  printf("  Pixel Format: %lu\n", (unsigned long)texture.pixelFormat);
  printf("  Mipmap Levels: %lu\n", (unsigned long)texture.mipmapLevelCount);
  printf("  Array Layers: %lu\n", (unsigned long)texture.arrayLength);
  printf("  Usage: %lu\n", (unsigned long)texture.usage);
}

void sample_texture_pixel(id<MTLTexture> texture, float x, float y,
                          float *out_rgba) {
  if (!texture || !out_rgba)
    return;
  if (texture.pixelFormat == MTLPixelFormatRGBA8Unorm) {
    uint8_t pixel[4] = {0};
    MTLRegion region = MTLRegionMake2D((NSUInteger)x, (NSUInteger)y, 1, 1);
    [texture getBytes:pixel bytesPerRow:4 fromRegion:region mipmapLevel:0];
    out_rgba[0] = pixel[0] / 255.0f;
    out_rgba[1] = pixel[1] / 255.0f;
    out_rgba[2] = pixel[2] / 255.0f;
    out_rgba[3] = pixel[3] / 255.0f;
  } else {
    float pixel[4] = {0};
    MTLRegion region = MTLRegionMake2D((NSUInteger)x, (NSUInteger)y, 1, 1);
    [texture getBytes:pixel bytesPerRow:16 fromRegion:region mipmapLevel:0];
    out_rgba[0] = pixel[0];
    out_rgba[1] = pixel[1];
    out_rgba[2] = pixel[2];
    out_rgba[3] = pixel[3];
  }
}

// Compute buffer from image (legacy path)

id<MTLBuffer> create_compute_buffer_from_image(id<MTLDevice> device,
                                               ImageBufferConfig *config,
                                               ProfilerConfig *profilerConfig) {
  if (!config || !config->image_path)
    return nil;
  size_t w = 0, h = 0;
  uint8_t *rgba =
      decode_image_to_rgba8(config->image_path, &w, &h, profilerConfig);
  if (!rgba)
    return nil;
  size_t pixelCount = w * h;
  size_t floatCount = pixelCount * 4;
  size_t bufferSize = floatCount * sizeof(float);
  id<MTLBuffer> buffer =
      [device newBufferWithLength:bufferSize
                          options:MTLResourceStorageModeShared];
  if (!buffer) {
    free(rgba);
    if (profilerConfig)
      record_error(&profilerConfig->debug, ERROR_SEVERITY_ERROR,
                   ERROR_CATEGORY_BUFFER, "Failed to allocate buffer",
                   config->name);
    return nil;
  }
  float *floatData = (float *)buffer.contents;
  for (size_t i = 0; i < pixelCount; i++) {
    size_t b = i * 4;
    floatData[i * 4 + 0] = (float)rgba[b + 0] / 255.0f;
    floatData[i * 4 + 1] = (float)rgba[b + 1] / 255.0f;
    floatData[i * 4 + 2] = (float)rgba[b + 2] / 255.0f;
    floatData[i * 4 + 3] = (float)rgba[b + 3] / 255.0f;
  }
  free(rgba);
  if (config->width == 0)
    config->width = (uint32_t)w;
  if (config->height == 0)
    config->height = (uint32_t)h;
  if (profilerConfig && profilerConfig->debug.enabled) {
    log_message(profilerConfig, 2, "ImageBuffer",
                "Loaded '%s' (%zux%zu) as %zu floats", config->name, w, h,
                floatCount);
  }
  return buffer;
}

// float -> half helper
static inline uint16_t float32_to_float16(float f) {
  uint32_t i;
  memcpy(&i, &f, sizeof(i));
  uint32_t sign = (i >> 16) & 0x8000;
  int32_t exp = ((i >> 23) & 0xff) - 127 + 15;
  uint32_t mant = i & 0x7fffff;
  if (exp <= 0) {
    mant = (mant | 0x800000) >> (1 - exp);
    exp = 0;
  } else if (exp > 30) {
    exp = 31;
    mant = 0;
  }
  return (uint16_t)(sign | ((uint32_t)exp << 10) | (mant >> 13));
}

id<MTLTexture> create_texture_from_image(id<MTLDevice> device,
                                         ImageBufferConfig *config,
                                         ProfilerConfig *profilerConfig) {
  if (!config)
    return nil;

  size_t w = config->width, h = config->height;
  uint8_t *rgba = NULL;

  // If image_path is provided, decode it; otherwise create empty texture
  if (config->image_path && strlen(config->image_path) > 0) {
    rgba = decode_image_to_rgba8(config->image_path, &w, &h, profilerConfig);
    if (!rgba) {
      if (profilerConfig)
        record_error(&profilerConfig->debug, ERROR_SEVERITY_ERROR,
                     ERROR_CATEGORY_BUFFER, "Failed to decode image",
                     config->name);
      return nil;
    }
  }

  // Fall back to config dimensions if decoder didn't set them
  if (w == 0)
    w = 512;
  if (h == 0)
    h = 512;

  MTLTextureDescriptor *desc = [[MTLTextureDescriptor alloc] init];
  desc.textureType = MTLTextureType2D;
  desc.pixelFormat = config->pixel_format;
  desc.width = w;
  desc.height = h;
  desc.depth = 1;
  desc.usage = config->texture_usage | MTLTextureUsageShaderRead;
  desc.storageMode = MTLStorageModeShared;

  if (config->mipmaps) {
    NSUInteger maxLevels = 1 + (NSUInteger)floor(log2(MAX(w, h)));
    desc.mipmapLevelCount = MIN(maxLevels, 15);
  }

  id<MTLTexture> texture = [device newTextureWithDescriptor:desc];
  if (!texture) {
    free(rgba);
    if (profilerConfig)
      record_error(&profilerConfig->debug, ERROR_SEVERITY_ERROR,
                   ERROR_CATEGORY_BUFFER, "Failed to create texture",
                   config->name);
    return nil;
  }

  // Upload pixel data if we decoded an image
  if (rgba) {
    MTLRegion region = MTLRegionMake2D(0, 0, w, h);
    if (config->pixel_format == MTLPixelFormatRGBA8Unorm) {
      [texture replaceRegion:region
                 mipmapLevel:0
                   withBytes:rgba
                 bytesPerRow:w * 4];
    } else if (config->pixel_format == MTLPixelFormatRGBA16Float) {
      size_t count = w * h;
      uint16_t *fp16 = malloc(count * 8);
      for (size_t i = 0; i < count; i++) {
        float r = rgba[i * 4 + 0] / 255.0f, g = rgba[i * 4 + 1] / 255.0f;
        float b = rgba[i * 4 + 2] / 255.0f, a = rgba[i * 4 + 3] / 255.0f;
        fp16[i * 4 + 0] = float32_to_float16(r);
        fp16[i * 4 + 1] = float32_to_float16(g);
        fp16[i * 4 + 2] = float32_to_float16(b);
        fp16[i * 4 + 3] = float32_to_float16(a);
      }
      [texture replaceRegion:region
                 mipmapLevel:0
                   withBytes:fp16
                 bytesPerRow:w * 8];
      free(fp16);
    } else if (config->pixel_format == MTLPixelFormatR32Float) {
      size_t count = w * h;
      float *f32 = malloc(count * 4);
      for (size_t i = 0; i < count; i++)
        f32[i] = rgba[i * 4 + 0] / 255.0f;
      [texture replaceRegion:region
                 mipmapLevel:0
                   withBytes:f32
                 bytesPerRow:w * 4];
      free(f32);
    } else if (config->pixel_format == MTLPixelFormatRGBA8Uint ||
               config->pixel_format == MTLPixelFormatRGBA8Sint) {
      // Same 4-byte-per-pixel byte layout as RGBA8Unorm
      [texture replaceRegion:region
                 mipmapLevel:0
                   withBytes:rgba
                 bytesPerRow:w * 4];
    } else {
      [texture replaceRegion:region
                 mipmapLevel:0
                   withBytes:rgba
                 bytesPerRow:w * 4];
    }
  }

  // Generate mipmaps if requested
  if (config->mipmaps && texture.mipmapLevelCount > 1) {
    id<MTLCommandQueue> q = [device newCommandQueue];
    id<MTLCommandBuffer> cb = [q commandBuffer];
    id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
    [blit generateMipmapsForTexture:texture];
    [blit endEncoding];
    [cb commit];
    [cb waitUntilCompleted];
  }

  free(rgba);

  config->width = (uint32_t)w;
  config->height = (uint32_t)h;

  if (profilerConfig && profilerConfig->debug.enabled) {
    log_message(profilerConfig, 2, "Texture",
                "Created texture '%s' (%zux%zu) fmt=%lu", config->name, w, h,
                (unsigned long)config->pixel_format);
  }
  return texture;
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
  config->metal_textures = [[NSMutableDictionary alloc] init];

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
      memset(imageBufferConfig, 0, sizeof(ImageBufferConfig));
      NSString *nameStr = imageBufferInfo[@"name"];
      imageBufferConfig->name =
          nameStr ? strdup([nameStr UTF8String]) : strdup("unnamed");
      NSString *imgPathStr = imageBufferInfo[@"image_path"];
      imageBufferConfig->image_path =
          imgPathStr ? strdup([imgPathStr UTF8String]) : NULL;
      imageBufferConfig->width = [imageBufferInfo[@"width"] unsignedLongValue];
      imageBufferConfig->height =
          [imageBufferInfo[@"height"] unsignedLongValue];
      imageBufferConfig->type =
          strdup([imageBufferInfo[@"type"] UTF8String] ?: "float");

      // Parse new texture fields
      NSString *backendStr = imageBufferInfo[@"backend"];
      NSString *pixelFormatStr = imageBufferInfo[@"pixel_format"];
      NSArray *textureUsageArr = imageBufferInfo[@"texture_usage"];
      NSDictionary *bindDict = imageBufferInfo[@"bind"];

      imageBufferConfig->pixel_format =
          pixelFormatStr ? pixel_format_from_string([pixelFormatStr UTF8String])
                         : MTLPixelFormatRGBA8Unorm;
      imageBufferConfig->mipmaps = [imageBufferInfo[@"mipmaps"] boolValue];
      imageBufferConfig->texture_usage =
          textureUsageArr ? texture_usage_from_string_array(textureUsageArr)
                          : MTLTextureUsageShaderRead;

      if (backendStr && [backendStr isEqualToString:@"buffer"]) {
        imageBufferConfig->backend = 1; // IMAGE_BACKEND_BUFFER
      } else {
        imageBufferConfig->backend = 0; // IMAGE_BACKEND_TEXTURE (default)
      }

      imageBufferConfig->bind_as = 0; // BIND_AS_TEXTURE default
      imageBufferConfig->bind_index = 0;
      if (bindDict) {
        NSString *bindAsStr = bindDict[@"as"];
        if (bindAsStr && [bindAsStr isEqualToString:@"buffer"]) {
          imageBufferConfig->bind_as = 1; // BIND_AS_BUFFER
        }
        imageBufferConfig->bind_index = [bindDict[@"index"] unsignedLongValue];
      }

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
    config->debug.low_end_gpu.enabled = [lowEndGpuConfig[@"enabled"] boolValue];

    config->debug.low_end_gpu.compute.processing_units_availability =
        [lowEndGpuConfig[@"compute"][@"processing_units_availability"]
            floatValue];
    config->debug.low_end_gpu.compute.clock_speed_reduction =
        [lowEndGpuConfig[@"compute"][@"clock_speed_reduction"] floatValue];
    config->debug.low_end_gpu.compute.compute_unit_failures =
        [lowEndGpuConfig[@"compute"][@"compute_unit_failures"] intValue];

    config->debug.low_end_gpu.memory.bandwidth_reduction =
        [lowEndGpuConfig[@"memory"][@"bandwidth_reduction"] floatValue];
    config->debug.low_end_gpu.memory.latency_multiplier =
        [lowEndGpuConfig[@"memory"][@"latency_multiplier"] floatValue];
    config->debug.low_end_gpu.memory.available_memory =
        [lowEndGpuConfig[@"memory"][@"available_memory"] unsignedLongValue];
    config->debug.low_end_gpu.memory.memory_error_rate =
        [lowEndGpuConfig[@"memory"][@"memory_error_rate"] floatValue];

    config->debug.low_end_gpu.thermal.enable_thermal_simulation =
        [lowEndGpuConfig[@"thermal"][@"enable_thermal_simulation"] boolValue];

    config->debug.low_end_gpu.logging.detailed_logging =
        [lowEndGpuConfig[@"logging"][@"detailed_logging"] boolValue];
    NSString *lowEndLogPath = lowEndGpuConfig[@"logging"][@"log_file_path"];
    config->debug.low_end_gpu.logging.log_file_path =
        lowEndLogPath ? strdup([lowEndLogPath UTF8String])
                      : strdup("low_end_gpu_sim.log");
  } else {
    config->debug.low_end_gpu.enabled = false;
    config->debug.low_end_gpu.compute.processing_units_availability = 0.7;
    config->debug.low_end_gpu.compute.clock_speed_reduction = 0.3;
    config->debug.low_end_gpu.compute.compute_unit_failures = 1;
    config->debug.low_end_gpu.memory.bandwidth_reduction = 0.5;
    config->debug.low_end_gpu.memory.latency_multiplier = 2.0;
    config->debug.low_end_gpu.memory.available_memory = 0;
    config->debug.low_end_gpu.memory.memory_error_rate = 0.01;
    config->debug.low_end_gpu.thermal.enable_thermal_simulation = true;
    config->debug.low_end_gpu.logging.detailed_logging = true;
    config->debug.low_end_gpu.logging.log_file_path =
        strdup("low_end_gpu_sim.log");
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

void close_log_file(void) {
  pthread_mutex_lock(&log_mutex);
  if (log_file_ptr) {
    fclose(log_file_ptr);
    log_file_ptr = NULL;
  }
  log_enabled = 0;
  pthread_mutex_unlock(&log_mutex);
}
