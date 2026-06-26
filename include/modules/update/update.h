#ifndef UPDATE_H
#define UPDATE_H
#include <Metal/Metal.h>
size_t write_callback(void *contents, size_t size, size_t nmemb, void *userp);
char *fetch_latest_version(void);
int compare_versions(const char *v1, const char *v2);
#endif