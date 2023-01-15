Very simple test program that we can try to
load into M0 or LP at runtime.

- Write to some address so we can know whether it has
  been run. Then halt to avoid undefined behaviour.
- Compiled for RV32E so it should work for M0 and LP.
- "pic" so it should work in any position (but the
  target address to write to is hardcoded).
