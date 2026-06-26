//
// lsp_integration.h
// Integration layer for Metal LSP Server with gpumkat
//

#ifndef LSP_INTEGRATION_H
#define LSP_INTEGRATION_H

#include "metal_lsp_server.h"

// Integration functions
int start_metal_lsp_server(void);
void stop_metal_lsp_server(void);
bool is_lsp_server_running(void);

// Configuration for LSP server
typedef struct {
  int port;
  bool enable_diagnostics;
  bool enable_completions;
  bool enable_hover;
  bool enable_formatting;
  bool verbose_logging;
} LSPConfig;

// Global LSP configuration
extern LSPConfig g_lsp_config;

#endif // LSP_INTEGRATION_H
