; Power-up-style binary counter for the four onboard LEDs.
; LED register = 0xFF00.

        LOADI_H 0xFF
        LOADI_L 0x00
        LOADI   R0, 0

main:
        STORE   R0, [IDX]
        LOADI   R1, 0xFF
        LOADI   R2, 0xFF
        LOADI   R3, 0x08

delay:
        SUBI    R1, 1
        BRNZ    delay
        LOADI   R1, 0xFF
        SUBI    R2, 1
        BRNZ    delay
        LOADI   R2, 0xFF
        SUBI    R3, 1
        BRNZ    delay

        ADDI    R0, 1
        JUMP_REL main
