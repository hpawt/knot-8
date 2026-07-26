; Knot-8 v4 architecture demonstration.
; Use both address pointers, increment one tape cell, verify the 16-bit value
; with CMPI/CPCI sticky equality, display 1011, send 'K', then halt.

start:
        LOADI_H 0x80
        LOADI_L 0x00
        LOADI   R0, 0x0A
        STORE   R0, [IDX]
        SWAPXY                  ; IDY=0x8000, IDX=0

        LOADI_H 0xFF
        LOADI_L 0x00            ; IDX=LED MMIO, IDY=tape cell
        SWAPXY                  ; IDX=tape cell, IDY=LED MMIO
        INC_MEM [IDX]
        LOAD    R0, [IDX]

        LOADI   R1, 0
        CMPI    R0, 0x0B        ; compare R1:R0 with 0x000B
        CPCI    R1, 0
        BRNZ    done

        SWAPXY                  ; IDX=LED MMIO, IDY=tape cell
        STORE   R0, [IDX]

        LOADI_L 0x03            ; UART status
uart_wait:
        LOAD    R1, [IDX]
        CMPI    R1, 1
        BRNZ    uart_wait

        LOADI_L 0x02            ; UART TX data
        LOADI   R0, 'K'
        STORE   R0, [IDX]
done:
        HALT
