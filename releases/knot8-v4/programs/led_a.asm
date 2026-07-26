; Quick hardware check: display binary 1010 and halt.

        LOADI_H 0xFF
        LOADI_L 0x00
        LOADI   R0, 0x0A
        STORE   R0, [IDX]
        HALT
