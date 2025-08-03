#ifndef TESTING_H
#define TESTING_H

#include "../debug/expose_from_debug.h"
#include <Foundation/Foundation.h>
#include <Metal/Metal.h>
#include <math.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define COLOR_RED "\x1b[31m"
#define COLOR_GREEN "\x1b[32m"
#define COLOR_YELLOW "\x1b[33m"
#define COLOR_BLUE "\x1b[34m"
#define COLOR_CYAN "\x1b[36m"
#define COLOR_RESET "\x1b[0m"

// Test result status
typedef enum {
  TEST_STATUS_PASSED,
  TEST_STATUS_FAILED,
  TEST_STATUS_SKIPPED,
  TEST_STATUS_ERROR
} TestStatus;

// Test assertion types
typedef enum {
  ASSERT_EQUALS,
  ASSERT_NOT_EQUALS,
  ASSERT_GREATER_THAN,
  ASSERT_LESS_THAN,
  ASSERT_GREATER_EQUAL,
  ASSERT_LESS_EQUAL,
  ASSERT_NEAR,
  ASSERT_TRUE,
  ASSERT_FALSE,
  ASSERT_NULL,
  ASSERT_NOT_NULL,
  ASSERT_BUFFER_EQUALS,
  ASSERT_BUFFER_NEAR,
  ASSERT_PERFORMANCE_LT,
  ASSERT_PERFORMANCE_GT
} AssertionType;

// Individual assertion definition
typedef struct {
  AssertionType type;
  char *description;

  // For numeric assertions
  float expected_float;
  float actual_float;
  float tolerance; // For ASSERT_NEAR

  // For buffer assertions
  char *buffer_name;
  int buffer_index;
  float *expected_buffer;
  size_t buffer_size;

  // For performance assertions
  double performance_threshold; // in milliseconds

  // For boolean assertions
  bool expected_bool;
  bool actual_bool;

  // For pointer assertions
  void *expected_ptr;
  void *actual_ptr;
} TestAssertion;

typedef struct {
  char *name;
  char *description;

  // Pipeline configuration
  PipelineType pipeline_type;
  char *shader_function; // For compute shader
  char *vertex_shader;   // For render pipeline vertex function
  char *fragment_shader; // For render pipeline fragment function

  // Render-specific configuration
  MTLPixelFormat render_target_pixel_format;
  NSUInteger render_target_width;
  NSUInteger render_target_height;

  // Test setup
  NSMutableArray *buffers;
  NSMutableArray *expected_outputs;

  // Assertions to run
  TestAssertion *assertions;
  size_t assertion_count;

  // Test configuration
  bool skip;
  char *skip_reason;
  double timeout_ms;

  // Performance expectations
  double max_execution_time_ms;
  double max_memory_usage_mb;

  // Test results (filled during execution)
  TestStatus status;
  char *failure_message;
  double actual_execution_time_ms;
  double actual_memory_usage_mb;
  size_t passed_assertions;
  size_t failed_assertions;

  uint64_t test_start_time; // For timing individual test
  bool verbose_output;      // For controlling per-test verbosity
} TestCase;

// Test suite configuration
typedef struct {
  char *name;
  char *description;
  char *metallib_path;

  // Test cases
  TestCase *test_cases;
  size_t test_case_count;

  // Global test configuration
  bool stop_on_failure;
  bool verbose_output;
  bool generate_report;
  char *report_path;

  // Setup and teardown functions (optional)
  char *setup_function;
  char *teardown_function;

  // Test filtering
  char **test_filters;
  size_t filter_count;

  // Performance baseline (for regression testing)
  char *baseline_file;

  // Test results summary
  size_t total_tests;
  size_t passed_tests;
  size_t failed_tests;
  size_t skipped_tests;
  size_t error_tests;
  double total_execution_time_ms;
} TestSuite;

// Test execution context
typedef struct {
  id<MTLDevice> device;
  id<MTLCommandQueue> command_queue;
  id<MTLLibrary> library;
  NSMutableDictionary *metal_buffers;

  // Timing
  uint64_t test_start_time;
  uint64_t test_end_time;

  // Memory tracking
  size_t initial_memory_usage;
  size_t peak_memory_usage;

  // Error tracking
  NSMutableArray *test_errors;
} TestContext;

// Function declarations
TestSuite *load_test_config(const char *config_path);
void free_test_suite(TestSuite *suite);

int run_test_suite(TestSuite *suite, const char *metallib_path);
int run_single_test(TestCase *test_case, TestContext *context);

bool execute_assertion(TestAssertion *assertion, TestContext *context);
void record_test_result(TestCase *test_case, TestStatus status,
                        const char *message);

void generate_test_report(TestSuite *suite);
void print_test_summary(TestSuite *suite);

// Utility functions
bool compare_buffers(float *buffer1, float *buffer2, size_t size,
                     float tolerance);
double get_execution_time_ms(uint64_t start_time, uint64_t end_time);
size_t get_memory_usage_mb(void);

// Test filtering
bool should_run_test(TestCase *test_case, char **filters, size_t filter_count);

// Performance baseline management
void save_performance_baseline(TestSuite *suite, const char *baseline_file);
bool load_performance_baseline(TestSuite *suite, const char *baseline_file);
void compare_with_baseline(TestSuite *suite);

// JSON parsing helpers for test configuration
TestCase *parse_test_case(NSString *json_string);
TestAssertion *parse_assertions(NSArray *assertion_array, size_t *count);

// Test output formatting
void print_test_header(const char *test_name);
void print_test_result(TestCase *test_case);
void print_assertion_failure(TestAssertion *assertion, const char *test_name);

// Error handling for tests
void report_test_error(TestContext *context, const char *error_message);
void cleanup_test_context(TestContext *context);

#endif // TESTING_H
