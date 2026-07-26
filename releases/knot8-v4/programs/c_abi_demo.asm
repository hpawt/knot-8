; Knot-8 C calling-convention demonstration.
; Pass the 16-bit value 0x000A on the stack, call add_one(), clean up the
; argument in the caller, then display the 0x000B return value on the LEDs.

start:
        PUSHI   0x00             ; argument high byte
        PUSHI   0x0A             ; argument low byte
        LOADI_H HIGH(add_one)
        LOADI_L LOW(add_one)
        CALL
        ADJSP   2                ; caller removes the argument

        LOADI_H 0xFF
        LOADI_L 0x00
        STORE   R0, [IDX]
        HALT

add_one:
        ADJSP   -2               ; two local bytes
        LOADSP  R0, 4            ; argument low
        LOADSP  R1, 5            ; argument high
        ADDI    R0, 1
        ADCI    R1, 0
        STORESP R0, 0
        STORESP R1, 1
        LOADSP  R0, 0            ; uint16_t return in R1:R0
        LOADSP  R1, 1
        ADJSP   2
        RET
