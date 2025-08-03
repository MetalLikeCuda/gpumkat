//
// lsp_integration.m
// Integration implementation for gpumkat
//

#import "lsp_integration.h"
#import <Foundation/Foundation.h>

static MetalLSPServer *g_lsp_server = NULL;
LSPConfig g_lsp_config = {.port = 0, // Use stdio by default
                          .enable_diagnostics = true,
                          .enable_completions = true,
                          .enable_hover = true,
                          .enable_formatting = true,
                          .verbose_logging = false};

int start_metal_lsp_server(void) {
  if (g_lsp_server) {
    NSLog(@"LSP server is already running");
    return -1;
  }

  g_lsp_server = metal_lsp_server_create();
  if (!g_lsp_server) {
    NSLog(@"Failed to create Metal LSP server");
    return -1;
  }

  int result = metal_lsp_server_start(g_lsp_server, g_lsp_config.port);
  if (result != 0) {
    NSLog(@"Failed to start Metal LSP server");
    metal_lsp_server_destroy(g_lsp_server);
    g_lsp_server = NULL;
    return -1;
  }

  if (g_lsp_config.verbose_logging) {
    NSLog(@"Metal LSP server started successfully on port %d",
          g_lsp_config.port);
  }

  return 0;
}

void stop_metal_lsp_server(void) {
  if (g_lsp_server) {
    metal_lsp_server_stop(g_lsp_server);
    metal_lsp_server_destroy(g_lsp_server);
    g_lsp_server = NULL;

    if (g_lsp_config.verbose_logging) {
      NSLog(@"Metal LSP server stopped");
    }
  }
}

bool is_lsp_server_running(void) {
  return g_lsp_server != NULL && g_lsp_server->is_running;
}
