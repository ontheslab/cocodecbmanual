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
