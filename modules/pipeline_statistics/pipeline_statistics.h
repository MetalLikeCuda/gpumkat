#ifndef PIPELINE_STATISTICS
#define PIPELINE_STATISTICS
#include <Metal/Metal.h>
typedef struct {
  double gpuTime;
  double cpuUsage;
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
  double threadgroupOccupancy;
  uint64_t threadExecutionWidth;
  uint64_t shaderInvocationCount;
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

static double getProgramCPUUsage();
static NSString *getStackTrace();
static void getProgramMemoryUsage(uint64_t *residentMemory,
                                  uint64_t *virtualMemory);
void getKernelStats(id<MTLComputePipelineState> pipelineState,
                    uint64_t *activeWarps, uint64_t *threadBlockSize);
double calculateThreadgroupOccupancy(id<MTLComputePipelineState> pipelineState);
PipelineStats
collect_pipeline_statistics(id<MTLCommandBuffer> commandBuffer,
                            id<MTLComputePipelineState> pipelineState);
#endif
