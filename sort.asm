;
; sort.asm - qsort_asm, a recursive quicksort callable from C.
;
; This is your starting point: it assembles and links as-is, so the build
; works before you write any code. Right now it does nothing, which makes
; the benchmark print "NOT SORTED" and "Match: NO". Your job is to replace
; that with the sort described below.
;
; The contract, from bench.c:
;
;       int n                     [ebp+12]
;       int *arr                  [ebp+8]
;
; Sort n 32-bit signed integers in place, ascending. This is the C-facing
; routine. It must obey cdecl (prologue, args at [ebp+8]+, return in eax,
; preserve ebx/esi/edi/ebp, clean arguments after every call it makes). The
; manual lets you use any convention you document for the internal recursive
; routine, but the outer one is fixed.
;
; Requirements from the manual:
;
;   * Recursive. An iterative sort with an explicit stack array does not
;     satisfy the activity.
;   * Lomuto partition with the last element as pivot (the manual's scheme).
;   * No calls into the C standard library.
;   * Clean the arguments off the stack after each call. The next pop
;     otherwise loads an argument into a register you promised to
;     preserve, and the outer call's array base is gone.
;
; The manual's pseudocode:
;
;   qsort(arr, lo, hi):
;       if lo >= hi: return
;       p = partition(arr, lo, hi)
;       qsort(arr, lo, p - 1)
;       qsort(arr, p + 1, hi)
;
;   partition(arr, lo, hi):
;       pivot = arr[hi]
;       i = lo - 1
;       for j = lo to hi - 1:
;           if arr[j] <= pivot:
;               i = i + 1
;               swap arr[i], arr[j]
;       swap arr[i + 1], arr[hi]
;       return i + 1
;

; Windows C puts a leading underscore on every exported name. Linux C does
; not. The Makefile passes -d ELF_TYPE on Linux. This block then respells
; the names below to match. asm_io.inc does the same for _asm_main in the
; bootcamp blocks. Leave this block alone.
%ifdef ELF_TYPE
  %define _qsort_asm qsort_asm
  section .note.GNU-stack noalloc noexec nowrite progbits
%endif

segment .text
        global  _qsort_asm
_qsort_asm:
        push    ebp
        mov     ebp, esp

        mov     eax, [ebp+12]
        cmp     eax, 1
        jle     .done

        dec     eax
        push    eax
        push    dword 0
        push    dword [ebp+8]
        call    qsort_inner
        add     esp, 12

.done:
        mov     eax, 0
        pop     ebp
        ret

qsort_inner:
        push    ebp
        mov     ebp, esp
        push    ebx
        push    esi
        push    edi
        sub     esp, 4

        mov     eax, [ebp+12]
        cmp     eax, [ebp+16]
        jge     .done

        push    dword [ebp+16]
        push    dword [ebp+12]
        push    dword [ebp+8]
        call    partition
        add     esp, 12
        mov     [ebp-16], eax

        mov     eax, [ebp-16]
        dec     eax
        push    eax
        push    dword [ebp+12]
        push    dword [ebp+8]
        call    qsort_inner
        add     esp, 12

        mov     eax, [ebp-16]
        inc     eax
        push    dword [ebp+16]
        push    eax
        push    dword [ebp+8]
        call    qsort_inner
        add     esp, 12

.done:
        add     esp, 4
        pop     edi
        pop     esi
        pop     ebx
        pop     ebp
        ret

partition:
        push    ebp
        mov     ebp, esp
        push    ebx
        push    esi
        push    edi

        mov     ebx, [ebp+8]
        mov     esi, [ebp+12]
        dec     esi
        mov     edi, [ebp+12]
        mov     ecx, [ebp+16]
        mov     edx, [ebx+ecx*4]

.loop:
        cmp     edi, ecx
        jge     .done

        mov     eax, [ebx+edi*4]
        cmp     eax, edx
        jg      .next

        inc     esi
        mov     eax, [ebx+esi*4]
        xchg    eax, [ebx+edi*4]
        mov     [ebx+esi*4], eax

.next:
        inc     edi
        jmp     .loop

.done:
        inc     esi
        mov     eax, [ebx+esi*4]
        xchg    eax, [ebx+ecx*4]
        mov     [ebx+esi*4], eax
        mov     eax, esi

        pop     edi
        pop     esi
        pop     ebx
        pop     ebp
        ret
