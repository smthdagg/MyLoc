#ifndef MYLOC_ENGINE_H
#define MYLOC_ENGINE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MyLocEngineHandle MyLocEngineHandle;

MyLocEngineHandle *myloc_engine_create(void);
void myloc_engine_destroy(MyLocEngineHandle *handle);

int32_t myloc_engine_probe_tunnel(const char *host, uint16_t port, uint32_t timeout_ms);

int32_t myloc_engine_connect(
    MyLocEngineHandle *handle,
    const char *host,
    uint16_t port,
    const uint8_t *pairing_bytes,
    size_t pairing_len,
    uint32_t timeout_ms
);

int32_t myloc_engine_set_location(
    MyLocEngineHandle *handle,
    double latitude,
    double longitude
);

int32_t myloc_engine_clear_location(MyLocEngineHandle *handle);
int32_t myloc_engine_disconnect(MyLocEngineHandle *handle);
int32_t myloc_engine_last_error_code(MyLocEngineHandle *handle);
size_t myloc_engine_last_error_message(MyLocEngineHandle *handle, uint8_t *out_buf, size_t out_cap);

int32_t myloc_engine_pair_device(
    MyLocEngineHandle *handle,
    const char *host,
    uint16_t port,
    uint32_t timeout_ms,
    uint8_t *out_buf,
    size_t out_cap,
    size_t *out_len
);

int32_t myloc_engine_start_pairing(
    MyLocEngineHandle *handle,
    const char *host,
    uint16_t port,
    uint32_t timeout_ms
);

int32_t myloc_engine_submit_pairing_pin(
    MyLocEngineHandle *handle,
    const char *pin,
    uint8_t *out_buf,
    size_t out_cap,
    size_t *out_len
);

#ifdef __cplusplus
}
#endif

#endif /* MYLOC_ENGINE_H */
