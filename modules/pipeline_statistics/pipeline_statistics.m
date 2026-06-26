#include "../debug/expose_from_debug.h"
#include <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <execinfo.h>
#include <stdint.h>

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
  double clockGatingMin;
  double clockGatingMax;

  double powerGatingMin;
  double powerGatingMax;

  uint32_t activeContexts;
  uint32_t queuedCommands;
  double memoryControllerLoad;
  char *powerState;
  uint32_t activeShaderCores;

  double temperatureMinC;
  double temperatureMaxC;

  double fanMinPercent;
  double fanMaxPercent;
} GPUSwState;

GPUSwState simulate_gpu_sw_states(double gpuTime, double gpuUtilization,
                                  uint64_t activeWarps, uint64_t totalThreads,
                                  double powerConsumption) {
  GPUSwState state = {0};

  NSProcessInfoThermalState thermalState =
      [NSProcessInfo processInfo].thermalState;

  switch (thermalState) {
  case NSProcessInfoThermalStateNominal:
    state.temperatureMinC = 35.0;
    state.temperatureMaxC = 75.0;
    state.fanMinPercent = 0.0;
    state.fanMaxPercent = 35.0;
    state.powerState = "P0";
    state.clockGatingMin = 0.0;
    state.clockGatingMax = 5.0;
    state.powerGatingMin = 0.0;
    state.powerGatingMax = 5.0;
    break;

  case NSProcessInfoThermalStateFair:
    state.temperatureMinC = 70.0;
    state.temperatureMaxC = 85.0;
    state.fanMinPercent = 20.0;
    state.fanMaxPercent = 60.0;
    state.powerState = "P1";
    state.clockGatingMin = 5.0;
    state.clockGatingMax = 20.0;
    state.powerGatingMin = 5.0;
    state.powerGatingMax = 15.0;
    break;

  case NSProcessInfoThermalStateSerious:
    state.temperatureMinC = 80.0;
    state.temperatureMaxC = 95.0;
    state.fanMinPercent = 60.0;
    state.fanMaxPercent = 100.0;
    state.powerState = "P2";
    state.clockGatingMin = 20.0;
    state.clockGatingMax = 50.0;
    state.powerGatingMin = 15.0;
    state.powerGatingMax = 35.0;
    break;

  case NSProcessInfoThermalStateCritical:
    state.temperatureMinC = 90.0;
    state.temperatureMaxC = 110.0;
    state.fanMinPercent = 90.0;
    state.fanMaxPercent = 100.0;
    state.powerState = "P3";
    state.clockGatingMin = 50.0;
    state.clockGatingMax = 80.0;
    state.powerGatingMin = 35.0;
    state.powerGatingMax = 60.0;
    break;
  }

  state.activeContexts = (uint32_t)(totalThreads / 1024) + 1;
  state.queuedCommands =
      (uint32_t)(state.activeContexts * (gpuUtilization * 10));

  state.memoryControllerLoad =
      gpuUtilization * 0.9 + (activeWarps / 256.0) * 0.1;
  state.memoryControllerLoad = fmin(1.0, state.memoryControllerLoad);

  const uint32_t MAX_SHADER_CORES = 2560;
  state.activeShaderCores = (uint32_t)(MAX_SHADER_CORES * gpuUtilization);

  if (thermalState == NSProcessInfoThermalStateCritical) {
    state.activeShaderCores = (uint32_t)(state.activeShaderCores * 0.8);
  }

  return state;
}

void print_gpu_sw_states(GPUSwState state) {
  log_printf(2, "Pipeline", "=== GPU Software States ===");
  log_printf(2, "Pipeline", "Power State: %s", state.powerState);

  log_printf(2, "Pipeline", "Temperature Range: %.1f°C - %.1f°C",
             state.temperatureMinC, state.temperatureMaxC);

  log_printf(2, "Pipeline", "Fan Speed Range: %.1f%% - %.1f%%",
             state.fanMinPercent, state.fanMaxPercent);

  log_printf(2, "Pipeline", "Clock Gating Range: %.1f%% - %.1f%%",
             state.clockGatingMin, state.clockGatingMax);

  log_printf(2, "Pipeline", "Power Gating Range: %.1f%% - %.1f%%",
             state.powerGatingMin, state.powerGatingMax);

  log_printf(2, "Pipeline", "Active Contexts: %u", state.activeContexts);
  log_printf(2, "Pipeline", "Queued Commands: %u", state.queuedCommands);
  log_printf(2, "Pipeline", "Memory Controller Load: %.1f%%",
             state.memoryControllerLoad * 100.0);
  log_printf(2, "Pipeline", "Active Shader Cores: %u", state.activeShaderCores);
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
    stats.currentFPS = fmin(gpuBasedFPS, systemMaxFPS);
    stats.actualFPS = gpuBasedFPS;

    // Update running FPS average
    static double totalFrameTime = 0.0;
    double frameDuration = fmax(stats.gpuTime, systemFrameTime);
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

    uint64_t totalThreads =
        threadBlockSize * activeWarps * 32; // 32 threads per warp

    double gpuUtilization = fmin(
        1.0, (double)activeWarps /
                 ((double)pipelineState.maxTotalThreadsPerThreadgroup / 32));

    // Base frequency estimation constants
    const double BASE_FREQUENCY_GHZ =
        1.5; // Conservative base frequency estimate
    const double MAX_FREQUENCY_GHZ = 2.5; // Maximum theoretical frequency

    double utilizationFactor =
        stats.kernelOccupancy * ((double)activeWarps / 64.0);
    utilizationFactor = fmin(1.0, utilizationFactor);

    double operationsPerSecond = stats.shaderInvocationCount / stats.gpuTime;

    double estimatedFrequency =
        (operationsPerSecond / (utilizationFactor * 1e9));

    double thermalFactor;
    switch ([[NSProcessInfo processInfo] thermalState]) {
    case NSProcessInfoThermalStateNominal:
      thermalFactor = 1.0;
      break;
    case NSProcessInfoThermalStateFair:
      thermalFactor = 0.925;
      break;
    case NSProcessInfoThermalStateSerious:
      thermalFactor = 0.8;
      break;
    case NSProcessInfoThermalStateCritical:
      thermalFactor = 0.65;
      break;
    default:
      thermalFactor = 1.0;
      break;
    }

    double finalFrequency =
        fmin(MAX_FREQUENCY_GHZ,
             fmax(BASE_FREQUENCY_GHZ, estimatedFrequency * thermalFactor));

    // Print comprehensive statistics
    log_printf(2, "Pipeline", "=== Pipeline Statistics ===");
    log_printf(2, "Pipeline", "Performance Metrics:");
    log_printf(2, "Pipeline", "Realistic Frames: %.2f", stats.currentFPS);
    log_printf(2, "Pipeline", "Actual Frames: %.2f", stats.actualFPS);

    log_printf(2, "Pipeline", "==GPU Metrics:==");
    log_printf(2, "Pipeline", "GPU Time: %.3f ms", stats.gpuTime * 1000.0);
    log_printf(2, "Pipeline", "GPU Frequency: %.2f GHz", finalFrequency);
    log_printf(2, "Pipeline", "GPU Utilization: %.2f%%",
               gpuUtilization * 100.0);

    log_printf(2, "Pipeline", "==Kernel Metrics:==");
    log_printf(2, "Pipeline", "Kernel Occupancy: %.2f%%",
               stats.kernelOccupancy * 100.0);
    log_printf(2, "Pipeline", "Active Warps: %llu", stats.activeWarps);
    log_printf(2, "Pipeline", "Max Warps: %llu", stats.maxWarps);
    log_printf(2, "Pipeline", "Thread Block Size: %llu", stats.threadBlockSize);
    log_printf(2, "Pipeline", "Grid Size: %llu", stats.gridSize);
    log_printf(2, "Pipeline", "Thread Execution Width: %lu",
               (unsigned long)stats.threadExecutionWidth);
    log_printf(2, "Pipeline", "Shader Invocation Count: %lu",
               (unsigned long)stats.shaderInvocationCount);
    log_printf(2, "Pipeline", "Threadgroup Occupancy: %.2f%%",
               stats.threadgroupOccupancy * 100.0);
    log_printf(2, "Pipeline", "Thread Divergence: %.2f%%",
               threadDivergence * 100.0);
    log_printf(2, "Pipeline", "Kernel Performance: %s", kernel_performance);
    log_printf(2, "Pipeline", "Total Threads: %llu", totalThreads);

    log_printf(2, "Pipeline", "==Shader Metrics:==");
    log_printf(2, "Pipeline", "Shader Complexity: %s", shaderComplexity);
    log_printf(2, "Pipeline", "Instructions per Thread: %.2f",
               instructionsPerThread);
    log_printf(2, "Pipeline", "Arithmetic Intensity: %.20Le ops/mem access",
               arithmeticIntensity);
    log_printf(2, "Pipeline", "Compute Intensity: %.2f",
               shaderMetrics.computeIntensity);
    log_printf(2, "Pipeline", "Memory Pressure: %.2f%%",
               shaderMetrics.memoryPressure * 100.0);
    log_printf(2, "Pipeline", "Branch Divergence: %.2f%%",
               shaderMetrics.branchDivergence * 100.0);
    log_printf(2, "Pipeline", "Register Pressure: %.2f%%",
               shaderMetrics.registerPressure * 100.0);
    log_printf(2, "Pipeline", "SIMD Utilization: %.2f%%",
               simdUtilization * 100.0);
    log_printf(2, "Pipeline", "Overall Shader Efficiency: %.2f%%",
               shaderEfficiency * 100.0);

    log_printf(2, "Pipeline", "==CPU Metrics:==");
    log_printf(2, "Pipeline", "CPU Usage: %.2f%%", stats.cpuUsage);
    log_printf(2, "Pipeline", "Program Memory Usage: %.2f MB",
               stats.usedMemory / 1e6);

    log_printf(2, "Pipeline", "==Interface Metrics:==");
    log_printf(2, "Pipeline", "GPU-CPU Transfer Time: %.3f ms",
               stats.gpuToCpuTransferTime * 1000.0);
    log_printf(2, "Pipeline", "GPU-CPU Transfer Efficiency: %.2f%%",
               gpuToCpuTransferEfficiency * 100.0);
    log_printf(2, "Pipeline", "Approximate Bandwidth: %.2f GB/s",
               stats.gpuToCpuBandwidth / 1e9);

    GPUSwState swState = simulate_gpu_sw_states(stats.gpuTime, gpuUtilization,
                                                activeWarps, totalThreads, 0.0);
    print_gpu_sw_states(swState);

    log_printf(2, "Pipeline", "==Cache Metrics:==");
    log_printf(2, "Pipeline", "Cache Hits: %llu", cacheHits);
    log_printf(2, "Pipeline", "Cache Misses: %llu", cacheMisses);
    log_printf(2, "Pipeline", "Total accesses: %llu", totalAccesses);
    log_printf(2, "Pipeline", "==Shader Optimization Recommendations:==");
    if (shaderMetrics.memoryPressure > 0.6) {
      log_printf(2, "Pipeline", "- Consider optimizing memory access patterns");
      log_printf(2, "Pipeline", "- Evaluate potential for memory coalescing");
    }
    if (shaderMetrics.branchDivergence > 0.5) {
      log_printf(2, "Pipeline",
                 "- High branch divergence detected. Consider reorganizing "
                 "conditional logic");
      log_printf(2, "Pipeline",
                 "- Evaluate potential for predication instead of branching");
    }
    if (shaderMetrics.registerPressure > 0.7) {
      log_printf(2, "Pipeline",
                 "- High register pressure. Consider splitting kernel or "
                 "reducing local variables");
    }
    if (simdUtilization < 0.7) {
      log_printf(2, "Pipeline",
                 "- Low SIMD utilization. Review work distribution and "
                 "thread block size");
    }

    if (stats.gpuTime > 0.001) { // More than 1ms
      log_printf(2, "Pipeline", "\nPerformance Analysis:");
      log_printf(2, "Pipeline", "- Long GPU execution time detected (%.3f ms)",
                 stats.gpuTime * 1000.0);
      log_printf(2, "Pipeline",
                 "- Consider reviewing shader complexity and memory access "
                 "patterns");
      if (stats.kernelOccupancy < 0.7) {
        log_printf(2, "Pipeline",
                   "- Low kernel occupancy (%.2f%%). Consider adjusting "
                   "thread block size",
                   stats.kernelOccupancy * 100.0);
      }
      if (stats.currentFPS < systemMaxFPS) {
        log_printf(2, "Pipeline",
                   "- Low frame rate (%.2f FPS). Consider optimization "
                   "strategies",
                   stats.currentFPS);
      }
    }

    log_printf(2, "Pipeline", "\nStack Trace:");
    log_printf(2, "Pipeline", "%s", [stackTrace UTF8String]);
  }];

  return stats;
}
