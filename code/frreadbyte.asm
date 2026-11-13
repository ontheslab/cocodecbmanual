FRReadByte
        PSHS    B             ; preserve B for the caller
        LDB     #1            ; file number 1
        STB     DEVNUM        ; select the open file for this one call
        JSR     CONSOLEIN_VEC ; byte comes back in A
        CLR     DEVNUM        ; back to the screen before anything else
        TST     CINBFL        ; DECB's own EOF flag
        BEQ     FRRB_Ok       ; zero means a real byte was read - go handle it
        LDB     #1
        STB     FRStatus      ; nonzero = EOF
        PULS    B             ; restore B before returning
        RTS                   ; A holds whatever DISK CONSOLE IN left there - ignore it
FRRB_Ok
        CLR     FRStatus      ; 0 = a real byte was read
        PSHS    A             ; protect the return value from ADDD below
        LDD     FRPos         ; load the current position into D
        ADDD    #1            ; advance it by one byte
        STD     FRPos         ; advance the module's own position tracker
        PULS    A             ; recover the byte read, now the return value
        PULS    B             ; restore B
        RTS                   ; A holds the byte just read
