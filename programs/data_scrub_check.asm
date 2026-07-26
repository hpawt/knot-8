; Hardware diagnostic for Knot-8 v4 data RAM scrub.
; A fresh upload must see [0x8000] == 0, write 0xA5 there, and print 'Z'.
; Uploading this same program again prints 'Z' only if the loader scrubbed the
; value left by the previous run. It prints 'N' on failure.

        LOADI_H 0x80
        LOADI_L 0x00
        LOAD    R0, [IDX]
        CMPI    R0, 0
        BRNZ    not_zero

        LOADI   R0, 0xA5
        STORE   R0, [IDX]
        LOADI   R2, 'Z'
        JUMP_REL uart_setup

not_zero:
        LOADI   R2, 'N'

uart_setup:
        LOADI_H 0xFF
        LOADI_L 0x03
uart_wait:
        LOAD    R1, [IDX]
        CMPI    R1, 1
        BRNZ    uart_wait

        LOADI_L 0x02
        STORE   R2, [IDX]
        HALT
