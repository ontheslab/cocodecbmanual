; ---- Fixed ROM/RAM addresses (see Quick reference above) ----
OPENFILE_VEC    EQU     $C48D ; OPEN DISK FILE
CONSOLEIN_VEC   EQU     $C5C4 ; DISK CONSOLE IN (read one byte)
SEARCHDIR_VEC   EQU     $C68C ; SEARCH DIRECTORY (safe existence check)
CLOSEALL_VEC    EQU     $CAE9 ; NOT $0191 - see the FRClose explanation above
CHROUT_VEC      EQU     $A002 ; CONSOLE OUT (write one byte, via DEVNUM)
DNAMBF          EQU     $094C ; 8-byte filename buffer
DEXTBF          EQU     $0954 ; 3-byte extension buffer
DFLTYP          EQU     $0957 ; file type - 1 = DATA
DASCFL          EQU     $0958 ; ASCII flag - 0 = binary
DFFLEN          EQU     $097C ; record length
DEVNUM          EQU     $006F ; current I/O device - scope tightly
CINBFL          EQU     $0070 ; nonzero after DISK CONSOLE IN means EOF
V973            EQU     $0973 ; SEARCH DIRECTORY's own "found?" flag

; ---- This module's own scratch RAM ----
FRPos           RMB     2     ; current byte position (read side only)
FRStatus        RMB     1     ; 0 = ok, nonzero = EOF / not found, per routine
FRIsOpen        RMB     1     ; nonzero once a file has been opened
FRFilename      RMB     11    ; scratch copy of the 11-byte name, for FRSeek
FOC_SaveX       RMB     2     ; scratch: caller's filename pointer, saved across FRClose
FOC_SaveA       RMB     1     ; scratch: caller's mode byte, saved across FRClose
FRSeekTarget    RMB     2     ; scratch: FRSeek's requested absolute byte offset

; ---- FROpen / FROpenWrite / FROpenCommon ----
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

; ---- FRReadByte ----
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

; ---- FRWriteByte ----
FRWriteByte
        PSHS    B             ; preserve B for the caller
        LDB     #1            ; file number 1
        STB     DEVNUM        ; select the open output file
        JSR     [CHROUT_VEC]  ; indirect call - CHROUT_VEC holds a
                              ; vector address, not code, at $A002
        CLR     DEVNUM        ; back to the screen immediately
        PULS    B             ; restore B
        RTS                   ; A (the byte written) is left unchanged

; ---- FRClose ----
FRClose
        JSR     CLOSEALL_VEC  ; no DEVNUM setup needed - this routine
                              ; sets DEVNUM itself, once per open file,
                              ; as part of its own internal loop
        CLR     FRIsOpen      ; record that nothing is open any more
        RTS                   ; note: A/B/X are left clobbered - see the Registers note above

; ---- FRExists ----
FRExists
        PSHS    A,B,X,Y,U     ; preserve everything for the caller
        LDU     #DNAMBF       ; fill in the two DECB buffers, same as FROpen
        LDY     #8            ; 8-byte filename
FE_CopyName
        LDA     ,X+           ; read one filename byte from the caller's buffer
        STA     ,U+           ; write it into DNAMBF
        LEAY    -1,Y          ; one fewer byte left
        BNE     FE_CopyName   ; loop until all 8 bytes are copied
        LDU     #DEXTBF       ; now the 3-byte extension
        LDY     #3
FE_CopyExt
        LDA     ,X+           ; read one extension byte
        STA     ,U+           ; write it into DEXTBF
        LEAY    -1,Y          ; one fewer byte left
        BNE     FE_CopyExt    ; loop until all 3 bytes are copied

        JSR     SEARCHDIR_VEC ; safe - does not abort on "not found"
        TST     V973          ; DECB's own "found?" flag
        BNE     FE_Found      ; nonzero means the file exists
        LDA     #1
        STA     FRStatus      ; nonzero = not found
        BRA     FE_Done       ; skip the "found" case below
FE_Found
        CLR     FRStatus      ; 0 = found
FE_Done
        PULS    A,B,X,Y,U     ; restore every register for the caller
        RTS

; ---- FRSeek ----
FRSeek
        PSHS    A,B,X         ; preserve for the caller - this also preserves D, since D is just A and B
        STD     FRSeekTarget  ; remember the requested offset
        CMPD    FRPos         ; compare it against the current position
        BHS     FRS_Forward   ; target at/after current position - seek forward, or nothing to do
                              ; target before current position - reopen, then fall through to seek forward
                              ; from 0 (FROpen resets FRPos to 0 as one of its own outputs)
        LDX     #FRFilename   ; reopen the same file FROpen last remembered
        LBSR    FROpen
FRS_Forward
FRS_Loop
        LDD     FRSeekTarget  ; reload the target (FRReadByte may have used D)
        CMPD    FRPos         ; how far is there left to go?
        BLS     FRS_Done      ; reached (or passed) the target
        LBSR    FRReadByte    ; read-and-discard to advance FRPos
        TST     FRStatus      ; did that read hit EOF?
        BNE     FRS_Done      ; stop early on EOF
        BRA     FRS_Loop      ; otherwise keep advancing
FRS_Done
        PULS    A,B,X         ; restore for the caller
        RTS
