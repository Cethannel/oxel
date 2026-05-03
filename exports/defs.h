#include <stdint.h>

typedef void* Engine;
typedef uint32_t BufferIdx;

BufferIdx create_generic_buffer(Engine engine, int size_of, int align_of);
