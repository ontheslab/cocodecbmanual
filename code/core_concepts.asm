        LBSR    FRClose      ; closes whatever was open first - accept that this
                             ; also closes any other file DECB has open
        CLR     DCDRV        ; NOW select drive 0 - after the close, not before
        LDX     #Fn_Buffer
        LBSR    FROpen       ; FRIsOpen is now clear, so no second internal close happens
