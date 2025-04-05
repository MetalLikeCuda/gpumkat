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
RenderPipelineStats collect_render_pipeline_statistics(
    id<MTLCommandBuffer> commandBuffer,
    id<MTLRenderPipelineState> pipelineState,
    MTLRenderPassDescriptor *renderPassDescriptor, NSUInteger vertexCount,
    NSUInteger instanceCount, NSUInteger drawCallCount);
#endif