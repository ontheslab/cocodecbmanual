FRSeekTarget    RMB     2    ; scratch: the requested absolute byte offset

FRSeek
        PSHS    A,B,X        ; preserve for the caller - this also preserves D, since D is just A and B
        STD     FRSeekTarget ; remember the requested offset
        CMPD    FRPos        ; compare it against the current position
        BHS     FRS_Forward  ; target at/after current position - seek forward, or nothing to do
                             ; target before current position - reopen, then fall through to seek forward
                             ; from 0 (FROpen resets FRPos to 0 as one of its own outputs)
        LDX     #FRFilename  ; reopen the same file FROpen last remembered
        LBSR    FROpen
FRS_Forward
FRS_Loop
        LDD     FRSeekTarget ; reload the target (FRReadByte may have used D)
        CMPD    FRPos        ; how far is there left to go?
        BLS     FRS_Done     ; reached (or passed) the target
        LBSR    FRReadByte   ; read-and-discard to advance FRPos
        TST     FRStatus     ; did that read hit EOF?
        BNE     FRS_Done     ; stop early on EOF
        BRA     FRS_Loop     ; otherwise keep advancing
FRS_Done
        PULS    A,B,X        ; restore for the caller
        RTS
