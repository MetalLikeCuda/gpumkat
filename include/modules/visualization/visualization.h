#ifndef VISUALIZATION_H
#define VISUALIZATION_H
#include <Metal/Metal.h>
void generate_buffer_heatmap(id<MTLBuffer> buffer, const char *buffer_name,
                             bool before_execution);
bool can_visualize_as_image(id<MTLBuffer> buffer, size_t width, size_t height);
void generate_buffer_image(id<MTLBuffer> buffer, const char *buffer_name,
                           bool before_execution, size_t width, size_t height);
void generate_buffer_surface_plot(id<MTLBuffer> buffer, const char *buffer_name,
                                  bool before_execution, size_t width,
                                  size_t height);
void generate_buffer_histogram(id<MTLBuffer> buffer, const char *buffer_name,
                               bool before_execution);
void generate_all_buffer_visualizations(id<MTLBuffer> buffer,
                                        const char *buffer_name,
                                        bool before_execution);

// Texture visualization
void generate_texture_image(id<MTLTexture> texture, const char *name,
                            bool before_execution);
void generate_texture_heatmap(id<MTLTexture> texture, const char *name,
                              bool before_execution);
void generate_texture_histogram(id<MTLTexture> texture, const char *name,
                                bool before_execution);
void generate_texture_surface_plot(id<MTLTexture> texture, const char *name,
                                   bool before_execution);
void generate_all_texture_visualizations(id<MTLTexture> texture,
                                         const char *name,
                                         bool before_execution);
#endif