#ifndef ONDINE_H
#define ONDINE_H

#include <stdbool.h>

/// Renders Mermaid source to SVG with Ondine. Free the outputs with ondine_free.
bool ondine_render(const char *source, double now, char **svg, char **error);
void ondine_free(char *string);

#endif
