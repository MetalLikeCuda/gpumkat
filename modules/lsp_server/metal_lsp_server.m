//
// metal_lsp_server.m
// Metal Language Server Protocol Implementation for gpumkat
//

#import "metal_lsp_server.h"
#import <Metal/Metal.h>
#import <stdlib.h>
#import <string.h>
#import <unistd.h>

// --- Static Data ---

typedef struct {
  const char *name;
  const char *signature;
  const char *documentation;
  const char **parameter_names;
  const char **parameter_docs;
  size_t parameter_count;
} MetalFunctionSignature;

static const char *dot_params[] = {"a", "b"};
static const char *dot_param_docs[] = {"First vector", "Second vector"};

static const char *cross_params[] = {"a", "b"};
static const char *cross_param_docs[] = {"First vector", "Second vector"};

static const char *normalize_params[] = {"v"};
static const char *normalize_param_docs[] = {"Vector to normalize"};

static const char *length_params[] = {"v"};
static const char *length_param_docs[] = {"Vector to get length of"};

static const char *pow_params[] = {"base", "exponent"};
static const char *pow_param_docs[] = {"Base value", "Exponent value"};

static const char *sin_params[] = {"x"};
static const char *sin_param_docs[] = {"Angle in radians"};

static const char *cos_params[] = {"x"};
static const char *cos_param_docs[] = {"Angle in radians"};

static const char *sqrt_params[] = {"x"};
static const char *sqrt_param_docs[] = {"Value to compute square root of"};

static const char *mix_params[] = {"a", "b", "t"};
static const char *mix_param_docs[] = {"First value", "Second value",
                                       "Interpolation factor (0.0 to 1.0)"};

static const char *clamp_params[] = {"value", "min", "max"};
static const char *clamp_param_docs[] = {"Value to clamp", "Minimum value",
                                         "Maximum value"};

static MetalFunctionSignature metal_function_signatures[] = {
    {"dot", "float dot(float2 a, float2 b)",
     "Compute dot product of two vectors", dot_params, dot_param_docs, 2},
    {"cross", "float3 cross(float3 a, float3 b)",
     "Compute cross product of two 3D vectors", cross_params, cross_param_docs,
     2},
    {"normalize", "floatN normalize(floatN v)", "Return normalized vector",
     normalize_params, normalize_param_docs, 1},
    {"length", "float length(floatN v)", "Return length of vector",
     length_params, length_param_docs, 1},
    {"pow", "T pow(T base, T exponent)",
     "Compute base raised to the power of exponent", pow_params, pow_param_docs,
     2},
    {"sin", "T sin(T x)", "Compute sine of x", sin_params, sin_param_docs, 1},
    {"cos", "T cos(T x)", "Compute cosine of x", cos_params, cos_param_docs, 1},
    {"sqrt", "T sqrt(T x)", "Compute square root of x", sqrt_params,
     sqrt_param_docs, 1},
    {"mix", "T mix(T a, T b, T t)", "Linear interpolation between a and b",
     mix_params, mix_param_docs, 3},
    {"clamp", "T clamp(T value, T min, T max)",
     "Constrain value to range [min, max]", clamp_params, clamp_param_docs, 3}};

static const size_t metal_function_signatures_count =
    sizeof(metal_function_signatures) / sizeof(metal_function_signatures[0]);

static const char *metal_keywords[] = {"kernel",
                                       "vertex",
                                       "fragment",
                                       "constant",
                                       "device",
                                       "threadgroup",
                                       "thread",
                                       "texture1d",
                                       "texture2d",
                                       "texture3d",
                                       "texturecube",
                                       "texture2d_array",
                                       "sampler",
                                       "texture_buffer",
                                       "texture1d_array",
                                       "texturecube_array",
                                       "texture2d_ms",
                                       "texture2d_ms_array",
                                       "depth2d",
                                       "depth2d_array",
                                       "depthcube",
                                       "depthcube_array",
                                       "float2",
                                       "float3",
                                       "float4",
                                       "int2",
                                       "int3",
                                       "int4",
                                       "uint2",
                                       "uint3",
                                       "uint4",
                                       "half2",
                                       "half3",
                                       "half4",
                                       "float2x2",
                                       "float3x3",
                                       "float4x4",
                                       "half2x2",
                                       "half3x3",
                                       "half4x4",
                                       "atomic_int",
                                       "atomic_uint",
                                       "atomic_flag",
                                       "simd_float2",
                                       "simd_float3",
                                       "simd_float4",
                                       "using",
                                       "namespace",
                                       "struct",
                                       "typedef",
                                       "enum",
                                       "union",
                                       "if",
                                       "else",
                                       "for",
                                       "while",
                                       "do",
                                       "switch",
                                       "case",
                                       "default",
                                       "return",
                                       "break",
                                       "continue",
                                       "const",
                                       "constexpr",
                                       "static",
                                       "inline",
                                       "template",
                                       "typename",
                                       "class",
                                       "public",
                                       "private",
                                       "protected",
                                       "void",
                                       "true",
                                       "false",
                                       "nullptr",
                                       "nullptr_t",
                                       "buffer",
                                       "array",
                                       "r32uint",
                                       "r32sint",
                                       "r32float",
                                       "a8unorm",
                                       "packed_float3",
                                       "packed_float2x2",
                                       "packed_half4x4",
                                       "stage_in",
                                       "index",
                                       "thread_position_in_grid",
                                       "thread_position_in_threadgroup",
                                       "threadgroup_position_in_grid",
                                       "thread_index_in_threadgroup",
                                       "thread_index_in_simdgroup",
                                       "simdgroup_index",
                                       "simdgroup_barrier",
                                       "device_address_t",
                                       "device_ptr",
                                       "friend",
                                       "operator",
                                       "this",
                                       "explicit",
                                       "noexcept",
                                       "auto",
                                       "decltype",
                                       "export",
                                       "extern",
                                       "mutable",
                                       "register",
                                       "static_assert",
                                       "thread_local",
                                       "discard",
                                       "vertex_id",
                                       "instance_id",
                                       "draw_id",
                                       "bool2",
                                       "bool3",
                                       "bool4",
                                       "char2",
                                       "char3",
                                       "char4",
                                       "short2",
                                       "short3",
                                       "short4",
                                       "long2",
                                       "long3",
                                       "long4",
                                       "uchar2",
                                       "uchar3",
                                       "uchar4",
                                       "ushort2",
                                       "ushort3",
                                       "ushort4",
                                       "ulong2",
                                       "ulong3",
                                       "ulong4",
                                       "vector_float2",
                                       "vector_float3",
                                       "vector_float4",
                                       "texture2d",
                                       "texture3d",
                                       "texture4d"};

static const char *metal_builtin_functions[] = {
    "dot",
    "cross",
    "normalize",
    "length",
    "distance",
    "reflect",
    "refract",
    "mix",
    "step",
    "smoothstep",
    "clamp",
    "saturate",
    "abs",
    "sign",
    "floor",
    "ceil",
    "round",
    "trunc",
    "fract",
    "modf",
    "mod",
    "sin",
    "cos",
    "tan",
    "asin",
    "acos",
    "atan",
    "atan2",
    "sinh",
    "cosh",
    "tanh",
    "exp",
    "exp2",
    "log",
    "log2",
    "pow",
    "sqrt",
    "rsqrt",
    "min",
    "max",
    "fmin",
    "fmax",
    "select",
    "isnan",
    "isinf",
    "isfinite",
    "sample",
    "read",
    "write",
    "gather",
    "fence",
    "barrier",
    "atomic_load",
    "atomic_store",
    "atomic_exchange",
    "atomic_compare_exchange_weak",
    "atomic_compare_exchange_strong",
    "atomic_fetch_add",
    "atomic_fetch_sub",
    "atomic_fetch_and",
    "atomic_fetch_or",
    "atomic_fetch_xor",
    "atomic_fetch_min",
    "atomic_fetch_max",
    "atomic_fetch_min_explicit",
    "atomic_fetch_max_explicit",
    "atomic_fetch_add_explicit",
    "atomic_fetch_sub_explicit",
    "atomic_fetch_and_explicit",
    "atomic_fetch_or_explicit",
    "atomic_fetch_xor_explicit",
    "get_thread_position_in_grid",
    "get_thread_position_in_threadgroup",
    "get_threadgroup_position_in_grid",
    "get_threads_per_threadgroup",
    "get_threadgroups_per_grid",
    "get_thread_index_in_threadgroup",
    "get_threadgroup_index_in_grid",
    "get_threads_per_simdgroup",
    "get_thread_index_in_simdgroup",
    "ddx",
    "ddy",
    "fwidth",
    "all",
    "any",
    "as_type",
    "asuint",
    "int2",
    "int3",
    "int4",
    "uint",
    "uint2",
    "uint3",
    "uint4",
    "float2",
    "float3",
    "float4",
    "half",
    "half2",
    "half3",
    "half4",
    "make_vector",
    "make_matrix",
    "transpose",
    "determinant",
    "inverse",
    "countbits",
    "reversebits",
    "clz",
    "popcount",
    "frexp",
    "ldexp",
    "fma",
    "clamp_to_edge",
    "textureSampleLevel",
    "textureSampleCompare",
    "textureGather",
    "simd_shuffle",
    "simd_prefix_exclusive_add",
    "simd_prefix_inclusive_add",
    "simd_any",
    "simd_all",
    "simd_reduce_add",
    "simd_reduce_mul",
    "simd_reduce_min",
    "simd_reduce_max",
    "memcpy",
    "memset"};

// --- Semantic Token Types ---
static const char *semantic_token_types[] = {
    "namespace",  "type",          "class",     "enum",     "interface",
    "struct",     "typeParameter", "parameter", "variable", "property",
    "enumMember", "event",         "function",  "method",   "macro",
    "keyword",    "modifier",      "comment",   "string",   "number",
    "regexp",     "operator"};

static const char *semantic_token_modifiers[] = {
    "declaration",   "definition",    "readonly", "static",
    "deprecated",    "abstract",      "async",    "modification",
    "documentation", "defaultLibrary"};

// --- Helper Functions ---

LSPTextDocument *find_document(MetalLSPServer *server, const char *uri);
BOOL is_metal_keyword(const char *word);
BOOL is_metal_builtin_function(const char *word);

// --- Server Lifecycle ---

MetalLSPServer *metal_lsp_server_create(void) {
  MetalLSPServer *server = malloc(sizeof(MetalLSPServer));
  if (!server)
    return NULL;

  server->documents = malloc(sizeof(LSPTextDocument *) * 64);
  server->document_count = 0;
  server->document_capacity = 64;
  server->is_running = false;
  server->client_socket = -1;
  pthread_mutex_init(&server->documents_mutex, NULL);

  // Initialize built-in Metal symbols
  size_t total_symbols =
      sizeof(metal_keywords) / sizeof(metal_keywords[0]) +
      sizeof(metal_builtin_functions) / sizeof(metal_builtin_functions[0]);

  server->built_in_symbols = malloc(sizeof(MetalSymbol) * total_symbols);
  server->symbol_count = 0;

  // Add keywords
  for (size_t i = 0; i < sizeof(metal_keywords) / sizeof(metal_keywords[0]);
       i++) {
    server->built_in_symbols[server->symbol_count].name =
        strdup(metal_keywords[i]);
    server->built_in_symbols[server->symbol_count].signature =
        strdup(metal_keywords[i]);
    server->built_in_symbols[server->symbol_count].documentation =
        strdup("Metal keyword");
    server->built_in_symbols[server->symbol_count].kind = COMPLETION_KEYWORD;
    server->symbol_count++;
  }

  // Add built-in functions
  for (size_t i = 0;
       i < sizeof(metal_builtin_functions) / sizeof(metal_builtin_functions[0]);
       i++) {
    server->built_in_symbols[server->symbol_count].name =
        strdup(metal_builtin_functions[i]);
    server->built_in_symbols[server->symbol_count].signature =
        strdup(metal_builtin_functions[i]);
    server->built_in_symbols[server->symbol_count].documentation =
        strdup("Metal built-in function");
    server->built_in_symbols[server->symbol_count].kind = COMPLETION_FUNCTION;
    server->symbol_count++;
  }

  return server;
}

void metal_lsp_server_destroy(MetalLSPServer *server) {
  if (!server)
    return;

  pthread_mutex_lock(&server->documents_mutex);

  // Free documents
  for (size_t i = 0; i < server->document_count; i++) {
    free(server->documents[i]->uri);
    free(server->documents[i]->text);
    free(server->documents[i]);
  }
  free(server->documents);

  // Free built-in symbols
  for (size_t i = 0; i < server->symbol_count; i++) {
    free(server->built_in_symbols[i].name);
    free(server->built_in_symbols[i].signature);
    free(server->built_in_symbols[i].documentation);
  }
  free(server->built_in_symbols);

  pthread_mutex_unlock(&server->documents_mutex);
  pthread_mutex_destroy(&server->documents_mutex);

  free(server);
}

// --- Server Thread & Communication ---

void *lsp_server_thread(void *arg) {
  MetalLSPServer *server = (MetalLSPServer *)arg;
  char header_buffer[256];

  while (server->is_running) {
    // Read Content-Length header
    if (fgets(header_buffer, sizeof(header_buffer), stdin) != NULL) {
      if (strncmp(header_buffer, "Content-Length:", 15) == 0) {
        int content_length = atoi(header_buffer + 15);

        // Skip the empty line separator
        fgets(header_buffer, sizeof(header_buffer), stdin);

        if (content_length > 0) {
          // Read the JSON-RPC message
          char *message_buffer = malloc(content_length + 1);
          fread(message_buffer, 1, content_length, stdin);
          message_buffer[content_length] = '\0';

          handle_lsp_message(server, message_buffer, content_length);
          free(message_buffer);
        }
      }
    } else {
      // End of input, stop the server
      server->is_running = false;
    }
  }
  return NULL;
}

int metal_lsp_server_start(MetalLSPServer *server, int port) {
  if (!server)
    return -1;

  server->is_running = true;

  // Start server thread for LSP communication
  pthread_t server_thread;
  if (pthread_create(&server_thread, NULL, lsp_server_thread, server) != 0) {
    server->is_running = false;
    return -1;
  }

  pthread_detach(server_thread);
  return 0;
}

void metal_lsp_server_stop(MetalLSPServer *server) {
  if (server) {
    server->is_running = false;
  }
}

// --- LSP JSON Communication ---

// Sends a raw C-string response. Used by the dictionary-based helpers.
void send_lsp_raw_response(const char *response) {
  printf("Content-Length: %zu\r\n\r\n%s", strlen(response), response);
  fflush(stdout);
}

void send_lsp_response_from_dict(NSDictionary *responseDict) {
  @autoreleasepool {
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:responseDict
                                                       options:0
                                                         error:&error];
    if (error) {
      NSLog(@"[LSP] Error serializing JSON response: %@", error);
      return;
    }
    NSString *responseStr =
        [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    send_lsp_raw_response([responseStr UTF8String]);
  }
}

// Sends a notification from an NSDictionary.
void send_lsp_notification(NSString *method, NSDictionary *params) {
  @autoreleasepool {
    NSDictionary *notificationDict =
        @{@"jsonrpc" : @"2.0",
          @"method" : method,
          @"params" : params ?: @{}};
    send_lsp_response_from_dict(notificationDict);
  }
}

LSPMethod parse_method(const char *method) {
  if (strcmp(method, "initialize") == 0)
    return LSP_METHOD_INITIALIZE;
  if (strcmp(method, "initialized") == 0)
    return LSP_METHOD_INITIALIZED;
  if (strcmp(method, "shutdown") == 0)
    return LSP_METHOD_SHUTDOWN;
  if (strcmp(method, "exit") == 0)
    return LSP_METHOD_EXIT;
  if (strcmp(method, "textDocument/didOpen") == 0)
    return LSP_METHOD_TEXT_DOCUMENT_DID_OPEN;
  if (strcmp(method, "textDocument/didChange") == 0)
    return LSP_METHOD_TEXT_DOCUMENT_DID_CHANGE;
  if (strcmp(method, "textDocument/didSave") == 0)
    return LSP_METHOD_TEXT_DOCUMENT_DID_SAVE;
  if (strcmp(method, "textDocument/didClose") == 0)
    return LSP_METHOD_TEXT_DOCUMENT_DID_CLOSE;
  if (strcmp(method, "textDocument/completion") == 0)
    return LSP_METHOD_TEXT_DOCUMENT_COMPLETION;
  if (strcmp(method, "textDocument/hover") == 0)
    return LSP_METHOD_TEXT_DOCUMENT_HOVER;
  if (strcmp(method, "textDocument/definition") == 0)
    return LSP_METHOD_TEXT_DOCUMENT_GOTO_DEFINITION;
  if (strcmp(method, "textDocument/formatting") == 0)
    return LSP_METHOD_TEXT_DOCUMENT_FORMATTING;
  if (strcmp(method, "textDocument/semanticTokens/full") == 0)
    return LSP_METHOD_TEXT_DOCUMENT_SEMANTIC_TOKENS_FULL;
  if (strcmp(method, "textDocument/signatureHelp") == 0)
    return LSP_METHOD_TEXT_DOCUMENT_SIGNATURE_HELP;
  return LSP_METHOD_UNKNOWN;
}

// Helper function to trim trailing whitespace
static char *trim_trailing(const char *s) {
  if (!s)
    return strdup("");
  size_t len = strlen(s);
  if (len == 0)
    return strdup("");

  int end = len - 1;
  while (end >= 0 && isspace((unsigned char)s[end])) {
    end--;
  }

  char *result = malloc(end + 2);
  if (!result)
    return NULL;

  strncpy(result, s, end + 1);
  result[end + 1] = '\0';
  return result;
}

// Helper function to trim leading whitespace
static char *trim_leading(const char *s) {
  if (!s)
    return strdup("");
  while (*s && isspace((unsigned char)*s)) {
    s++;
  }
  return strdup(s);
}

static char *create_indent_string(int num_spaces) {
  if (num_spaces <= 0) {
    return strdup("");
  }

  char *indent = malloc(num_spaces + 1);
  if (!indent)
    return NULL;

  memset(indent, ' ', num_spaces);
  indent[num_spaces] = '\0';
  return indent;
}

static LSPRange get_full_document_range(const char *text) {
  LSPRange range = {0};
  if (!text || !*text) {
    return range;
  }

  int line_count = 0;
  int current_line_length = 0;
  const char *p = text;

  while (*p) {
    if (*p == '\n') {
      line_count++;
      current_line_length = 0;
    } else {
      current_line_length++;
    }
    p++;
  }

  // Handle last line
  range.end.line = line_count;
  range.end.character = current_line_length;
  return range;
}

// --- Core Message Handler ---

void handle_lsp_message(MetalLSPServer *server, const char *message,
                        size_t length) {
  @autoreleasepool {
    NSData *data = [NSData dataWithBytes:message length:length];
    NSError *error = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                         options:0
                                                           error:&error];

    if (error || ![json isKindOfClass:[NSDictionary class]]) {
      NSLog(@"[LSP] Failed to parse JSON message: %@", error);
      return;
    }

    NSString *method = json[@"method"];
    id messageId = json[@"id"];
    NSDictionary *params = json[@"params"];

    if (![method isKindOfClass:[NSString class]]) {
      return; // Not a request/notification we can handle
    }

    LSPMethod lsp_method = parse_method([method UTF8String]);

    switch (lsp_method) {
    case LSP_METHOD_INITIALIZE: {
      // Create semantic token types and modifiers arrays
      NSMutableArray *tokenTypes = [NSMutableArray array];
      for (size_t i = 0;
           i < sizeof(semantic_token_types) / sizeof(semantic_token_types[0]);
           i++) {
        [tokenTypes addObject:@(semantic_token_types[i])];
      }

      NSMutableArray *tokenModifiers = [NSMutableArray array];
      for (size_t i = 0; i < sizeof(semantic_token_modifiers) /
                                 sizeof(semantic_token_modifiers[0]);
           i++) {
        [tokenModifiers addObject:@(semantic_token_modifiers[i])];
      }

      NSDictionary *response = @{
        @"jsonrpc" : @"2.0",
        @"id" : messageId ?: [NSNull null],
        @"result" : @{
          @"capabilities" : @{
            @"textDocumentSync" : @(1), // 1 = Full sync
            @"completionProvider" :
                @{@"resolveProvider" : @(NO), @"triggerCharacters" : @[ @"." ]},
            @"hoverProvider" : @(YES),
            @"definitionProvider" : @(YES),
            @"documentFormattingProvider" : @(YES),
            @"semanticTokensProvider" : @{
              @"legend" : @{
                @"tokenTypes" : tokenTypes,
                @"tokenModifiers" : tokenModifiers
              },
              @"range" : @(NO),
              @"full" : @(YES)
            }
          },
          @"serverInfo" : @{@"name" : @"Metal-LSP", @"version" : @"1.2"}
        }
      };
      send_lsp_response_from_dict(response);
      break;
    }

    case LSP_METHOD_SHUTDOWN: {
      NSDictionary *response = @{
        @"jsonrpc" : @"2.0",
        @"id" : messageId ?: [NSNull null],
        @"result" : [NSNull null]
      };
      send_lsp_response_from_dict(response);
      break;
    }

    case LSP_METHOD_EXIT: {
      metal_lsp_server_stop(server);
      break;
    }

    case LSP_METHOD_TEXT_DOCUMENT_DID_OPEN: {
      if (![params isKindOfClass:[NSDictionary class]])
        break;
      NSDictionary *textDocument = params[@"textDocument"];
      if (![textDocument isKindOfClass:[NSDictionary class]])
        break;

      NSString *uri = textDocument[@"uri"];
      NSString *text = textDocument[@"text"];
      NSNumber *version = textDocument[@"version"];

      if ([uri isKindOfClass:[NSString class]] &&
          [text isKindOfClass:[NSString class]]) {
        LSPTextDocument *doc = malloc(sizeof(LSPTextDocument));
        doc->uri = strdup([uri UTF8String]);
        doc->text = strdup([text UTF8String]);
        doc->version = [version intValue];
        doc->text_length =
            [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        add_document(server, doc);

        // Send diagnostics
        size_t diag_count;
        LSPDiagnostic *diagnostics =
            get_diagnostics(server, [uri UTF8String], &diag_count);

        NSMutableArray *diag_array = [NSMutableArray array];
        for (size_t i = 0; i < diag_count; i++) {
          [diag_array addObject:@{
            @"range" : @{
              @"start" : @{
                @"line" : @(diagnostics[i].range.start.line),
                @"character" : @(diagnostics[i].range.start.character)
              },
              @"end" : @{
                @"line" : @(diagnostics[i].range.end.line),
                @"character" : @(diagnostics[i].range.end.character)
              }
            },
            @"severity" : @(diagnostics[i].severity),
            @"source" : @(diagnostics[i].source),
            @"message" : @(diagnostics[i].message)
          }];
          free(diagnostics[i].message);
          free(diagnostics[i].source);
        }
        free(diagnostics);

        NSDictionary *diag_params =
            @{@"uri" : uri, @"diagnostics" : diag_array};
        send_lsp_notification(@"textDocument/publishDiagnostics", diag_params);
      }
      break;
    }

    case LSP_METHOD_TEXT_DOCUMENT_DID_CLOSE: {
      if (![params isKindOfClass:[NSDictionary class]])
        break;
      NSDictionary *textDocument = params[@"textDocument"];
      if (![textDocument isKindOfClass:[NSDictionary class]])
        break;
      NSString *uri = textDocument[@"uri"];
      if ([uri isKindOfClass:[NSString class]]) {
        remove_document(server, [uri UTF8String]);
      }
      break;
    }

    case LSP_METHOD_TEXT_DOCUMENT_COMPLETION: {
      if (![params isKindOfClass:[NSDictionary class]])
        break;
      NSDictionary *textDocument = params[@"textDocument"];
      NSDictionary *positionDict = params[@"position"];
      if (![textDocument isKindOfClass:[NSDictionary class]] ||
          ![positionDict isKindOfClass:[NSDictionary class]])
        break;

      NSString *uri = textDocument[@"uri"];
      NSNumber *line = positionDict[@"line"];
      NSNumber *character = positionDict[@"character"];

      if ([uri isKindOfClass:[NSString class]] &&
          [line isKindOfClass:[NSNumber class]] &&
          [character isKindOfClass:[NSNumber class]]) {
        LSPPosition pos = {.line = [line intValue],
                           .character = [character intValue]};
        size_t completion_count;
        LSPCompletionItem *completions =
            get_completions(server, [uri UTF8String], pos, &completion_count);

        NSMutableArray *items = [NSMutableArray array];
        for (size_t i = 0; i < completion_count; i++) {
          [items addObject:@{
            @"label" : @(completions[i].label),
            @"kind" : @(completions[i].kind),
            @"detail" : @(completions[i].detail ?: ""),
            @"documentation" : @(completions[i].documentation ?: "")
          }];
          free(completions[i].label);
          free(completions[i].detail);
          free(completions[i].documentation);
          free(completions[i].insert_text);
        }
        free(completions);

        NSDictionary *response = @{
          @"jsonrpc" : @"2.0",
          @"id" : messageId ?: [NSNull null],
          @"result" : @{@"isIncomplete" : @NO, @"items" : items}
        };
        send_lsp_response_from_dict(response);
      }
      break;
    }

    case LSP_METHOD_TEXT_DOCUMENT_SEMANTIC_TOKENS_FULL: {
      if (![params isKindOfClass:[NSDictionary class]])
        break;
      NSDictionary *textDocument = params[@"textDocument"];
      if (![textDocument isKindOfClass:[NSDictionary class]])
        break;

      NSString *uri = textDocument[@"uri"];
      if ([uri isKindOfClass:[NSString class]]) {
        size_t token_count;
        uint32_t *tokens =
            get_semantic_tokens(server, [uri UTF8String], &token_count);

        NSMutableArray *tokenArray = [NSMutableArray array];
        for (size_t i = 0; i < token_count; i++) {
          [tokenArray addObject:@(tokens[i])];
        }
        free(tokens);

        NSDictionary *response = @{
          @"jsonrpc" : @"2.0",
          @"id" : messageId ?: [NSNull null],
          @"result" : @{@"data" : tokenArray}
        };
        send_lsp_response_from_dict(response);
      }
      break;
    }
    case LSP_METHOD_TEXT_DOCUMENT_DID_CHANGE: {
      if (![params isKindOfClass:[NSDictionary class]])
        break;
      NSDictionary *textDocument = params[@"textDocument"];
      NSArray *changes = params[@"contentChanges"];
      NSNumber *version = params[@"version"];

      if (![textDocument isKindOfClass:[NSDictionary class]] ||
          ![changes isKindOfClass:[NSArray class]])
        break;

      NSString *uri = textDocument[@"uri"];
      if ([uri isKindOfClass:[NSString class]] && [changes count] > 0) {
        // We're using full sync (capability=1), so take first full text
        NSDictionary *firstChange = changes[0];
        if ([firstChange isKindOfClass:[NSDictionary class]]) {
          NSString *text = firstChange[@"text"];
          if ([text isKindOfClass:[NSString class]]) {
            update_document(server, [uri UTF8String], [text UTF8String],
                            [version intValue]);

            // Send updated diagnostics
            size_t diag_count;
            LSPDiagnostic *diagnostics =
                get_diagnostics(server, [uri UTF8String], &diag_count);

            NSMutableArray *diag_array = [NSMutableArray array];
            for (size_t i = 0; i < diag_count; i++) {
              [diag_array addObject:@{
                @"range" : @{
                  @"start" : @{
                    @"line" : @(diagnostics[i].range.start.line),
                    @"character" : @(diagnostics[i].range.start.character)
                  },
                  @"end" : @{
                    @"line" : @(diagnostics[i].range.end.line),
                    @"character" : @(diagnostics[i].range.end.character)
                  }
                },
                @"severity" : @(diagnostics[i].severity),
                @"source" : @(diagnostics[i].source),
                @"message" : @(diagnostics[i].message)
              }];
              free(diagnostics[i].message);
              free(diagnostics[i].source);
            }
            free(diagnostics);

            NSDictionary *diag_params =
                @{@"uri" : uri, @"diagnostics" : diag_array};
            send_lsp_notification(@"textDocument/publishDiagnostics",
                                  diag_params);
          }
        }
      }
      break;
    }

    case LSP_METHOD_TEXT_DOCUMENT_FORMATTING: {
      if (![params isKindOfClass:[NSDictionary class]])
        break;
      NSDictionary *textDocument = params[@"textDocument"];
      if (![textDocument isKindOfClass:[NSDictionary class]])
        break;

      NSString *uri = textDocument[@"uri"];
      if ([uri isKindOfClass:[NSString class]]) {
        size_t edit_count;
        LSPTextEdit *edits =
            get_document_formatting(server, [uri UTF8String], &edit_count);

        NSMutableArray *edits_array = [NSMutableArray array];
        for (size_t i = 0; i < edit_count; i++) {
          [edits_array addObject:@{
            @"range" : @{
              @"start" : @{
                @"line" : @(edits[i].range.start.line),
                @"character" : @(edits[i].range.start.character)
              },
              @"end" : @{
                @"line" : @(edits[i].range.end.line),
                @"character" : @(edits[i].range.end.character)
              }
            },
            @"newText" : @(edits[i].newText)
          }];
          free(edits[i].newText);
        }
        free(edits);

        NSDictionary *response = @{
          @"jsonrpc" : @"2.0",
          @"id" : messageId ?: [NSNull null],
          @"result" : edits_array
        };
        send_lsp_response_from_dict(response);
      }
      break;
    }
    case LSP_METHOD_TEXT_DOCUMENT_SIGNATURE_HELP: {
      if (![params isKindOfClass:[NSDictionary class]])
        break;
      NSDictionary *textDocument = params[@"textDocument"];
      NSDictionary *positionDict = params[@"position"];
      if (![textDocument isKindOfClass:[NSDictionary class]] ||
          ![positionDict isKindOfClass:[NSDictionary class]])
        break;

      NSString *uri = textDocument[@"uri"];
      NSNumber *line = positionDict[@"line"];
      NSNumber *character = positionDict[@"character"];

      if ([uri isKindOfClass:[NSString class]] &&
          [line isKindOfClass:[NSNumber class]] &&
          [character isKindOfClass:[NSNumber class]]) {
        LSPPosition pos = {.line = [line intValue],
                           .character = [character intValue]};
        LSPSignatureHelp *signature_help =
            get_signature_help(server, [uri UTF8String], pos);

        if (signature_help && signature_help->signature_count > 0) {
          NSMutableArray *signaturesArray = [NSMutableArray array];

          for (size_t i = 0; i < signature_help->signature_count; i++) {
            LSPSignatureInformation *sig = &signature_help->signatures[i];

            NSMutableArray *parametersArray = [NSMutableArray array];
            for (size_t j = 0; j < sig->parameter_count; j++) {
              LSPParameterInformation *param = &sig->parameters[j];
              [parametersArray addObject:@{
                @"label" : @[ @(param->start), @(param->end) ],
                @"documentation" : @(param->documentation ?: "")
              }];
            }

            [signaturesArray addObject:@{
              @"label" : @(sig->label),
              @"documentation" : @(sig->documentation ?: ""),
              @"parameters" : parametersArray,
              @"activeParameter" : @(sig->active_parameter)
            }];
          }

          NSDictionary *response = @{
            @"jsonrpc" : @"2.0",
            @"id" : messageId ?: [NSNull null],
            @"result" : @{
              @"signatures" : signaturesArray,
              @"activeSignature" : @(signature_help->active_signature),
              @"activeParameter" : @(signature_help->active_parameter)
            }
          };
          send_lsp_response_from_dict(response);
        } else {
          // No signature help available
          NSDictionary *response = @{
            @"jsonrpc" : @"2.0",
            @"id" : messageId ?: [NSNull null],
            @"result" : [NSNull null]
          };
          send_lsp_response_from_dict(response);
        }

        if (signature_help) {
          free_signature_help(signature_help);
        }
      }
      break;
    }
    case LSP_METHOD_TEXT_DOCUMENT_GOTO_DEFINITION: {
      if (![params isKindOfClass:[NSDictionary class]])
        break;
      NSDictionary *textDocument = params[@"textDocument"];
      NSDictionary *positionDict = params[@"position"];
      if (![textDocument isKindOfClass:[NSDictionary class]] ||
          ![positionDict isKindOfClass:[NSDictionary class]])
        break;

      NSString *uri = textDocument[@"uri"];
      NSNumber *line = positionDict[@"line"];
      NSNumber *character = positionDict[@"character"];

      if ([uri isKindOfClass:[NSString class]] &&
          [line isKindOfClass:[NSNumber class]] &&
          [character isKindOfClass:[NSNumber class]]) {
        LSPPosition pos = {.line = [line intValue],
                           .character = [character intValue]};

        size_t location_count;
        LSPLocation *locations = get_definition_locations(
            server, [uri UTF8String], pos, &location_count);

        if (locations && location_count > 0) {
          NSMutableArray *locationsArray = [NSMutableArray array];

          for (size_t i = 0; i < location_count; i++) {
            [locationsArray addObject:@{
              @"uri" : @(locations[i].uri),
              @"range" : @{
                @"start" : @{
                  @"line" : @(locations[i].range.start.line),
                  @"character" : @(locations[i].range.start.character)
                },
                @"end" : @{
                  @"line" : @(locations[i].range.end.line),
                  @"character" : @(locations[i].range.end.character)
                }
              }
            }];
            free(locations[i].uri);
          }
          free(locations);

          NSDictionary *response = @{
            @"jsonrpc" : @"2.0",
            @"id" : messageId ?: [NSNull null],
            @"result" : locationsArray
          };
          send_lsp_response_from_dict(response);
        } else {
          // No definition found
          NSDictionary *response = @{
            @"jsonrpc" : @"2.0",
            @"id" : messageId ?: [NSNull null],
            @"result" : [NSNull null]
          };
          send_lsp_response_from_dict(response);
        }
      }
      break;
    }

    case LSP_METHOD_TEXT_DOCUMENT_HOVER: {
      if (![params isKindOfClass:[NSDictionary class]])
        break;
      NSDictionary *textDocument = params[@"textDocument"];
      NSDictionary *positionDict = params[@"position"];
      if (![textDocument isKindOfClass:[NSDictionary class]] ||
          ![positionDict isKindOfClass:[NSDictionary class]])
        break;

      NSString *uri = textDocument[@"uri"];
      NSNumber *line = positionDict[@"line"];
      NSNumber *character = positionDict[@"character"];

      if ([uri isKindOfClass:[NSString class]] &&
          [line isKindOfClass:[NSNumber class]] &&
          [character isKindOfClass:[NSNumber class]]) {
        LSPPosition pos = {.line = [line intValue],
                           .character = [character intValue]};

        LSPHover *hover_info = get_hover_info(server, [uri UTF8String], pos);

        if (hover_info && hover_info->content) {
          NSMutableDictionary *result = [NSMutableDictionary dictionary];

          // Handle hover content - can be string or MarkupContent
          if (hover_info->is_markup) {
            result[@"contents"] = @{
              @"kind" : @(hover_info->markup_kind), // "markdown" or "plaintext"
              @"value" : @(hover_info->content)
            };
          } else {
            result[@"contents"] = @(hover_info->content);
          }

          // Add range if available
          if (hover_info->has_range) {
            result[@"range"] = @{
              @"start" : @{
                @"line" : @(hover_info->range.start.line),
                @"character" : @(hover_info->range.start.character)
              },
              @"end" : @{
                @"line" : @(hover_info->range.end.line),
                @"character" : @(hover_info->range.end.character)
              }
            };
          }

          NSDictionary *response = @{
            @"jsonrpc" : @"2.0",
            @"id" : messageId ?: [NSNull null],
            @"result" : result
          };
          send_lsp_response_from_dict(response);

          free_hover_info(hover_info);
        } else {
          // No hover information available
          NSDictionary *response = @{
            @"jsonrpc" : @"2.0",
            @"id" : messageId ?: [NSNull null],
            @"result" : [NSNull null]
          };
          send_lsp_response_from_dict(response);
        }
      }
      break;
    }

    default:
      // Method not implemented
      break;
    }
  }
}

// --- Document Management ---

LSPTextDocument *find_document(MetalLSPServer *server, const char *uri) {
  pthread_mutex_lock(&server->documents_mutex);

  for (size_t i = 0; i < server->document_count; i++) {
    if (strcmp(server->documents[i]->uri, uri) == 0) {
      pthread_mutex_unlock(&server->documents_mutex);
      return server->documents[i];
    }
  }

  pthread_mutex_unlock(&server->documents_mutex);
  return NULL;
}

void update_document(MetalLSPServer *server, const char *uri, const char *text,
                     int version) {
  // Find document and update its content
  LSPTextDocument *doc = find_document(server, uri);
  if (doc) {
    free(doc->text);
    doc->text = strdup(text);
    doc->version = version;
    doc->text_length = strlen(text);
  }
}

LSPTextEdit *get_document_formatting(MetalLSPServer *server, const char *uri,
                                     size_t *edit_count) {
  *edit_count = 0;

  // Find document
  LSPTextDocument *doc = find_document(server, uri);
  if (!doc || !doc->text) {
    return NULL;
  }

  const char *text = doc->text;
  size_t text_len = strlen(text);
  if (text_len == 0) {
    return NULL;
  }

  // Count lines and detect if document ends with newline
  int line_count = 1;
  bool ends_with_newline = false;
  const char *p = text;
  while (*p) {
    if (*p == '\n') {
      line_count++;
      if (*(p + 1) == '\0') {
        ends_with_newline = true;
      }
    }
    p++;
  }

  // Split into lines
  char **lines = malloc(line_count * sizeof(char *));
  if (!lines)
    return NULL;

  int index = 0;
  const char *start = text;
  p = text;
  while (*p) {
    if (*p == '\n') {
      size_t len = p - start;
      lines[index] = malloc(len + 1);
      strncpy(lines[index], start, len);
      lines[index][len] = '\0';
      index++;
      start = p + 1;
    }
    p++;
  }
  if (p > start) {
    size_t len = p - start;
    lines[index] = malloc(len + 1);
    strncpy(lines[index], start, len);
    lines[index][len] = '\0';
    index++;
  }

  line_count = index;

  // Format lines
  int indent_level = 0;
  char *output = calloc(1, 1);
  size_t output_len = 1;

  for (int i = 0; i < line_count; i++) {
    char *trail_trimmed = trim_trailing(lines[i]);
    char *ltrimmed = trim_leading(trail_trimmed);
    free(trail_trimmed);

    int adjust = 0;
    if (ltrimmed[0] == '}') {
      adjust = -1;
    }

    int current_indent = indent_level + adjust;
    if (current_indent < 0)
      current_indent = 0;

    int net_braces = 0;
    for (char *c = ltrimmed; *c; c++) {
      if (*c == '{')
        net_braces++;
      else if (*c == '}')
        net_braces--;
    }

    char *indent_str = create_indent_string(current_indent * 2);
    char *formatted_line = NULL;

    if (strlen(ltrimmed) > 0) {
      if (i == line_count - 1 && !ends_with_newline) {
        asprintf(&formatted_line, "%s%s", indent_str, ltrimmed);
      } else {
        asprintf(&formatted_line, "%s%s\n", indent_str, ltrimmed);
      }
    } else {
      if (i == line_count - 1 && !ends_with_newline) {
        formatted_line = strdup(""); // prevent final newline
      } else {
        formatted_line = strdup("\n"); // allow internal blank lines
      }
    }

    if (!formatted_line) {
      free(indent_str);
      free(ltrimmed);
      continue;
    }

    size_t formatted_len = strlen(formatted_line);
    char *new_output = realloc(output, output_len + formatted_len);
    if (!new_output) {
      free(formatted_line);
      free(indent_str);
      free(ltrimmed);
      continue;
    }
    output = new_output;
    strcat(output + output_len - 1, formatted_line);
    output_len += formatted_len;

    indent_level += net_braces;
    if (indent_level < 0)
      indent_level = 0;

    free(formatted_line);
    free(indent_str);
    free(ltrimmed);
    free(lines[i]);
  }

  free(lines);

  if (strcmp(output, doc->text) == 0) {
    free(output);
    return NULL;
  }

  *edit_count = 1;
  LSPTextEdit *edits = malloc(sizeof(LSPTextEdit));
  if (!edits) {
    free(output);
    return NULL;
  }

  edits[0].range = get_full_document_range(doc->text);
  edits[0].newText = output;

  return edits;
}

void add_document(MetalLSPServer *server, LSPTextDocument *document) {
  pthread_mutex_lock(&server->documents_mutex);

  // Check if document already exists and update it
  for (size_t i = 0; i < server->document_count; i++) {
    if (strcmp(server->documents[i]->uri, document->uri) == 0) {
      free(server->documents[i]->text);
      server->documents[i]->text = document->text;
      server->documents[i]->version = document->version;
      server->documents[i]->text_length = document->text_length;
      free(document->uri); // Free the new doc's URI as it's a duplicate
      free(document);      // Free the new doc container
      pthread_mutex_unlock(&server->documents_mutex);
      return;
    }
  }

  // If not found, add as a new document
  if (server->document_count >= server->document_capacity) {
    server->document_capacity *= 2;
    server->documents =
        realloc(server->documents,
                sizeof(LSPTextDocument *) * server->document_capacity);
  }

  server->documents[server->document_count++] = document;

  pthread_mutex_unlock(&server->documents_mutex);
}

void remove_document(MetalLSPServer *server, const char *uri) {
  pthread_mutex_lock(&server->documents_mutex);

  for (size_t i = 0; i < server->document_count; i++) {
    if (strcmp(server->documents[i]->uri, uri) == 0) {
      free(server->documents[i]->uri);
      free(server->documents[i]->text);
      free(server->documents[i]);

      // Shift remaining documents
      for (size_t j = i; j < server->document_count - 1; j++) {
        server->documents[j] = server->documents[j + 1];
      }
      server->document_count--;
      break;
    }
  }

  pthread_mutex_unlock(&server->documents_mutex);
}

// --- Helper Functions ---

BOOL is_metal_keyword(const char *word) {
  for (size_t i = 0; i < sizeof(metal_keywords) / sizeof(metal_keywords[0]);
       i++) {
    if (strcmp(word, metal_keywords[i]) == 0) {
      return YES;
    }
  }
  return NO;
}

BOOL is_metal_builtin_function(const char *word) {
  for (size_t i = 0;
       i < sizeof(metal_builtin_functions) / sizeof(metal_builtin_functions[0]);
       i++) {
    if (strcmp(word, metal_builtin_functions[i]) == 0) {
      return YES;
    }
  }
  return NO;
}

// --- Language Feature Providers ---

// Helper: Tokenize Metal source code
typedef NS_ENUM(NSUInteger, MetalTokenType) {
  TOKEN_IDENTIFIER,
  TOKEN_KEYWORD,
  TOKEN_PUNCTUATION,
  TOKEN_COMMENT,
  TOKEN_PREPROCESSOR,
  TOKEN_STRING,
  TOKEN_NUMBER,
  TOKEN_OPERATOR,
  TOKEN_OTHER
};

@interface MetalToken : NSObject
@property(assign) MetalTokenType type;
@property(copy) NSString *value;
@property(assign) NSRange range;
@property(assign) int line;
@property(assign) int character;
@end

@implementation MetalToken
@end

NSArray<MetalToken *> *tokenizeMetal(NSString *source) {
  NSMutableArray<MetalToken *> *tokens = [NSMutableArray array];
  NSUInteger length = source.length;
  NSUInteger position = 0;
  int currentLine = 0;
  int currentChar = 0;

  NSCharacterSet *whitespaceSet = [NSCharacterSet whitespaceCharacterSet];
  NSCharacterSet *newlineSet = [NSCharacterSet newlineCharacterSet];
  NSCharacterSet *alphanumericSet = [NSCharacterSet alphanumericCharacterSet];
  NSCharacterSet *digitSet = [NSCharacterSet decimalDigitCharacterSet];

  while (position < length) {
    unichar c = [source characterAtIndex:position];
    NSUInteger start = position;
    int startLine = currentLine;
    int startChar = currentChar;

    // Handle newlines
    if ([newlineSet characterIsMember:c]) {
      currentLine++;
      currentChar = 0;
      position++;
      continue;
    }

    // Skip whitespace
    if ([whitespaceSet characterIsMember:c]) {
      currentChar++;
      position++;
      continue;
    }

    // Handle single-line comments
    if (c == '/' && position + 1 < length) {
      unichar next = [source characterAtIndex:position + 1];
      if (next == '/') {
        position += 2;
        currentChar += 2;
        while (position < length &&
               ![newlineSet
                   characterIsMember:[source characterAtIndex:position]]) {
          position++;
          currentChar++;
        }

        MetalToken *token = [MetalToken new];
        token.type = TOKEN_COMMENT;
        token.value =
            [source substringWithRange:NSMakeRange(start, position - start)];
        token.range = NSMakeRange(start, position - start);
        token.line = startLine;
        token.character = startChar;
        [tokens addObject:token];
        continue;
      }

      // Handle multi-line comments
      if (next == '*') {
        position += 2;
        currentChar += 2;
        while (position < length - 1) {
          if ([source characterAtIndex:position] == '*' &&
              [source characterAtIndex:position + 1] == '/') {
            position += 2;
            currentChar += 2;
            break;
          }
          if ([newlineSet
                  characterIsMember:[source characterAtIndex:position]]) {
            currentLine++;
            currentChar = 0;
          } else {
            currentChar++;
          }
          position++;
        }

        MetalToken *token = [MetalToken new];
        token.type = TOKEN_COMMENT;
        token.value =
            [source substringWithRange:NSMakeRange(start, position - start)];
        token.range = NSMakeRange(start, position - start);
        token.line = startLine;
        token.character = startChar;
        [tokens addObject:token];
        continue;
      }
    }

    // Handle preprocessor directives
    if (c == '#') {
      while (position < length &&
             ![newlineSet
                 characterIsMember:[source characterAtIndex:position]]) {
        position++;
        currentChar++;
      }

      MetalToken *token = [MetalToken new];
      token.type = TOKEN_PREPROCESSOR;
      token.value =
          [source substringWithRange:NSMakeRange(start, position - start)];
      token.range = NSMakeRange(start, position - start);
      token.line = startLine;
      token.character = startChar;
      [tokens addObject:token];
      continue;
    }

    // Handle string literals
    if (c == '"') {
      position++;
      currentChar++;
      while (position < length) {
        unichar sc = [source characterAtIndex:position];
        if (sc == '"' &&
            (position == 0 || [source characterAtIndex:position - 1] != '\\')) {
          position++;
          currentChar++;
          break;
        }
        if ([newlineSet characterIsMember:sc]) {
          currentLine++;
          currentChar = 0;
        } else {
          currentChar++;
        }
        position++;
      }

      MetalToken *token = [MetalToken new];
      token.type = TOKEN_STRING;
      token.value =
          [source substringWithRange:NSMakeRange(start, position - start)];
      token.range = NSMakeRange(start, position - start);
      token.line = startLine;
      token.character = startChar;
      [tokens addObject:token];
      continue;
    }

    // Handle numbers
    if ([digitSet characterIsMember:c] ||
        (c == '.' && position + 1 < length &&
         [digitSet characterIsMember:[source characterAtIndex:position + 1]])) {
      while (position < length) {
        unichar nc = [source characterAtIndex:position];
        if (![digitSet characterIsMember:nc] && nc != '.' && nc != 'f' &&
            nc != 'F')
          break;
        position++;
        currentChar++;
      }

      MetalToken *token = [MetalToken new];
      token.type = TOKEN_NUMBER;
      token.value =
          [source substringWithRange:NSMakeRange(start, position - start)];
      token.range = NSMakeRange(start, position - start);
      token.line = startLine;
      token.character = startChar;
      [tokens addObject:token];
      continue;
    }

    // Handle identifiers and keywords
    if ([alphanumericSet characterIsMember:c] || c == '_') {
      while (position < length) {
        unichar nc = [source characterAtIndex:position];
        if (![alphanumericSet characterIsMember:nc] && nc != '_')
          break;
        position++;
        currentChar++;
      }

      NSString *value =
          [source substringWithRange:NSMakeRange(start, position - start)];
      MetalToken *token = [MetalToken new];
      token.value = value;
      token.range = NSMakeRange(start, position - start);
      token.line = startLine;
      token.character = startChar;

      // Check for keywords
      token.type = is_metal_keyword([value UTF8String]) ? TOKEN_KEYWORD
                                                        : TOKEN_IDENTIFIER;
      [tokens addObject:token];
      continue;
    }

    // Handle operators and punctuation
    NSString *operators = @"+-*/=<>!&|^~%?:;,(){}[]";
    if ([operators rangeOfString:[NSString stringWithCharacters:&c length:1]]
            .location != NSNotFound) {
      position++;
      currentChar++;

      MetalToken *token = [MetalToken new];
      token.type = (c == ';' || c == '{' || c == '}' || c == '(' || c == ')' ||
                    c == '[' || c == ']' || c == ',')
                       ? TOKEN_PUNCTUATION
                       : TOKEN_OPERATOR;
      token.value = [NSString stringWithCharacters:&c length:1];
      token.range = NSMakeRange(start, 1);
      token.line = startLine;
      token.character = startChar;
      [tokens addObject:token];
      continue;
    }

    // Default: advance by one character
    position++;
    currentChar++;
  }

  return tokens;
}

uint32_t *get_semantic_tokens(MetalLSPServer *server, const char *uri,
                              size_t *count) {
  LSPTextDocument *doc = find_document(server, uri);
  if (!doc) {
    *count = 0;
    return NULL;
  }

  NSString *source = [NSString stringWithUTF8String:doc->text];
  NSArray<MetalToken *> *tokens = tokenizeMetal(source);

  // Filter tokens that need semantic highlighting
  NSMutableArray<MetalToken *> *semanticTokens = [NSMutableArray array];

  for (MetalToken *token in tokens) {
    if (token.type == TOKEN_KEYWORD || token.type == TOKEN_IDENTIFIER ||
        token.type == TOKEN_STRING || token.type == TOKEN_NUMBER ||
        token.type == TOKEN_COMMENT) {
      [semanticTokens addObject:token];
    }
  }

  // Convert to LSP semantic tokens format (delta encoded)
  // Each token is represented by 5 integers: deltaLine, deltaStart, length,
  // tokenType, tokenModifiers
  *count = semanticTokens.count * 5;
  if (*count == 0)
    return NULL;

  uint32_t *result = malloc(sizeof(uint32_t) * (*count));

  int prevLine = 0;
  int prevChar = 0;

  for (NSUInteger i = 0; i < semanticTokens.count; i++) {
    MetalToken *token = semanticTokens[i];

    // Calculate deltas
    uint32_t deltaLine = token.line - prevLine;
    uint32_t deltaChar =
        (deltaLine == 0) ? (token.character - prevChar) : token.character;
    uint32_t length = (uint32_t)token.value.length;

    // Determine token type index
    uint32_t tokenType = 0; // default to namespace
    switch (token.type) {
    case TOKEN_KEYWORD:
      if (is_metal_builtin_function([token.value UTF8String])) {
        tokenType = 12; // function
      } else {
        tokenType = 15; // keyword
      }
      break;
    case TOKEN_IDENTIFIER:
      // Check if it's a known type
      if ([@[ @"float", @"int", @"bool", @"void", @"half", @"uint" ]
              containsObject:token.value] ||
          [token.value hasPrefix:@"float"] || [token.value hasPrefix:@"int"] ||
          [token.value hasPrefix:@"uint"] || [token.value hasPrefix:@"half"]) {
        tokenType = 1; // type
      } else if (is_metal_builtin_function([token.value UTF8String])) {
        tokenType = 12; // function
      } else {
        tokenType = 8; // variable
      }
      break;
    case TOKEN_STRING:
      tokenType = 18; // string
      break;
    case TOKEN_NUMBER:
      tokenType = 19; // number
      break;
    case TOKEN_COMMENT:
      tokenType = 17; // comment
      break;
    default:
      tokenType = 0;
      break;
    }

    uint32_t tokenModifiers = 0; // no modifiers for now

    // Store in result array
    size_t baseIndex = i * 5;
    result[baseIndex] = deltaLine;
    result[baseIndex + 1] = deltaChar;
    result[baseIndex + 2] = length;
    result[baseIndex + 3] = tokenType;
    result[baseIndex + 4] = tokenModifiers;

    // Update previous position
    prevLine = token.line;
    prevChar = token.character;
  }

  return result;
}

LSPCompletionItem *get_completions(MetalLSPServer *server, const char *uri,
                                   LSPPosition position, size_t *count) {
  LSPTextDocument *doc = find_document(server, uri);
  if (!doc) {
    *count = 0;
    return NULL;
  }

  // Tokenize document and analyze context
  NSString *source = [NSString stringWithUTF8String:doc->text];
  NSArray<MetalToken *> *tokens = tokenizeMetal(source);

  // Find token at cursor position
  NSUInteger cursorPos = 0;
  for (NSUInteger i = 0; i < position.line; i++) {
    cursorPos =
        [source rangeOfString:@"\n"
                      options:0
                        range:NSMakeRange(cursorPos, source.length - cursorPos)]
            .location +
        1;
  }
  cursorPos += position.character;

  // Determine context from previous tokens
  BOOL inKernelContext = NO;
  for (MetalToken *token in tokens) {
    if (NSLocationInRange(cursorPos, token.range))
      break;

    if (token.type == TOKEN_KEYWORD && [token.value isEqual:@"kernel"]) {
      inKernelContext = YES;
    }
  }

  // Filter symbols based on context
  NSMutableArray *filteredSymbols = [NSMutableArray array];
  for (size_t i = 0; i < server->symbol_count; i++) {
    MetalSymbol symbol = server->built_in_symbols[i];

    // Skip kernel-specific types in non-kernel contexts
    if (!inKernelContext &&
        [@[ @"metal::kernel", @"metal::texture2d" ]
            containsObject:[NSString stringWithUTF8String:symbol.name]]) {
      continue;
    }

    [filteredSymbols addObject:[NSValue value:&symbol
                                   withObjCType:@encode(MetalSymbol)]];
  }

  // Allocate completion items
  *count = filteredSymbols.count;
  if (*count == 0)
    return NULL;

  LSPCompletionItem *items = malloc(sizeof(LSPCompletionItem) * (*count));

  for (size_t i = 0; i < filteredSymbols.count; i++) {
    MetalSymbol symbol;
    [filteredSymbols[i] getValue:&symbol];

    items[i].label = strdup(symbol.name);
    items[i].kind = symbol.kind;
    items[i].detail = strdup(symbol.signature);
    items[i].documentation = strdup(symbol.documentation);
    items[i].insert_text = strdup(symbol.name);
  }

  return items;
}

void addDiagnostic(NSMutableArray *diagnostics, int line, int character,
                   int length, LSPDiagnosticSeverity severity,
                   const char *message) {
  LSPDiagnostic diag;
  diag.range = (LSPRange){{line, character}, {line, character + length}};
  diag.severity = severity;
  diag.message = strdup(message);
  diag.source = strdup("metal-lsp");
  [diagnostics addObject:[NSValue value:&diag
                             withObjCType:@encode(LSPDiagnostic)]];
}

LSPDiagnostic *get_diagnostics(MetalLSPServer *server, const char *uri,
                               size_t *count) {
  LSPTextDocument *doc = find_document(server, uri);
  if (!doc) {
    *count = 0;
    return NULL;
  }

  NSMutableArray *diagnostics = [NSMutableArray array];

  // Create a temporary file
  NSString *tempDir = NSTemporaryDirectory();
  NSString *tempFilePath =
      [tempDir stringByAppendingPathComponent:@"temp_metal.metal"];
  NSString *source = [NSString stringWithUTF8String:doc->text];
  [source writeToFile:tempFilePath
           atomically:YES
             encoding:NSUTF8StringEncoding
                error:nil];

  // Compile using xcrun metal
  NSTask *task = [[NSTask alloc] init];
  [task setLaunchPath:@"/usr/bin/xcrun"];

  NSArray *arguments = @[
    @"metal", @"-x", @"metal", @"-std=macos-metal2.3", @"-Wall", @"-Wextra",
    @"-Werror", @"-o", @"/dev/null", tempFilePath
  ];

  [task setArguments:arguments];

  NSPipe *errorPipe = [NSPipe pipe];
  [task setStandardError:errorPipe];

  @try {
    [task launch];
    [task waitUntilExit];
  } @catch (NSException *exception) {
    // Handle task launch failure
    LSPDiagnostic diag;
    diag.range = (LSPRange){{0, 0}, {0, 10}};
    diag.severity = DIAGNOSTIC_ERROR;
    diag.message = strdup("Failed to run metal compiler");
    diag.source = strdup("metal-lsp");
    [diagnostics addObject:[NSValue value:&diag
                               withObjCType:@encode(LSPDiagnostic)]];

    *count = diagnostics.count;
    if (*count == 0)
      return NULL;

    LSPDiagnostic *result = malloc(sizeof(LSPDiagnostic) * (*count));
    for (size_t i = 0; i < *count; i++) {
      [diagnostics[i] getValue:&result[i]];
    }
    return result;
  }

  // Only process errors if compilation failed
  if ([task terminationStatus] != 0) {
    NSData *errorData = [[errorPipe fileHandleForReading] readDataToEndOfFile];
    NSString *errorString =
        [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];

    // Parse compiler output
    NSArray *errorLines = [errorString componentsSeparatedByString:@"\n"];
    for (NSString *line in errorLines) {
      if ([line length] == 0)
        continue;

      // Parse error line (format: filename:line:column: error: message)
      NSArray *components = [line componentsSeparatedByString:@":"];
      if ([components count] < 4)
        continue;

      NSString *filename = components[0];
      if (![filename isEqualToString:tempFilePath])
        continue;

      int lineNum = [components[1] intValue];
      int column = [components[2] intValue];
      NSString *severity = [components[3]
          stringByTrimmingCharactersInSet:[NSCharacterSet
                                              whitespaceCharacterSet]];
      NSString *message =
          [[components subarrayWithRange:NSMakeRange(4, [components count] - 4)]
              componentsJoinedByString:@":"];
      message =
          [message stringByTrimmingCharactersInSet:[NSCharacterSet
                                                       whitespaceCharacterSet]];

      LSPDiagnosticSeverity diagSeverity;
      if ([severity rangeOfString:@"error"].location != NSNotFound) {
        diagSeverity = DIAGNOSTIC_ERROR;
      } else if ([severity rangeOfString:@"warning"].location != NSNotFound) {
        diagSeverity = DIAGNOSTIC_WARNING;
      } else {
        diagSeverity = DIAGNOSTIC_INFO;
      }

      // Adjust line numbers to 0-based for LSP
      lineNum = MAX(0, lineNum - 1);
      column = MAX(0, column - 1);

      // Create diagnostic
      LSPDiagnostic diag;
      diag.range = (LSPRange){{lineNum, column}, {lineNum, column + 1}};
      diag.severity = diagSeverity;
      diag.message = strdup([message UTF8String]);
      diag.source = strdup("metal-compiler");

      [diagnostics addObject:[NSValue value:&diag
                                 withObjCType:@encode(LSPDiagnostic)]];
    }
  }

  // Clean up temporary file
  [[NSFileManager defaultManager] removeItemAtPath:tempFilePath error:nil];

  // Convert to C array
  *count = diagnostics.count;
  if (*count == 0)
    return NULL;

  LSPDiagnostic *result = malloc(sizeof(LSPDiagnostic) * (*count));
  for (size_t i = 0; i < *count; i++) {
    [diagnostics[i] getValue:&result[i]];
  }

  return result;
}

static char *find_function_call_at_position(const char *text, int line,
                                            int character, int *param_index) {
  if (!text || line < 0 || character < 0) {
    return NULL;
  }

  // Convert line/character to absolute position
  int pos = 0;
  int current_line = 0;
  int current_char = 0;

  while (text[pos] && current_line < line) {
    if (text[pos] == '\n') {
      current_line++;
      current_char = 0;
    } else {
      current_char++;
    }
    pos++;
  }

  pos += character;
  if (pos >= strlen(text)) {
    pos = strlen(text) - 1;
  }

  // Search backwards for opening parenthesis
  int paren_count = 0;
  int comma_count = 0;
  int search_pos = pos;

  while (search_pos >= 0) {
    char c = text[search_pos];

    if (c == ')') {
      paren_count++;
    } else if (c == '(') {
      if (paren_count == 0) {
        // Found the opening parenthesis
        // Now find the function name before it
        int name_end = search_pos - 1;

        // Skip whitespace
        while (name_end >= 0 && isspace(text[name_end])) {
          name_end--;
        }

        if (name_end < 0)
          return NULL;

        // Find start of function name
        int name_start = name_end;
        while (name_start >= 0 &&
               (isalnum(text[name_start]) || text[name_start] == '_')) {
          name_start--;
        }
        name_start++;

        // Extract function name
        int name_len = name_end - name_start + 1;
        if (name_len <= 0)
          return NULL;

        char *function_name = malloc(name_len + 1);
        strncpy(function_name, text + name_start, name_len);
        function_name[name_len] = '\0';

        *param_index = comma_count;
        return function_name;
      } else {
        paren_count--;
      }
    } else if (c == ',' && paren_count == 0) {
      comma_count++;
    }

    search_pos--;
  }

  return NULL;
}

LSPSignatureHelp *get_signature_help(MetalLSPServer *server, const char *uri,
                                     LSPPosition position) {
  LSPTextDocument *doc = find_document(server, uri);
  if (!doc || !doc->text) {
    return NULL;
  }

  int param_index = 0;
  char *function_name = find_function_call_at_position(
      doc->text, position.line, position.character, &param_index);

  if (!function_name) {
    return NULL;
  }

  // Find matching function signature
  MetalFunctionSignature *found_sig = NULL;
  for (size_t i = 0; i < metal_function_signatures_count; i++) {
    if (strcmp(metal_function_signatures[i].name, function_name) == 0) {
      found_sig = &metal_function_signatures[i];
      break;
    }
  }

  free(function_name);

  if (!found_sig) {
    return NULL;
  }

  // Create signature help response
  LSPSignatureHelp *help = malloc(sizeof(LSPSignatureHelp));
  help->signature_count = 1;
  help->active_signature = 0;
  help->active_parameter = (param_index < found_sig->parameter_count)
                               ? param_index
                               : found_sig->parameter_count - 1;

  help->signatures = malloc(sizeof(LSPSignatureInformation));
  LSPSignatureInformation *sig = &help->signatures[0];

  sig->label = strdup(found_sig->signature);
  sig->documentation = strdup(found_sig->documentation);
  sig->parameter_count = found_sig->parameter_count;
  sig->active_parameter = help->active_parameter;

  // Create parameter information
  sig->parameters =
      malloc(sizeof(LSPParameterInformation) * sig->parameter_count);

  // Parse signature to find parameter positions
  const char *sig_text = found_sig->signature;
  const char *paren_start = strchr(sig_text, '(');
  if (!paren_start) {
    free_signature_help(help);
    return NULL;
  }

  int current_pos = (paren_start - sig_text) + 1; // Start after '('

  for (size_t i = 0; i < sig->parameter_count; i++) {
    LSPParameterInformation *param = &sig->parameters[i];
    param->label = strdup(found_sig->parameter_names[i]);
    param->documentation = strdup(found_sig->parameter_docs[i]);

    // Find parameter in signature string
    const char *param_start =
        strstr(sig_text + current_pos, found_sig->parameter_names[i]);
    if (param_start) {
      param->start = param_start - sig_text;
      param->end = param->start + strlen(found_sig->parameter_names[i]);

      // Move current_pos past this parameter
      const char *comma = strchr(param_start, ',');
      if (comma) {
        current_pos = (comma - sig_text) + 1;
      }
    } else {
      param->start = current_pos;
      param->end = current_pos + strlen(found_sig->parameter_names[i]);
    }
  }

  return help;
}

void free_signature_help(LSPSignatureHelp *signature_help) {
  if (!signature_help)
    return;

  for (size_t i = 0; i < signature_help->signature_count; i++) {
    LSPSignatureInformation *sig = &signature_help->signatures[i];

    free(sig->label);
    free(sig->documentation);

    for (size_t j = 0; j < sig->parameter_count; j++) {
      free(sig->parameters[j].label);
      free(sig->parameters[j].documentation);
    }
    free(sig->parameters);
  }

  free(signature_help->signatures);
  free(signature_help);
}

char *get_symbol_at_position(const char *text, LSPPosition position) {
  if (!text)
    return NULL;

  // Find the target line
  int current_line = 0;
  const char *line_start = text;
  const char *p = text;

  while (*p && current_line < position.line) {
    if (*p == '\n') {
      current_line++;
      line_start = p + 1;
    }
    p++;
  }

  if (current_line != position.line) {
    return NULL; // Line not found
  }

  // Find the character position in the line
  const char *char_pos = line_start;
  int current_char = 0;

  while (*char_pos && *char_pos != '\n' && current_char < position.character) {
    char_pos++;
    current_char++;
  }

  if (current_char != position.character || !*char_pos || *char_pos == '\n') {
    return NULL; // Character position not valid
  }

  // Find the start of the identifier
  const char *start = char_pos;
  while (start > line_start && (isalnum(*(start - 1)) || *(start - 1) == '_')) {
    start--;
  }

  // Find the end of the identifier
  const char *end = char_pos;
  while (*end && (isalnum(*end) || *end == '_')) {
    end++;
  }

  // Check if we have a valid identifier
  if (start == end || (!isalpha(*start) && *start != '_')) {
    return NULL;
  }

  // Extract the identifier
  size_t length = end - start;
  char *symbol = malloc(length + 1);
  if (!symbol)
    return NULL;

  strncpy(symbol, start, length);
  symbol[length] = '\0';

  return symbol;
}

LSPLocation *find_symbol_definitions(const char *text, const char *symbol,
                                     size_t *count) {
  *count = 0;
  if (!text || !symbol)
    return NULL;

  LSPLocation *locations = NULL;
  size_t capacity = 0;

  const char *p = text;
  int line = 0;
  int character = 0;
  const char *line_start = text;

  while (*p) {
    if (*p == '\n') {
      line++;
      character = 0;
      line_start = p + 1;
    } else {
      character++;
    }

    // Skip whitespace
    while (*p && isspace(*p)) {
      if (*p == '\n') {
        line++;
        character = 0;
        line_start = p + 1;
      } else {
        character++;
      }
      p++;
    }

    if (!*p)
      break;

    // Check for function definitions
    if (strncmp(p, "float", 5) == 0 || strncmp(p, "int", 3) == 0 ||
        strncmp(p, "bool", 4) == 0 || strncmp(p, "void", 4) == 0 ||
        strncmp(p, "float2", 6) == 0 || strncmp(p, "float3", 6) == 0 ||
        strncmp(p, "float4", 6) == 0 || strncmp(p, "int2", 4) == 0 ||
        strncmp(p, "int3", 4) == 0 || strncmp(p, "int4", 4) == 0 ||
        strncmp(p, "half", 4) == 0 || strncmp(p, "half2", 5) == 0 ||
        strncmp(p, "half3", 5) == 0 || strncmp(p, "half4", 5) == 0) {

      // Skip the type
      while (*p && (isalnum(*p) || *p == '_')) {
        p++;
        character++;
      }

      // Skip whitespace
      while (*p && isspace(*p) && *p != '\n') {
        p++;
        character++;
      }

      // Check if next token is our symbol
      if (strncmp(p, symbol, strlen(symbol)) == 0 &&
          !isalnum(p[strlen(symbol)]) && p[strlen(symbol)] != '_') {

        // Look ahead for opening parenthesis (function) or assignment/semicolon
        // (variable)
        const char *ahead = p + strlen(symbol);
        while (*ahead && isspace(*ahead) && *ahead != '\n')
          ahead++;

        if (*ahead == '(' || *ahead == '=' || *ahead == ';' || *ahead == '[') {
          // Found a definition
          if (*count >= capacity) {
            capacity = capacity == 0 ? 4 : capacity * 2;
            LSPLocation *new_locations =
                realloc(locations, capacity * sizeof(LSPLocation));
            if (!new_locations) {
              free(locations);
              *count = 0;
              return NULL;
            }
            locations = new_locations;
          }

          locations[*count].uri = strdup(""); // Will be filled by caller
          locations[*count].range.start.line = line;
          locations[*count].range.start.character = character;
          locations[*count].range.end.line = line;
          locations[*count].range.end.character = character + strlen(symbol);
          (*count)++;
        }
      }
    }

    // Check for struct definitions
    if (strncmp(p, "struct", 6) == 0 && (isspace(p[6]) || p[6] == '\0')) {
      p += 6;
      character += 6;

      // Skip whitespace
      while (*p && isspace(*p) && *p != '\n') {
        p++;
        character++;
      }

      // Check if next token is our symbol
      if (strncmp(p, symbol, strlen(symbol)) == 0 &&
          !isalnum(p[strlen(symbol)]) && p[strlen(symbol)] != '_') {

        // Found a struct definition
        if (*count >= capacity) {
          capacity = capacity == 0 ? 4 : capacity * 2;
          LSPLocation *new_locations =
              realloc(locations, capacity * sizeof(LSPLocation));
          if (!new_locations) {
            free(locations);
            *count = 0;
            return NULL;
          }
          locations = new_locations;
        }

        locations[*count].uri = strdup(""); // Will be filled by caller
        locations[*count].range.start.line = line;
        locations[*count].range.start.character = character;
        locations[*count].range.end.line = line;
        locations[*count].range.end.character = character + strlen(symbol);
        (*count)++;
      }
    }

    // Check for constant definitions
    if (strncmp(p, "constant", 8) == 0 && (isspace(p[8]) || p[8] == '\0')) {
      const char *const_start = p;
      p += 8;
      character += 8;

      // Skip whitespace and type
      while (*p && isspace(*p) && *p != '\n') {
        p++;
        character++;
      }

      // Skip type name
      while (*p && (isalnum(*p) || *p == '_')) {
        p++;
        character++;
      }

      // Skip whitespace
      while (*p && isspace(*p) && *p != '\n') {
        p++;
        character++;
      }

      // Check if next token is our symbol
      if (strncmp(p, symbol, strlen(symbol)) == 0 &&
          !isalnum(p[strlen(symbol)]) && p[strlen(symbol)] != '_') {

        // Found a constant definition
        if (*count >= capacity) {
          capacity = capacity == 0 ? 4 : capacity * 2;
          LSPLocation *new_locations =
              realloc(locations, capacity * sizeof(LSPLocation));
          if (!new_locations) {
            free(locations);
            *count = 0;
            return NULL;
          }
          locations = new_locations;
        }

        locations[*count].uri = strdup(""); // Will be filled by caller
        locations[*count].range.start.line = line;
        locations[*count].range.start.character = character;
        locations[*count].range.end.line = line;
        locations[*count].range.end.character = character + strlen(symbol);
        (*count)++;
      }
    }

    if (*p) {
      p++;
      character++;
    }
  }

  return locations;
}

char *generate_hover_content(const char *symbol, const char *text,
                             LSPPosition position) {
  if (!symbol)
    return NULL;

  // Metal built-in functions
  if (strcmp(symbol, "dot") == 0) {
    return strdup("```metal\nfloat dot(float2 x, float2 y)\nfloat dot(float3 "
                  "x, float3 y)\nfloat dot(float4 x, float4 y)\nhalf dot(half2 "
                  "x, half2 y)\nhalf dot(half3 x, half3 y)\nhalf dot(half4 x, "
                  "half4 y)\n```\n\nCompute the dot product of two vectors.");
  }

  if (strcmp(symbol, "cross") == 0) {
    return strdup(
        "```metal\nfloat3 cross(float3 x, float3 y)\nhalf3 cross(half3 x, "
        "half3 y)\n```\n\nCompute the cross product of two 3D vectors.");
  }

  if (strcmp(symbol, "normalize") == 0) {
    return strdup(
        "```metal\nfloat2 normalize(float2 x)\nfloat3 normalize(float3 "
        "x)\nfloat4 normalize(float4 x)\nhalf2 normalize(half2 x)\nhalf3 "
        "normalize(half3 x)\nhalf4 normalize(half4 x)\n```\n\nReturn a vector "
        "in the same direction as x but with length 1.");
  }

  if (strcmp(symbol, "length") == 0) {
    return strdup(
        "```metal\nfloat length(float2 x)\nfloat length(float3 x)\nfloat "
        "length(float4 x)\nhalf length(half2 x)\nhalf length(half3 x)\nhalf "
        "length(half4 x)\n```\n\nReturn the length of vector x.");
  }

  if (strcmp(symbol, "distance") == 0) {
    return strdup("```metal\nfloat distance(float2 p0, float2 p1)\nfloat "
                  "distance(float3 p0, float3 p1)\nfloat distance(float4 p0, "
                  "float4 p1)\n```\n\nReturn the distance between two points.");
  }

  if (strcmp(symbol, "mix") == 0) {
    return strdup(
        "```metal\nfloat mix(float x, float y, float a)\nfloat2 mix(float2 x, "
        "float2 y, float2 a)\nfloat3 mix(float3 x, float3 y, float3 a)\nfloat4 "
        "mix(float4 x, float4 y, float4 a)\n```\n\nLinear interpolation "
        "between x and y using parameter a.");
  }

  if (strcmp(symbol, "clamp") == 0) {
    return strdup(
        "```metal\nfloat clamp(float x, float minVal, float maxVal)\nfloat2 "
        "clamp(float2 x, float2 minVal, float2 maxVal)\nfloat3 clamp(float3 x, "
        "float3 minVal, float3 maxVal)\nfloat4 clamp(float4 x, float4 minVal, "
        "float4 maxVal)\n```\n\nConstrain x to lie between minVal and maxVal.");
  }

  if (strcmp(symbol, "saturate") == 0) {
    return strdup("```metal\nfloat saturate(float x)\nfloat2 saturate(float2 "
                  "x)\nfloat3 saturate(float3 x)\nfloat4 saturate(float4 "
                  "x)\n```\n\nClamp x to the range [0, 1].");
  }

  if (strcmp(symbol, "step") == 0) {
    return strdup(
        "```metal\nfloat step(float edge, float x)\nfloat2 step(float2 edge, "
        "float2 x)\nfloat3 step(float3 edge, float3 x)\nfloat4 step(float4 "
        "edge, float4 x)\n```\n\nGenerate a step function by comparing x to "
        "edge.");
  }

  if (strcmp(symbol, "smoothstep") == 0) {
    return strdup(
        "```metal\nfloat smoothstep(float edge0, float edge1, float x)\nfloat2 "
        "smoothstep(float2 edge0, float2 edge1, float2 x)\nfloat3 "
        "smoothstep(float3 edge0, float3 edge1, float3 x)\nfloat4 "
        "smoothstep(float4 edge0, float4 edge1, float4 x)\n```\n\nPerform "
        "smooth Hermite interpolation between 0 and 1.");
  }

  if (strcmp(symbol, "pow") == 0) {
    return strdup(
        "```metal\nfloat pow(float x, float y)\nfloat2 pow(float2 x, float2 "
        "y)\nfloat3 pow(float3 x, float3 y)\nfloat4 pow(float4 x, float4 "
        "y)\n```\n\nReturn x raised to the y power.");
  }

  if (strcmp(symbol, "sqrt") == 0) {
    return strdup("```metal\nfloat sqrt(float x)\nfloat2 sqrt(float2 "
                  "x)\nfloat3 sqrt(float3 x)\nfloat4 sqrt(float4 "
                  "x)\n```\n\nReturn the square root of x.");
  }

  if (strcmp(symbol, "sin") == 0) {
    return strdup(
        "```metal\nfloat sin(float x)\nfloat2 sin(float2 x)\nfloat3 sin(float3 "
        "x)\nfloat4 sin(float4 x)\n```\n\nReturn the sine of x (in radians).");
  }

  if (strcmp(symbol, "cos") == 0) {
    return strdup("```metal\nfloat cos(float x)\nfloat2 cos(float2 x)\nfloat3 "
                  "cos(float3 x)\nfloat4 cos(float4 x)\n```\n\nReturn the "
                  "cosine of x (in radians).");
  }

  if (strcmp(symbol, "tan") == 0) {
    return strdup("```metal\nfloat tan(float x)\nfloat2 tan(float2 x)\nfloat3 "
                  "tan(float3 x)\nfloat4 tan(float4 x)\n```\n\nReturn the "
                  "tangent of x (in radians).");
  }

  if (strcmp(symbol, "abs") == 0) {
    return strdup("```metal\nfloat abs(float x)\nfloat2 abs(float2 x)\nfloat3 "
                  "abs(float3 x)\nfloat4 abs(float4 x)\nint abs(int x)\nint2 "
                  "abs(int2 x)\nint3 abs(int3 x)\nint4 abs(int4 "
                  "x)\n```\n\nReturn the absolute value of x.");
  }

  if (strcmp(symbol, "floor") == 0) {
    return strdup(
        "```metal\nfloat floor(float x)\nfloat2 floor(float2 x)\nfloat3 "
        "floor(float3 x)\nfloat4 floor(float4 x)\n```\n\nReturn the largest "
        "integer value not greater than x.");
  }

  if (strcmp(symbol, "ceil") == 0) {
    return strdup(
        "```metal\nfloat ceil(float x)\nfloat2 ceil(float2 x)\nfloat3 "
        "ceil(float3 x)\nfloat4 ceil(float4 x)\n```\n\nReturn the smallest "
        "integer value not less than x.");
  }

  if (strcmp(symbol, "fract") == 0) {
    return strdup("```metal\nfloat fract(float x)\nfloat2 fract(float2 "
                  "x)\nfloat3 fract(float3 x)\nfloat4 fract(float4 "
                  "x)\n```\n\nReturn the fractional part of x.");
  }

  if (strcmp(symbol, "max") == 0) {
    return strdup("```metal\nfloat max(float x, float y)\nfloat2 max(float2 x, "
                  "float2 y)\nfloat3 max(float3 x, float3 y)\nfloat4 "
                  "max(float4 x, float4 y)\nint max(int x, int y)\nint2 "
                  "max(int2 x, int2 y)\nint3 max(int3 x, int3 y)\nint4 "
                  "max(int4 x, int4 y)\n```\n\nReturn the maximum of x and y.");
  }

  if (strcmp(symbol, "min") == 0) {
    return strdup("```metal\nfloat min(float x, float y)\nfloat2 min(float2 x, "
                  "float2 y)\nfloat3 min(float3 x, float3 y)\nfloat4 "
                  "min(float4 x, float4 y)\nint min(int x, int y)\nint2 "
                  "min(int2 x, int2 y)\nint3 min(int3 x, int3 y)\nint4 "
                  "min(int4 x, int4 y)\n```\n\nReturn the minimum of x and y.");
  }

  // Metal built-in types
  if (strcmp(symbol, "float2") == 0) {
    return strdup("```metal\nstruct float2 {\n    float x, y;\n}\n```\n\nA "
                  "2-component floating-point vector.");
  }

  if (strcmp(symbol, "float3") == 0) {
    return strdup("```metal\nstruct float3 {\n    float x, y, z;\n}\n```\n\nA "
                  "3-component floating-point vector.");
  }

  if (strcmp(symbol, "float4") == 0) {
    return strdup("```metal\nstruct float4 {\n    float x, y, z, "
                  "w;\n}\n```\n\nA 4-component floating-point vector.");
  }

  if (strcmp(symbol, "half2") == 0) {
    return strdup("```metal\nstruct half2 {\n    half x, y;\n}\n```\n\nA "
                  "2-component half-precision floating-point vector.");
  }

  if (strcmp(symbol, "half3") == 0) {
    return strdup("```metal\nstruct half3 {\n    half x, y, z;\n}\n```\n\nA "
                  "3-component half-precision floating-point vector.");
  }

  if (strcmp(symbol, "half4") == 0) {
    return strdup("```metal\nstruct half4 {\n    half x, y, z, w;\n}\n```\n\nA "
                  "4-component half-precision floating-point vector.");
  }

  if (strcmp(symbol, "int2") == 0) {
    return strdup("```metal\nstruct int2 {\n    int x, y;\n}\n```\n\nA "
                  "2-component integer vector.");
  }

  if (strcmp(symbol, "int3") == 0) {
    return strdup("```metal\nstruct int3 {\n    int x, y, z;\n}\n```\n\nA "
                  "3-component integer vector.");
  }

  if (strcmp(symbol, "int4") == 0) {
    return strdup("```metal\nstruct int4 {\n    int x, y, z, w;\n}\n```\n\nA "
                  "4-component integer vector.");
  }

  if (strcmp(symbol, "float4x4") == 0) {
    return strdup("```metal\nstruct float4x4 {\n    float4 "
                  "columns[4];\n}\n```\n\nA 4x4 floating-point matrix.");
  }

  if (strcmp(symbol, "float3x3") == 0) {
    return strdup("```metal\nstruct float3x3 {\n    float3 "
                  "columns[3];\n}\n```\n\nA 3x3 floating-point matrix.");
  }

  // Try to find symbol definition in the text
  size_t def_count;
  LSPLocation *definitions = find_symbol_definitions(text, symbol, &def_count);

  if (definitions && def_count > 0) {
    // Found user-defined symbol, try to extract context
    char *content = malloc(512);
    if (content) {
      snprintf(content, 512,
               "```metal\n%s\n```\n\nUser-defined symbol found at line %d.",
               symbol, definitions[0].range.start.line + 1);
    }

    // Free the definitions
    for (size_t i = 0; i < def_count; i++) {
      free(definitions[i].uri);
    }
    free(definitions);

    return content;
  }

  return NULL;
}

LSPRange get_symbol_range(const char *text, LSPPosition position) {
  LSPRange range = {0};
  range.start.line = -1; // Invalid marker

  if (!text)
    return range;

  // Find the target line
  int current_line = 0;
  const char *line_start = text;
  const char *p = text;

  while (*p && current_line < position.line) {
    if (*p == '\n') {
      current_line++;
      line_start = p + 1;
    }
    p++;
  }

  if (current_line != position.line) {
    return range;
  }

  const char *char_pos = line_start;
  int current_char = 0;

  while (*char_pos && *char_pos != '\n' && current_char < position.character) {
    char_pos++;
    current_char++;
  }

  if (current_char != position.character || !*char_pos || *char_pos == '\n') {
    return range;
  }

  // Find the start of the identifier
  const char *start = char_pos;
  int start_char = current_char;

  while (start > line_start && (isalnum(*(start - 1)) || *(start - 1) == '_')) {
    start--;
    start_char--;
  }

  // Find the end of the identifier
  const char *end = char_pos;
  int end_char = current_char;

  while (*end && (isalnum(*end) || *end == '_')) {
    end++;
    end_char++;
  }

  // Check if we have a valid identifier
  if (start == end || (!isalpha(*start) && *start != '_')) {
    return range;
  }

  // Set the range
  range.start.line = position.line;
  range.start.character = start_char;
  range.end.line = position.line;
  range.end.character = end_char;

  return range;
}

LSPLocation *get_definition_locations(MetalLSPServer *server, const char *uri,
                                      LSPPosition position, size_t *count) {
  *count = 0;

  // Find the document
  LSPTextDocument *doc = find_document(server, uri);
  if (!doc) {
    return NULL;
  }

  // Get the symbol at the cursor position
  char *symbol = get_symbol_at_position(doc->text, position);
  if (!symbol) {
    return NULL;
  }

  // Search for definitions of this symbol
  LSPLocation *locations = find_symbol_definitions(doc->text, symbol, count);

  // Set the URI for each location (since find_symbol_definitions leaves it
  // empty)
  if (locations && *count > 0) {
    for (size_t i = 0; i < *count; i++) {
      free(locations[i].uri); // Free the empty string
      locations[i].uri = strdup(uri);
    }
  }

  free(symbol);
  return locations;
}

LSPHover *get_hover_info(MetalLSPServer *server, const char *uri,
                         LSPPosition position) {
  // Find the document
  LSPTextDocument *doc = find_document(server, uri);
  if (!doc) {
    return NULL;
  }

  // Get symbol at position
  char *symbol = get_symbol_at_position(doc->text, position);
  if (!symbol) {
    return NULL;
  }

  LSPHover *hover = malloc(sizeof(LSPHover));
  if (!hover) {
    free(symbol);
    return NULL;
  }

  // Initialize hover info
  hover->content = NULL;
  hover->is_markup = true;
  hover->markup_kind = strdup("markdown");
  hover->has_range = false;

  // Generate hover content based on symbol type
  char *hover_content = generate_hover_content(symbol, doc->text, position);
  if (hover_content) {
    hover->content = hover_content;

    // Set the range for the hovered symbol
    LSPRange symbol_range = get_symbol_range(doc->text, position);
    if (symbol_range.start.line >= 0) {
      hover->has_range = true;
      hover->range = symbol_range;
    }
  } else {
    // No hover content available, free and return NULL
    free(hover->markup_kind);
    free(hover);
    free(symbol);
    return NULL;
  }

  free(symbol);
  return hover;
}

void free_hover_info(LSPHover *hover) {
  if (!hover)
    return;

  free(hover->content);
  free(hover->markup_kind);
  free(hover);
}
