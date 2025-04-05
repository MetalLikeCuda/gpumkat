#import <WebKit/WebKit.h>
#include <Metal/Metal.h>

void generate_buffer_heatmap(id<MTLBuffer> buffer, const char *buffer_name,
                             bool before_execution) {
  if (!buffer || !buffer_name) {
    NSLog(@"Error: Invalid buffer or buffer name");
    return;
  }

  float *data = (float *)[buffer contents];
  size_t buffer_length = buffer.length / sizeof(float);

  if (!data || buffer_length == 0) {
    NSLog(@"Error: Buffer data is null or empty");
    return;
  }

  NSMutableString *htmlContent = [NSMutableString string];
  [htmlContent appendString:@"<!DOCTYPE html>\n<html>\n<head>\n"];
  [htmlContent appendString:@"<script "
                            @"src=\"https://cdnjs.cloudflare.com/ajax/libs/"
                            @"Chart.js/3.7.1/chart.min.js\"></script>\n"];
  [htmlContent appendString:@"<style>body { font-family: Arial; max-width: "
                            @"800px; margin: auto; }</style>\n"];
  [htmlContent appendString:@"</head>\n<body>\n"];

  // Create a unique filename based on buffer name and execution stage
  char filename[256];
  snprintf(filename, sizeof(filename), "%s_%s_heatmap.html", buffer_name,
           before_execution ? "before" : "after");

  // Prepare data for heatmap
  NSMutableArray *dataArray = [NSMutableArray array];
  for (size_t i = 0; i < buffer_length; i++) {
    if (isnan(data[i]) || isinf(data[i])) {
      NSLog(@"Warning: Buffer contains NaN or Inf at index %zu", i);
      continue;
    }
    [dataArray addObject:@[ @(i), @(data[i]) ]]; // Storing index-value pairs
  }

  if ([dataArray count] == 0) {
    NSLog(@"Error: No valid data to plot in heatmap");
    return;
  }

  [htmlContent appendFormat:@"<h2>%s Buffer Heatmap (%s Execution)</h2>\n",
                            buffer_name, before_execution ? "Before" : "After"];
  [htmlContent appendString:@"<canvas id=\"heatmapChart\"></canvas>\n"];
  [htmlContent appendString:@"<script>\n"];
  [htmlContent
      appendString:
          @"var ctx = "
          @"document.getElementById('heatmapChart').getContext('2d');\n"];
  [htmlContent appendString:@"var chart = new Chart(ctx, {\n"];
  [htmlContent appendString:@"    type: 'scatter',\n"];
  [htmlContent appendString:@"    data: {\n"];
  [htmlContent appendString:@"        datasets: [{\n"];
  [htmlContent appendString:@"            label: 'Buffer Data',\n"];
  [htmlContent
      appendString:
          @"            backgroundColor: 'rgba(75, 192, 192, 0.6)',\n"];
  [htmlContent
      appendString:@"            borderColor: 'rgba(75, 192, 192, 1)',\n"];
  [htmlContent appendString:@"            pointRadius: 3,\n"];

  // Convert data array to JSON safely
  NSError *jsonError = nil;
  NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dataArray
                                                     options:0
                                                       error:&jsonError];

  if (jsonError) {
    NSLog(@"Error serializing JSON: %@", jsonError);
    return;
  }

  NSString *jsonString = [[NSString alloc] initWithData:jsonData
                                               encoding:NSUTF8StringEncoding];

  [htmlContent appendFormat:@"            data: %@\n", jsonString];
  [htmlContent appendString:@"        }]\n"];
  [htmlContent appendString:@"    },\n"];
  [htmlContent appendString:@"    options: {\n"];
  [htmlContent appendString:@"        plugins: {\n"];
  [htmlContent appendString:@"            title: { display: true, text: "
                            @"'Buffer Data Heatmap' },\n"];
  [htmlContent appendString:@"        },\n"];
  [htmlContent appendString:@"        scales: {\n"];
  [htmlContent
      appendString:@"            x: { type: 'linear', position: 'bottom' },\n"];
  [htmlContent appendString:@"            y: { type: 'linear' }\n"];
  [htmlContent appendString:@"        }\n"];
  [htmlContent appendString:@"    }\n"];
  [htmlContent appendString:@"});\n"];
  [htmlContent appendString:@"</script>\n"];
  [htmlContent appendString:@"</body>\n</html>"];

  // Write to file
  NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(
      NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
  NSString *filePath =
      [documentsPath stringByAppendingPathComponent:@(filename)];

  NSError *error;
  BOOL success = [htmlContent writeToFile:filePath
                               atomically:YES
                                 encoding:NSUTF8StringEncoding
                                    error:&error];

  if (!success) {
    NSLog(@"Error writing heatmap file: %@", error);
  } else {
    NSLog(@"Heatmap saved: %@", filePath);
  }
}


bool can_visualize_as_image(id<MTLBuffer> buffer, size_t width, size_t height) {
    if (!buffer) return false;
    
    size_t float_count = buffer.length / sizeof(float);
    
    // If width and height are specified and match buffer size
    if (width > 0 && height > 0 && width * height <= float_count) {
        return true;
    }
    
    // Try to determine if the buffer is a square or rectangular image
    if (float_count >= 4) {  // At least a 2x2 image
        size_t sqrt_size = (size_t)sqrt((double)float_count);
        // Check if it's a perfect square or close to it
        if (sqrt_size * sqrt_size == float_count || 
            sqrt_size * (sqrt_size + 1) == float_count) {
            return true;
        }
    }
    
    return false;
}

void generate_buffer_image(id<MTLBuffer> buffer, const char *buffer_name, 
                          bool before_execution, size_t width, size_t height) {
    if (!buffer || !buffer_name) {
        NSLog(@"Error: Invalid buffer or buffer name");
        return;
    }
    
    float *data = (float *)[buffer contents];
    size_t buffer_length = buffer.length / sizeof(float);
    
    if (!data || buffer_length == 0) {
        NSLog(@"Error: Buffer data is null or empty");
        return;
    }
    
    // Determine width and height if not specified
    if (width == 0 || height == 0) {
        size_t sqrt_size = (size_t)sqrt((double)buffer_length);
        if (sqrt_size * sqrt_size == buffer_length) {
            // Perfect square
            width = height = sqrt_size;
        } else {
            // Try to find a reasonable rectangular shape
            width = sqrt_size;
            height = (buffer_length + width - 1) / width; // Ceiling division
        }
    }
    
    // Ensure width and height don't exceed buffer size
    if (width * height > buffer_length) {
        NSLog(@"Warning: Specified dimensions exceed buffer size, adjusting");
        height = buffer_length / width;
    }
    
    NSMutableString *htmlContent = [NSMutableString string];
    [htmlContent appendString:@"<!DOCTYPE html>\n<html>\n<head>\n"];
    [htmlContent appendString:@"<script src=\"https://cdnjs.cloudflare.com/ajax/libs/Chart.js/3.7.1/chart.min.js\"></script>\n"];
    [htmlContent appendString:@"<style>body { font-family: Arial; max-width: 800px; margin: auto; }</style>\n"];
    [htmlContent appendString:@"</head>\n<body>\n"];
    
    // Create a unique filename based on buffer name and execution stage
    char filename[256];
    snprintf(filename, sizeof(filename), "%s_%s_image.html", buffer_name,
             before_execution ? "before" : "after");
    
    [htmlContent appendFormat:@"<h2>%s Buffer as Image (%s Execution)</h2>\n",
                            buffer_name, before_execution ? "Before" : "After"];
    [htmlContent appendString:@"<canvas id=\"imageCanvas\"></canvas>\n"];
    [htmlContent appendString:@"<script>\n"];
    
    // Create a canvas and draw the buffer data as an image
    [htmlContent appendFormat:@"var canvas = document.getElementById('imageCanvas');\n"];
    [htmlContent appendFormat:@"canvas.width = %zu;\n", width];
    [htmlContent appendFormat:@"canvas.height = %zu;\n", height];
    [htmlContent appendFormat:@"canvas.style.width = '%dpx';\n", (int)(width * 2)];
    [htmlContent appendFormat:@"canvas.style.height = '%dpx';\n", (int)(height * 2)];
    [htmlContent appendString:@"var ctx = canvas.getContext('2d');\n"];
    [htmlContent appendString:@"var imgData = ctx.createImageData(canvas.width, canvas.height);\n"];
    [htmlContent appendString:@"var data = imgData.data;\n"];
    
    // Create the pixel data
    [htmlContent appendString:@"var bufferData = [\n"];
    for (size_t i = 0; i < width * height && i < buffer_length; i++) {
        float value = data[i];
        // Handle NaN and Inf values
        if (isnan(value) || isinf(value)) {
            value = 0;
        }
        [htmlContent appendFormat:@"  %f%s\n", value, (i < width * height - 1) ? "," : ""];
    }
    [htmlContent appendString:@"];\n"];
    
    // Normalize and convert to pixel data
    [htmlContent appendString:@"// Find min and max for normalization\n"];
    [htmlContent appendString:@"var min = Number.MAX_VALUE;\n"];
    [htmlContent appendString:@"var max = Number.MIN_VALUE;\n"];
    [htmlContent appendString:@"for (var i = 0; i < bufferData.length; i++) {\n"];
    [htmlContent appendString:@"  if (bufferData[i] < min) min = bufferData[i];\n"];
    [htmlContent appendString:@"  if (bufferData[i] > max) max = bufferData[i];\n"];
    [htmlContent appendString:@"}\n"];
    
    // Handle case where min and max are the same
    [htmlContent appendString:@"if (min === max) { max = min + 1; }\n"];
    
    // Convert normalized values to RGBA
    [htmlContent appendString:@"for (var i = 0; i < bufferData.length; i++) {\n"];
    [htmlContent appendString:@"  var normalized = (bufferData[i] - min) / (max - min);\n"];
    [htmlContent appendString:@"  var pixel = Math.floor(normalized * 255);\n"];
    [htmlContent appendString:@"  data[i*4] = pixel;     // R\n"];
    [htmlContent appendString:@"  data[i*4+1] = pixel;   // G\n"];
    [htmlContent appendString:@"  data[i*4+2] = pixel;   // B\n"];
    [htmlContent appendString:@"  data[i*4+3] = 255;     // A\n"];
    [htmlContent appendString:@"}\n"];
    
    [htmlContent appendString:@"ctx.putImageData(imgData, 0, 0);\n"];
    
    // Add information about min/max values
    [htmlContent appendString:@"// Add color scale\n"];
    [htmlContent appendString:@"var scale = document.createElement('div');\n"];
    [htmlContent appendFormat:@"scale.innerHTML = '<div style=\"margin-top: 10px;\">Value range: ' + min.toFixed(4) + ' to ' + max.toFixed(4) + '</div>';\n"];
    [htmlContent appendString:@"document.body.appendChild(scale);\n"];
    
    // Create a gradient color scale
    [htmlContent appendString:@"var gradientCanvas = document.createElement('canvas');\n"];
    [htmlContent appendString:@"gradientCanvas.width = 200;\n"];
    [htmlContent appendString:@"gradientCanvas.height = 20;\n"];
    [htmlContent appendString:@"gradientCanvas.style.marginTop = '5px';\n"];
    [htmlContent appendString:@"document.body.appendChild(gradientCanvas);\n"];
    [htmlContent appendString:@"var gradCtx = gradientCanvas.getContext('2d');\n"];
    [htmlContent appendString:@"var gradient = gradCtx.createLinearGradient(0, 0, 200, 0);\n"];
    [htmlContent appendString:@"gradient.addColorStop(0, 'black');\n"];
    [htmlContent appendString:@"gradient.addColorStop(1, 'white');\n"];
    [htmlContent appendString:@"gradCtx.fillStyle = gradient;\n"];
    [htmlContent appendString:@"gradCtx.fillRect(0, 0, 200, 20);\n"];
    
    // Add labels to the gradient
    [htmlContent appendString:@"var labels = document.createElement('div');\n"];
    [htmlContent appendString:@"labels.style.display = 'flex';\n"];
    [htmlContent appendString:@"labels.style.justifyContent = 'space-between';\n"];
    [htmlContent appendString:@"labels.style.width = '200px';\n"];
    [htmlContent appendFormat:@"labels.innerHTML = '<span>' + min.toFixed(2) + '</span><span>' + max.toFixed(2) + '</span>';\n"];
    [htmlContent appendString:@"document.body.appendChild(labels);\n"];
    
    [htmlContent appendString:@"</script>\n"];
    [htmlContent appendString:@"</body>\n</html>"];
    
    // Write to file
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *filePath =
        [documentsPath stringByAppendingPathComponent:@(filename)];
    
    NSError *error;
    BOOL success = [htmlContent writeToFile:filePath
                                 atomically:YES
                                   encoding:NSUTF8StringEncoding
                                      error:&error];
    
    if (!success) {
        NSLog(@"Error writing image visualization file: %@", error);
    } else {
        NSLog(@"Image visualization saved: %@", filePath);
    }
}

void generate_buffer_surface_plot(id<MTLBuffer> buffer, const char *buffer_name, 
                                bool before_execution, size_t width, size_t height) {
    if (!buffer || !buffer_name) {
        NSLog(@"Error: Invalid buffer or buffer name");
        return;
    }
    
    float *data = (float *)[buffer contents];
    size_t buffer_length = buffer.length / sizeof(float);
    
    if (!data || buffer_length == 0) {
        NSLog(@"Error: Buffer data is null or empty");
        return;
    }
    
    // Determine width and height if not specified
    if (width == 0 || height == 0) {
        size_t sqrt_size = (size_t)sqrt((double)buffer_length);
        if (sqrt_size * sqrt_size == buffer_length) {
            // Perfect square
            width = height = sqrt_size;
        } else {
            // Try to find a reasonable rectangular shape
            width = sqrt_size;
            height = (buffer_length + width - 1) / width; // Ceiling division
        }
    }
    
    // Ensure width and height don't exceed buffer size
    if (width * height > buffer_length) {
        NSLog(@"Warning: Specified dimensions exceed buffer size, adjusting");
        height = buffer_length / width;
    }
    
    NSMutableString *htmlContent = [NSMutableString string];
    [htmlContent appendString:@"<!DOCTYPE html>\n<html>\n<head>\n"];
    [htmlContent appendString:@"<script src=\"https://cdnjs.cloudflare.com/ajax/libs/plotly.js/2.16.1/plotly.min.js\"></script>\n"];
    [htmlContent appendString:@"<style>body { font-family: Arial; max-width: 900px; margin: auto; }</style>\n"];
    [htmlContent appendString:@"</head>\n<body>\n"];
    
    // Create a unique filename based on buffer name and execution stage
    char filename[256];
    snprintf(filename, sizeof(filename), "%s_%s_surface3d.html", buffer_name,
             before_execution ? "before" : "after");
    
    [htmlContent appendFormat:@"<h2>%s Buffer as 3D Surface (%s Execution)</h2>\n",
                            buffer_name, before_execution ? "Before" : "After"];
    [htmlContent appendString:@"<div id=\"surfacePlot\" style=\"width:800px;height:600px;\"></div>\n"];
    [htmlContent appendString:@"<script>\n"];
    
    // Prepare data for 3D plot
    [htmlContent appendString:@"var z = [\n"];
    for (size_t row = 0; row < height; row++) {
        [htmlContent appendString:@"  ["];
        for (size_t col = 0; col < width; col++) {
            size_t idx = row * width + col;
            if (idx < buffer_length) {
                float value = data[idx];
                // Handle NaN and Inf values
                if (isnan(value) || isinf(value)) {
                    value = 0;
                }
                [htmlContent appendFormat:@"%f%s", value, (col < width - 1) ? ", " : ""];
            } else {
                [htmlContent appendFormat:@"0%s", (col < width - 1) ? ", " : ""];
            }
        }
        [htmlContent appendFormat:@"]%s\n", (row < height - 1) ? "," : ""];
    }
    [htmlContent appendString:@"];\n"];
    
    // Create x and y coordinate arrays
    [htmlContent appendString:@"var x = [];\n"];
    [htmlContent appendString:@"for (var i = 0; i < z[0].length; i++) {\n"];
    [htmlContent appendString:@"  x.push(i);\n"];
    [htmlContent appendString:@"}\n"];
    
    [htmlContent appendString:@"var y = [];\n"];
    [htmlContent appendString:@"for (var i = 0; i < z.length; i++) {\n"];
    [htmlContent appendString:@"  y.push(i);\n"];
    [htmlContent appendString:@"}\n"];
    
    // Create the plot
    [htmlContent appendString:@"var data = [\n"];
    [htmlContent appendString:@"  {\n"];
    [htmlContent appendString:@"    z: z,\n"];
    [htmlContent appendString:@"    x: x,\n"];
    [htmlContent appendString:@"    y: y,\n"];
    [htmlContent appendString:@"    type: 'surface',\n"];
    [htmlContent appendString:@"    colorscale: 'Viridis'\n"];
    [htmlContent appendString:@"  }\n"];
    [htmlContent appendString:@"];\n"];
    
    [htmlContent appendString:@"var layout = {\n"];
    [htmlContent appendFormat:@"  title: '%s Buffer Data Visualization',\n", buffer_name];
    [htmlContent appendString:@"  autosize: true,\n"];
    [htmlContent appendString:@"  scene: {\n"];
    [htmlContent appendString:@"    xaxis: { title: 'X' },\n"];
    [htmlContent appendString:@"    yaxis: { title: 'Y' },\n"];
    [htmlContent appendString:@"    zaxis: { title: 'Value' },\n"];
    [htmlContent appendString:@"    camera: {\n"];
    [htmlContent appendString:@"      eye: { x: 1.5, y: 1.5, z: 1 }\n"];
    [htmlContent appendString:@"    }\n"];
    [htmlContent appendString:@"  }\n"];
    [htmlContent appendString:@"};\n"];
    
    [htmlContent appendString:@"Plotly.newPlot('surfacePlot', data, layout);\n"];
    [htmlContent appendString:@"</script>\n"];
    [htmlContent appendString:@"</body>\n</html>"];
    
    // Write to file
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *filePath =
        [documentsPath stringByAppendingPathComponent:@(filename)];
    
    NSError *error;
    BOOL success = [htmlContent writeToFile:filePath
                                 atomically:YES
                                   encoding:NSUTF8StringEncoding
                                      error:&error];
    
    if (!success) {
        NSLog(@"Error writing 3D surface plot file: %@", error);
    } else {
        NSLog(@"3D surface plot saved: %@", filePath);
    }
}

void generate_buffer_histogram(id<MTLBuffer> buffer, const char *buffer_name, 
                              bool before_execution) {
    if (!buffer || !buffer_name) {
        NSLog(@"Error: Invalid buffer or buffer name");
        return;
    }
    
    float *data = (float *)[buffer contents];
    size_t buffer_length = buffer.length / sizeof(float);
    
    if (!data || buffer_length == 0) {
        NSLog(@"Error: Buffer data is null or empty");
        return;
    }
    
    NSMutableString *htmlContent = [NSMutableString string];
    [htmlContent appendString:@"<!DOCTYPE html>\n<html>\n<head>\n"];
    [htmlContent appendString:@"<script src=\"https://cdnjs.cloudflare.com/ajax/libs/Chart.js/3.7.1/chart.min.js\"></script>\n"];
    [htmlContent appendString:@"<style>body { font-family: Arial; max-width: 800px; margin: auto; }</style>\n"];
    [htmlContent appendString:@"</head>\n<body>\n"];
    
    // Create a unique filename based on buffer name and execution stage
    char filename[256];
    snprintf(filename, sizeof(filename), "%s_%s_histogram.html", buffer_name,
             before_execution ? "before" : "after");
    
    [htmlContent appendFormat:@"<h2>%s Buffer Value Distribution (%s Execution)</h2>\n",
                            buffer_name, before_execution ? "Before" : "After"];
    [htmlContent appendString:@"<canvas id=\"histogramChart\"></canvas>\n"];
    [htmlContent appendString:@"<script>\n"];
    
    // Collect values for histogram
    [htmlContent appendString:@"var rawValues = [\n"];
    for (size_t i = 0; i < buffer_length; i++) {
        float value = data[i];
        // Skip NaN and Inf values
        if (!isnan(value) && !isinf(value)) {
            [htmlContent appendFormat:@"  %f%s\n", value, (i < buffer_length - 1) ? "," : ""];
        } else {
            [htmlContent appendFormat:@"  0%s\n", (i < buffer_length - 1) ? "," : ""];
        }
    }
    [htmlContent appendString:@"];\n"];
    
    // Create histogram bins
    [htmlContent appendString:@"function generateHistogramData(values, numBins) {\n"];
    [htmlContent appendString:@"  // Find min and max values\n"];
    [htmlContent appendString:@"  var min = Math.min(...values);\n"];
    [htmlContent appendString:@"  var max = Math.max(...values);\n"];
    [htmlContent appendString:@"  \n"];
    [htmlContent appendString:@"  // Handle edge case where all values are the same\n"];
    [htmlContent appendString:@"  if (min === max) {\n"];
    [htmlContent appendString:@"    min = min - 0.5;\n"];
    [htmlContent appendString:@"    max = max + 0.5;\n"];
    [htmlContent appendString:@"  }\n"];
    [htmlContent appendString:@"  \n"];
    [htmlContent appendString:@"  var binWidth = (max - min) / numBins;\n"];
    [htmlContent appendString:@"  var bins = Array(numBins).fill(0);\n"];
    [htmlContent appendString:@"  var labels = [];\n"];
    [htmlContent appendString:@"  \n"];
    [htmlContent appendString:@"  // Create bin labels\n"];
    [htmlContent appendString:@"  for (var i = 0; i < numBins; i++) {\n"];
    [htmlContent appendString:@"    var binStart = min + (i * binWidth);\n"];
    [htmlContent appendString:@"    var binEnd = binStart + binWidth;\n"];
    [htmlContent appendString:@"    labels.push(binStart.toFixed(2) + ' to ' + binEnd.toFixed(2));\n"];
    [htmlContent appendString:@"  }\n"];
    [htmlContent appendString:@"  \n"];
    [htmlContent appendString:@"  // Count values in each bin\n"];
    [htmlContent appendString:@"  for (var i = 0; i < values.length; i++) {\n"];
    [htmlContent appendString:@"    var binIndex = Math.min(Math.floor((values[i] - min) / binWidth), numBins - 1);\n"];
    [htmlContent appendString:@"    bins[binIndex]++;\n"];
    [htmlContent appendString:@"  }\n"];
    [htmlContent appendString:@"  \n"];
    [htmlContent appendString:@"  return { bins: bins, labels: labels, min: min, max: max };\n"];
    [htmlContent appendString:@"}\n"];
    
    // Generate histogram with 20 bins
    [htmlContent appendString:@"var histData = generateHistogramData(rawValues, 20);\n"];
    
    // Create the chart
    [htmlContent appendString:@"var ctx = document.getElementById('histogramChart').getContext('2d');\n"];
    [htmlContent appendString:@"var myChart = new Chart(ctx, {\n"];
    [htmlContent appendString:@"  type: 'bar',\n"];
    [htmlContent appendString:@"  data: {\n"];
    [htmlContent appendString:@"    labels: histData.labels,\n"];
    [htmlContent appendString:@"    datasets: [{\n"];
    [htmlContent appendString:@"      label: 'Frequency',\n"];
    [htmlContent appendString:@"      data: histData.bins,\n"];
    [htmlContent appendString:@"      backgroundColor: 'rgba(54, 162, 235, 0.5)',\n"];
    [htmlContent appendString:@"      borderColor: 'rgba(54, 162, 235, 1)',\n"];
    [htmlContent appendString:@"      borderWidth: 1\n"];
    [htmlContent appendString:@"    }]\n"];
    [htmlContent appendString:@"  },\n"];
    [htmlContent appendString:@"  options: {\n"];
    [htmlContent appendString:@"    responsive: true,\n"];
    [htmlContent appendString:@"    plugins: {\n"];
    [htmlContent appendFormat:@"      title: { display: true, text: '%s Buffer Value Distribution' },\n", buffer_name];
    [htmlContent appendString:@"      tooltip: { mode: 'index', intersect: false }\n"];
    [htmlContent appendString:@"    },\n"];
    [htmlContent appendString:@"    scales: {\n"];
    [htmlContent appendString:@"      x: { title: { display: true, text: 'Value Range' } },\n"];
    [htmlContent appendString:@"      y: { title: { display: true, text: 'Frequency' } }\n"];
    [htmlContent appendString:@"    }\n"];
    [htmlContent appendString:@"  }\n"];
    [htmlContent appendString:@"});\n"];
    
    // Add buffer statistics
    [htmlContent appendString:@"// Calculate and display statistics\n"];
    [htmlContent appendString:@"function calculateStats(values) {\n"];
    [htmlContent appendString:@"  var sum = values.reduce((a, b) => a + b, 0);\n"];
    [htmlContent appendString:@"  var mean = sum / values.length;\n"];
    [htmlContent appendString:@"  \n"];
    [htmlContent appendString:@"  var squaredDiffs = values.map(x => Math.pow(x - mean, 2));\n"];
    [htmlContent appendString:@"  var variance = squaredDiffs.reduce((a, b) => a + b, 0) / values.length;\n"];
    [htmlContent appendString:@"  var stdDev = Math.sqrt(variance);\n"];
    [htmlContent appendString:@"  \n"];
    [htmlContent appendString:@"  var sortedValues = [...values].sort((a, b) => a - b);\n"];
    [htmlContent appendString:@"  var median = 0;\n"];
    [htmlContent appendString:@"  if (sortedValues.length % 2 === 0) {\n"];
    [htmlContent appendString:@"    median = (sortedValues[sortedValues.length/2 - 1] + sortedValues[sortedValues.length/2]) / 2;\n"];
    [htmlContent appendString:@"  } else {\n"];
    [htmlContent appendString:@"    median = sortedValues[Math.floor(sortedValues.length/2)];\n"];
    [htmlContent appendString:@"  }\n"];
    [htmlContent appendString:@"  \n"];
    [htmlContent appendString:@"  return {\n"];
    [htmlContent appendString:@"    min: Math.min(...values),\n"];
    [htmlContent appendString:@"    max: Math.max(...values),\n"];
    [htmlContent appendString:@"    mean: mean,\n"];
    [htmlContent appendString:@"    median: median,\n"];
    [htmlContent appendString:@"    stdDev: stdDev,\n"];
    [htmlContent appendString:@"    count: values.length\n"];
    [htmlContent appendString:@"  };\n"];
    [htmlContent appendString:@"}\n"];
    
    [htmlContent appendString:@"var stats = calculateStats(rawValues);\n"];
    [htmlContent appendString:@"var statsDiv = document.createElement('div');\n"];
    [htmlContent appendString:@"statsDiv.innerHTML = '<h3>Buffer Statistics</h3>' +\n"];
    [htmlContent appendString:@"  '<table style=\"width:100%; border-collapse: collapse;\">' +\n"];
    [htmlContent appendString:@"  '<tr><th style=\"text-align:left; padding:8px; border:1px solid #ddd;\">Statistic</th><th style=\"text-align:right; padding:8px; border:1px solid #ddd;\">Value</th></tr>' +\n"];
    [htmlContent appendString:@"  '<tr><td style=\"padding:8px; border:1px solid #ddd;\">Count</td><td style=\"text-align:right; padding:8px; border:1px solid #ddd;\">' + stats.count + '</td></tr>' +\n"];
    [htmlContent appendString:@"  '<tr><td style=\"padding:8px; border:1px solid #ddd;\">Minimum</td><td style=\"text-align:right; padding:8px; border:1px solid #ddd;\">' + stats.min.toFixed(4) + '</td></tr>' +\n"];
    [htmlContent appendString:@"  '<tr><td style=\"padding:8px; border:1px solid #ddd;\">Maximum</td><td style=\"text-align:right; padding:8px; border:1px solid #ddd;\">' + stats.max.toFixed(4) + '</td></tr>' +\n"];
    [htmlContent appendString:@"  '<tr><td style=\"padding:8px; border:1px solid #ddd;\">Mean</td><td style=\"text-align:right; padding:8px; border:1px solid #ddd;\">' + stats.mean.toFixed(4) + '</td></tr>' +\n"];
    [htmlContent appendString:@"  '<tr><td style=\"padding:8px; border:1px solid #ddd;\">Median</td><td style=\"text-align:right; padding:8px; border:1px solid #ddd;\">' + stats.median.toFixed(4) + '</td></tr>' +\n"];
    [htmlContent appendString:@"  '<tr><td style=\"padding:8px; border:1px solid #ddd;\">Standard Deviation</td><td style=\"text-align:right; padding:8px; border:1px solid #ddd;\">' + stats.stdDev.toFixed(4) + '</td></tr>' +\n"];
    [htmlContent appendString:@"  '</table>';\n"];
    [htmlContent appendString:@"document.body.appendChild(statsDiv);\n"];
    
    [htmlContent appendString:@"</script>\n"];
    [htmlContent appendString:@"</body>\n</html>"];
    
    // Write to file
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *filePath =
        [documentsPath stringByAppendingPathComponent:@(filename)];
    
    NSError *error;
    BOOL success = [htmlContent writeToFile:filePath
                                 atomically:YES
                                   encoding:NSUTF8StringEncoding
                                      error:&error];
    
    if (!success) {
        NSLog(@"Error writing histogram file: %@", error);
    } else {
        NSLog(@"Histogram saved: %@", filePath);
    }
}


void generate_all_buffer_visualizations(id<MTLBuffer> buffer, const char *buffer_name,
                                      bool before_execution) {
    if (!buffer || !buffer_name) {
        NSLog(@"Error: Invalid buffer or buffer name");
        return;
    }

    size_t buffer_length = buffer.length / sizeof(float);

    // Generate the standard heatmap (already implemented)
    generate_buffer_heatmap(buffer, buffer_name, before_execution);

    // Generate histogram visualization
    generate_buffer_histogram(buffer, buffer_name, before_execution);

    // Try to determine if this buffer can be visualized as an image
    size_t width = 0, height = 0;

    // Try to find a reasonable square or rectangular shape
    size_t sqrt_size = (size_t)sqrt((double)buffer_length);
    if (sqrt_size * sqrt_size == buffer_length) {
        // Perfect square
        width = height = sqrt_size;
    } else if (sqrt_size * (sqrt_size + 1) <= buffer_length) {
        // Rectangular
        width = sqrt_size;
        height = sqrt_size + 1;
    } else {
        // Default to a reasonable width and height
        width = sqrt_size;
        height = (buffer_length + width - 1) / width; // Ceiling division
    }

    // Generate image visualization if possible
    if (can_visualize_as_image(buffer, width, height)) {
        generate_buffer_image(buffer, buffer_name, before_execution, width, height);
    }

    // Generate 3D surface plot visualization
    generate_buffer_surface_plot(buffer, buffer_name, before_execution, width, height);
}
