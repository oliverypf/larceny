;;; i386 millicode entry points and millicode jump vector initialization.
;;;
;;; $Id: i386-millicode.asm 3077 2006-06-02 21:45:50Z pnkfelix $
;;;
;;; Millicode implementation for the x86-nasm system.  Most millicode
;;; entry points here just jump to the C implementation, incurring
;;; the cost of context switching.  The performance-critical ones can
;;; be replaced by hand-coded assembler or similar code.
	
%include "i386-machine.ah"
%define fixnum(n)           ((n)<<2)

;;; It is generally helpful to enable OPTIMIZE_MILLICODE: it turns
;;; on some assembler versions of millicode routines normally written
;;; in C, and by avoiding taking a context switch to C we gain
;;; some performance.
;;;
;;; Note, though, that only code outside this %define is necessary
;;; for correct operation.  The amount of assembler in this file
;;; is not an indication of the required porting effort.
	
%define OPTIMIZE_MILLICODE

	section	.text align=4
	
	global  EXTNAME(i386_scheme_jump)
	global	EXTNAME(i386_stack_underflow)
	global	EXTNAME(i386_return_from_scheme)
	global	EXTNAME(i386_dispatch_loop_return)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; 
;;; Machine language stubs for system operations implemented in C.
	
	extern	EXTNAME(mem_stkuflow)
	extern	EXTNAME(return_from_scheme)
	extern	EXTNAME(dispatch_loop_return)
	extern	EXTNAME(gclib_pagebase)
	extern	EXTNAME(mc_exception)

;;; This is an assertion (which requires eax to be free)
;;; that REG0 points to a procedure object.
;;; XXX turn off before release.
%macro CHECKZEROREG 2
%ifdef REG0
	mov	eax, REG0
%else
	mov	eax, dword [GLOBALS + G_REG0 + %1]
%endif
	lea	eax, [eax+(8 - PROC_TAG)]
	test	al, 7
	jz	%%L1
%ifdef REG0
	mov	eax, REG0
%else
	mov	eax, dword [GLOBALS + G_REG0 + %1]
%endif
	int3
	add	eax, %2
%%L1:	
%endmacro	
		
;;; The return address of the bottommost frame in the stack cache points
;;; to i386_stack_underflow; all we do is call the C function that
;;; escapes to the dispatch loop to restore a frame and continue execution.
	
	align	code_align
EXTNAME(i386_stack_underflow):
	mov	eax, EXTNAME(mem_stkuflow)
	jmp	callout_to_C_leave_retaddr_absolute

	
;;; The return address of a frame created by a callout from Scheme to
;;; millicode points to i386_return_from_scheme; all we do is call 
;;; the C function that escapes to the dispatch loop to restore state
;;; and continue execution
	
	align	code_align
EXTNAME(i386_return_from_scheme):
%ifdef REG0
	mov	REG0, dword [ CONT + 5*4 ]
%else
	mov	eax, dword [ CONT + 5*4 ]
	mov	[GLOBALS + G_REG0], eax
%endif
	CHECKZEROREG 0, 3
	mov	eax, EXTNAME(return_from_scheme)
	jmp	callout_to_C

	
;;; The return address of the bottommost frame on the stack points
;;; to i386_dispatch_loop_return; all we do is call the C function
;;; that terminates the dispatch loop.
	
	align	code_align
EXTNAME(i386_dispatch_loop_return):
	CHECKZEROREG 0, 4
	mov	eax, EXTNAME(dispatch_loop_return)
	jmp	callout_to_C

	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; 
;;; Enter scheme mode.  Arguments are globals ptr and address to 
;;; jump to.  Does not return, so need to save ESP only.

EXTNAME(i386_scheme_jump):
	;; Switch to Scheme mode
	mov	eax, [esp+8]	; Address to jump to
	mov	ebx, [esp+4]	; globals table

	mov	[ebx+G_SAVED_ESP], esp
	
	mov	GLOBALS, ebx
%ifdef REG0
	mov	REG0, [GLOBALS+G_REG0]
%endif
	mov	REG1, [GLOBALS+G_REG1]
	mov	REG2, [GLOBALS+G_REG2]
	mov	REG3, [GLOBALS+G_REG3]
%ifdef REG4
	mov	REG4, [GLOBALS+G_REG4]
%endif
	mov	RESULT, [GLOBALS+G_RESULT]
	mov	CONT, [GLOBALS+G_STKP]

	jmp	TEMP		; TEMP is eax always

	
;;; Millicode stubs
;;; 
;;; Millicode is generally implemented in C.  Switch to C mode, call out
;;; to the C code, and if it returns then switch back to Scheme mode and
;;; return to the caller.

%macro PUBLIC 1
	global	EXTNAME(%1)
	align	code_align
EXTNAME(%1):
%endmacro

;;; The unadjusted return address is in GLOBALS[-1]; adjust it and
;;; save it in G_RETADDR.
;;;
;;; Destroys: EAX

%macro SAVE_RETURN_ADDRESS 0
	mov	eax, dword [GLOBALS-4]          ; return address
	add	eax, 3		                ;  rounded up
	and	eax, 0xFFFFFFFC	                ;   to 4-byte boundary
	mov	dword [GLOBALS+G_RETADDR], eax  ;    saved for later
%endmacro

	;; On entry, GLOBALS pointer is off by 4
%macro SAVE_RETURN_ADDRESS_INTRSAFE 0
	mov	eax, dword [GLOBALS]			; return address
	add	eax, 3		                	;  rounded up
	and	eax, 0xFFFFFFFC	                	;   to 4-byte boundary
	mov	dword [GLOBALS+G_RETADDR+4], eax	;    saved for later
	add	GLOBALS, 4				; fixup globals
%endmacro

;;; Arguments: second? c-name callout-method

%macro MILLICODE_STUB 3
	extern	EXTNAME(%2)
%if %1
	mov	[GLOBALS+G_SECOND+4], eax
%endif
	SAVE_RETURN_ADDRESS_INTRSAFE
	mov	eax, EXTNAME(%2)
	jmp	%3
%endmacro
	
%macro MCg 1
	MILLICODE_STUB 0, %1, callout_to_C
%endmacro

%macro MCgk 1
	MILLICODE_STUB 0, %1, callout_to_Ck
%endmacro

%macro MC2g 1
	MILLICODE_STUB 1, %1, callout_to_C
%endmacro

%macro MC2gk 1
	MILLICODE_STUB 1, %1, callout_to_Ck
%endmacro

	;; On entry, GLOBALS pointer is off by 4
PUBLIC i386_alloc_bv
	MCg	mc_alloc_bv
PUBLIC i386_alloc
%ifdef OPTIMIZE_MILLICODE
	mov	TEMP, [GLOBALS+G_ETOP+4]
	add	RESULT, 7
	and	RESULT, 0xfffffff8
	add	TEMP, RESULT
	cmp	TEMP, CONT
	jg	L1
	mov	RESULT, [GLOBALS+G_ETOP+4]
	mov	[GLOBALS+G_ETOP+4], TEMP
	xor	TEMP, TEMP
	ret
L1:	xor	TEMP, TEMP
%endif ; OPTIMIZE_MILLICODE
	MCg	mc_alloc

	;; On entry, GLOBALS pointer is off by 4
PUBLIC i386_alloci
%ifdef OPTIMIZE_MILLICODE
	mov	[GLOBALS+G_SECOND+4], SECOND
	mov	[GLOBALS+G_REGALIAS_ECX+4], ecx
	mov	[GLOBALS+G_REGALIAS_EDI+4], edi
	add	RESULT, 7
	and	RESULT, 0xfffffff8
	mov	ecx, RESULT		; Byte count for initialization
	shr	ecx, 2			;   really want words
	mov	TEMP, [GLOBALS+G_ETOP+4]
	add	TEMP, RESULT
	cmp	TEMP, CONT
	jg	L2
	mov	RESULT, [GLOBALS+G_ETOP+4]
	mov	[GLOBALS+G_ETOP+4], TEMP
	mov	eax, [ GLOBALS+G_SECOND+4 ]
	mov	edi, RESULT
	cld
	rep stosd
	mov	REG1, [GLOBALS+G_REG1+4]
	mov	REG3, [GLOBALS+G_REG3+4]
	xor	SECOND, SECOND
	ret
L2:	mov	SECOND, [GLOBALS+G_SECOND+4]
	mov	ecx, [GLOBALS+G_REGALIAS_ECX+4]
	mov	edi, [GLOBALS+G_REGALIAS_EDI+4]
%endif ; OPTIMIZE_MILLICODE
	MC2g	mc_alloci
	
PUBLIC i386_morecore
	MCg	mc_morecore
	
PUBLIC i386_stack_overflow
	MILLICODE_STUB 0, mc_stack_overflow, callout_to_C
	
PUBLIC i386_capture_continuation
	MCg	mc_capture_continuation
	
PUBLIC i386_restore_continuation
	MCg	mc_restore_continuation
	
PUBLIC i386_full_barrier
%ifdef OPTIMIZE_MILLICODE
	test	SECOND, 1			; If rhs is ptr
	jnz	EXTNAME(i386_partial_barrier)	;   enter the barrier
	ret					; Otherwise return
%else  ; OPTIMIZE_MILLICODE
	MC2g	mc_full_barrier
%endif ; OPTIMIZE_MILLICODE
	
PUBLIC i386_partial_barrier
%ifdef OPTIMIZE_MILLICODE
  %ifdef GCLIB_LARGE_TABLE
    %error Optimized write barrier does not work with GCLIB_LARGE_TABLE yet
  %endif
	cmp	dword [GLOBALS+G_GENV+4], 0	; Barrier is enabled
	jne	Lpb1				;   if generation map not 0
	ret					; Otherwise return to scheme
Lpb1:	mov	[GLOBALS+G_RESULT+4], RESULT	; Free up some
	mov	[GLOBALS+G_REG1+4], REG1	;   working registers
	mov	REG1, [GLOBALS+G_GENV+4]	; Map page -> generation
	sub	RESULT, [EXTNAME(gclib_pagebase)]	; Load
	shr	RESULT, 12			;   generation number
	shl	RESULT, 2			;     (using byte offset)
	mov	RESULT, [REG1+RESULT]		;       for lhs
	sub	SECOND, [EXTNAME(gclib_pagebase)]	; Load
	shr	SECOND, 12			;   generation number
	shl	SECOND, 2			;     (using byte offset)
	mov	SECOND, [REG1+SECOND]		;       for rhs
	cmp	RESULT, SECOND			; Only store lhs in SSB
	jg	Lpb3				;   if gen(lhs) > gen(rhs)
Lpb2:	xor	RESULT, RESULT			; Clean
	xor	SECOND, SECOND			;   state
	mov	REG1, [GLOBALS+G_REG1+4]	;     and
	ret					;       return to Scheme
Lpb3:	shl	RESULT, 2			; Gen(lhs) as byte offset
	mov	REG1, [GLOBALS+G_SSBTOPV+4]	; Array of ptrs into SSBs
	mov	SECOND, [GLOBALS+G_RESULT+4]	; The value to store (lhs)
	mov	REG1, [REG1+RESULT]		; The correct SSB ptr
	mov	[REG1], SECOND			; Store lhs
	mov	SECOND, [GLOBALS+G_SSBTOPV+4]	; Array of ptrs into SSBs
	add	REG1, 4				; Move SSB ptr
	mov	[SECOND+RESULT], REG1		; Store moved ptr
	mov	SECOND, [GLOBALS+G_SSBLIMV+4]	; Array of SSB limit ptrs
	mov	SECOND, [SECOND+RESULT]		; The correct limit ptr
	cmp	REG1, SECOND			; If ptr!=limit
	jne	Lpb2				;   then no overflow, so done
	xor	RESULT, RESULT			; Clean
	xor	SECOND, SECOND			;   state
	mov	REG1, [GLOBALS+G_REG1+4]	;     and
	MCg	mc_compact_ssbs			;       handle overflow
%else  ; OPTIMIZE_MILLICODE
	MC2g	mc_partial_barrier
%endif ; OPTIMIZE_MILLICODE
	
PUBLIC i386_break
	MCg	mc_break
	
PUBLIC i386_timer_exception
	MCgk	mc_timer_exception
	
PUBLIC i386_enable_interrupts
	MCgk	mc_enable_interrupts
	
PUBLIC i386_disable_interrupts
	MCgk	mc_disable_interrupts
	
;;; With Sassy:
;;; Can't convert retaddr to a relative offset from
;;; the codevector for r0 here, because mc_apply
;;; overwrites r0 and so we would not be able to
;;; recover the original address.		
PUBLIC i386_apply
	MILLICODE_STUB 1, mc_apply, callout_to_C_leave_retaddr_absolute
	
PUBLIC i386_restargs
	MC2g	mc_restargs
	
PUBLIC i386_syscall
	MC2gk	mc_syscall
	
PUBLIC i386_typetag
	MCg	mc_typetag
	
PUBLIC i386_typetag_set
	MC2g	mc_typetag_set
	
PUBLIC i386_eqv
	MC2gk	mc_eqv
	
PUBLIC i386_partial_list2vector
	MC2g	mc_partial_list2vector
	
PUBLIC i386_bytevector_like_fill
	MC2g	mc_bytevector_like_fill
	
PUBLIC i386_bytevector_like_compare
	MC2g	mc_bytevector_like_compare
	
PUBLIC i386_add
	MC2gk	mc_add
	
PUBLIC i386_sub
	MC2gk	mc_sub
	
PUBLIC i386_mul
	MC2gk	mc_mul
	
PUBLIC i386_div
	MC2gk	mc_div
	
PUBLIC i386_quo
	MC2gk	mc_quo
	
PUBLIC i386_rem
	MC2gk	mc_rem
	
PUBLIC i386_neg
	MCgk	mc_neg
	
PUBLIC i386_abs
	MCgk	mc_abs
	
PUBLIC i386_equalp
	MC2gk	mc_equalp
	
PUBLIC i386_lessp
	MC2gk	mc_lessp
	
PUBLIC i386_less_or_equalp
	MC2gk	mc_less_or_equalp
	
PUBLIC i386_greaterp
	MC2gk	mc_greaterp
	
PUBLIC i386_greater_or_equalp
	MC2gk	mc_greater_or_equalp
	
PUBLIC i386_exact2inexact
	MCgk	mc_exact2inexact
	
PUBLIC i386_inexact2exact
	MCgk	mc_inexact2exact
	
PUBLIC i386_real_part
	MCg	mc_real_part
	
PUBLIC i386_imag_part
	MCg	mc_imag_part
	
PUBLIC i386_round
	MCgk	mc_round
	
PUBLIC i386_truncate
	MCgk	mc_truncate
	
PUBLIC i386_zerop
	MCg	mc_zerop
	
PUBLIC i386_complexp
	MCg	mc_complexp
	
PUBLIC i386_rationalp
	MCg	mc_rationalp
	
PUBLIC i386_integerp
	MCg	mc_integerp
	
PUBLIC i386_exactp
	MCg	mc_exactp
	
PUBLIC i386_inexactp
	MCg	mc_inexactp
	
PUBLIC i386_exception				; Exn encoded in instr stream
	mov	[GLOBALS+G_SECOND+4], SECOND
	mov	SECOND, [GLOBALS]		; Exn code address
	mov	ax, [SECOND]			; Exn code
	and	eax, 0xFFFF			;   is 16 bits
	shl	eax, 2				;     encoded as fixnum
	jmp	i386_signal_exception_intrsafe
	
PUBLIC i386_global_exception			; RESULT holds the global cell
	mov	dword [GLOBALS+G_SECOND+4], FALSE_CONST
	mov	SECOND, fixnum(EX_UNDEF_GLOBAL)
	jmp	i386_signal_exception_intrsafe
	
PUBLIC i386_invoke_exception			; RESULT holds defined value
	cmp	dword [GLOBALS+G_TIMER+4], 0
	jnz	Linv1
	jmp	EXTNAME(i386_timer_exception)
Linv1:	mov	dword [GLOBALS+G_SECOND+4], FALSE_CONST
	mov	SECOND, fixnum(EX_NONPROC)
	jmp	i386_signal_exception_intrsafe
	
PUBLIC i386_global_invoke_exception		; RESULT holds the global cell
	mov	dword [GLOBALS+G_SECOND+4], FALSE_CONST
	cmp	dword [GLOBALS+G_TIMER+4], 0
	jnz	Lginv1
	jmp	EXTNAME(i386_timer_exception)
Lginv1:	cmp	dword [RESULT-PAIR_TAG], UNDEFINED_CONST
	jnz	Lginv2
	mov	SECOND, fixnum(EX_UNDEF_GLOBAL)
	jmp	i386_signal_exception_intrsafe
Lginv2:	mov	RESULT, [RESULT-PAIR_TAG]
	mov	SECOND, fixnum(EX_NONPROC)
	jmp	i386_signal_exception_intrsafe
	
PUBLIC i386_argc_exception			; RESULT holds actual arg cnt
%ifdef REG0
	mov	dword [GLOBALS+G_THIRD+4], REG0
%else
        mov     SECOND, [GLOBALS+G_REG0+4]
	mov	dword [GLOBALS+G_THIRD+4], SECOND
%endif
	mov	SECOND, fixnum(EX_ARGC)
	jmp	i386_signal_exception_intrsafe
	
PUBLIC i386_petit_patch_boot_code
%ifdef X86_SASSY
	int3
%else
	MCg	mc_petit_patch_boot_code
%endif

%macro INTERNAL_FIXNUM_TO_RETADDR 0
	mov	[saved_temp_reg], eax
	CHECKZEROREG 0, 1
%ifdef REG0
	mov	eax, dword [REG0 - PROC_TAG + PROC_CODEVECTOR_NATIVE]
%else
	mov	eax, dword [GLOBALS + G_REG0]
	mov	eax, dword [eax - PROC_TAG + PROC_CODEVECTOR_NATIVE]
%endif
	add	eax, BVEC_HEADER_BYTES - BVEC_TAG
	add	dword [GLOBALS + G_RETADDR], eax
	mov	eax, [saved_temp_reg]
%endmacro

%macro INTERNAL_RETADDR_TO_FIXNUM 0
	mov	[saved_temp_reg], eax
	CHECKZEROREG 0, 2
%ifdef REG0
	mov	eax, dword [REG0 - PROC_TAG + PROC_CODEVECTOR_NATIVE]
%else
	mov	eax, dword [GLOBALS + G_REG0]
	mov	eax, dword [eax - PROC_TAG + PROC_CODEVECTOR_NATIVE]
%endif
	add	eax, BVEC_HEADER_BYTES - BVEC_TAG
	sub	dword [GLOBALS + G_RETADDR], eax
	mov	eax, [saved_temp_reg]
%endmacro

%macro SAVE_STATE 1
 %ifdef X86_SASSY
	INTERNAL_RETADDR_TO_FIXNUM
 %endif
	SAVE_STATE_ABSOLUTE %1
%endmacro

%macro RESTORE_STATE 1
	RESTORE_STATE_ABSOLUTE %1
 %ifdef X86_SASSY
	INTERNAL_FIXNUM_TO_RETADDR
 %endif
%endmacro

%macro SAVE_STATE_ABSOLUTE 1
	mov	[%1], GLOBALS
	mov	[GLOBALS + G_STKP], CONT
	mov	[GLOBALS + G_RESULT], RESULT
%ifdef REG0
	mov	[GLOBALS + G_REG0], REG0
%endif
	mov	[GLOBALS + G_REG1], REG1
	mov	[GLOBALS + G_REG2], REG2
	mov	[GLOBALS + G_REG3], REG3
%ifdef REG4
	mov	[GLOBALS + G_REG4], REG4
%endif
%endmacro

%macro RESTORE_STATE_ABSOLUTE 1
	mov	GLOBALS, [%1]
	mov	CONT, [GLOBALS + G_STKP]
	mov	RESULT, [GLOBALS + G_RESULT]
%ifdef REG0
	mov	REG0, [GLOBALS + G_REG0]
%endif
	mov	REG1, [GLOBALS + G_REG1]
	mov	REG2, [GLOBALS + G_REG2]
	mov	REG3, [GLOBALS + G_REG3]
%ifdef REG4
	mov	REG4, [GLOBALS + G_REG4]
%endif
%endmacro

%macro CALLOUT_TO_C 1
	mov	ebx, GLOBALS
	mov	esp, [ebx+G_SAVED_ESP]
	mov	ecx, [ebx+G_RETADDR]	
	push	0		; stack on OS X must be 16-byte aligned
	push	ecx
	push	ebx		; globals
	call	eax
	add	esp, 12
%endmacro

;;; i386_signal_exception
;;;	Signal the exception by calling signal_exception in the
;;;	C millicode.
;;;
;;; On entry:
;;;	RESULT has first value
;;;	globals[G_SECOND] has second value
;;;	globals[G_THIRD] has third value
;;;	SECOND has fixnum exception code
;;;	globals[-1] has the unadjusted return address

i386_signal_exception:
	shr	SECOND, 2			; fixnum -> native
	mov	[tmp_exception_code], SECOND    ; SECOND=eax
	SAVE_RETURN_ADDRESS			; compute G_RETADDR
	SAVE_STATE saved_globals_pointer	; forces RESULT into GLOBALS
	mov	ebx, GLOBALS
	mov	esp, [ebx+G_SAVED_ESP]
	push	0		; stack on OS X must be 16-byte aligned
	push	dword [tmp_exception_code]	; exception code
	push	ebx				; globals
	call	EXTNAME(mc_exception)
	add	esp, 12
	RESTORE_STATE saved_globals_pointer
	jmp	[GLOBALS + G_RETADDR]

	;; On entry, GLOBALS pointer is off by 4	
i386_signal_exception_intrsafe:
	shr	SECOND, 2			; fixnum -> native
	mov	[tmp_exception_code], SECOND    ; SECOND=eax
	SAVE_RETURN_ADDRESS_INTRSAFE		; compute G_RETADDR, fixup globals
	SAVE_STATE saved_globals_pointer	; forces RESULT into GLOBALS
	mov	ebx, GLOBALS
	mov	esp, [ebx+G_SAVED_ESP]
	push	0		; stack on OS X must be 16-byte aligned
	push	dword [tmp_exception_code]	; exception code
	push	ebx				; globals
	call	EXTNAME(mc_exception)
	add	esp, 12
	RESTORE_STATE saved_globals_pointer
	jmp	[GLOBALS + G_RETADDR]

;;; callout_to_C
;;;	Switch from Scheme to C mode and call a C function, then
;;;	restore Scheme mode and return.  Do not change the Scheme
;;;	continuation; C code may longjump out of the call.
;;;
;;;	On entry, eax/TEMP/SECOND contains the address of the C
;;; 	procedure to call, and the scheme return address has been saved
;;;	in G_RETADDR.

callout_to_C:
	SAVE_STATE saved_globals_pointer
	CALLOUT_TO_C 0
	RESTORE_STATE saved_globals_pointer
	jmp	[GLOBALS + G_RETADDR]

callout_to_C_leave_retaddr_absolute:
	SAVE_STATE_ABSOLUTE saved_globals_pointer
	CALLOUT_TO_C 0
	RESTORE_STATE_ABSOLUTE saved_globals_pointer
	jmp	[GLOBALS + G_RETADDR]

callout_to_Ck:
	SAVE_STATE saved_globals_pointer
	CALLOUT_TO_C 1
	RESTORE_STATE saved_globals_pointer
	jmp	[GLOBALS + G_RETADDR]
	

	section	.data

saved_temp_reg:
	dd	0
saved_globals_pointer:
	dd	0
tmp_exception_code:
	dd	0

;;; eof