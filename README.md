<!--no-pdf-->
# CMSC 131 Lab 2 Starter

[![lab2-checks](https://github.com/Pascasio-s-Tweakers/cmsc-131-lab2-starter/actions/workflows/test.yml/badge.svg)](https://github.com/WhiteLicorice/cmsc-131-lab2-starter/actions/workflows/test.yml)

A C-callable library of sort, search, and utility routines in assembly. The manual is the assignment. This file is the repository's own notes.

## Layout

```text
Makefile       platform preamble and build rules
bench.c        provided: file I/O, timing, the C-side comparison, the hostile caller
cdecl.h        provided: the calling-convention macros
LICENSE        provided
sort.asm       yours
search.asm     yours
util.asm       yours
run_tests.sh   provided: the correctness gate
tests/         provided: the test corpus
```

## What to Run

On Windows, run these commands in Git Bash, the shell from Block 1. In that
shell, `make` is your alias for `mingw32-make`. On Linux, use your terminal.

```bash
make
make check
```

`make` builds `bench`. `make check` builds, then runs `./run_tests.sh`,
which reports each check and exits nonzero when any of them fail. Each run
is captured first. Its exit status is read before its text is examined,
so a program that prints the right line and then crashes still fails.

## Reading a First Run

The assembly files ship as stubs that assemble and link as-is, so the build
works before you write any code. Right now they do nothing useful, and 19
of the 36 checks fail. The seventeen that pass prove little. Four are files
that arrive empty, single-element, or already sorted. `gcd(0, 0)` expects 0.
The hostile caller cannot be upset by a stub that touches no register. The
rest are argument and file refusals that the harness performs before any
assembly runs. That red run is the correct starting state for a starter. The
badge stays red until you implement the routines.

The provided files are fixtures. The grader compares your fork against the
starter. An edit to `bench.c`, `Makefile`, `run_tests.sh`, or a `tests/`
file appears as a diff in the open.

## Documentation

The three sections at the end of this file are yours. Complete Design Notes
and Subsystem Ownership before the Week 1 progress report. Complete Quirks
and Issues before the Week 3 progress report. Each section says what it
needs. Leave the rest of this file as it is.

---

## Design Notes

This describes the completed implementation. All 36 checks pass, and the
frame layouts below match the code.

### Problem analysis

The library provides four C-callable routines in three separately assembled
modules, linked with `bench.c` into one executable.

| Module | Routine | Behavior |
|---|---|---|
| `sort.asm` | `qsort_asm(arr, n)` | Sort signed 32-bit integers in place, ascending; no return value |
| `search.asm` | `bsearch_asm(arr, n, key)` | Return a matching index in a sorted array, or `-1` |
| `util.asm` | `gcd_asm(a, b)` | Return the GCD of nonnegative operands and record maximum recursion depth |
| `util.asm` | `sum_range_asm(lo, hi)` | Return the inclusive sum, or `0` when `lo > hi` |

The range sum is defined when its mathematical result fits a signed 32-bit
integer. Sort and search must handle empty arrays, single elements, duplicates,
and negative values. GCD must handle either or both operands being zero.

C-facing routines use cdecl: arguments are pushed right to left, callers remove
arguments after calls, and integer results return in `eax`. Any use of `ebx`,
`esi`, `edi`, and `ebp` must preserve the caller's values. The stack pointer must
also be restored before returning. Assembly uses integer arithmetic and makes
no C standard-library calls.

### Solution architecture

**Sorting.** The public `qsort_asm(arr, n)` wrapper returns immediately for
`n <= 1`; otherwise, it calls `qsort_inner(arr, 0, n - 1)`. The helper uses
last-element Lomuto partitioning with signed comparisons. Partition returns
the pivot's final index `p`; the recursive calls receive `[lo, p - 1]` and
`[p + 1, hi]`. Array elements use four-byte scaled indexing.

Although the manual permits a custom internal convention, every internal
helper (`qsort_inner`, `partition`, `bsearch_rec`, `gcd_inner`,
`sum_range_inner`) also uses cdecl to keep argument passing and register
preservation consistent. The recursive quicksort helper frame is:

```text
Higher addresses
[ebp+16]  hi
[ebp+12]  lo
[ebp+8]   array pointer
[ebp+4]   return address
[ebp]     saved caller ebp
[ebp-4]   saved ebx
[ebp-8]   saved esi
[ebp-12]  saved edi
[ebp-16]  local partition index p  <- esp after setup
Lower addresses
```

The helper establishes `ebp`, pushes `ebx`, `esi`, and `edi`, then
allocates four bytes for `p`. Each recursive call has its own frame. The
caller removes the three arguments with `add esp, 12`; the epilogue releases
the local and restores registers in reverse order. Keeping `p` in a local
preserves it across the first recursive call, whose return value overwrites
`eax`. Explicit register saves avoid accidentally restoring an old `eax` over
a return value with `popa`.

`partition` has the same argument layout and saves `ebx`, `esi`, and `edi`,
with no locals. It keeps the array base in `ebx`, `i` in `esi`, `j` in `edi`,
`hi` in `ecx`, and the pivot value in `edx`, and returns `i + 1` in `eax`.

**Searching.** The public wrapper calls `bsearch_rec(arr, 0, n - 1, key)`.
The helper checks `lo > hi` (signed) before reading the array and returns `-1`
for an empty interval, so `n = 0` (`hi = -1`) never touches memory. It
calculates `mid = lo + (hi - lo) / 2` with `shr`, which is safe because
`hi - lo` is non-negative after the base case; this avoids the potentially
overflowing sum `lo + hi`. The file header explains this choice. Signed
comparisons select the remaining interval. Every path jumps to one epilogue
that only pops registers, so the result returns unchanged through each level
in `eax`. The helper frame is:

```text
[ebp+20]  key
[ebp+16]  hi
[ebp+12]  lo
[ebp+8]   array pointer
[ebp+4]   return address
[ebp]     saved caller ebp
[ebp-4]   saved ebx
[ebp-8]   saved esi
[ebp-12]  saved edi
[ebp-16]  local mid  <- esp after setup
```

**GCD.** The public entry sets `gcd_depth` to 0 and calls
`gcd_inner(a, b, 1)`. The helper first records its depth argument in
`gcd_depth` when it exceeds the stored value. It returns `a` when `b == 0`;
otherwise, it computes `a % b` with `cdq` and `idiv`, then calls itself with
`(b, a % b, depth + 1)`. Because the depth travels on the stack, the global
keeps only the peak, including the base-case call. Thus, `gcd(1071, 462)`
returns 21 at depth 4. Recursive calls target the helper so they do not reset
the depth diagnostic. The helper frame is `a`, `b`, and `depth` at
`[ebp+8]`, `[ebp+12]`, and `[ebp+16]`, with `ebx`, `esi`, and `edi` saved
below `ebp`.

**Reentrant range sum.** The public entry calls `bench_callback` once, then
invokes `sum_range_inner(lo, hi)`, which does not call the callback. The
arguments survive the callback in the entry's own frame at `[ebp+8]` and
`[ebp+12]`, so nothing is saved around it. Each helper frame holds only its
two arguments, the return address, and the saved `ebp`; the helper uses only
`eax`. After the recursive call returns, it re-reads its own `lo` from
`[ebp+8]` to compute `lo + sum(lo + 1, hi)`. No mutable global is used. The
callback's nested invocation builds its frames below the outer invocation's
and therefore cannot overwrite the outer invocation's state. The reentrancy
demonstration expects two callback calls in total, one per C entry.

### Measurements

Measured with `bench --sort` after all 36 checks passed, on Windows (MinGW
gcc, `-m32`). The ratio is assembly sorting time divided by C sorting time;
smaller is better. The harness reports the mean of 200 runs, each sorting a
fresh copy. Timings vary between runs and machines, so treat the ratios as
orders of magnitude.

| File | Elements | `qsort_asm` (ms) | C `qsort` (ms) | Measured ratio |
|---|---|---|---|---|
| `random1000.txt` | 1000 | 0.037 | 0.044 | 0.85x |
| `sorted1000.txt` | 1000 | 2.873 | 0.017 | 168.98x |
| `reverse1000.txt` | 1000 | 1.543 | 0.019 | 82.67x |
| `duplicates.txt` | 500 | 0.182 | 0.004 | 48.01x |
| `identical.txt` | 100 | 0.029 | 0.000 | 88.78x |

On random input the assembly sort beats C's `qsort`, which pays for a
function-pointer comparison call per element pair. Every other file is
degenerate for last-element Lomuto partitioning. The measured worst case is
`sorted1000.txt`: the pivot is always the maximum, so each partition removes
one element, giving `O(n^2)` comparisons and `O(n)` recursion depth.
Reverse-sorted input degenerates the same way. Identical values all satisfy
`arr[j] <= pivot`, so the pivot always lands at `hi`. The `identical.txt`
ratio is imprecise because C's time rounds to 0.000 ms at this resolution.

A possible improvement is median-of-three pivot selection, moving the selected
pivot to the last position before Lomuto partitioning. On distinct sorted
input, this should produce more balanced partitions and reduce growth toward
`O(n log n)`. At 1,000 elements, roughly 500,000 baseline comparisons versus
about 10,000 for balanced partitions suggests an order-of-magnitude improvement
in comparison work; this is an estimate, not a measured speedup. It does not
solve identical-value degeneration under the same two-way partition rule; a
three-way partition would. The group did not implement it, so only the
baseline ratios above are reported.

### Timeline

| Week | Goal | Owner |
|---|---|---|
| 1 | Confirm interfaces and ownership; start design notes; build and run the starter prototype | All members; JP coordinates convention documentation |
| 2 | Complete recursive quicksort and binary search, including signed values; complete recursive GCD and depth tracking | Eusef: sorting; Yuan and Renz: searching and GCD |
| 3 | Complete reentrant summation and integration; pass all 36 checks; add an ordered two-element test; finish measurements, design notes, and quirks | JP coordinates; all members review |
| 4 | Trace stack frames, explain other members' subsystems, and prepare the final defended commit | All members |

## Subsystem Ownership

Complete this section before the Week 1 progress report. The manual lists
the three subsystems. Each member owns one. In a group of four, two members
share one. The commit history must agree with this table.

| Subsystem | Owner |
|---|---|
| Sorting (`qsort_asm` and its partition) | Eusef |
| Searching (`bsearch_asm`, `gcd_asm`) | Yuan and Renz|
| Convention and measurement (`sum_range_asm`, the benchmarks) | JP |

## Quirks and Issues

Complete this section before the Week 3 progress report. The syllabus asks
for documentation of quirks and issues with the complete implementation.
One entry per item. State what happens, what causes it, and what the group
did about it.

### Known issues

- **Quicksort is quadratic on sorted, reverse-sorted, and repeated input.**
  `sorted1000.txt` runs about 169 times slower than C's `qsort`. Cause:
  last-element Lomuto partitioning removes one element per partition when the
  pivot is the maximum or when every element ties with it. The group
  documented median-of-three as a fix for distinct sorted input (see
  Measurements) but kept the manual's required scheme.
- **Deep recursion on degenerate input can exhaust the stack.** Sorted input
  of `n` elements nests `n` `qsort_inner` frames of 36 bytes each, and
  `sum_range_asm(lo, hi)` nests `hi - lo + 2` frames of 16 bytes each. The
  test corpus stays far below the limit (about 36 KB and 16 KB), but arrays or
  ranges in the tens or hundreds of thousands can overflow a default-sized
  thread stack. Cause: both routines are recursive by requirement. The group
  accepted this because the manual forbids an iterative rewrite.
- **`sum_range_asm` wraps on overflow.** Ranges whose true sum exceeds a
  signed 32-bit integer return a wrapped value without warning. Cause: plain
  32-bit `add`. The design notes define the routine only for results that fit
  in 32 bits.
- **The README badge points to two repositories.** The badge image uses this
  fork's workflow, but its link still opens the upstream starter's workflow
  page.

### Quirks

- **`bsearch_asm` may return any matching index among duplicates.** It
  returns whichever equal element a midpoint lands on first, not necessarily
  the leftmost. The manual and `bench.c` only require `arr[idx] == key`.
- **`pusha`/`popa` were removed from `bsearch_rec`.** An early version saved
  registers with `pusha` and restored them with `popa`, which also restored
  the old `eax` over the return value. Commit `00914e5` replaced them with
  explicit `push`/`pop` of `ebx`, `esi`, and `edi`.
- **`gcd_asm` is not reentrant.** Two overlapping calls would both write the
  global `gcd_depth`. This is allowed: only `sum_range_asm` must be
  reentrant, and `gcd_depth` is a diagnostic, not part of the result.
- **`qsort_inner` saves registers it never uses.** It pushes `ebx`, `esi`,
  and `edi` to keep the frame layout in the design notes, which costs a few
  instructions per call but is otherwise harmless. Line 99 of `sort.asm` also
  reloads `p` immediately after storing it.
- **Swaps use `xchg` with a memory operand.** `xchg` with memory carries an
  implicit bus lock, which is slower than a plain three-`mov` swap. The swap
  is correct, and `partition` also swaps an element with itself when `i == j`.
- **`qsort_asm` returns 0 in `eax`.** C declares it `void`, so the value is
  ignored; the wrapper clears `eax` anyway.
- **The frame setup style differs by file.** `sort.asm` and `bsearch_rec`
  write `push ebp` / `mov ebp, esp` by hand, while the wrappers in
  `search.asm` and both routines in `util.asm` use `enter 0,0` and `leave`.
  The resulting frames are identical.
