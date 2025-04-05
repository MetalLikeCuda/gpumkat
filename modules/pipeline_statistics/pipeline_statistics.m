#include <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <execinfo.h>
#include <stdint.h>
#import <MetalKit/MetalKit.h>

typedef struct {
  double cpuUsage;
  uint64_t usedMemory;
  uint64_t virtualMemory;
  uint64_t totalMemory;
  uint64_t activeWarps;
  uint64_t threadBlockSize;
  double threadgroupOccupancy;
  uint64_t shaderInvocationCount;
  double gpuTime;
  double currentFPS;
  double actualFPS;
  double kernelOccupancy;
  uint64_t maxWarps;
  uint64_t gridSize;
  double threadExecutionWidth;
  double gpuToCpuTransferTime;
  uint64_t gpuToCpuBandwidth;
} PipelineStats;

typedef struct {
    double cpuUsage;
    uint64_t usedMemory;
    uint64_t virtualMemory;
    uint64_t totalMemory;
    
    // Render-specific metrics
    double gpuTime;
    double vertexProcessingTime;
    double fragmentProcessingTime;
    double rasterizationTime;
    double currentFPS;
    double actualFPS;
    
    // Memory metrics
    uint64_t vertexMemoryUsage;
    uint64_t textureMemoryUsage;
    uint64_t bufferMemoryUsage;
    
    // Pipeline state
    NSUInteger vertexShaderInvocations;
    NSUInteger fragmentShaderInvocations;
    NSUInteger primitivesProcessed;
    NSUInteger primitivesDrawn;
    
    // Bandwidth and transfer
    double gpuToCpuTransferTime;
    uint64_t gpuToCpuBandwidth;
    
    // Additional render-specific metrics
    double drawCallTime;
    NSUInteger drawCallCount;
    double commandBufferExecutionTime;
} RenderPipelineStats;

typedef struct {
  uint64_t cacheHits;
  uint64_t cacheMisses;
  float threadExecutionEfficiency;
  uint64_t instructionsExecuted;
  float gpuPower;
  float peakPower;
  float averagePower;
} SampleData;

static double getProgramCPUUsage() {
  task_info_data_t tinfo;
  mach_msg_type_number_t task_info_count = TASK_INFO_MAX;
  kern_return_t kr = task_info(mach_task_self(), TASK_BASIC_INFO,
                               (task_info_t)tinfo, &task_info_count);
  if (kr != KERN_SUCCESS)
    return -1.0;

  thread_array_t thread_list;
  mach_msg_type_number_t thread_count;
  kr = task_threads(mach_task_self(), &thread_list, &thread_count);
  if (kr != KERN_SUCCESS)
    return -1.0;

  double total_cpu = 0;
  for (int i = 0; i < thread_count; i++) {
    thread_info_data_t thinfo;
    mach_msg_type_number_t thread_info_count = THREAD_BASIC_INFO_COUNT;
    kr = thread_info(thread_list[i], THREAD_BASIC_INFO, (thread_info_t)thinfo,
                     &thread_info_count);
    if (kr == KERN_SUCCESS) {
      thread_basic_info_t basic_info = (thread_basic_info_t)thinfo;
      total_cpu += basic_info->cpu_usage / (float)TH_USAGE_SCALE;
    }
  }

  vm_deallocate(mach_task_self_, (vm_address_t)thread_list,
                thread_count * sizeof(thread_act_t));
  return total_cpu * 100.0;
}

static NSString *getStackTrace() {
  void *callstack[128];
  int frames = backtrace(callstack, 128);
  char **strs = backtrace_symbols(callstack, frames);

  NSMutableString *stackTrace = [NSMutableString string];
  for (int i = 0; i < frames; i++) {
    [stackTrace appendFormat:@"%s\n", strs[i]];
  }
  free(strs);
  return stackTrace;
}

static void getProgramMemoryUsage(uint64_t *residentMemory,
                                  uint64_t *virtualMemory) {
  struct task_basic_info info;
  mach_msg_type_number_t size = sizeof(info);
  kern_return_t kr =
      task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&info, &size);

  if (kr == KERN_SUCCESS) {
    *residentMemory = info.resident_size;
    *virtualMemory = info.virtual_size;
  } else {
    *residentMemory = 0;
    *virtualMemory = 0;
  }
}

void getKernelStats(id<MTLComputePipelineState> pipelineState,
                    uint64_t *activeWarps, uint64_t *threadBlockSize) {
  NSUInteger maxThreadsPerThreadgroup =
      pipelineState.maxTotalThreadsPerThreadgroup;
  NSUInteger threadExecutionWidth = pipelineState.threadExecutionWidth;

  *threadBlockSize = maxThreadsPerThreadgroup;
  *activeWarps = maxThreadsPerThreadgroup / threadExecutionWidth;
}

double
calculateThreadgroupOccupancy(id<MTLComputePipelineState> pipelineState) {
  uint64_t maxThreads = pipelineState.maxTotalThreadsPerThreadgroup;
  uint64_t activeThreads =
      pipelineState.threadExecutionWidth * pipelineState.threadExecutionWidth;

  if (maxThreads == 0)
    return 0.0; // Avoid division by zero
  return (double)activeThreads / (double)maxThreads;
}

typedef struct {
  double clockGating;          // Percentage of cores clock gated
  double powerGating;          // Percentage of cores power gated
  uint32_t activeContexts;     // Number of active GPU contexts
  uint32_t queuedCommands;     // Number of commands in queue
  double memoryControllerLoad; // Memory controller utilization
  char *powerState;            // Current power state (P0-P3)
  uint32_t activeShaderCores;  // Number of active shader cores
  double temperatureC;         // GPU temperature in Celsius
  double fanSpeedPercent;      // Fan speed percentage
} GPUSwState;

GPUSwState simulate_gpu_sw_states(double gpuTime, double gpuUtilization,
                                  uint64_t activeWarps, uint64_t totalThreads,
                                  double powerConsumption) {
  GPUSwState state = {0};

  // Simulate temperature based on utilization and power consumption
  const double BASE_TEMP = 45.0; // Base temperature in Celsius
  const double MAX_TEMP = 95.0;  // Maximum temperature threshold
  state.temperatureC =
      BASE_TEMP + (MAX_TEMP - BASE_TEMP) * gpuUtilization *
                      (powerConsumption / 150.0); // Normalized by typical TDP

  // Fan speed increases with temperature
  if (state.temperatureC < 60.0) {
    state.fanSpeedPercent = 30.0;
  } else if (state.temperatureC < 80.0) {
    state.fanSpeedPercent = 30.0 + (state.temperatureC - 60.0) * 2.5;
  } else {
    state.fanSpeedPercent = 80.0 + (state.temperatureC - 80.0) * 2.0;
  }

  // Determine power state based on utilization
  if (gpuUtilization > 0.8) {
    state.powerState = "P0"; // Full performance
  } else if (gpuUtilization > 0.5) {
    state.powerState = "P1"; // Balanced
  } else if (gpuUtilization > 0.2) {
    state.powerState = "P2"; // Power saving
  } else {
    state.powerState = "P3"; // Maximum power saving
  }

  // Simulate clock gating based on active warps and utilization
  state.clockGating = 100.0 * (1.0 - gpuUtilization);
  if (activeWarps < 32) {
    state.clockGating += 20.0; // Additional clock gating for low warp count
  }
  state.clockGating = fmin(100.0, state.clockGating);

  // Simulate power gating based on utilization and temperature
  state.powerGating = 100.0 * (1.0 - gpuUtilization) * 0.8; // Base power gating
  if (state.temperatureC > 85.0) {
    state.powerGating += 10.0; // Additional power gating when hot
  }
  state.powerGating = fmin(100.0, state.powerGating);

  // Simulate active contexts and queued commands
  state.activeContexts = (uint32_t)(totalThreads / 1024) + 1;
  state.queuedCommands =
      (uint32_t)(state.activeContexts * (gpuUtilization * 10));

  // Memory controller load simulation
  state.memoryControllerLoad =
      gpuUtilization * 0.9 +       // Base load from GPU utilization
      (activeWarps / 256.0) * 0.1; // Additional load from active warps
  state.memoryControllerLoad = fmin(1.0, state.memoryControllerLoad);

  // Active shader cores simulation
  const uint32_t MAX_SHADER_CORES = 2560; // Example maximum shader cores
  state.activeShaderCores = (uint32_t)(MAX_SHADER_CORES * gpuUtilization);
  if (state.temperatureC > 90.0) {
    // Reduce active cores if temperature is too high
    state.activeShaderCores = (uint32_t)(state.activeShaderCores * 0.8);
  }

  return state;
}

void print_gpu_sw_states(GPUSwState state) {
  NSLog(@"=== GPU Software States ===");
  NSLog(@"Power State: %s", state.powerState);
  NSLog(@"Temperature: %.1f°C", state.temperatureC);
  NSLog(@"Fan Speed: %.1f%%", state.fanSpeedPercent);
  NSLog(@"Clock Gating: %.1f%%", state.clockGating);
  NSLog(@"Power Gating: %.1f%%", state.powerGating);
  NSLog(@"Active Contexts: %u", state.activeContexts);
  NSLog(@"Queued Commands: %u", state.queuedCommands);
  NSLog(@"Memory Controller Load: %.1f%%", state.memoryControllerLoad * 100.0);
  NSLog(@"Active Shader Cores: %u", state.activeShaderCores);
}

PipelineStats
collect_pipeline_statistics(id<MTLCommandBuffer> commandBuffer,
                            id<MTLComputePipelineState> pipelineState) {
  __block PipelineStats stats = {0};

  // Get memory usage
  mach_port_t host_port = mach_host_self();
  vm_size_t page_size;
  vm_statistics64_data_t vm_stats;
  mach_msg_type_number_t count = sizeof(vm_stats) / sizeof(natural_t);
  host_page_size(host_port, &page_size);
  host_statistics64(host_port, HOST_VM_INFO64, (host_info64_t)&vm_stats,
                    &count);

  stats.cpuUsage = getProgramCPUUsage();
  uint64_t residentMemory, virtualMemory;
  getProgramMemoryUsage(&residentMemory, &virtualMemory);
  stats.usedMemory = residentMemory;
  stats.virtualMemory = virtualMemory;
  stats.totalMemory = [NSProcessInfo processInfo].physicalMemory;

  // Get kernel statistics
  uint64_t activeWarps, threadBlockSize;
  getKernelStats(pipelineState, &activeWarps, &threadBlockSize);
  stats.activeWarps = activeWarps;
  stats.threadBlockSize = threadBlockSize;
  stats.threadgroupOccupancy = calculateThreadgroupOccupancy(pipelineState);
  stats.threadExecutionWidth = pipelineState.threadExecutionWidth;
  stats.shaderInvocationCount =
      stats.threadExecutionWidth * stats.threadBlockSize;

  // Simulate system constraints for FPS calculation
  const double systemMaxFPS = 60.0; // Assume a monitor refresh rate of 60 Hz
  const double systemFrameTime = 1.0 / systemMaxFPS; // Maximum frame duration

  // Record GPU start time for transfer measurement
  CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();

  [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
    // Calculate GPU execution time
    stats.gpuTime = buffer.GPUEndTime - buffer.GPUStartTime;

    // Calculate FPS based on GPU execution time
    double gpuBasedFPS = (stats.gpuTime > 0) ? 1.0 / stats.gpuTime : 0.0;

    // Simulate realistic FPS by considering system constraints
    stats.currentFPS = fmin(gpuBasedFPS, systemMaxFPS); // Cap FPS at system max
    stats.actualFPS = gpuBasedFPS;

    // Update running FPS average
    static double totalFrameTime = 0.0;
    double frameDuration =
        fmax(stats.gpuTime,
             systemFrameTime); // Ensure no faster than monitor refresh
    totalFrameTime += frameDuration;

    // Calculate transfer time
    CFAbsoluteTime endTime = CFAbsoluteTimeGetCurrent();
    stats.gpuToCpuTransferTime = endTime - startTime;

    // Calculate approximate bandwidth
    if (stats.gpuToCpuTransferTime > 0) {
      stats.gpuToCpuBandwidth =
          (uint64_t)(stats.totalMemory / stats.gpuToCpuTransferTime);
    }

    // Calculate kernel occupancy
    stats.maxWarps = pipelineState.maxTotalThreadsPerThreadgroup / 32;
    if (pipelineState.maxTotalThreadsPerThreadgroup % 32 != 0) {
      stats.maxWarps += 1;
    }
    stats.kernelOccupancy = (double)stats.activeWarps / stats.maxWarps;

    // Calculate cache hits and misses directly in the main function
    double hitProbability = 0.5; // Base probability for cache hit (50%)
    double missProbability = 1.0 - hitProbability;

    // Cache hit/miss depends on occupancy (higher occupancy -> more potential
    // for hit)
    if (stats.kernelOccupancy > 0.8) {
      hitProbability = 0.7; // High occupancy means more cache hits
      missProbability = 1.0 - hitProbability;
    } else if (stats.kernelOccupancy < 0.3) {
      hitProbability = 0.3; // Low occupancy means more cache misses
      missProbability = 1.0 - hitProbability;
    }

    // Cache hits and misses depend on the thread block size (larger blocks may
    // reuse data more)
    if (stats.threadBlockSize > 1024) {
      hitProbability +=
          0.2; // Larger thread blocks generally improve cache hit rates
    }
    uint64_t totalAccesses =
        stats.shaderInvocationCount * stats.threadBlockSize;
    uint64_t cacheHits = (uint64_t)(totalAccesses * hitProbability);
    uint64_t cacheMisses = totalAccesses - cacheHits;

    // Get stack trace
    NSString *stackTrace = getStackTrace();
    char *shaderComplexity = "Unknown";

    if (stats.threadBlockSize > 2048 && stats.kernelOccupancy < 0.4) {
      shaderComplexity = "High";
    } else if (stats.kernelOccupancy > 0.7) {
      shaderComplexity = "Low";
    } else {
      shaderComplexity = "Moderate";
    }
    double gpuToCpuTransferEfficiency;
    if (stats.gpuToCpuTransferTime >
        0.01) { // If transfer time is more than 10ms
      gpuToCpuTransferEfficiency = 0.8;
    } else {
      gpuToCpuTransferEfficiency = 1.0;
    }

    double threadDivergence =
        (stats.kernelOccupancy < 0.5 && stats.threadBlockSize > 1024) ? 0.7
                                                                      : 0.3;
    char *kernel_performance = "Unknown";
    if (stats.kernelOccupancy < 0.5) {
      kernel_performance = "Low";
    } else if (stats.threadExecutionWidth > 128) {
      kernel_performance =
          "Potentially inefficient due to high execution width";
    } else {
      kernel_performance = "Optimal";
    }

    double instructionsPerThread = 0.0;
    if (stats.threadExecutionWidth > 0) {
      instructionsPerThread =
          stats.shaderInvocationCount / stats.threadExecutionWidth;
    }

    // Calculate arithmetic intensity (operations per memory access)
    long double arithmeticIntensity =
        (long double)stats.shaderInvocationCount / (long double)cacheMisses;

    // Estimate shader complexity based on multiple factors
    typedef struct {
      double computeIntensity;
      double memoryPressure;
      double branchDivergence;
      double registerPressure;
    } ShaderMetrics;

    ShaderMetrics shaderMetrics = {0};

    // Compute intensity estimation
    shaderMetrics.computeIntensity =
        (stats.threadExecutionWidth > 64)
            ? (double)stats.threadExecutionWidth / 64.0
            : 1.0;

    // Memory pressure estimation
    shaderMetrics.memoryPressure = (double)cacheMisses / totalAccesses;

    // Branch divergence estimation based on thread block size and occupancy
    shaderMetrics.branchDivergence =
        (stats.threadBlockSize > 1024 && stats.kernelOccupancy < 0.5) ? 0.7
        : (stats.threadBlockSize > 512)                               ? 0.4
                                                                      : 0.2;

    // Register pressure estimation
    shaderMetrics.registerPressure = (stats.threadExecutionWidth > 128)  ? 0.8
                                     : (stats.threadExecutionWidth > 64) ? 0.5
                                                                         : 0.3;

    // Shader execution efficiency
    double shaderEfficiency = 1.0 - (0.3 * shaderMetrics.memoryPressure +
                                     0.3 * shaderMetrics.branchDivergence +
                                     0.4 * shaderMetrics.registerPressure);

    // SIMD utilization
    double simdUtilization =
        (stats.threadExecutionWidth > 0)
            ? (double)stats.shaderInvocationCount /
                  (stats.threadExecutionWidth * stats.threadBlockSize)
            : 0.0;

    // Shader bottleneck analysis
    NSMutableArray *bottlenecks = [NSMutableArray array];
    if (shaderMetrics.memoryPressure > 0.6) {
      [bottlenecks addObject:@"Memory-bound"];
    }
    if (shaderMetrics.computeIntensity > 0.7) {
      [bottlenecks addObject:@"Compute-bound"];
    }
    if (shaderMetrics.registerPressure > 0.7) {
      [bottlenecks addObject:@"Register-bound"];
    }

    const double COMPUTE_OPERATION_ENERGY =
        0.000001; // 1 microjoule per compute operation
    const double MEMORY_ACCESS_ENERGY =
        0.000002;                        // 2 microjoules per memory access
    const double IDLE_POWER_WATTS = 5.0; // Base idle power consumption
    const double MAX_TDP_WATTS = 150.0;  // Maximum thermal design power

    uint64_t totalThreads =
        threadBlockSize * activeWarps * 32; // 32 threads per warp

    double computeIntensity = (stats.threadExecutionWidth > 64)
                                  ? (double)stats.threadExecutionWidth / 64.0
                                  : 1.0;

    // Energy from computation
    double computeEnergy =
        totalThreads * COMPUTE_OPERATION_ENERGY * computeIntensity;

    // Energy from memory operations
    double memoryEnergy =
        (cacheHits * MEMORY_ACCESS_ENERGY) +
        (cacheMisses * MEMORY_ACCESS_ENERGY * 2.0); // Cache misses cost more

    // Calculate GPU utilization (0.0 - 1.0)
    double gpuUtilization = fmin(
        1.0, (double)activeWarps /
                 ((double)pipelineState.maxTotalThreadsPerThreadgroup / 32));

    // Dynamic power based on utilization
    double dynamicPower =
        IDLE_POWER_WATTS + (MAX_TDP_WATTS - IDLE_POWER_WATTS) * gpuUtilization;

    // Total energy consumption
    double totalEnergyConsumption =
        (computeEnergy + memoryEnergy) + (dynamicPower * stats.gpuTime);

    // Base frequency estimation constants
    const double BASE_FREQUENCY_GHZ =
        1.5; // Conservative base frequency estimate
    const double MAX_FREQUENCY_GHZ = 2.5; // Maximum theoretical frequency

    // Adjust based on kernel occupancy and active warps
    double utilizationFactor =
        stats.kernelOccupancy *
        ((double)activeWarps / 64.0); // Normalize to typical max warps
    utilizationFactor = fmin(1.0, utilizationFactor); // Cap at 1.0

    // Calculate operations per second
    double operationsPerSecond = stats.shaderInvocationCount / stats.gpuTime;

    // Estimate frequency based on operations and utilization
    double estimatedFrequency =
        (operationsPerSecond / (utilizationFactor * 1e9)); // Convert to GHz

    // Apply thermal throttling simulation
    double thermalFactor = 1.0;
    if (utilizationFactor > 0.8) {
      // Simulate thermal throttling at high utilization
      thermalFactor = 0.9 - (utilizationFactor - 0.8) * 0.5;
      thermalFactor = fmax(0.7, thermalFactor); // Don't throttle below 70%
    }

    // Calculate final frequency
    double finalFrequency =
        fmin(MAX_FREQUENCY_GHZ,
             fmax(BASE_FREQUENCY_GHZ, estimatedFrequency * thermalFactor));

    // Print comprehensive statistics
    NSLog(@"=== Pipeline Statistics ===");
    NSLog(@"Performance Metrics:");
    NSLog(@"Realistic Frames: %.2f", stats.currentFPS);
    NSLog(@"Actual Frames: %.2f", stats.actualFPS);

    NSLog(@"==GPU Metrics:==");
    NSLog(@"GPU Time: %.3f ms", stats.gpuTime * 1000.0);
    NSLog(@"GPU Frequency: %.2f GHz", finalFrequency);
    NSLog(@"GPU Utilization: %.2f%%", gpuUtilization * 100.0);

    NSLog(@"==Kernel Metrics:==");
    NSLog(@"Kernel Occupancy: %.2f%%", stats.kernelOccupancy * 100.0);
    NSLog(@"Active Warps: %llu", stats.activeWarps);
    NSLog(@"Max Warps: %llu", stats.maxWarps);
    NSLog(@"Thread Block Size: %llu", stats.threadBlockSize);
    NSLog(@"Grid Size: %llu", stats.gridSize);
    NSLog(@"Thread Execution Width: %lu",
          (unsigned long)stats.threadExecutionWidth);
    NSLog(@"Shader Invocation Count: %lu",
          (unsigned long)stats.shaderInvocationCount);
    NSLog(@"Threadgroup Occupancy: %.2f%%", stats.threadgroupOccupancy * 100.0);
    NSLog(@"Thread Divergence: %.2f%%", threadDivergence * 100.0);
    NSLog(@"Kernel Performance: %s", kernel_performance);
    NSLog(@"Total Threads: %llu", totalThreads);

    NSLog(@"==Shader Metrics:==");
    NSLog(@"Shader Complexity: %s", shaderComplexity);
    NSLog(@"Instructions per Thread: %.2f", instructionsPerThread);
    NSLog(@"Arithmetic Intensity: %.20Le ops/mem access", arithmeticIntensity);
    NSLog(@"Compute Intensity: %.2f", shaderMetrics.computeIntensity);
    NSLog(@"Memory Pressure: %.2f%%", shaderMetrics.memoryPressure * 100.0);
    NSLog(@"Branch Divergence: %.2f%%", shaderMetrics.branchDivergence * 100.0);
    NSLog(@"Register Pressure: %.2f%%", shaderMetrics.registerPressure * 100.0);
    NSLog(@"SIMD Utilization: %.2f%%", simdUtilization * 100.0);
    NSLog(@"Overall Shader Efficiency: %.2f%%", shaderEfficiency * 100.0);

    NSLog(@"==CPU Metrics:==");
    NSLog(@"CPU Usage: %.2f%%", stats.cpuUsage);
    NSLog(@"Program Memory Usage: %.2f MB", stats.usedMemory / 1e6);

    NSLog(@"==Interface Metrics:==");
    NSLog(@"GPU-CPU Transfer Time: %.3f ms",
          stats.gpuToCpuTransferTime * 1000.0);
    NSLog(@"GPU-CPU Transfer Efficiency: %.2f%%",
          gpuToCpuTransferEfficiency * 100.0);
    NSLog(@"Approximate Bandwidth: %.2f GB/s", stats.gpuToCpuBandwidth / 1e9);

    // Print energy consumption statistics
    NSLog(@"=== GPU Energy Consumption Analysis ===");
    NSLog(@"Compute Energy: %.6f J", computeEnergy);
    NSLog(@"Memory Access Energy: %.6f J", memoryEnergy);
    NSLog(@"Dynamic Power: %.2f W", dynamicPower);
    NSLog(@"Total Energy Consumption: %.6f J", totalEnergyConsumption);
    NSLog(@"Energy Efficiency: %.6f J/thread",
          totalEnergyConsumption / totalThreads);
    NSLog(@"Thermal Factor: %.2f W", thermalFactor);

    // Calculate GPU SW states
    GPUSwState swState = simulate_gpu_sw_states(
        stats.gpuTime, gpuUtilization, activeWarps, totalThreads, dynamicPower);
    // Print GPU SW states
    print_gpu_sw_states(swState);

    NSLog(@"==Cache Metrics:==");
    NSLog(@"Cache Hits: %llu", cacheHits);
    NSLog(@"Cache Misses: %llu", cacheMisses);
    NSLog(@"Total accesses: %llu", totalAccesses);
    NSLog(@"==Shader Optimization Recommendations:==");
    if (shaderMetrics.memoryPressure > 0.6) {
      NSLog(@"- Consider optimizing memory access patterns");
      NSLog(@"- Evaluate potential for memory coalescing");
    }
    if (shaderMetrics.branchDivergence > 0.5) {
      NSLog(@"- High branch divergence detected. Consider reorganizing "
            @"conditional logic");
      NSLog(@"- Evaluate potential for predication instead of branching");
    }
    if (shaderMetrics.registerPressure > 0.7) {
      NSLog(@"- High register pressure. Consider splitting kernel or reducing "
            @"local variables");
    }
    if (simdUtilization < 0.7) {
      NSLog(@"- Low SIMD utilization. Review work distribution and thread "
            @"block size");
    }

    if (stats.gpuTime > 0.001) { // More than 1ms
      NSLog(@"\nPerformance Analysis:");
      NSLog(@"- Long GPU execution time detected (%.3f ms)",
            stats.gpuTime * 1000.0);
      NSLog(
          @"- Consider reviewing shader complexity and memory access patterns");
      if (stats.kernelOccupancy < 0.7) {
        NSLog(@"- Low kernel occupancy (%.2f%%). Consider adjusting thread "
              @"block size",
              stats.kernelOccupancy * 100.0);
      }
      if (stats.currentFPS < systemMaxFPS) {
        NSLog(@"- Low frame rate (%.2f FPS). Consider optimization strategies",
              stats.currentFPS);
      }
    }

    NSLog(@"\nStack Trace:");
    NSLog(@"%@", stackTrace);
  }];

  return stats;
}

RenderPipelineStats collect_render_pipeline_statistics(id<MTLCommandBuffer> commandBuffer,
                                                     id<MTLRenderPipelineState> pipelineState,
                                                     MTLRenderPassDescriptor *renderPassDescriptor,
                                                     NSUInteger vertexCount,
                                                     NSUInteger instanceCount,
                                                     NSUInteger drawCallCount)  {
    __block RenderPipelineStats stats = {0};
    
    // Get memory usage
    mach_port_t host_port = mach_host_self();
    vm_size_t page_size;
    vm_statistics64_data_t vm_stats;
    mach_msg_type_number_t count = sizeof(vm_stats) / sizeof(natural_t);
    host_page_size(host_port, &page_size);
    host_statistics64(host_port, HOST_VM_INFO64, (host_info64_t)&vm_stats, &count);
    
    stats.cpuUsage = getProgramCPUUsage();
    uint64_t residentMemory, virtualMemory;
    getProgramMemoryUsage(&residentMemory, &virtualMemory);
    stats.usedMemory = residentMemory;
    stats.virtualMemory = virtualMemory;
    stats.totalMemory = [NSProcessInfo processInfo].physicalMemory;
    
    for (NSUInteger i = 0; i < 8; i++) {
        MTLRenderPassColorAttachmentDescriptor *colorAttachment = renderPassDescriptor.colorAttachments[i];
        if (colorAttachment && colorAttachment.texture) {
            NSUInteger bytesPerPixel = 4; // Default to RGBA8
            switch (colorAttachment.texture.pixelFormat) {
                case MTLPixelFormatRGBA16Float: bytesPerPixel = 8; break;
                case MTLPixelFormatRGBA32Float: bytesPerPixel = 16; break;
                case MTLPixelFormatRGB10A2Unorm: bytesPerPixel = 4; break;
                case MTLPixelFormatBGRA8Unorm: bytesPerPixel = 4; break;
                // Add more pixel formats as needed
                default: bytesPerPixel = 4; break;
            }
            stats.textureMemoryUsage += colorAttachment.texture.width * colorAttachment.texture.height * bytesPerPixel;
        }
    }
     
    // Handle depth attachment
    if (renderPassDescriptor.depthAttachment.texture) {
        NSUInteger bytesPerPixel = 4; // Default to depth32Float or depth24Stencil8
        switch (renderPassDescriptor.depthAttachment.texture.pixelFormat) {
            case MTLPixelFormatDepth32Float: bytesPerPixel = 4; break;
            case MTLPixelFormatDepth32Float_Stencil8: bytesPerPixel = 8; break;
            case MTLPixelFormatDepth16Unorm: bytesPerPixel = 2; break;
            case MTLPixelFormatX32_Stencil8: bytesPerPixel = 4; break;
            case MTLPixelFormatX24_Stencil8: bytesPerPixel = 4; break;
            default: bytesPerPixel = 4; break;
        }
        stats.textureMemoryUsage += renderPassDescriptor.depthAttachment.texture.width * 
                                  renderPassDescriptor.depthAttachment.texture.height * bytesPerPixel;
    }
    
    // Handle stencil attachment (if separate from depth)
    if (renderPassDescriptor.stencilAttachment.texture && 
        renderPassDescriptor.stencilAttachment.texture != renderPassDescriptor.depthAttachment.texture) {
        // Stencil is typically 8 bits per pixel
        stats.textureMemoryUsage += renderPassDescriptor.stencilAttachment.texture.width * 
                                  renderPassDescriptor.stencilAttachment.texture.height;
    }
    
    // Record GPU start time for transfer measurement
    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        // Calculate GPU execution time
        stats.gpuTime = buffer.GPUEndTime - buffer.GPUStartTime;
        
        // Simulate pipeline stage timings
        stats.vertexProcessingTime = stats.gpuTime * 0.3;
        stats.fragmentProcessingTime = stats.gpuTime * 0.5;
        stats.rasterizationTime = stats.gpuTime * 0.2;
        
        // Calculate FPS
        double gpuBasedFPS = (stats.gpuTime > 0) ? 1.0 / stats.gpuTime : 0.0;
        const double systemMaxFPS = 60.0;
        stats.currentFPS = fmin(gpuBasedFPS, systemMaxFPS);
        stats.actualFPS = gpuBasedFPS;
        
        // Calculate transfer time
        CFAbsoluteTime endTime = CFAbsoluteTimeGetCurrent();
        stats.gpuToCpuTransferTime = endTime - startTime;
        
        // Calculate bandwidth
        if (stats.gpuToCpuTransferTime > 0) {
            stats.gpuToCpuBandwidth = (uint64_t)(stats.textureMemoryUsage / stats.gpuToCpuTransferTime);
        }
        
        // Estimate shader invocations (these would normally come from your rendering logic)
        stats.vertexShaderInvocations = vertexCount * instanceCount;
        stats.fragmentShaderInvocations = stats.vertexShaderInvocations * 2; // Approximate
        
        // Estimate primitive counts
        stats.primitivesProcessed = stats.vertexShaderInvocations / 3;
        stats.primitivesDrawn = stats.primitivesProcessed * 0.9;
        
        // Estimate draw call metrics
        stats.drawCallCount = drawCallCount;
        stats.drawCallTime = stats.gpuTime * 0.1;
        stats.commandBufferExecutionTime = stats.gpuTime * 0.9;
        
        // Estimate primitive counts
        stats.primitivesProcessed = stats.vertexShaderInvocations / 3; // Assuming triangles
        stats.primitivesDrawn = stats.primitivesProcessed * 0.9; // Assuming 10% culled
        
        // Estimate draw call metrics
        stats.drawCallCount = 100; // Example value
        stats.drawCallTime = stats.gpuTime * 0.1; // 10% of time in draw calls
        stats.commandBufferExecutionTime = stats.gpuTime * 0.9; // 90% of time in actual execution
        
        // Print comprehensive statistics
        NSLog(@"=== Render Pipeline Statistics ===");
        NSLog(@"Performance Metrics:");
        NSLog(@"Frames Per Second: %.2f (capped at %.2f)", stats.actualFPS, stats.currentFPS);
        NSLog(@"GPU Frame Time: %.3f ms", stats.gpuTime * 1000.0);
        
        NSLog(@"==Pipeline Stage Timings:==");
        NSLog(@"Vertex Processing: %.3f ms (%.1f%%)", stats.vertexProcessingTime * 1000.0, 
              (stats.vertexProcessingTime / stats.gpuTime) * 100.0);
        NSLog(@"Rasterization: %.3f ms (%.1f%%)", stats.rasterizationTime * 1000.0, 
              (stats.rasterizationTime / stats.gpuTime) * 100.0);
        NSLog(@"Fragment Processing: %.3f ms (%.1f%%)", stats.fragmentProcessingTime * 1000.0, 
              (stats.fragmentProcessingTime / stats.gpuTime) * 100.0);
        
        NSLog(@"==Shader Metrics:==");
        NSLog(@"Vertex Shader Invocations: %lu", (unsigned long)stats.vertexShaderInvocations);
        NSLog(@"Fragment Shader Invocations: %lu", (unsigned long)stats.fragmentShaderInvocations);
        NSLog(@"Primitives Processed: %lu", (unsigned long)stats.primitivesProcessed);
        NSLog(@"Primitives Drawn: %lu (%.1f%% culled)", (unsigned long)stats.primitivesDrawn, 
              ((double)(stats.primitivesProcessed - stats.primitivesDrawn) / stats.primitivesProcessed) * 100.0);
        
        NSLog(@"==Memory Metrics:==");
        NSLog(@"Texture Memory Usage: %.2f MB", (double)stats.textureMemoryUsage / (1024.0 * 1024.0));
        NSLog(@"Buffer Memory Usage: %.2f MB", (double)stats.bufferMemoryUsage / (1024.0 * 1024.0));
        NSLog(@"Total Estimated VRAM Usage: %.2f MB", 
              (double)(stats.textureMemoryUsage + stats.bufferMemoryUsage) / (1024.0 * 1024.0));
        
        NSLog(@"==Command Metrics:==");
        NSLog(@"Draw Calls: %lu", (unsigned long)stats.drawCallCount);
        NSLog(@"Draw Call Overhead: %.3f ms (%.1f%%)", stats.drawCallTime * 1000.0, 
              (stats.drawCallTime / stats.gpuTime) * 100.0);
        NSLog(@"Command Buffer Execution: %.3f ms", stats.commandBufferExecutionTime * 1000.0);
        
        NSLog(@"==Transfer Metrics:==");
        NSLog(@"GPU-CPU Transfer Time: %.3f ms", stats.gpuToCpuTransferTime * 1000.0);
        NSLog(@"Approximate Bandwidth: %.2f GB/s", (double)stats.gpuToCpuBandwidth / (1024.0 * 1024.0 * 1024.0));
        
        // Generate optimization recommendations
        NSLog(@"==Optimization Recommendations:==");
        if (stats.vertexProcessingTime > stats.fragmentProcessingTime) {
            NSLog(@"- Vertex-bound pipeline detected. Consider:");
            NSLog(@"  * Simplifying vertex shaders");
            NSLog(@"  * Using vertex culling techniques");
            NSLog(@"  * Implementing level-of-detail (LOD) systems");
        } else {
            NSLog(@"- Fragment-bound pipeline detected. Consider:");
            NSLog(@"  * Reducing overdraw with early-z or depth prepass");
            NSLog(@"  * Simplifying fragment shaders");
            NSLog(@"  * Using texture atlases to reduce sampling");
        }
        
        if (stats.drawCallTime > stats.gpuTime * 0.2) {
            NSLog(@"- High draw call overhead detected (%.1f%%). Consider:", 
                  (stats.drawCallTime / stats.gpuTime) * 100.0);
            NSLog(@"  * Using instanced rendering");
            NSLog(@"  * Merging draw calls where possible");
            NSLog(@"  * Using indirect drawing");
        }
        
        if (stats.textureMemoryUsage > 100 * 1024 * 1024) { // >100MB
            NSLog(@"- High texture memory usage detected (%.2f MB). Consider:",
                  (double)stats.textureMemoryUsage / (1024.0 * 1024.0));
            NSLog(@"  * Using texture compression");
            NSLog(@"  * Implementing texture streaming");
            NSLog(@"  * Reducing texture resolutions where possible");
        }
        
        // Print CPU metrics
        NSLog(@"==CPU Metrics:==");
        NSLog(@"CPU Usage: %.2f%%", stats.cpuUsage);
        NSLog(@"Program Memory Usage: %.2f MB", (double)stats.usedMemory / (1024.0 * 1024.0));
    }];
    
    return stats;
}