//
// metal_lsp_server.h
// Metal Language Server Protocol Definitions for gpumkat
//

#ifndef metal_lsp_server_h
#define metal_lsp_server_h
#import <Foundation/Foundation.h>
#import <pthread.h>
#import <stdbool.h>

// Forward declaration
struct MetalLSPServer;

// --- LSP Data Structures ---

typedef enum {
  DIAGNOSTIC_ERROR = 1,
  DIAGNOSTIC_WARNING = 2,
  DIAGNOSTIC_INFO = 3,
  DIAGNOSTIC_HINT = 4
} LSPDiagnosticSeverity;

typedef enum {
  COMPLETION_TEXT = 1,
  COMPLETION_METHOD = 2,
  COMPLETION_FUNCTION = 3,
  COMPLETION_CONSTRUCTOR = 4,
  COMPLETION_FIELD = 5,
  COMPLETION_VARIABLE = 6,
  COMPLETION_CLASS = 7,
  COMPLETION_INTERFACE = 8,
  COMPLETION_MODULE = 9,
  COMPLETION_PROPERTY = 10,
  COMPLETION_UNIT = 11,
  COMPLETION_VALUE = 12,
  COMPLETION_ENUM = 13,
  COMPLETION_KEYWORD = 14,
  COMPLETION_SNIPPET = 15,
  COMPLETION_COLOR = 16,
  COMPLETION_FILE = 17,
  COMPLETION_REFERENCE = 18,
  COMPLETION_FOLDER = 19,
  COMPLETION_ENUMMEMBER = 20,
  COMPLETION_CONSTANT = 21,
  COMPLETION_STRUCT = 22,
  COMPLETION_EVENT = 23,
  COMPLETION_OPERATOR = 24,
  COMPLETION_TYPEPARAMETER = 25
} LSPCompletionItemKind;

typedef enum {
  LSP_METHOD_UNKNOWN,
  LSP_METHOD_INITIALIZE,
  LSP_METHOD_INITIALIZED,
  LSP_METHOD_SHUTDOWN,
  LSP_METHOD_EXIT,
  LSP_METHOD_TEXT_DOCUMENT_DID_OPEN,
  LSP_METHOD_TEXT_DOCUMENT_DID_CHANGE,
  LSP_METHOD_TEXT_DOCUMENT_DID_SAVE,
  LSP_METHOD_TEXT_DOCUMENT_DID_CLOSE,
  LSP_METHOD_TEXT_DOCUMENT_COMPLETION,
  LSP_METHOD_TEXT_DOCUMENT_HOVER,
  LSP_METHOD_TEXT_DOCUMENT_GOTO_DEFINITION,
  LSP_METHOD_TEXT_DOCUMENT_FORMATTING,
  LSP_METHOD_TEXT_DOCUMENT_SEMANTIC_TOKENS_FULL,
  LSP_METHOD_TEXT_DOCUMENT_SIGNATURE_HELP
} LSPMethod;

typedef struct {
  int line;
  int character;
} LSPPosition;

typedef struct {
  LSPPosition start;
  LSPPosition end;
} LSPRange;

typedef struct {
  LSPRange range;
  LSPDiagnosticSeverity severity;
  char *message;
  char *source;
} LSPDiagnostic;

typedef struct {
  char *label;
  LSPCompletionItemKind kind;
  char *detail;
  char *documentation;
  char *insert_text;
} LSPCompletionItem;

typedef struct {
  char *uri;
  char *text;
  int version;
  size_t text_length;
} LSPTextDocument;

typedef struct {
  char *name;
  char *signature;
  char *documentation;
  LSPCompletionItemKind kind;
} MetalSymbol;

typedef struct MetalLSPServer {
  LSPTextDocument **documents;
  size_t document_count;
  size_t document_capacity;
  bool is_running;
  int client_socket;
  pthread_mutex_t documents_mutex;
  MetalSymbol *built_in_symbols;
  size_t symbol_count;
} MetalLSPServer;

typedef struct {
  LSPRange range;
  char *newText;
} LSPTextEdit;

typedef struct {
  char *label;
  char *documentation;
  int start; // Start index of parameter in signature
  int end;   // End index of parameter in signature
} LSPParameterInformation;

typedef struct {
  char *label;
  char *documentation;
  LSPParameterInformation *parameters;
  size_t parameter_count;
  int active_parameter;
} LSPSignatureInformation;

typedef struct {
  LSPSignatureInformation *signatures;
  size_t signature_count;
  int active_signature;
  int active_parameter;
} LSPSignatureHelp;

typedef struct {
  char *uri;
  LSPRange range;
} LSPLocation;

typedef struct {
  char *content;
  bool is_markup;
  char *markup_kind; // "markdown" or "plaintext"
  bool has_range;
  LSPRange range;
} LSPHover;

// --- Function Declarations ---

MetalLSPServer *metal_lsp_server_create(void);
void metal_lsp_server_destroy(MetalLSPServer *server);
int metal_lsp_server_start(MetalLSPServer *server, int port);
void metal_lsp_server_stop(MetalLSPServer *server);

void handle_lsp_message(MetalLSPServer *server, const char *message,
                        size_t length);

void add_document(MetalLSPServer *server, LSPTextDocument *document);
void remove_document(MetalLSPServer *server, const char *uri);

LSPCompletionItem *get_completions(MetalLSPServer *server, const char *uri,
                                   LSPPosition position, size_t *count);
LSPDiagnostic *get_diagnostics(MetalLSPServer *server, const char *uri,
                               size_t *count);

// Semantic tokens support
uint32_t *get_semantic_tokens(MetalLSPServer *server, const char *uri,
                              size_t *count);

void analyze_metal_syntax(const char *text, LSPDiagnostic **diagnostics,
                          size_t *count);
void update_document(MetalLSPServer *server, const char *uri, const char *text,
                     int version);
LSPTextEdit *get_document_formatting(MetalLSPServer *server, const char *uri,
                                     size_t *edit_count);

LSPSignatureHelp *get_signature_help(MetalLSPServer *server, const char *uri,
                                     LSPPosition position);
void free_signature_help(LSPSignatureHelp *signature_help);

LSPLocation *get_definition_locations(MetalLSPServer *server, const char *uri,
                                      LSPPosition position, size_t *count);

LSPHover *get_hover_info(MetalLSPServer *server, const char *uri,
                         LSPPosition position);
void free_hover_info(LSPHover *hover);

#endif /* metal_lsp_server_h */
