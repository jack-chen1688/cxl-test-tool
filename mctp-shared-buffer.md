# MCTP shared buffer: how two QEMU instances exchange CXL MCTP commands

This note documents how QEMU’s CXL Type 3 device and the `i2c_mctp_cxl` endpoint cooperate to forward MCTP commands between two separate QEMU processes using a small POSIX shared-memory buffer plus a QMP notification.

## TL;DR

- Data moves between VMs via a POSIX shared-memory object named `/mctp-message-buf` (constant `MCTP_MESSAGE_BUF_NAME`).
- The sender VM writes the request into this shared buffer and sets `status = 1`, then sends a QMP command that carries only the `cci-name`.
- The receiver VM’s QMP handler looks up its local `CXLCCI *` by that `cci-name`, reads the request from the same shared buffer, processes it, writes the response back, and clears `status = 0`.
- The large `-object memory-backend-file,mem-path=...` memory regions for the devices do not need to match across VMs; they are unrelated to this MCTP exchange path.

## Key components and files

- Interface/structures: `include/hw/cxl/cxl_mctp_message.h`
  - `#define MCTP_CXL_MAILBOX_BYTES 512`
  - `#define MCTP_MESSAGE_BUF_NAME "mctp-message-buf"`
  - `typedef struct CXLMCTPSharedBuf { int status; CXLMCTPCommandBuf command_buf; }`
  - `extern struct CXLCCINamePtrMaps *cci_map_buf;`

- Type 3 device: `hw/mem/cxl_type3.c`
  - Creates/opens/maps the POSIX shm via:
    - `ct3_mctp_buf_open()` → `shm_open("/mctp-message-buf", ...)`
    - `ct3_mctp_buf_create()` → `shm_open(..., O_CREAT)` + `ftruncate`
    - `ct3_mctp_buf_map()` → `mmap(..., MAP_SHARED, fd, 0)`
    - `ct3_setup_mctp_command_share_buffer(CXLType3Dev *ct3d, bool create)`
  - Registers CCI name→pointer mapping:
    - `init_cci_name_ptr_mapping()` and `add_cci_name_ptr_mapping()` populate `cci_map_buf` with pairs `{ cci_name, cci_pointer }`.
  - QMP handler that executes on the receiver:
    - `qmp_cxl_process_mctp_message(const char *cci_name, Error **errp)`

- I2C MCTP endpoint: `hw/cxl/i2c_mctp_cxl.c`
  - Message forwarding path (sender side) in `i2c_mctp_cxl_handle_message()`:
    - Copies incoming MCTP request into `ct3d->mctp_shared_buffer->command_buf`.
    - Sets `ct3d->mctp_shared_buffer->status = 1`.
    - Calls `qmp_cxl_mctp_process_cci_message(s->qmp_fd, cci_name)`.

- QMP client helper: `hw/cxl/cxl-mctp-qmp.c`
  - Sends the notification-only QMP command:
    - `{ "execute": "cxl-process-mctp-message", "arguments": { "cci-name": "..." } }`

- QAPI command schema: `qapi/cxl.json`
  - Declares `cxl-process-mctp-message` (arg: `cci-name`).
  - Marshaller in `build/qapi/qapi-commands-cxl.c` calls `qmp_cxl_process_mctp_message()`.

## End-to-end flow

1) Sender VM: receive guest MCTP over I2C
- Function: `i2c_mctp_cxl_handle_message()`
- Copies request into shared buffer:
  - `CXLMCTPCommandBuf *m = &ct3d->mctp_shared_buffer->command_buf;`
  - `m->command_set = msg->command_set; m->command = msg->command;`
  - `m->len_in = len_in; memcpy(m->payload, msg->payload, len_in);`
  - `ct3d->mctp_shared_buffer->status = 1;`
- Sends QMP to receiver: `qmp_cxl_mctp_process_cci_message(fd, cci_name)`.

2) Receiver VM: QMP handler runs
- Function: `qmp_cxl_process_mctp_message(const char *cci_name, Error **errp)`
- Validates `cci_map_buf != NULL` and finds its local `CXLCCI *` by matching `cci_name` in `cci_map_buf->maps[i].cci_name`.
- Validates `ct3d->mctp_shared_buffer->status == 1`.
- Reads request from shared buffer, calls the CCI dispatcher:
  - `buf = &ct3d->mctp_shared_buffer->command_buf;`
  - `buf->ret_val = cxl_process_cci_message(cci, buf->command_set, buf->command, buf->len_in, buf->payload, &buf->len_out, buf->payload_out, &buf->bg_started);`
- Clears `ct3d->mctp_shared_buffer->status = 0`.

3) Sender VM: completes
- After QMP returns, the sender can read `buf->len_out`, `buf->payload_out`, and `buf->ret_val` from its mapped shared buffer and construct the MCTP response to the guest.

## Process boundary and why different mem-paths work

- The large device memory backends (`-object memory-backend-file,mem-path=...`) are unrelated to the MCTP forwarding path.
- The MCTP path uses a small, dedicated POSIX shared memory object (`/mctp-message-buf`). Both QEMU processes map the same object, so they see the same bytes for requests/responses.
- The QMP command only carries `cci-name` as a trigger, not the payload. Payload moves via shared memory.

## Bringing it up: required device properties

On the receiver (the VM that processes the command):
- The Type 3 device must allow the FM attach and initialize the buffer:
  - `allow-fm-attach=on`
  - `mctp-buf-init=on`
- These flags cause `ct3_setup_mctp_command_share_buffer(ct3d, true)` to create and map `/mctp-message-buf`, and register the `cci_name → cci_pointer` mapping via `init_cci_name_ptr_mapping()` / `add_cci_name_ptr_mapping()`.

On the sender (the VM that forwards the command):
- The I2C endpoint must be configured to forward MCTP over QMP:
  - `mctp-msg-forward=on`
  - `qmp=HOST:PORT` (pointing to the receiver’s QMP)
- The `i2c_mctp_cxl` device writes into the shared buffer and then triggers the receiver via QMP.

Notes:
- Startup order: creating side (receiver) should run first to ensure `/mctp-message-buf` exists; the non-creating side opens it. The current code tolerates creating on either side (`O_CREAT` used), but bringing up the receiver first is clearer.
- The `cci-name` value is derived from device state, e.g., `"<serial>:oob_mctp_cci"`, and both processes populate their own `cci_map_buf` with matching key strings for their local `CXLCCI *`.

## Verifying at runtime (host)

- Check that the shm object exists:

```bash
ls -l /dev/shm/mctp-message-buf
```

- Peek at contents (will change while running):

```bash
sudo hexdump -C /dev/shm/mctp-message-buf | head
```

- Enable QMP logging or console prints to see `cxl-process-mctp-message` arrivals and returns.

## Tracepoints you may find useful

- MCTP I2C path: `hw/i2c/mctp.c` defines trace events for send/receive and framing.
- You can enable tracing via `-trace enable=...` or the QEMU monitor; see project `trace-events` files.

## Caveats and limitations

- The shared memory name is global and fixed (`/mctp-message-buf`); multiple independent pairs would require name parameterization to avoid collisions.
- Synchronization is coarse: a single `status` flag with QMP sequencing. If you extend to concurrency, you’ll need stronger synchronization/queueing.
- Payload limits are fixed by `MCTP_CXL_MAILBOX_BYTES` (512 bytes). Larger messages must fit the protocol’s fragmentation/reassembly path above this layer.

## Pointers to source

- `include/hw/cxl/cxl_mctp_message.h` — buffer structs, constants, externs
- `hw/mem/cxl_type3.c` — shm open/create/map; buffer setup; QMP handler; name→pointer mapping
- `hw/cxl/i2c_mctp_cxl.c` — sender’s message handling/forwarding logic
- `hw/cxl/cxl-mctp-qmp.c` — QMP notification client utility
- `qapi/cxl.json` and `build/qapi/qapi-commands-cxl.c` — QMP schema and marshaller for `cxl-process-mctp-message`

## Appendix: success criteria

A successful round-trip has these observable signs:
- `/dev/shm/mctp-message-buf` exists and is mapped by both QEMU processes.
- Sender writes a request (status transitions from 0 → 1), QMP `cxl-process-mctp-message` is seen on receiver.
- Receiver reads request, calls `cxl_process_cci_message(...)`, writes response, and sets status 1 → 0.
- Sender observes `len_out > 0` and forwards the response to the guest over MCTP.
