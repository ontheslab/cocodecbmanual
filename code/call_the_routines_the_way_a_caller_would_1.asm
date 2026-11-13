        ORG     $2800

CHROUT_VEC      EQU     $A002   ; CONSOLE OUT (write one byte, via DEVNUM)

Start
        LDX     #Message        ; X walks through the message, one byte at a time
PrintLoop
        LDA     ,X+             ; fetch the next character, advance X
        CMPA    #0              ; the FCB 0 below marks the end of the text
        BEQ     Done
        JSR     [CHROUT_VEC]    ; print it - DEVNUM is 0 (screen) by default,
                                ; so no DEVNUM setup is needed here at all
        BRA     PrintLoop
Done
        RTS                     ; back to BASIC's OK prompt, same as any EXEC'd program finishing

Message         FCC     "HELLO FROM 6809 ASSEMBLY"
                FCB     0       ; null terminator - PrintLoop's own signal to stop

        END     Start
