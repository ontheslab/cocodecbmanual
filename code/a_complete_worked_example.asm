OPENFILE_VEC    EQU     $C48D                           ; OPEN DISK FILE
CONSOLEIN_VEC   EQU     $C5C4                           ; DISK CONSOLE IN (read one byte)
CLOSEALL_VEC    EQU     $CAE9                           ; close the open file - see FRClose above
CHROUT_VEC      EQU     $A002                           ; CONSOLE OUT (write one byte, via DEVNUM)
CINBFL          EQU     $0070                           ; nonzero after DISK CONSOLE IN means EOF
DNAMBF          EQU     $094C                           ; 8-byte filename buffer
DEXTBF          EQU     $0954                           ; 3-byte extension buffer
DFLTYP          EQU     $0957                           ; file type - 1 = DATA
DASCFL          EQU     $0958                           ; ASCII flag - 0 = binary
DFFLEN          EQU     $097C                           ; record length
DEVNUM          EQU     $006F                           ; current I/O device

TESTLEN         EQU     8                               ; how many test bytes to round-trip
TestBytes       FCB     $00,$FF,$0D,$0A,$41,$7E,$01,$80 ; deliberately includes $00/$FF/CR/LF
ReadBack        RMB     TESTLEN                         ; bytes read back land here
Fn_Name8        FCC     "TESTWRIT"                      ; 8-byte filename
Fn_Ext3         FCC     "DAT"                           ; 3-byte extension

WorkedExample                                           ; call this with JSR/LBSR - it ends in an RTS below
        ; - open TESTWRIT.DAT for OUTPUT -
        LDX     #DNAMBF                                 ; destination: the DECB filename buffer
        LDU     #Fn_Name8                               ; source: this program's own filename literal
        LDB     #8                                      ; copy all 8 name bytes
CopyName1
        LDA     ,U+                                     ; read one byte from Fn_Name8, advance U
        STA     ,X+                                     ; write it into DNAMBF, advance X
        DECB                                            ; one fewer byte left
        BNE     CopyName1                               ; loop until all 8 bytes are copied
        LDX     #DEXTBF                                 ; destination: the DECB extension buffer
        LDU     #Fn_Ext3                                ; source: this program's own extension literal
        LDB     #3                                      ; copy all 3 extension bytes
CopyExt1
        LDA     ,U+                                     ; read one byte from Fn_Ext3
        STA     ,X+                                     ; write it into DEXTBF
        DECB                                            ; one fewer byte left
        BNE     CopyExt1                                ; loop until all 3 bytes are copied
        LDA     #1                                      ; DFLTYP: 1 = DATA file
        STA     DFLTYP
        CLR     DASCFL                                  ; 0 = binary, not ASCII/crunched
        LDD     #$00FF                                  ; matches BASIC's own OPEN default
        STD     DFFLEN
        LDA     #1                                      ; file number 1
        STA     DEVNUM                                  ; scope DEVNUM tightly around the call
        LDA     #'O                                     ; mode = OUTPUT
        LDB     #1                                      ; file number 1 (ACCB, per the calling convention)
        JSR     OPENFILE_VEC                            ; the ROM call
        CLR     DEVNUM                                  ; back to the screen immediately

        ; - write 8 known bytes, including non-ASCII values -
        LDX     #TestBytes                              ; X walks through the bytes to be written
        LDB     #TESTLEN                                ; 8 bytes to write
WriteLoop
        PSHS    B,X                                     ; protect the loop counter/pointer across the call
        LDA     ,X                                      ; fetch the next byte to write (X not advanced yet)
        LDB     #1                                      ; file number 1
        STB     DEVNUM                                  ; select the open output file
        JSR     [CHROUT_VEC]                            ; indirect call - CHROUT_VEC holds a vector address
        CLR     DEVNUM                                  ; back to the screen immediately
        PULS    B,X                                     ; recover the loop counter and pointer
        LEAX    1,X                                     ; now advance the pointer - one byte written
        DECB                                            ; one fewer byte left
        BNE     WriteLoop                               ; loop until all 8 bytes are written

        ; - close it (the safe close - see FRClose above) -
        JSR     CLOSEALL_VEC

        ; - reopen the SAME name for INPUT -
        ; (DNAMBF/DEXTBF/DFLTYP/DASCFL/DFFLEN still hold the values set
        ; above - only the mode byte changes)
        LDA     #1
        STA     DEVNUM
        LDA     #'I                                     ; mode = INPUT
        LDB     #1                                      ; file number 1
        JSR     OPENFILE_VEC
        CLR     DEVNUM

        ; - read the same 8 bytes back -
        LDX     #ReadBack                               ; X walks through where each byte read gets stored
        LDB     #TESTLEN                                ; 8 bytes to read
ReadLoop
        PSHS    B,X                                     ; protect the loop counter/pointer across the call
        LDA     #1                                      ; file number 1
        STA     DEVNUM                                  ; select the open file for this one call
        JSR     CONSOLEIN_VEC                           ; byte comes back in A
        CLR     DEVNUM                                  ; back to the screen before anything else
        PULS    B,X                                     ; recover the loop counter and pointer
        TST     CINBFL                                  ; check EOF BEFORE trusting A as real data -
        BNE     EarlyEOF                                ; a short file must fail here, not compare garbage
        STA     ,X+                                     ; store the byte just read, advance X
        DECB                                            ; one fewer byte left
        BNE     ReadLoop                                ; loop until all 8 bytes are read back

        ; - confirm there's nothing MORE in the file than expected -
        LDA     #1
        STA     DEVNUM                                  ; select the open file for this one call
        JSR     CONSOLEIN_VEC                           ; try to read one more byte
        CLR     DEVNUM                                  ; back to the screen immediately
        TST     CINBFL                                  ; 0 here would mean a 9th real byte existed
        BEQ     TooMuch                                 ; file was longer than expected - its own failure

        ; - compare the 8 bytes read back against the 8 bytes written -
        LDX     #TestBytes
        LDU     #ReadBack
        LDB     #TESTLEN
CompareLoop
        LDA     ,X+                                     ; the byte that was written
        CMPA    ,U+                                     ; against the byte read back
        BNE     Mismatch
        DECB
        BNE     CompareLoop
        LDX     #PassMsg                                ; every byte matched, and EOF landed
        BRA     PrintResult
Mismatch
        LDX     #FailMsg
        BRA     PrintResult
TooMuch
        LDX     #TooMuchMsg
        BRA     PrintResult
EarlyEOF
        LDX     #EarlyEOFMsg
PrintResult
        LDA     ,X+                                     ; walk the chosen message and print it
        BEQ     ResultDone                              ; FCB 0 marks the end, as with the messages above
        JSR     [CHROUT_VEC]
        BRA     PrintResult
ResultDone
        JSR     CLOSEALL_VEC                            ; done - close the file again
        RTS                                             ; return to whatever called this block - see below

PassMsg         FCC     "PASS - ALL 8 BYTES MATCHED, EOF WHERE EXPECTED"
                FCB     0
FailMsg         FCC     "FAIL - A BYTE READ BACK DID NOT MATCH"
                FCB     0
TooMuchMsg      FCC     "FAIL - FILE HAD MORE DATA THAN EXPECTED"
                FCB     0
EarlyEOFMsg     FCC     "FAIL - FILE HAD FEWER BYTES THAN EXPECTED"
                FCB     0
