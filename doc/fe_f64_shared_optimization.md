# FE f64 shared-resource optimization

## Design goal

Falcon uses double-precision `fpr` arithmetic on the FFT/signing path.  A fully
parallel FE array is fast, but each lane contains a complex double datapath, so
the area grows quickly with lane count.

The PQPU architecture motivates two practical implementation choices used here:
task-level configuration over arithmetic clusters, and in-place/vector
forwarding so intermediate vectors are not copied through an extra gather
stage.  The shared FE follows that direction by letting the output vector
registers act as the gather buffer and by allowing a task to update only the
active lanes.

This project now keeps three FE options:

- `reconfig_fe_f64_array`: throughput-oriented.  It instantiates one full
  reference `reconfig_fe_f64` lane per vector lane.
- `reconfig_fe_f64_pipe_array`: microarchitecture-oriented.  It instantiates
  one pipelined FE lane per vector lane.  Each lane is split into pre-add,
  shared 4-multiplier complex stage, and post-add stages.
- `reconfig_fe_f64_shared_array`: area-oriented.  It instantiates one
  `reconfig_fe_f64` lane and time-multiplexes it across the vector lanes.

## Why this matches the reconfigurable idea

The FE is treated as a configurable FFT/complex-arithmetic front end rather than
as a fixed one-algorithm unit.  CT butterfly, GS butterfly, scalar f64
add/sub/mul, complex add/sub/mul/sqr, and complex MAC all use the same lane
datapath.  The pipe lane makes the FE different from a general FPU: it does not
decode arbitrary floating-point instructions, but schedules Falcon/FFT-specific
complex modes over a fixed f64 add/mul backend.  The array wrappers move the
area/performance decision above the arithmetic lane:

- keep one lane for small devices or area-sensitive Falcon support;
- use pipelined lanes when timing and sustained issue rate matter;
- instantiate parallel lanes when throughput is the priority;
- preserve the same arithmetic mode semantics for both implementations.

## Pipelined lane

`reconfig_fe_f64_pipe` is the main FE microarchitecture path:

- stage 1: pre-add/pre-sub for CT/GS and simple complex add/sub modes;
- stage 2: four shared f64 multipliers for complex/twiddle multiplication;
- stage 3: post-add/post-sub for CT, complex multiply, square, and MAC modes.

The lane accepts one operation per cycle and returns the result after two
cycles.  This avoids the large duplicated multiplier network in the original
reference lane while keeping high sustained throughput.

## Interface behavior

`reconfig_fe_f64_shared_array` accepts one vector batch when `valid_in` is
asserted and the engine is idle.  It raises `busy` while processing lanes and
asserts `valid_out` when the full vector output has been written.  The result
is held until `ready_in` is asserted, so downstream logic may apply backpressure
without requiring a second output buffer.

`lane_mask` marks which lanes belong to the current task.  Inactive lanes are
not issued to the shared FE lane, so they do not consume cycles or toggle the
f64 datapath.  Their output slots are preserved, which enables partial in-place
updates and avoids clearing the whole output vector at task start.

The shared wrapper is a two-state `IDLE/RUN` scheduler.  It tags each issued
lane and delays the tag through a small `FE_LATENCY` pipeline, so output capture
can stay aligned if the internal f64 lane is later pipelined.  The output vector
registers are the gather buffer: each lane result is written directly to its
final output slice.  When the last tagged lane is captured, `valid_out` is
asserted and the vector remains stable until `ready_in` consumes it.

For `LANES = N`, throughput is one vector batch per multi-cycle lane sweep,
while the heavy f64 multiplier/add datapath is instantiated only once.

## FFT wrapper

`reconfig_fft_f64_shared_operator` wraps the shared FE array for Falcon-style
FFT butterflies:

- `inverse = 0`: CT butterfly mode;
- `inverse = 1`: GS butterfly mode.

This keeps the external FFT operator shape close to the fully parallel
`reconfig_fft_f64_operator`, with the addition of `busy` for scheduling.

## Area tradeoff

The current `reconfig_fe_f64` lane contains the f64 helper instances needed for
all supported modes.  With `LANES = 8`:

- full array: 8 complete f64 lanes;
- shared array: 1 complete f64 lane plus a small lane scheduler.

So the shared version reduces the dominant f64 datapath replication by about
8x for an 8-lane vector configuration, at the cost of multi-cycle vector
latency.
