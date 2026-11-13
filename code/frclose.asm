CLOSEALL_VEC    EQU     $CAE9 ; NOT $0191 - see above

FRClose
        JSR     CLOSEALL_VEC  ; no DEVNUM setup needed - this routine
                              ; sets DEVNUM itself, once per open file,
                              ; as part of its own internal loop
        CLR     FRIsOpen      ; record that nothing is open any more
        RTS                   ; note: A/B/X are left clobbered - see the Registers note above
