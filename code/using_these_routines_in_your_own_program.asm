DCDRV   EQU     $00EB

        LBSR    FRClose      ; close whatever was open first - its own internal
                              ; close would otherwise overwrite DCDRV again
        CLR     DCDRV        ; NOW select drive 0 - after the close, not before
        LDX     #Fn_Buffer
        LBSR    FROpen       ; FRIsOpen is clear now, so no second internal close happens
