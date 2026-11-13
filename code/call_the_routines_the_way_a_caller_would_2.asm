        ORG     $2800

Start
        CLR     FRIsOpen        ; must happen once, before the very first FROpen -
                                ; see the Gotcha under FROpen/FROpenWrite above
        LDX     #MyFilename     ; -> an 11-byte space-padded name+ext buffer
        LBSR    FROpen          ; opens for INPUT

PrintLoop
        LBSR    FRReadByte      ; byte comes back in A
        TST     FRStatus        ; 0 = got a real byte, nonzero = EOF
        BNE     Done
        JSR     [CHROUT_VEC]    ; print it - same call as the "before" version,
                                ; DEVNUM is already back to 0 (screen) by the
                                ; time FRReadByte returns, so this just works
        BRA     PrintLoop
Done
        LBSR    FRClose         ; always close what you opened
        RTS                     ; back to BASIC's OK prompt

MyFilename      FCC     "MYFILE  TXT"   ; 8-byte name (space-padded) + 3-byte extension, no dot

; ---- paste the Appendix block here (FROpen, FROpenWrite, FRReadByte, ----
; ---- FRWriteByte, FRClose, FRExists, FRSeek, and their scratch RAM/ ----
; ---- constants) - this program calls three of them: FROpen, FRReadByte, ----
; ---- FRClose. See step 1 and step 2 above before pasting. Note that the ----
; ---- Appendix block already defines CHROUT_VEC, along with every other ----
; ---- constant this program needs - don't declare CHROUT_VEC a second time ----
; ---- up near Start, or the assembler will reject it as already defined. ----

        END     Start
