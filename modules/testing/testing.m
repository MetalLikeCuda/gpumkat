#include "testing.h"
#include <mach/mach_time.h>
#include <sys/resource.h>
#include <time.h>

// Utility function to get current time in nanoseconds
static uint64_t get_time_ns(void) { return mach_absolute_time(); }

static double ns_to_ms(uint64_t ns) {
  mach_timebase_info_data_t timebase_info;
  mach_timebase_info(&timebase_info);
  return (double)ns * timebase_info.numer / timebase_info.denom / 1e6;
}

size_t get_memory_usage_mb(void) {
  struct rusage usage;
  if (getrusage(RUSAGE_SELF, &usage) == 0) {
    return usage.ru_maxrss / 1024 / 1024; // Convert to MB
  }
  return 0;
}

// Load test configuration from JSON file
TestSuite *load_test_config(const char *config_path) {
  printf("Loading test configuration from: %s\n", config_path);

  NSError *error = nil;
  NSString *configPath = [NSString stringWithUTF8String:config_path];
  NSData *jsonData = [NSData dataWithContentsOfFile:configPath];

  if (!jsonData) {
    fprintf(stderr, "Error: Could not read test configuration file: %s\n",
            config_path);
    return NULL;
  }

  id jsonObject =
      [NSJSONSerialization JSONObjectWithData:jsonData
                                      options:NSJSONReadingMutableContainers
                                        error:&error];

  if (error) {
    fprintf(stderr, "Error parsing JSON: %s\n",
            [[error localizedDescription] UTF8String]);
    return NULL;
  }

  if (![jsonObject isKindOfClass:[NSDictionary class]]) {
    fprintf(stderr, "Error: Test configuration must be a JSON object\n");
    return NULL;
  }

  NSDictionary *config = (NSDictionary *)jsonObject;
  TestSuite *suite = calloc(1, sizeof(TestSuite));

  // Parse suite information
  suite->name = strdup([[config objectForKey:@"name"] UTF8String]
                           ?: "Unnamed Test Suite");
  suite->description =
      strdup([[config objectForKey:@"description"] UTF8String] ?: "");
  suite->metallib_path =
      strdup([[config objectForKey:@"metallib_path"] UTF8String] ?: "");

  // Parse global configuration
  suite->stop_on_failure = [[config objectForKey:@"stop_on_failure"] boolValue];
  suite->verbose_output = [[config objectForKey:@"verbose_output"] boolValue];
  suite->generate_report = [[config objectForKey:@"generate_report"] boolValue];
  suite->report_path = strdup([[config objectForKey:@"report_path"] UTF8String]
                                  ?: "test_report.html");

  // Parse test cases
  NSArray *testCases = [config objectForKey:@"test_cases"];
  if (testCases && [testCases isKindOfClass:[NSArray class]]) {
    suite->test_case_count = [testCases count];
    suite->test_cases = calloc(suite->test_case_count, sizeof(TestCase));

    for (NSUInteger i = 0; i < suite->test_case_count; i++) {
      NSDictionary *testCaseDict = [testCases objectAtIndex:i];
      TestCase *testCase = &suite->test_cases[i];

      testCase->name =
          strdup([[testCaseDict objectForKey:@"name"] UTF8String] ?: "");
      testCase->description =
          strdup([[testCaseDict objectForKey:@"description"] UTF8String] ?: "");
      testCase->skip = [[testCaseDict objectForKey:@"skip"] boolValue];
      testCase->skip_reason =
          strdup([[testCaseDict objectForKey:@"skip_reason"] UTF8String] ?: "");
      testCase->timeout_ms =
          [[testCaseDict objectForKey:@"timeout_ms"] doubleValue] ?: 5000.0;
      testCase->max_execution_time_ms =
          [[testCaseDict objectForKey:@"max_execution_time_ms"] doubleValue]
              ?: 1000.0;
      testCase->max_memory_usage_mb =
          [[testCaseDict objectForKey:@"max_memory_usage_mb"] doubleValue]
              ?: 100.0;

      // Parse pipeline configuration
      NSString *pipelineTypeStr = [testCaseDict objectForKey:@"pipeline_type"];
      if ([pipelineTypeStr isEqualToString:@"render"]) {
        testCase->pipeline_type = PIPELINE_TYPE_RENDERER;
        testCase->vertex_shader = strdup(
            [[testCaseDict objectForKey:@"vertex_shader"] UTF8String] ?: "");
        testCase->fragment_shader = strdup(
            [[testCaseDict objectForKey:@"fragment_shader"] UTF8String] ?: "");
        testCase->render_target_pixel_format =
            MTLPixelFormatRGBA8Unorm; // Default, can be extended
        testCase->render_target_width =
            [[testCaseDict objectForKey:@"render_target_width"]
                unsignedIntegerValue]
                ?: 1;
        testCase->render_target_height =
            [[testCaseDict objectForKey:@"render_target_height"]
                unsignedIntegerValue]
                ?: 1;
      } else { // Default to compute
        testCase->pipeline_type = PIPELINE_TYPE_COMPUTE;
        testCase->shader_function = strdup(
            [[testCaseDict objectForKey:@"shader_function"] UTF8String] ?: "");
      }

      // Parse assertions
      NSArray *assertions = [testCaseDict objectForKey:@"assertions"];
      if (assertions && [assertions isKindOfClass:[NSArray class]]) {
        testCase->assertions =
            parse_assertions(assertions, &testCase->assertion_count);
      }

      // Initialize buffers and expected outputs arrays
      testCase->buffers = [[NSMutableArray alloc] init];
      testCase->expected_outputs = [[NSMutableArray alloc] init];

      // Parse input buffers
      NSArray *inputBuffers = [testCaseDict objectForKey:@"input_buffers"];
      if (inputBuffers && [inputBuffers isKindOfClass:[NSArray class]]) {
        for (NSDictionary *bufferDict in inputBuffers) {
          [testCase->buffers addObject:bufferDict];
        }
      }

      // Parse expected outputs
      NSArray *expectedOutputs =
          [testCaseDict objectForKey:@"expected_outputs"];
      if (expectedOutputs && [expectedOutputs isKindOfClass:[NSArray class]]) {
        for (NSDictionary *outputDict in expectedOutputs) {
          [testCase->expected_outputs addObject:outputDict];
        }
      }
    }
  }

  printf("Loaded test suite '%s' with %zu test cases\n", suite->name,
         suite->test_case_count);
  return suite;
}

// Parse assertions from JSON array
TestAssertion *parse_assertions(NSArray *assertion_array, size_t *count) {
  *count = [assertion_array count];
  if (*count == 0)
    return NULL;

  TestAssertion *assertions = calloc(*count, sizeof(TestAssertion));

  for (NSUInteger i = 0; i < *count; i++) {
    NSDictionary *assertDict = [assertion_array objectAtIndex:i];
    TestAssertion *assertion = &assertions[i];

    assertion->description =
        strdup([[assertDict objectForKey:@"description"] UTF8String] ?: "");

    NSString *typeStr = [assertDict objectForKey:@"type"];
    if ([typeStr isEqualToString:@"equals"]) {
      assertion->type = ASSERT_EQUALS;
    } else if ([typeStr isEqualToString:@"not_equals"]) {
      assertion->type = ASSERT_NOT_EQUALS;
    } else if ([typeStr isEqualToString:@"greater_than"]) {
      assertion->type = ASSERT_GREATER_THAN;
    } else if ([typeStr isEqualToString:@"less_than"]) {
      assertion->type = ASSERT_LESS_THAN;
    } else if ([typeStr isEqualToString:@"near"]) {
      assertion->type = ASSERT_NEAR;
      assertion->tolerance =
          [[assertDict objectForKey:@"tolerance"] floatValue] ?: 0.001f;
    } else if ([typeStr isEqualToString:@"buffer_equals"]) {
      assertion->type = ASSERT_BUFFER_EQUALS;
      assertion->buffer_name =
          strdup([[assertDict objectForKey:@"buffer_name"] UTF8String] ?: "");
    } else if ([typeStr isEqualToString:@"buffer_near"]) {
      assertion->type = ASSERT_BUFFER_NEAR;
      assertion->buffer_name =
          strdup([[assertDict objectForKey:@"buffer_name"] UTF8String] ?: "");
      assertion->tolerance =
          [[assertDict objectForKey:@"tolerance"] floatValue] ?: 0.001f;
    } else if ([typeStr isEqualToString:@"performance_lt"]) {
      assertion->type = ASSERT_PERFORMANCE_LT;
      assertion->performance_threshold =
          [[assertDict objectForKey:@"threshold_ms"] doubleValue];
    }

    // Parse values based on assertion type
    assertion->expected_float =
        [[assertDict objectForKey:@"expected"] floatValue];
    assertion->buffer_index = [[assertDict objectForKey:@"index"] intValue];
  }

  return assertions;
}

// Run the entire test suite
int run_test_suite(TestSuite *suite, const char *metallib_path) {
  printf("\n" COLOR_CYAN "=== Running Test Suite: %s ===" COLOR_RESET "\n",
         suite->name);
  if (strlen(suite->description) > 0) {
    printf("Description: %s\n", suite->description);
  }
  printf("Total tests: %zu\n\n", suite->test_case_count);

  // Initialize test context
  TestContext context = {0};
  context.device = MTLCreateSystemDefaultDevice();
  if (!context.device) {
    fprintf(stderr, "Error: Metal is not supported on this device\n");
    return -1;
  }

  context.command_queue = [context.device newCommandQueue];
  if (!context.command_queue) {
    fprintf(stderr, "Error: Failed to create command queue\n");
    return -1;
  }

  // Load Metal library
  NSString *libPath =
      metallib_path ? [NSString stringWithUTF8String:metallib_path]
                    : [NSString stringWithUTF8String:suite->metallib_path];
  NSError *error = nil;
  context.library =
      [context.device newLibraryWithURL:[NSURL fileURLWithPath:libPath]
                                  error:&error];
  if (!context.library) {
    fprintf(stderr, "Error loading Metal library: %s\n",
            [[error localizedDescription] UTF8String]);
    return -1;
  }

  context.metal_buffers = [[NSMutableDictionary alloc] init];
  context.test_errors = [[NSMutableArray alloc] init];
  context.initial_memory_usage = get_memory_usage_mb();

  // Run each test case
  uint64_t suite_start_time = get_time_ns();

  for (size_t i = 0; i < suite->test_case_count; i++) {
    TestCase *test_case = &suite->test_cases[i];

    if (test_case->skip) {
      test_case->status = TEST_STATUS_SKIPPED;
      suite->skipped_tests++;
      printf(COLOR_YELLOW "[SKIP]" COLOR_RESET " %s", test_case->name);
      if (strlen(test_case->skip_reason) > 0) {
        printf(" - %s", test_case->skip_reason);
      }
      printf("\n");
      continue;
    }

    printf(COLOR_BLUE "[RUN ]" COLOR_RESET " %s\n", test_case->name);

    int result = run_single_test(test_case, &context);

    switch (test_case->status) {
    case TEST_STATUS_PASSED:
      suite->passed_tests++;
      printf(COLOR_GREEN "[PASS]" COLOR_RESET " %s (%.2fms)\n", test_case->name,
             test_case->actual_execution_time_ms);
      break;
    case TEST_STATUS_FAILED:
      suite->failed_tests++;
      printf(COLOR_RED "[FAIL]" COLOR_RESET " %s (%.2fms)\n", test_case->name,
             test_case->actual_execution_time_ms);
      if (test_case->failure_message) {
        printf("        %s\n", test_case->failure_message);
      }
      if (suite->stop_on_failure) {
        printf("\nStopping test execution due to failure\n");
        break;
      }
      break;
    case TEST_STATUS_ERROR:
      suite->error_tests++;
      printf(COLOR_RED "[ERROR]" COLOR_RESET " %s\n", test_case->name);
      if (test_case->failure_message) {
        printf("         %s\n", test_case->failure_message);
      }
      break;
    default:
      break;
    }

    if (suite->verbose_output) {
      printf("         Assertions: %zu passed, %zu failed\n",
             test_case->passed_assertions, test_case->failed_assertions);
      printf("         Memory usage: %.2f MB\n",
             test_case->actual_memory_usage_mb);
    }

    if (suite->stop_on_failure && test_case->status == TEST_STATUS_FAILED) {
      break;
    }
  }

  uint64_t suite_end_time = get_time_ns();
  suite->total_execution_time_ms = ns_to_ms(suite_end_time - suite_start_time);
  suite->total_tests = suite->test_case_count;

  // Print summary
  print_test_summary(suite);

  // Generate report if requested
  if (suite->generate_report) {
    generate_test_report(suite);
  }

  // Cleanup
  cleanup_test_context(&context);

  return (suite->failed_tests > 0 || suite->error_tests > 0) ? 1 : 0;
}

int run_single_test(TestCase *test_case, TestContext *context) {
  test_case->test_start_time = get_time_ns();
  size_t initial_memory = get_memory_usage_mb();
  NSError *error = nil;

  // Prepare input buffers (common for both pipelines)
  [context->metal_buffers removeAllObjects];
  for (NSDictionary *bufferDict in test_case->buffers) {
    NSString *bufferName = [bufferDict objectForKey:@"name"];
    NSArray *data = [bufferDict objectForKey:@"data"];
    NSUInteger size = [[bufferDict objectForKey:@"size"] unsignedIntegerValue]
                          ?: [data count];

    id<MTLBuffer> buffer =
        [context->device newBufferWithLength:size * sizeof(float)
                                     options:MTLResourceStorageModeShared];
    if (!buffer) {
      record_test_result(test_case, TEST_STATUS_ERROR,
                         "Failed to create buffer");
      return -1;
    }

    // Initialize buffer with test data
    float *bufferPtr = (float *)[buffer contents];
    for (NSUInteger i = 0; i < MIN(size, [data count]); i++) {
      bufferPtr[i] = [[data objectAtIndex:i] floatValue];
    }

    [context->metal_buffers setObject:buffer forKey:bufferName];
  }

  id<MTLCommandBuffer> commandBuffer = [context->command_queue commandBuffer];

  if (test_case->pipeline_type == PIPELINE_TYPE_RENDERER) {
    // --- RENDER PIPELINE ---
    NSString *vertexFuncName =
        [NSString stringWithUTF8String:test_case->vertex_shader];
    NSString *fragmentFuncName =
        [NSString stringWithUTF8String:test_case->fragment_shader];
    id<MTLFunction> vertexFunc =
        [context->library newFunctionWithName:vertexFuncName];
    id<MTLFunction> fragmentFunc =
        [context->library newFunctionWithName:fragmentFuncName];

    if (!vertexFunc || !fragmentFunc) {
      record_test_result(test_case, TEST_STATUS_ERROR,
                         "Render shader function not found");
      return -1;
    }

    MTLRenderPipelineDescriptor *pipelineDescriptor =
        [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.vertexFunction = vertexFunc;
    pipelineDescriptor.fragmentFunction = fragmentFunc;
    pipelineDescriptor.colorAttachments[0].pixelFormat =
        test_case->render_target_pixel_format;

    id<MTLRenderPipelineState> pipelineState =
        [context->device newRenderPipelineStateWithDescriptor:pipelineDescriptor
                                                        error:&error];
    if (!pipelineState) {
      char error_msg[512];
      snprintf(error_msg, sizeof(error_msg),
               "Failed to create render pipeline state: %s",
               [[error localizedDescription] UTF8String]);
      record_test_result(test_case, TEST_STATUS_ERROR, error_msg);
      return -1;
    }

    MTLTextureDescriptor *texDesc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:test_case->render_target_pixel_format
                                     width:test_case->render_target_width
                                    height:test_case->render_target_height
                                 mipmapped:NO];
    texDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    id<MTLTexture> renderTargetTexture =
        [context->device newTextureWithDescriptor:texDesc];

    MTLRenderPassDescriptor *renderPassDescriptor =
        [MTLRenderPassDescriptor renderPassDescriptor];
    renderPassDescriptor.colorAttachments[0].texture = renderTargetTexture;
    renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    renderPassDescriptor.colorAttachments[0].clearColor =
        MTLClearColorMake(0, 0, 0, 0);

    id<MTLRenderCommandEncoder> encoder =
        [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    [encoder setRenderPipelineState:pipelineState];

    NSUInteger bufferIndex = 0;
    for (NSString *bufferName in context->metal_buffers) {
      id<MTLBuffer> buffer = [context->metal_buffers objectForKey:bufferName];
      [encoder setVertexBuffer:buffer offset:0 atIndex:bufferIndex++];
    }

    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                vertexStart:0
                vertexCount:4];
    [encoder endEncoding];

    // Copy render target to a buffer for analysis
    id<MTLBuffer> outputBuffer = [context->device
        newBufferWithLength:test_case->render_target_width *
                            test_case->render_target_height * 4 * sizeof(float)
                    options:MTLResourceStorageModeShared];
    id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
    [blitEncoder copyFromTexture:renderTargetTexture
                     sourceSlice:0
                     sourceLevel:0
                    sourceOrigin:MTLOriginMake(0, 0, 0)
                      sourceSize:MTLSizeMake(renderTargetTexture.width,
                                             renderTargetTexture.height, 1)
                        toBuffer:outputBuffer
               destinationOffset:0
          destinationBytesPerRow:renderTargetTexture.width * 4 * sizeof(float)
        destinationBytesPerImage:0];
    [blitEncoder endEncoding];
    [context->metal_buffers setObject:outputBuffer forKey:@"__render_output"];

  } else {
    // --- COMPUTE PIPELINE ---
    NSString *functionName =
        [NSString stringWithUTF8String:test_case->shader_function];
    id<MTLFunction> function =
        [context->library newFunctionWithName:functionName];
    if (!function) {
      record_test_result(test_case, TEST_STATUS_ERROR,
                         "Shader function not found");
      return -1;
    }

    id<MTLComputePipelineState> pipelineState =
        [context->device newComputePipelineStateWithFunction:function
                                                       error:&error];
    if (!pipelineState) {
      char error_msg[512];
      snprintf(error_msg, sizeof(error_msg),
               "Failed to create pipeline state: %s",
               [[error localizedDescription] UTF8String]);
      record_test_result(test_case, TEST_STATUS_ERROR, error_msg);
      return -1;
    }

    id<MTLComputeCommandEncoder> encoder =
        [commandBuffer computeCommandEncoder];
    [encoder setComputePipelineState:pipelineState];

    NSUInteger bufferIndex = 0;
    for (NSString *bufferName in context->metal_buffers) {
      id<MTLBuffer> buffer = [context->metal_buffers objectForKey:bufferName];
      [encoder setBuffer:buffer offset:0 atIndex:bufferIndex++];
    }

    MTLSize gridSize = MTLSizeMake(1024, 1, 1);
    MTLSize threadGroupSize = MTLSizeMake(32, 1, 1);
    [encoder dispatchThreads:gridSize threadsPerThreadgroup:threadGroupSize];
    [encoder endEncoding];
  }

  // Execute and wait
  uint64_t execution_start = get_time_ns();
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  uint64_t execution_end = get_time_ns();

  test_case->actual_execution_time_ms =
      ns_to_ms(execution_end - execution_start);
  test_case->actual_memory_usage_mb = get_memory_usage_mb() - initial_memory;

  // Check for Metal errors
  if (commandBuffer.error) {
    char error_msg[512];
    snprintf(error_msg, sizeof(error_msg), "Metal execution error: %s",
             [[commandBuffer.error localizedDescription] UTF8String]);
    record_test_result(test_case, TEST_STATUS_ERROR, error_msg);
    return -1;
  }

  // Run assertions
  bool all_assertions_passed = true;
  test_case->passed_assertions = 0;
  test_case->failed_assertions = 0;

  for (size_t i = 0; i < test_case->assertion_count; i++) {
    TestAssertion *assertion = &test_case->assertions[i];

    if (execute_assertion(assertion, context)) {
      test_case->passed_assertions++;
    } else {
      test_case->failed_assertions++;
      all_assertions_passed = false;

      if (test_case->verbose_output) {
        print_assertion_failure(assertion, test_case->name);
      }
    }
  }

  // Check performance constraints
  if (test_case->actual_execution_time_ms > test_case->max_execution_time_ms) {
    char perf_msg[256];
    snprintf(perf_msg, sizeof(perf_msg),
             "Execution time %.2fms exceeded limit %.2fms",
             test_case->actual_execution_time_ms,
             test_case->max_execution_time_ms);
    record_test_result(test_case, TEST_STATUS_FAILED, perf_msg);
    return -1;
  }

  if (test_case->actual_memory_usage_mb > test_case->max_memory_usage_mb) {
    char mem_msg[256];
    snprintf(mem_msg, sizeof(mem_msg),
             "Memory usage %.2fMB exceeded limit %.2fMB",
             test_case->actual_memory_usage_mb, test_case->max_memory_usage_mb);
    record_test_result(test_case, TEST_STATUS_FAILED, mem_msg);
    return -1;
  }

  // Set final test status
  if (all_assertions_passed) {
    record_test_result(test_case, TEST_STATUS_PASSED, NULL);
  } else {
    record_test_result(test_case, TEST_STATUS_FAILED,
                       "One or more assertions failed");
  }

  return 0;
}

// Execute a single assertion
bool execute_assertion(TestAssertion *assertion, TestContext *context) {
  switch (assertion->type) {
  case ASSERT_PERFORMANCE_LT: {
    // Performance assertions are handled in run_single_test
    return true;
  }

  case ASSERT_BUFFER_EQUALS:
  case ASSERT_BUFFER_NEAR: {
    NSString *bufferName =
        [NSString stringWithUTF8String:assertion->buffer_name];
    id<MTLBuffer> buffer = [context->metal_buffers objectForKey:bufferName];
    if (!buffer)
      return false;

    float *bufferPtr = (float *)[buffer contents];

    if (assertion->type == ASSERT_BUFFER_EQUALS) {
      return bufferPtr[assertion->buffer_index] == assertion->expected_float;
    } else {
      float diff =
          fabsf(bufferPtr[assertion->buffer_index] - assertion->expected_float);
      return diff <= assertion->tolerance;
    }
  }

  case ASSERT_EQUALS:
    return assertion->actual_float == assertion->expected_float;

  case ASSERT_NOT_EQUALS:
    return assertion->actual_float != assertion->expected_float;

  case ASSERT_NEAR: {
    float diff = fabsf(assertion->actual_float - assertion->expected_float);
    return diff <= assertion->tolerance;
  }

  case ASSERT_GREATER_THAN:
    return assertion->actual_float > assertion->expected_float;

  case ASSERT_LESS_THAN:
    return assertion->actual_float < assertion->expected_float;

  default:
    return false;
  }
}

void record_test_result(TestCase *test_case, TestStatus status,
                        const char *message) {
  test_case->status = status;
  if (message) {
    test_case->failure_message = strdup(message);
  }
}

void print_test_summary(TestSuite *suite) {
  printf("\n" COLOR_CYAN "=== Test Summary ===" COLOR_RESET "\n");
  printf("Tests run: %zu\n", suite->total_tests);
  printf(COLOR_GREEN "Passed: %zu" COLOR_RESET "\n", suite->passed_tests);
  if (suite->failed_tests > 0) {
    printf(COLOR_RED "Failed: %zu" COLOR_RESET "\n", suite->failed_tests);
  }
  if (suite->skipped_tests > 0) {
    printf(COLOR_YELLOW "Skipped: %zu" COLOR_RESET "\n", suite->skipped_tests);
  }
  if (suite->error_tests > 0) {
    printf(COLOR_RED "Errors: %zu" COLOR_RESET "\n", suite->error_tests);
  }
  printf("Total execution time: %.2f ms\n", suite->total_execution_time_ms);

  if (suite->failed_tests == 0 && suite->error_tests == 0) {
    printf("\n" COLOR_GREEN "All tests passed!" COLOR_RESET "\n");
  } else {
    printf("\n" COLOR_RED "Some tests failed or had errors." COLOR_RESET "\n");
  }
}

void generate_test_report(TestSuite *suite) {
  FILE *report = fopen(suite->report_path, "w");
  if (!report) {
    fprintf(stderr, "Warning: Could not create test report file: %s/n",
            suite->report_path);
    return;
  }

  fprintf(report,
          "<!DOCTYPE html>\n<html><head><title>Test Report: %s</title>\n",
          suite->name);
  fprintf(report, "<style>\n");
  fprintf(report, "body { font-family: Arial, sans-serif; margin: 20px; }\n");
  fprintf(report, ".pass { color: green; }\n");
  fprintf(report, ".fail { color: red; }\n");
  fprintf(report, ".skip { color: orange; }\n");
  fprintf(report, ".error { color: red; font-weight: bold; }\n");
  fprintf(report, "table { border-collapse: collapse; width: 100%%; }\n");
  fprintf(
      report,
      "th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }\n");
  fprintf(report, "th { background-color: #f2f2f2; }\n");
  fprintf(report, "</style></head><body>\n");

  fprintf(report, "<h1>Test Report: %s</h1>\n", suite->name);
  fprintf(report, "<p>%s</p>\n", suite->description);

  // Summary table
  fprintf(report, "<h2>Summary</h2>\n");
  fprintf(report, "<table>\n");
  fprintf(report, "<tr><th>Metric</th><th>Value</th></tr>\n");
  fprintf(report, "<tr><td>Total Tests</td><td>%zu</td></tr>\n",
          suite->total_tests);
  fprintf(report, "<tr><td class='pass'>Passed</td><td>%zu</td></tr>\n",
          suite->passed_tests);
  fprintf(report, "<tr><td class='fail'>Failed</td><td>%zu</td></tr>\n",
          suite->failed_tests);
  fprintf(report, "<tr><td class='skip'>Skipped</td><td>%zu</td></tr>\n",
          suite->skipped_tests);
  fprintf(report, "<tr><td class='error'>Errors</td><td>%zu</td></tr>\n",
          suite->error_tests);
  fprintf(report, "<tr><td>Total Time</td><td>%.2f ms</td></tr>\n",
          suite->total_execution_time_ms);
  fprintf(report, "</table>\n");

  // Detailed results
  fprintf(report, "<h2>Test Results</h2>\n");
  fprintf(report, "<table>\n");
  fprintf(report,
          "<tr><th>Test Name</th><th>Status</th><th>Time (ms)</th><th>Memory "
          "(MB)</th><th>Assertions</th><th>Message</th></tr>\n");

  for (size_t i = 0; i < suite->test_case_count; i++) {
    TestCase *test = &suite->test_cases[i];
    const char *status_class = "";
    const char *status_text = "";

    switch (test->status) {
    case TEST_STATUS_PASSED:
      status_class = "pass";
      status_text = "PASS";
      break;
    case TEST_STATUS_FAILED:
      status_class = "fail";
      status_text = "FAIL";
      break;
    case TEST_STATUS_SKIPPED:
      status_class = "skip";
      status_text = "SKIP";
      break;
    case TEST_STATUS_ERROR:
      status_class = "error";
      status_text = "ERROR";
      break;
    }

    fprintf(report, "<tr>\n");
    fprintf(report, "<td>%s</td>\n", test->name);
    fprintf(report, "<td class='%s'>%s</td>\n", status_class, status_text);
    fprintf(report, "<td>%.2f</td>\n", test->actual_execution_time_ms);
    fprintf(report, "<td>%.2f</td>\n", test->actual_memory_usage_mb);
    fprintf(report, "<td>%zu/%zu</td>\n", test->passed_assertions,
            test->assertion_count);
    fprintf(report, "<td>%s</td>\n",
            test->failure_message ? test->failure_message : "");
    fprintf(report, "</tr>\n");
  }

  fprintf(report, "</table>\n");
  fprintf(report, "</body></html>\n");
  fclose(report);

  printf("Test report generated: %s\n", suite->report_path);
}

void print_assertion_failure(TestAssertion *assertion, const char *test_name) {
  printf("        " COLOR_RED "ASSERTION FAILED:" COLOR_RESET " %s\n",
         assertion->description);

  switch (assertion->type) {
  case ASSERT_EQUALS:
    printf("        Expected: %.6f, Actual: %.6f\n", assertion->expected_float,
           assertion->actual_float);
    break;
  case ASSERT_NEAR:
    printf("        Expected: %.6f ± %.6f, Actual: %.6f\n",
           assertion->expected_float, assertion->tolerance,
           assertion->actual_float);
    break;
  case ASSERT_BUFFER_EQUALS:
    printf("        Buffer '%s'[%d] expected: %.6f\n", assertion->buffer_name,
           assertion->buffer_index, assertion->expected_float);
    break;
  case ASSERT_BUFFER_NEAR:
    printf("        Buffer '%s'[%d] expected: %.6f ± %.6f\n",
           assertion->buffer_name, assertion->buffer_index,
           assertion->expected_float, assertion->tolerance);
    break;
  case ASSERT_PERFORMANCE_LT:
    printf("        Performance threshold: %.2f ms\n",
           assertion->performance_threshold);
    break;
  default:
    break;
  }
}

void cleanup_test_context(TestContext *context) {
  [context->metal_buffers release];
  [context->test_errors release];
}

void free_test_suite(TestSuite *suite) {
  if (!suite)
    return;

  free((void *)suite->name);
  free((void *)suite->description);
  free((void *)suite->metallib_path);
  free((void *)suite->report_path);

  for (size_t i = 0; i < suite->test_case_count; i++) {
    TestCase *test = &suite->test_cases[i];
    free((void *)test->name);
    free((void *)test->description);
    free((void *)test->shader_function);
    free((void *)test->vertex_shader);
    free((void *)test->fragment_shader);
    free((void *)test->skip_reason);
    free((void *)test->failure_message);

    [test->buffers release];
    [test->expected_outputs release];

    for (size_t j = 0; j < test->assertion_count; j++) {
      free((void *)test->assertions[j].description);
      free((void *)test->assertions[j].buffer_name);
      free(test->assertions[j].expected_buffer);
    }
    free(test->assertions);
  }

  free(suite->test_cases);

  if (suite->test_filters) {
    for (size_t i = 0; i < suite->filter_count; i++) {
      free(suite->test_filters[i]);
    }
    free(suite->test_filters);
  }

  free(suite);
}

// Compare two buffers with tolerance
bool compare_buffers(float *buffer1, float *buffer2, size_t size,
                     float tolerance) {
  for (size_t i = 0; i < size; i++) {
    if (fabsf(buffer1[i] - buffer2[i]) > tolerance) {
      return false;
    }
  }
  return true;
}

// Check if test should run based on filters
bool should_run_test(TestCase *test_case, char **filters, size_t filter_count) {
  if (filter_count == 0)
    return true;

  for (size_t i = 0; i < filter_count; i++) {
    if (strstr(test_case->name, filters[i]) != NULL) {
      return true;
    }
  }
  return false;
}

void report_test_error(TestContext *context, const char *error_message) {
  NSString *error = [NSString stringWithUTF8String:error_message];
  [context->test_errors addObject:error];
}

// Get execution time in milliseconds
double get_execution_time_ms(uint64_t start_time, uint64_t end_time) {
  return ns_to_ms(end_time - start_time);
}

void print_test_header(const char *test_name) {
  printf("\n" COLOR_BLUE "--- Running Test: %s ---" COLOR_RESET "\n",
         test_name);
}

void print_test_result(TestCase *test_case) {
  const char *status_color = "";
  const char *status_text = "";

  switch (test_case->status) {
  case TEST_STATUS_PASSED:
    status_color = COLOR_GREEN;
    status_text = "PASSED";
    break;
  case TEST_STATUS_FAILED:
    status_color = COLOR_RED;
    status_text = "FAILED";
    break;
  case TEST_STATUS_SKIPPED:
    status_color = COLOR_YELLOW;
    status_text = "SKIPPED";
    break;
  case TEST_STATUS_ERROR:
    status_color = COLOR_RED;
    status_text = "ERROR";
    break;
  }

  printf("%s[%s]%s %s (%.2fms)\n", status_color, status_text, COLOR_RESET,
         test_case->name, test_case->actual_execution_time_ms);
}
