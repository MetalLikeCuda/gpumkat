#import <Foundation/Foundation.h>
#include <curl/curl.h>
#include <json-c/json.h>

size_t write_callback(void *contents, size_t size, size_t nmemb, void *userp) {
  size_t total_size = size * nmemb;
  char **response_ptr = (char **)userp;

  char *temp =
      realloc(*response_ptr,
              total_size + (*response_ptr ? strlen(*response_ptr) : 0) + 1);
  if (temp == NULL) {
    fprintf(stderr, "Failed to allocate memory.\n");
    return 0; // Abort the transfer
  }
  *response_ptr = temp;

  if (*response_ptr) {
    memcpy(*response_ptr + (*response_ptr ? strlen(*response_ptr) : 0),
           contents, total_size);
    (*response_ptr)[total_size + (*response_ptr ? strlen(*response_ptr) : 0)] =
        '\0'; // Null-terminate
  }

  return total_size;
}

char *fetch_latest_version(void) {
  CURL *curl;
  CURLcode res;
  char *latest_version = NULL;

  curl = curl_easy_init();
  if (curl) {
    struct curl_slist *headers = NULL;
    headers = curl_slist_append(headers, "User-Agent: gpumkat-update-checker");

    curl_easy_setopt(
        curl, CURLOPT_URL,
        "https://api.github.com/repos/MetalLikeCuda/gpumkat/releases/latest");
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);

    char *response = NULL;

    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_callback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);

    res = curl_easy_perform(curl);

    if (res == CURLE_OK) {
      if (response) {
        struct json_object *parsed_json = json_tokener_parse(response);
        if (parsed_json == NULL) {
          fprintf(stderr, "Failed to parse JSON.\n");
        } else {
          struct json_object *tag_name;
          if (json_object_object_get_ex(parsed_json, "tag_name", &tag_name)) {
            const char *version = json_object_get_string(tag_name);
            latest_version = strdup(version);
          } else {
            fprintf(stderr, "JSON does not contain 'tag_name' field.\n");
          }

          json_object_put(parsed_json);
        }
      } else {
        fprintf(stderr, "No response data received.\n");
      }
    } else {
      fprintf(stderr, "CURL request failed: %s\n", curl_easy_strerror(res));
    }

    curl_easy_cleanup(curl);
    curl_slist_free_all(headers);
    free(response);
  } else {
    fprintf(stderr, "Failed to initialize CURL.\n");
  }

  return latest_version;
}

int compare_versions(const char *v1, const char *v2) {
  return strcmp(v1, v2) == 0 ? 0 : -1;
}
