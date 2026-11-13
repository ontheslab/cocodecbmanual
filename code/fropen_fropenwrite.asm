FOC_SaveX       RMB     2     ; scratch: caller's filename pointer, saved across FRClose
FOC_SaveA       RMB     1     ; scratch: caller's mode byte, saved across FRClose

FROpenCommon
        PSHS    A,B,X,Y,U     ; preserve everything for the caller
        STX     FOC_SaveX     ; stash the filename pointer somewhere
        STA     FOC_SaveA     ; safe from FRClose clobbering it below

        TST     FRIsOpen      ; is a file already open from an earlier call?
        BEQ     FOC_SkipClose ; no - skip straight to opening the new one
        LBSR    FRClose       ; close whatever was open first - FRClose
FOC_SkipClose                 ; may freely clobber A/B/X/Y/U; the real
                              ; values are parked in scratch RAM above,
                              ; not just the hardware stack
        LDX     FOC_SaveX     ; recover the filename pointer
        LDA     FOC_SaveA     ; recover the mode byte
        PSHS    A             ; mode ('I'/'O') - survives the name-
                              ; copy loops below

        LDU     #FRFilename   ; remember the name for FRSeek's reopen
        LDY     #11           ; copy all 11 bytes (8 name + 3 extension)
FOC_SaveName
        LDA     ,X+           ; read one byte from the caller's buffer, advance X
        STA     ,U+           ; write it into FRFilename, advance U
        LEAY    -1,Y          ; one fewer byte left to copy
        BNE     FOC_SaveName  ; loop until all 11 bytes are copied

        LDX     #FRFilename   ; re-read from the scratch copy just made
        LDU     #DNAMBF       ; split into the two DECB buffers
        LDY     #8            ; first 8 bytes are the filename
FOC_CopyName
        LDA     ,X+           ; read one filename byte
        STA     ,U+           ; write it into DNAMBF
        LEAY    -1,Y          ; one fewer byte left
        BNE     FOC_CopyName  ; loop until the 8-byte name is copied
        LDU     #DEXTBF       ; now fill the 3-byte extension buffer
        LDY     #3            ; remaining 3 bytes are the extension
FOC_CopyExt
        LDA     ,X+           ; read one extension byte
        STA     ,U+           ; write it into DEXTBF
        LEAY    -1,Y          ; one fewer byte left
        BNE     FOC_CopyExt   ; loop until the 3-byte extension is copied

        LDA     #1            ; DFLTYP: 1 = DATA file
        STA     DFLTYP        ; tell DECB this is a plain data file
        CLR     DASCFL        ; 0 = binary, not ASCII/crunched
        LDD     #$00FF        ; matches BASIC's own OPEN default
        STD     DFFLEN        ; initialise BASIC's default record length

        LDD     #0            ; start position is always 0 on a fresh open
        STD     FRPos         ; the module's own position tracker starts at 0

        LDA     #1            ; file number 1
        STA     DEVNUM        ; scope DEVNUM tightly around the call
        PULS    A             ; recover the mode saved above
        LDB     #1            ; file number 1
        JSR     OPENFILE_VEC  ; the ROM call
        CLR     DEVNUM        ; back to the screen immediately

        CLR     FRStatus      ; reaching here at all means success
        LDA     #1
        STA     FRIsOpen      ; record that a file is now open
        PULS    A,B,X,Y,U     ; restore every register for the caller
        RTS                   ; back to whoever called FROpen/FROpenWrite

FROpen
        LDA     #'I           ; mode = INPUT
        LBRA    FROpenCommon  ; fall into the shared body above

FROpenWrite
        LDA     #'O           ; mode = OUTPUT
        LBRA    FROpenCommon  ; fall into the shared body above
