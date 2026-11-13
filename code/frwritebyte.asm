FRWriteByte
        PSHS    B            ; preserve B for the caller
        LDB     #1           ; file number 1
        STB     DEVNUM       ; select the open output file
        JSR     [CHROUT_VEC] ; indirect call - CHROUT_VEC holds a
                             ; vector address, not code, at $A002
        CLR     DEVNUM       ; back to the screen immediately
        PULS    B            ; restore B
        RTS                  ; A (the byte written) is left unchanged
