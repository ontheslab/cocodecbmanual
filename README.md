# CoCo Disk File I/O via DECB ROM Calls - A Practical Manual

## Forward

Every routine address here, and the end-of-file flag `DISK CONSOLE IN` uses, has been checked directly against real ROM bytes. The compatibility results further down come from runs on real hardware and emulators. See "Compatibility notes" below for exactly what was tested and what wasn't.

This has been checked as described above; it isn't a guarantee that every possible address or behaviour has been verified.

Every routine below is documented three ways:

- **Pseudocode** - the shape of what it does, independent of 6809 register-allocation detail.
- **Functional description** - inputs, outputs, side effects, clobbered registers, and error behaviour: the things you'd want to know before calling it without reading its body.
- **Annotated 6809 code** - the routine itself, with a comment on every non-obvious line.

This manual is written for someone who already uses a CoCo and DECB, but may be new to 6809 assembly. It explains the assembly ideas it needs - registers, addressing modes, the calling convention - as it goes. It doesn't explain what DECB is, or how to use a CoCo.

It covers one interface, end to end: DECB 1.1's ROM-callable disk routines. It isn't a 6809 tutorial, and it isn't a survey of every way to do disk I/O on a CoCo. "Why ROM calls, not raw hardware" below compares the three options.

None of this claims that ROM calls are the best or the only way to do disk I/O on a CoCo, or that these routines are the most efficient way to use them. They're one working, tested set, documented accurately as I can. Treat them as a reference or a starting point rather than the last word.

**FINAL** - written 2026-08-28. The routines and examples here are drawn from the disk layer of the Beatle Quest CoCo port, a text adventure taken to six different machines. The write-up of that work is listed under References.

Copyright (c) 2026 Intangybles (Mark Casteleijn). All rights reserved.

## Table of contents

- [**Prerequisites**](#prerequisites) - what you need running before any of this does anything: a real disk drive or modern equivalent, DECB itself, and a 6809 assembler.
- [**Why ROM calls, not raw hardware**](#why-rom-calls-not-raw-hardware) - the three ways to do CoCo disk I/O, and why this manual targets the one that doesn't depend on how a particular storage system implements the layers underneath.
- [**Compatibility notes**](#compatibility-notes) - what's confirmed working (and not yet working) across CoCoSDC, FujiNet, and emulators.
- [**Core concepts**](#core-concepts) - the global-RAM-variable calling convention, `DEVNUM` and why it must be scoped tightly, choosing a file number, and DECB's abort-to-BASIC-on-error behaviour.
- [**A quick 6809 assembly primer, for readers new to it**](#a-quick-6809-assembly-primer-for-readers-new-to-it) - what the registers, PSHS/PULS, JSR/RTS and the addressing modes in this manual mean. Enough to read the annotated code below without having written 6809 assembly before.
- [**Which assembler these examples use**](#which-assembler-these-examples-use) - the exact toolchain and invocation behind every listing, and what's worth double-checking if you're using a different one.
- [**Quick reference**](#quick-reference) - the ROM entry points and RAM variables used by these wrappers, with their addresses and purposes.
- [**Function reference**](#function-reference) - every routine (`FROpen`/`FROpenWrite`, `FRReadByte`, `FRWriteByte`, `FRClose`, `FRExists`, `FRSeek`), each with pseudocode, a full functional description, and annotated real code.
- [**A complete worked example: write, close, reopen, read back**](#a-complete-worked-example-write-close-reopen-read-back) - all the above chained together in one runnable, probe-derived listing.
- [**Verifying against a different ROM revision**](#verifying-against-a-different-rom-revision) - why the addresses in this manual are DECB-1.1-specific, and how to re-confirm them for a different one, including how to use a live debugger to do it.
- [**Glossary**](#glossary) - plain-English definitions for every technical term used above.
- [**Appendix A: a complete, ready-to-assemble listing**](#appendix-a-a-complete-ready-to-assemble-listing) - all seven entry points (across six function-reference sections) and their constants gathered into one self-contained file.
- [**Appendix B: DECB disk error codes**](#appendix-b-decb-disk-error-codes) - DECB-specific disk errors and selected BASIC errors relevant to disk operations, what triggers each one, and whether it can reach the routines this manual documents.
- [**Using these routines in your own program**](#using-these-routines-in-your-own-program) - the full practical walkthrough. Filenames, drives and file numbers explained, copying the code in, and the rules about when each routine may be called. Then a before-and-after example that turns a simple screen-printing program into a file-reading one, creating the input file, building a disk image with decb, and running it on a real or emulated CoCo.
- [**Troubleshooting**](#troubleshooting) - the checks worth doing first when something doesn't work, before assuming a deeper explanation elsewhere in this manual is the problem.
- [**References**](#references) - the book, web sources, and tools this manual draws on.
- [**About this copy**](#about-this-copy) - the PDF release, and the code listings that ship beside the manual.

## Prerequisites

You need a disk drive running Disk Extended Color BASIC (DECB) before any of this does anything at all. A modern equivalent is fine: a CoCoSDC, a FujiNet, or an emulator with virtual disk support.

Most of the routines below live only in the Disk BASIC ROM pack, not in plain Color BASIC. That includes the disk-file entry points `OPEN DISK FILE`, `DISK CONSOLE IN`, `SEARCH DIRECTORY` and the close routines. The one exception in this manual is `CHROUT_VEC` (`$A002`), for screen output, which plain Color BASIC has as well.

You also need a 6809 cross-assembler on your development machine, and a way to get the assembled binary onto something the CoCo (or emulator) can load from. "Which assembler these examples use" below covers the assembler.

**In a hurry?** If you would rather see a complete, working program before reading how any of it works, start at "Using these routines in your own program".

It's written to stand on its own - filenames, building a disk image, running it, and what to check if it doesn't work - and it links back to the sections above wherever it relies on them.

## Why ROM calls, not raw hardware

There are three ways to do disk I/O on a Color Computer from your own assembly program:

1. Drive the WD1793 floppy controller chip directly. Its control latch sits at `$FF40`, and the controller's own command, status and data registers at `$FF48` and up. This is fast, and it's what many hobbyist 6809 tutorials show. It also bypasses DECB completely and talks to the floppy controller itself, or to a faithful emulation of one. That means it bypasses whatever a particular storage device does to stay compatible higher up, so it's the option most likely to behave differently from one piece of hardware to the next.
1. Call `DSKCON`, the documented low-level ROM disk vector. This looks like the "proper" documented way, and it genuinely is a real, sanctioned entry point. But storage systems handle it differently inside. HDB-DOS, for one, patches `DSKCON` itself so that it jumps into HDB-DOS's own storage-dispatch code rather than the original floppy-driving routine. So relying on undocumented details of what happens after you call it may still be risky.
1. Call the same machine-language-callable file routines that BASIC's own `OPEN`, `GET#`, `PUT#` and `CLOSE` statements use. This is what this manual covers. At this level you're using the interface DECB itself uses, rather than depending on how a particular storage system implements the layers underneath. This was confirmed by testing on the Beatle Quest CoCo port's own hardware and storage setups - "Compatibility notes" says exactly what was and wasn't tested.

If you want one program that runs on more than one storage setup without separate code for each, this is the layer to aim at. It's also less code than options 1 or 2, because DECB's own open, read and write machinery already handles directory scanning, FAT-chain walking and multi-sector management.

## Compatibility notes

This is what has been confirmed, from the Beatle Quest CoCo port's own testing. It isn't a claim that it works everywhere.

On a real CoCo 3 with a CoCoSDC card, a full playthrough and both SAVE and LOAD are confirmed working. The same holds on VCC and on XRoar, using either native disk or CoCoSDC emulation.

On the FujiNet PC emulator, a SAVE was confirmed to write through the real DriveWire protocol: the write-protocol log showed the data arriving, rather than the call quietly doing nothing.

On real FujiNet hardware, reading is confirmed working. Writing (SAVE) hasn't been separately confirmed working on real FujiNet hardware yet, so test it on your own hardware before relying on it. A real floppy drive or CoCoSDC isn't affected either way.

## Core concepts

The filename and the file parameters go in global RAM variables, not registers. You fill in a handful of fixed RAM addresses, then call a fixed ROM address with only a couple of registers set - usually a mode byte and a file number.

This is a long way from a modern calling convention, and it's the biggest adjustment if you're used to passing everything in registers, or through a pointer to a parameter block.

**This assumes the 6809's direct page register (DP) is still $00.**

`DEVNUM`, `CINBFL` and the other low-RAM variables this manual uses are all reached by direct-page addressing inside the ROM. That takes the high byte of the address from `DP` rather than from the instruction itself, so `DP=$00` is what makes `$006F` and `$0070` resolve correctly.

A normal BASIC program never changes `DP`, so routines called from code `EXEC`'d out of BASIC just work without your having to think about it. But if your own code sets `DP` to something else - or anything else in the same program does - set it back to `$00` before calling any of these routines.

`DEVNUM` (`$006F`) is the global "currently selected I/O device". Every routine in this manual reads it to know which file, or the screen, it's talking to. It's also what BASIC's own screen print dispatcher consults, including `CHROUT_VEC` (`$A002`) - the vector your own on-screen text almost certainly goes through already.

So if you leave `DEVNUM` set to a file number and then print something of your own, your text goes to the file (or nowhere) instead of the screen, with no error to tell you.

Keep every write to `DEVNUM` as tight as you can: set it immediately before the one ROM call that needs it, and clear it back to 0 immediately afterwards, before doing anything else - including printing your own error or status messages.

File number 1 is the simplest choice if you only ever need one file open at a time. Nothing in this manual requires it, but every example uses it. That matches the Beatle Quest CoCo port's own engine, which this manual is drawn from, and which never has more than one file open at once.

None of the routines in this manual let you ask for a drive - though some of them can still overwrite `DCDRV`.

DECB keeps the selected drive in a separate variable of its own, `DCDRV` (`$00EB`), and none of `FROpen`, `FROpenWrite` or `FRExists` take a drive number. Opening or searching for a file uses whatever drive was left selected by whatever ran before your program, which isn't necessarily drive 0.

A file number and a drive number are different things. The file number says which open file you mean; the drive number says which physical or virtual disk a filename is looked up on.

If your program needs to guarantee a specific drive, set `DCDRV` yourself immediately before calling `FRExists` - it has no implicit-close behaviour of its own, so there's nothing to catch you out there.

`FROpen` and `FROpenWrite` are the tricky ones. If a file is already open, they close it first (see Side effects in the Function reference below). DECB's own close routine writes the drive number of the file it closed back into `DCDRV` - the ROM disassembly shows this plainly: `LDB FCBDRV,X` / `STB DCDRV`. That close runs *inside* the call, before the open does. So if you set `DCDRV` and then call `FROpen` or `FROpenWrite`, the close can overwrite your drive number, and nothing tells you it happened. Setting `DCDRV` immediately before the call doesn't help, because the close still comes after you set it.

The only sequence that works with the current wrappers is: close first yourself, set `DCDRV`, then open -

```asm
        LBSR    FRClose      ; closes whatever was open first - accept that this
                             ; also closes any other file DECB has open
        CLR     DCDRV        ; NOW select drive 0 - after the close, not before
        LDX     #Fn_Buffer
        LBSR    FROpen       ; FRIsOpen is now clear, so no second internal close happens
```

If `FRIsOpen` is already clear then nothing was open to begin with, so the explicit `FRClose` isn't needed - just set `DCDRV` and open.

Sticking to one drive is a reasonable alternative to all of this. But that means setting `DCDRV` once at program start and never touching it again - not simply never intending to switch drives while `DCDRV` holds whatever the previous program left in it. If you take that route, document the restriction rather than writing drive-switching code you don't need.

**Errors mostly don't come back to you.** `OPEN DISK FILE`'s documented behaviour on any error - file not found, disk full, anything at all - is to jump straight into BASIC's own error handler and print a real `?XX ERROR`, not to return to your code with a status flag.

If you need to handle "file doesn't exist" gracefully - the commonest case by far, a first run with no save file yet, or an optional script file that may not be on the disk - check first with `SEARCH DIRECTORY`, covered below. It does *not* abort just because the filename is missing.

It can still reach BASIC's error handler on a genuine disk problem, though, because it calls the same lower-level sector-read code `OPEN` does.

**Can a disk-full or write-protect error be caught instead of aborting?** Not with these wrappers as they stand. The error appendix below lists every error DECB can raise, and they all end in the same place: the base ROM's error entry, reached through `$0191`, the "ERROR DRIVER" hook in RAM. DECB points that hook at `$C265` when it starts up, as `FRClose` below explains.

You could point that hook at your own code instead, and catch errors before BASIC sees them. Three things make that harder than it sounds:

- `$0191` holds a `JMP` instruction and its target address, so it's three bytes of *executable* code rather than one address you can overwrite.
- Your handler must follow `$C265`'s own calling convention, which is the `PULS Y` contract `FRClose` describes.
- It has to tidy up whatever DECB was left part-way through, then put the original hook back.

**None of that is written or tested here.** *Treat recovering cleanly from a full or write-protected disk as a project of its own, not something these routines give you.*

## A quick 6809 assembly primer, for readers new to it

If you're already comfortable with 6809 assembly, skip this section. It's here so that someone who knows what they want to do - call these routines - but hasn't written 6809 code before isn't stopped by the annotated listings further down.

**Registers** are small pieces of storage built into the CPU itself, much faster than RAM. The 6809 has:

- `A` and `B` - two 8-bit (one-byte) general-purpose registers. They can also be used together as one 16-bit (two-byte) register called `D` (`A` is the high byte, `B` is the low byte).
- `X`, `Y`, and `U` - three 16-bit registers, normally used to hold a memory address (a pointer), the same idea as a pointer variable in a higher-level language.
- `S` - the hardware stack pointer. You don't usually touch it directly; `PSHS`/`PULS`/`JSR`/`RTS` all use it behind the scenes (see below).

**Instructions used throughout this manual:**

- `LDA`/`LDB`/`LDD`/`LDX`/`LDY`/`LDU` - "load": copy a value into that register. `LDA #1` loads the literal number 1 into `A`. The `#` means use the value of the expression itself, rather than reading whatever it points at. For a label like `DNAMBF`, that value is the label's address, so `LDX #DNAMBF` loads the address of `DNAMBF` into `X` - it doesn't read the buffer.
- `STA`**/**`STB`**/**`STD`**/**`STX`**/**`STY`**/**`STU` - "store": the opposite of load - copy a register's value out into a memory address. `STA DEVNUM` writes `A`'s current value into the `DEVNUM` memory location.
- `CLR` - set a memory location (or register) to zero. `CLR DEVNUM` is shorthand for "store 0 into `DEVNUM`".
- `TST` - check whether a value is zero, without changing it, and record the answer so the next branch instruction (`BEQ`/`BNE`/below) can act on it.
- `CMPD` - compare `D` against a value, again just to set up the next branch instruction.
- `BEQ` ("branch if equal"), `BNE` ("branch if not equal"), `BHS` ("branch if higher or same"), `BLS` ("branch if lower or same") and `BRA` ("branch always") jump to a different label in the code, based on the result of the most recent `TST`, `CMPD` and so on. This is a 6809 *if* or *goto*, not a function call: nothing is pushed anywhere, and there's nothing to return from.
- `JSR` ("jump to subroutine") and `RTS` ("return from subroutine") are a real function call and return, the same idea as calling a function in any other language. `JSR` remembers where it was called from by pushing that address onto the stack, and `RTS` reads the address back and jumps to it. `LBSR` and `BSR` are the same thing under another name - long and short branch-to-subroutine. The difference is how far away the target may be, not what they do. `JSR [CHROUT_VEC]`, with square brackets, means "read a 16-bit address stored at `CHROUT_VEC`, and call that address". That's one more level of indirection, the same idea as calling through a function pointer.
- `PSHS`/`PULS` ("push" and "pull", both on and off the `S` stack) save a list of registers so they can be used and changed safely, then restore them afterwards. `PSHS A,B,X,Y,U` at the top of a routine and `PULS A,B,X,Y,U` at the bottom is how a routine promises its caller that every register comes back unchanged, even though it overwrites them freely in between.
- `LEAX`/`LEAY` ("load effective address") work out an address from the expression given and write the result into the register named in the mnemonic: `LEAX` always writes `X`, `LEAY` always writes `Y`. The destination register doesn't have to be the one used inside the expression. When it is, as in `LEAY -1,Y` ("work out Y minus 1, and store the result back in Y"), the effect is a decrement: `Y` goes down by one. Unlike most uses of the 6809's addressing modes, `LEAX`/`LEAY` also update the `Z` condition code from the result. That's what lets the `BNE` straight afterwards ask "did this reach zero?" without a separate compare. This manual uses `LEAY -1,Y` as a loop counter throughout.
- `EQU` gives a name to a fixed number, usually a memory address, so the code can say `DEVNUM` instead of `$006F` everywhere. It reserves no memory of its own. It's a label for an address that already means something, either a fixed ROM address or a RAM location the code will use.
- `RMB` ("reserve memory bytes") - the opposite of `EQU`: this actually sets aside a block of RAM of the given size, for the assembler to hand out an address for. `FOC_SaveX RMB 2` reserves two bytes and calls that location `FOC_SaveX`.
- `FCB`**/**`FCC` - write fixed byte values (`FCB`, "form constant byte") or fixed text (`FCC`, "form constant characters") directly into the program, at assembly time. `Fn_Name8 FCC "TESTWRIT"` places those eight characters in memory under the label `Fn_Name8`.

**Addressing modes seen in the annotated code:**

- `#1` - the literal number 1 itself.
- `DEVNUM` (no `#`) - the *value stored at* the address `DEVNUM`.
- `#DNAMBF` - the *address of* `DNAMBF`, not its contents.
- `,X+` - use the address currently in `X`, then increment `X` by one afterwards (handy for walking through a buffer one byte at a time).
- `-1,Y` is an indexed address: "the address one byte before wherever `Y` currently points". Unlike `,X+` above, it has no side effect of its own - referring to `-1,Y` in most instructions, a `CMPD -1,Y` say, doesn't change `Y`. `LEAY -1,Y` is the exception, and only because `LEAY` writes its computed address back into `Y` - the destination is part of the instruction. See `LEAX`/`LEAY` above.

**Comments**: a semicolon (`;`) starts a comment that runs to the end of the line, exactly like `//` in C or `#` in Python. Everything after is for the human reader only and has no effect on the program.

With that, every annotated listing below should read roughly like a short recipe: load an address, store it somewhere ROM expects it, call a fixed ROM address, check the result.

## Which assembler these examples use

Every listing in this manual is written for **lwasm**, part of the open-source lwtools 6809/6309 cross-assembler toolchain, invoked as:

```text
lwasm -9b -o OUTPUT.bin SOURCE.asm
```

`-9b` targets the plain 6809 rather than the 6309, and produces a DECB-loadable machine-language binary - the same file format BASIC's own `LOADM` and `SAVEM` commands use - rather than a raw memory dump or a linkable object file. This is the exact toolchain and flag the Beatle Quest CoCo port builds with.

**Conventions used here, mostly standard but worth naming explicitly:**

- `;` starts a trailing comment anywhere on a line. A `*` in column 1 also works as a full comment line in lwasm (and is what the Beatle Quest CoCo port uses for file-header comment blocks), but every example *in* *this manual* sticks to `;` throughout, for one consistent look.
- `[EXPR]`, square brackets around an address or label, is indirect addressing: "the address stored at `EXPR`", not `EXPR` itself. `FRWriteByte`'s `JSR [CHROUT_VEC]` uses it, as do the before-and-after programs and the worked example further down. Most other Motorola-syntax 6809 assemblers, such as `asm6809` and `os9asm`, support the same bracket notation. If you're using something older, or something with a DOS-toolchain heritage, check its manual for how it spells indirect addressing before assuming the brackets will work.
- `EQU`**,** `RMB`**,** `FCB`**,** `FCC`**,** `ORG`**,** and `END` are standard Motorola-syntax assembler directives with the same meaning across essentially every 6809 assembler in common use. If your assembler calls one of these something slightly different, it almost certainly has an equivalent - check its directive reference.

These listings were tested with `lwasm`. If you're assembling with something else, check three things before assuming a listing will assemble and load unchanged: its comment style, how it writes indirect addressing, and its settings for DECB binary output.

## Quick reference

### All addresses below are for DECB 1.1 ROM.

The entry points and the fixed RAM-variable addresses were checked directly against a live DECB 1.1 ROM image, byte by byte, rather than taken from a book. A program built on them has also been run successfully on both VCC and FujiNet hardware.

That run exercises the whole table together, though. It doesn't pin down each individual address on its own. If you're targeting a different ROM revision, check them again - see "Verifying against a different ROM revision" at the end.

| Name | Address | Purpose |
|---|---|---|
| `OPENFILE_VEC` | `$C48D` | OPEN DISK FILE |
| `CONSOLEIN_VEC` | `$C5C4` | DISK CONSOLE IN (read one byte) |
| `SEARCHDIR_VEC` | `$C68C` | SEARCH DIRECTORY (safe existence check) |
| `CLOSEALL_VEC` | `$CAE9` | close every open file (see `FRClose` below - don't use `$0191`) |
| `CHROUT_VEC` | `$A002` | CONSOLE OUT (write one byte, via `DEVNUM`) |
| `DNAMBF` | `$094C` (8 bytes) | filename (space-padded, no dot) |
| `DEXTBF` | `$0954` (3 bytes) | extension (space-padded) |
| `DFLTYP` | `$0957` (1 byte) | file type - use `1` (DATA) |
| `DASCFL` | `$0958` (1 byte) | ASCII flag - use `0` (binary) |
| `DFFLEN` | `$097C` (2 bytes) | record length - use `$00FF`, matching BASIC's own default (see note below) |
| `DEVNUM` | `$006F` (1 byte) | current I/O device - scope tightly, see above |
| `DCDRV` | `$00EB` (1 byte) | current drive - set it yourself to choose one, after any close (see Core concepts) |
| `CINBFL` | `$0070` (1 byte) | nonzero after DISK CONSOLE IN means end-of-file |
| `V973` | `$0973` (1 byte) | SEARCH DIRECTORY's own "found?" flag |

`DFFLEN` ("record length") is a DECB idea for random-access files, used with BASIC's own `FIELD`, `PUT` and `GET` statements - a way of dividing a file into fixed-size records.

These wrappers use sequential input and output instead. `DFFLEN` doesn't set their byte-read or byte-write size, and the sequential open path they use neither checks nor depends on its value.

They do initialise it to `$00FF`, following BASIC's own default setup. Leave that initialisation as supplied.

## Function reference

Every routine here is written the way the Beatle Quest CoCo port's own engine implements it.

Most of them preserve every register from the caller's point of view: whatever the routine uses is `PSHS`'d and `PULS`'d around the body. You can call them from the middle of other code and worry only about the documented outputs.

`FRClose` and `FROpen`/`FROpenWrite` are the two exceptions. Each one's own Registers note below says what isn't preserved, and why.

#### `FROpen` / `FROpenWrite` - open a file for input or output

**Pseudocode**

```text
function FROpen(filenamePtr):
    return FROpenCommon(filenamePtr, mode = 'I')

function FROpenWrite(filenamePtr):
    return FROpenCommon(filenamePtr, mode = 'O')

function FROpenCommon(filenamePtr, mode):
    if a file is already known to be open:
        FRClose()                      # never leave two files open at once
    copy filenamePtr[0..7]  -> DNAMBF  # 8-byte name
    copy filenamePtr[8..10] -> DEXTBF  # 3-byte extension
    DFLTYP <- 1                        # DATA file
    DASCFL <- 0                        # binary, not ASCII/crunched
    DFFLEN <- $00FF                    # matches BASIC's own OPEN default
    FRPos  <- 0                        # this module's own byte-position tracker
    DEVNUM <- 1
    call OPEN DISK FILE (A = mode, B = 1)
    DEVNUM <- 0
    FRStatus <- 0
    FRIsOpen <- true
    return
```

**Functional description**

**In plain terms:** hand this routine a filename and it opens that file, ready to read from (`FROpen`) or write to (`FROpenWrite`). If something else was already open, it's closed first, so you never have to remember to close the previous file yourself.

- **Input:** `X` points at an 11-byte, space-padded filename buffer - 8 bytes of name and 3 of extension, with no dot stored anywhere. You don't set the mode. `FROpen` and `FROpenWrite` are the two public entry points, and each hard-codes its own mode before falling into the shared body.
- **Output:** `FRStatus` is 0 on success, `FRPos` is reset to 0, and `FRIsOpen` is set nonzero. `OPEN DISK FILE`'s own documented behaviour is to abort straight to BASIC's error handler on any failure, rather than return. So if your code carries on at all after this call, the open already succeeded.
- **Side effects:** if a file is already open - tracked through `FRIsOpen` - it's closed first, through `FRClose` below. Real DECB rejects a second `OPEN` on an already-open file number with a real `?AO ERROR`. The filename is also copied into `FRFilename`, an 11-byte scratch copy owned by this module, so that `FRSeek` can reopen the same file later without the caller having to remember the name.
- **Registers:** `B`, `X`, `Y` and `U` are preserved. `A` isn't, despite appearances. `FROpen` and `FROpenWrite` load `A` with the mode character, `'I'` or `'O'`, before falling into the shared body, and it's that value the routine saves and restores - not whatever `A` held when your code made the call. Treat `A` as gone.
- **Gotcha:** zero `FRIsOpen` yourself once, at program start, before the first call. `RMB`-reserved variables aren't zero-filled by `LOADM`, so an uninitialised `FRIsOpen` can read as nonzero by chance and trigger an unnecessary `FRClose` on the very first open. That isn't unsafe in itself - see the `FRClose` note on calling it with nothing open. But `FRClose` closes every file DECB has open, not only this module's, so an unplanned call could close a file that another part of your program, or BASIC itself, is still using.

**Annotated code**

```asm
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
```

#### `FRReadByte` - read one byte, advance position, detect EOF

**Pseudocode**

```text
function FRReadByte():
    DEVNUM <- 1
    byte <- call DISK CONSOLE IN
    DEVNUM <- 0
    if CINBFL != 0:
        FRStatus <- EOF
        return                  # byte value on EOF is not meaningful
    FRStatus <- OK
    FRPos <- FRPos + 1
    return byte
```

**Functional description**

In plain terms: call this once per byte you want to read from the currently open file. It hands back one byte at a time and tells you, via `FRStatus`, when there's nothing left to read.

- **Input:** none. It does require a file already opened for input by `FROpen` - not `FROpenWrite`, since reading from a file opened for output isn't a supported DECB operation.
- **Output**: the byte read, in `A`. `FRStatus` is `0` on a normal read, nonzero at end-of-file - check it after every call before trusting the byte in `A`.
- **Side effects**: advances the module's own `FRPos` byte counter by one on a successful read (not on EOF).
- **Registers**: `A` carries the return value on success; `B` is preserved.
- **Note:** `CINBFL` is the real DECB end-of-file flag that `DISK CONSOLE IN` sets itself. Using it directly is simpler and more reliable than working out how many bytes are left from the FCB yourself.

**Annotated code**

```asm
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
```

#### `FRWriteByte` - write one byte to the open output file

**Pseudocode**

```text
function FRWriteByte(byte):
    DEVNUM <- 1
    call CONSOLE OUT (byte)
    DEVNUM <- 0
```

**Functional description**

In plain terms: call this once per byte you want to write to the currently open output file. `CONSOLE OUT` is the same reliable routine BASIC itself uses for every character it ever prints.

- **Input**: `A` = the byte to write.
- **Output:** none. Reaching the next instruction after the call means the write succeeded. As with the other ROM calls in this manual, a genuine failure - a full disk, say - is expected to abort straight to BASIC's own error handler rather than return a status flag. That particular failure path wasn't separately exercised during testing, but there's no reason to expect `CONSOLE OUT` to differ from `OPEN DISK FILE` or `SEARCH DIRECTORY` here.
- **Side effects:** none beyond the write itself. Unlike `FRReadByte`, this module keeps no separate write position: `FRSeek` and `FRPos` are only meaningful for reading.
- **Registers**: `A` preserved; `B` used and restored.
- **Binary safety, confirmed by direct testing:** `CONSOLE OUT` is the same routine BASIC's `PRINT` statement uses to put a character on the screen. It's only writing to a file here because `DEVNUM` is pointed at one. `$00`, `$FF`, and the byte values that would be CR and LF if this were text (`$0D` and `$0A`) were all confirmed to survive a write-then-read-back cycle byte for byte, with no translation applied.

**Annotated code**

```asm
FRWriteByte
        PSHS    B            ; preserve B for the caller
        LDB     #1           ; file number 1
        STB     DEVNUM       ; select the open output file
        JSR     [CHROUT_VEC] ; indirect call - CHROUT_VEC holds a
                             ; vector address, not code, at $A002
        CLR     DEVNUM       ; back to the screen immediately
        PULS    B            ; restore B
        RTS                  ; A (the byte written) is left unchanged
```

#### `FRClose` - close the currently open file

Call `FRClose` to finish file access. It calls DECB 1.1's close-all routine, `CLOSEALL_VEC` (`$CAE9`) - not `$0191`, a nearby RAM address that looks similar but is a different hook altogether. The optional project note below has the full story of how that was confirmed.

**Pseudocode**

```text
function FRClose():
    call CLOSEALL_VEC            # $CAE9 - NOT $0191, see below
    FRIsOpen <- false
```

**Functional description**

**In plain terms:** call this to close whatever file is currently open. It's a single call, with no filename or file number to pass in.

- **Input**: none.
- **Output**: none.
- **Side effects:** it clears `FRIsOpen` and closes every file DECB currently has open, not only this module's - see the note below. It also sets `DCDRV` back to whichever drive the file being closed was on, so select the drive you want again afterwards if the next operation needs a particular one. See Core concepts above. It's safe to call even when nothing is open at all.
- **Registers:** not preserved. `FRClose` clobbers whatever `CLOSEALL_VEC` clobbers, which is at least `A`, `B` and `X`. Treat every register as gone after calling it, or wrap the call yourself if you need one kept.
- **Note:** calling `$CAE9` when nothing is open is safe. The close-one-file subroutine it runs for each reserved slot checks the file's type byte first and returns straight away if that slot is already closed. `FRIsOpen` still matters, but for a different reason: it's what `FROpenCommon` checks to decide whether to close an old file before opening a new one. You don't need it to protect a bare `FRClose` call.
- **Sharing files with other code:** `$CAE9`'s loop walks every reserved file buffer DECB knows about, not only the one this module opened. If other code in the same program, or the surrounding BASIC session, has its own file open, `FRClose` closes that too. This is the correct, by-design behaviour of "close all files", not a bug. It's worth knowing before reaching for `FRClose` in a program that shares file access with other code.

**Annotated code**

```asm
CLOSEALL_VEC    EQU     $CAE9 ; NOT $0191 - see above

FRClose
        JSR     CLOSEALL_VEC  ; no DEVNUM setup needed - this routine
                              ; sets DEVNUM itself, once per open file,
                              ; as part of its own internal loop
        CLR     FRIsOpen      ; record that nothing is open any more
        RTS                   ; note: A/B/X are left clobbered - see the Registers note above
```

**Project note: verifying the close hook** (optional - the summary above is everything you need to call `FRClose` correctly)

DECB's RAM hook table has an entry at `$0173` (`RVEC7`) that BASIC calls to close all files. On DECB 1.1 that hook's stored jump target is `DVEC7 = $CAE9`.

This was confirmed two ways. Reading a booted, stock DECB 1.1 machine's real RAM at `$0173` found `7E CA E9` there, which is `JMP $CAE9`. Disassembling `$CAE9` itself gave `LDB $095B` (extended - `FCBACT`) / `INCB` / `PSHS B` / `STB DEVNUM` / `BSR <close-one>` / `PULS B` / `DECB` / `BNE <loop>` / `RTS` - a loop over every reserved file buffer, which is "close all files" exactly.

`$0191` (RVEC17) is a different hook entirely, whose DECB 1.1 target is `DVEC17` = `$C265`. Its routine opens with a `PULS Y`, expecting its actual caller (BASIC's own error-handling flow) to have already pushed something onto the hardware stack. Calling it directly, with nothing pushed, corrupts the stack. It has nothing to do with closing files - it just sits near the close-file hooks in the same table. Always call `$CAE9`, never `$0191`.

#### `FRExists` - check whether a filename exists

**Pseudocode**

```text
function FRExists(filenamePtr):
    copy filenamePtr -> DNAMBF/DEXTBF
    call SEARCH DIRECTORY
    if V973 != 0:
        FRStatus <- FOUND (0)
    else:
        FRStatus <- NOT_FOUND (nonzero)
```

**Functional description**

**In plain terms:** call this to check whether a file exists before deciding whether to open it, without the program aborting back to BASIC just because the filename isn't there. It's the safe alternative to trying `FROpen` and hoping.

A real disk problem, as opposed to "file not found", can still hand control to BASIC. `SEARCH DIRECTORY` calls into DECB's own low-level sector-read code to do the lookup, and that deeper code has its own error handling. This routine's guarantee covers the missing-file case, not disk errors in general.

- **Input**: `X` -> an 11-byte space-padded filename, same format as `FROpen`.
- **Output**: `FRStatus` is `0` if the file exists, nonzero if not.
- **Why this exists:** `OPEN DISK FILE` aborts straight to BASIC on any error, including a plain "file not found". That's fine for a quick standalone probe, and wrong for a program's "no save file yet" or "optional script file not present" case - both are the normal outcome on a fresh disk, not an exceptional one. `SEARCH DIRECTORY` does the same directory lookup `OPEN` does internally, but reports a missing file in a plain flag instead of aborting. Its own disassembly confirms this: `CLR V973` ... `TST V973`, a flag set and tested, with no jump to an error handler around that comparison. It still calls into DECB's sector-read code to do the lookup, though, and that code has its own error handling. A real disk problem - no media, a genuine read error - can still hand control to BASIC, exactly as it could from any other disk call. The guarantee here is "a missing filename comes back as not-found rather than an abort", not "this call can never reach BASIC's error handler".
- **Registers**: `A`, `B`, `X`, `Y`, and `U` are preserved on a normal return. Condition codes aren't part of that guarantee.
- **Usage pattern:** call this before `FROpen` whenever "the file might not exist, and that is fine" is a possibility, and only call `FROpen` once you know the file is there. The exception is opening for output, where "doesn't exist yet" is the normal case. DECB's own open-for-output logic handles it internally, deciding on its own whether to overwrite in place or allocate new.

**Annotated code**

```asm
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
```

#### `FRSeek` - move to an absolute byte offset

**Pseudocode**

```text
function FRSeek(targetOffset):
    if targetOffset < FRPos:
        # can't rewind - reopen from scratch, which resets FRPos to 0
        FROpen(FRFilename)
    while FRPos < targetOffset:
        FRReadByte()
        if FRStatus != OK:
            break                # hit EOF before reaching the target
```

**Functional description**

**In plain terms:** call this to jump to a specific byte position in the currently open file, instead of reading byte by byte through everything in between yourself.

Internally it's still reading through the file for a forward seek, because DECB has no seek primitive. This routine just hides that behind one call.

- **Input**: `D` = the target absolute byte offset into the currently open file.
- **Output**: none directly; after return, `FRPos` equals `targetOffset` (or wherever EOF stopped it short).
- **Registers:** `A`, `B` and `X` are preserved, and since `D` is just `A` and `B` together, the offset you passed in comes back unchanged too. `Y` and `U` aren't touched at all.
- **Why there's no primitive for this:** DECB's ROM calls don't expose a general seek operation at all. You may not need one, though. If your file format's sections are laid out in a known, ascending order - true of most simple formats, and of the `.ADV` format the Beatle Quest CoCo port uses - track your own current byte position and build "seek" on top of what you already have:
  - [**Forward**](#forward): read and discard bytes one at a time via `FRReadByte` until reaching the target position.
  - **Backward**: there's no cheap way to rewind. Close the file, reopen it (which also resets `FRPos` to `0`), and seek forward from there.
- **Cost:** a forward seek reads through every byte in between, so its cost grows with the distance. That's fine for the small, structured seeks a section-based file format needs, and not something to use for a large scan.
- **Bounds:** `FRPos` and the seek target are both 16-bit, so this works correctly only for files and offsets under 65,536 bytes. Past that the position wraps back to 0 and later seeks will be wrong.
- These wrappers provide no file-size query either. For a file shorter than 65,536 bytes, read with `FRReadByte` until `FRStatus` reports end-of-file, then use `FRPos` as the byte count. That consumes the remaining input and leaves the file at end-of-file, so reopen it - or `FRSeek` back to 0 - before reading from the beginning again. Larger files need a wider counter, or a different approach based on metadata, outside this interface. DECB itself has other ways to learn a file's length, through directory and FAT metadata and BASIC's own `LOF`, but neither is exposed through these wrappers.
- **Seeking to where you already are does nothing.** If `targetOffset` already equals `FRPos`, `FRSeek` returns immediately without reading anything. That means `FRStatus` is left untouched, still holding whatever the previous call set it to - which may be a stale end-of-file or not-found result from an earlier operation. Don't read `FRStatus` after a seek that might not have moved anywhere and assume it reflects the seek.

**Annotated code**

```asm
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
```

## A complete worked example: write, close, reopen, read back

This is adapted directly from the Beatle Quest CoCo port's own write, close, reopen and read-back probe, confirmed as a byte-exact round trip on both real hardware and VCC.

It's the same operations as the function reference above, chained together as one flat, self-contained listing rather than through the `FR*` wrapper routines, so you can see every ROM call in sequence with nothing hidden behind a subroutine.

**This is a code module, not a standalone program.** It has no `ORG` and no `END`, because it's meant to be pasted into a program that supplies both, or `INCLUDE`d from one, the same way the Appendix further down is.

It has a real entry label, `WorkedExample`, and ends in an `RTS`. Call it with `JSR WorkedExample` or `LBSR WorkedExample` from your own code, and don't execute anything above or below that label directly.

The four result messages (`PassMsg`, `FailMsg`, `TooMuchMsg`, `EarlyEOFMsg`) sit after that `RTS`, safely out of the way. The test bytes, the read-back buffer and the filename literals sit before `WorkedExample`, so they're data your caller must not fall into either.

The `WorkedExample` label itself is what marks the real entry point - not "somewhere past the data at the top". See "Using these routines in your own program" for a genuinely standalone example, with `ORG`, `END` and an execution entry point.

```asm
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
```

If you assemble this into a program, running it should print exactly one of those four lines to the screen - not nothing, and not something you have to inspect memory to check. "Using these routines in your own program" below covers what that needs, including calling `WorkedExample` with `JSR` rather than falling into it.

Each of the first eight reads is checked for an early end-of-file before its byte is trusted, not just the ninth "is there anything more?" check. A file shorter than expected gets its own distinct failure message, instead of comparing whatever an early end-of-file happened to leave in `A`.

That's the verification this example is making: not just "the program ran and returned to BASIC", but "here is what it found".

The Beatle Quest CoCo port's own disk module adds a couple of convenience routines on top of these - `LoadTextToBuffer` and `InitTextFile`, for loading a whole text file into a buffer in one call.

They aren't included here, being specific to the Beatle Quest CoCo port's own file layout. They're worth knowing about as an example of the kind of higher-level layer that is a natural next step once the primitives above are working.

## Verifying against a different ROM revision

**Everything in this manual is for DECB 1.1 specifically.** If you're targeting a different revision, don't assume the same fixed addresses hold.

Disk Basic Unravelled II (see References below) documents different addresses for DECB 1.0 and 1.1 for several of these entry points.

The most reliable way to verify is to boot the target ROM in an emulator with a real debug interface and read the bytes at a candidate address yourself, rather than trusting a book extraction alone.

XRoar, a CoCo emulator, has a `-gdb -gdb-port <N>` flag that exposes a standard GDB (GNU Debugger) remote-serial-protocol target. Any GDB client can then connect to a running, booted CoCo and read its real memory. Relaunch the emulator fresh for each check, because the stub accepts only one connection per launch.

MAME has a considerably more capable debugger, but setting it up for this is beyond the scope of this manual. Whichever you use, record the ROM revision and any DOS extension you tested against, since the result is specific to that combination.

## Glossary

Plain-English definitions for terms used throughout this manual, for a reader who's new to 6809 assembly - not to the CoCo or DECB itself.

- **Vector:** loosely, "a fixed address you call to reach some behaviour". The two kinds in this manual work differently inside, and it's worth telling them apart. `OPENFILE_VEC` and the RAM hooks such as `$0173` and `$0191` are instruction hooks: the address itself holds an executable instruction, so `JSR $0173` runs whatever is sitting there - a `JMP`, in the RAM hooks' case. `CHROUT_VEC` (`$A002`) is an address vector instead: a ROM location holding a stored 16-bit address rather than an instruction. That's why calling it needs the extra indirection of `JSR [CHROUT_VEC]`, with square brackets, rather than a plain `JSR`. Whether a location is in ROM or RAM doesn't decide which kind it is. What a RAM hook buys you over a ROM instruction hook is that DECB, or you, can change which code runs by overwriting a few bytes of RAM - something you can't do to unchangeable ROM.
- **RAM hook:** the name this manual and its source material use for a RAM-resident instruction hook that BASIC calls internally at a fixed point in its own operation - opening a file, printing a character, checking for a break key, and so on. They exist so that other software can redirect that behaviour by overwriting the hook.
- **RVEC:** the reference book's own name for one numbered slot in the RAM hook table above. `RVEC7` is the slot at `$0173`, `RVEC17` the slot at `$0191`. The name identifies the slot, a fixed RAM address; it says nothing about what is currently stored there. See `DVEC` below for the value Disk BASIC writes into it.
- **DVEC:** the reference book's own name, in its alphabetical symbol table, for a constant Disk BASIC uses internally - the value Disk BASIC's start-up code writes into one of the `RVEC` slots above, to redirect it toward disk-aware behaviour. `DVEC7` (`$CAE9`, written into `RVEC7`) and `DVEC17` (`$C265`, written into `RVEC17`) are the two that matter for the `FRClose` explanation above.
- **FCB (File Control Block):** a fixed-size block of memory DECB uses internally to track one open file's state - its buffer, current position, directory entry and similar bookkeeping. The routines in this manual never touch an FCB directly, going through the documented calling convention instead, but the term appears in the explanations of why things work as they do.
- **DECB** (Disk Extended Color BASIC): the version of the CoCo's BASIC interpreter that adds disk file support (`OPEN`, `GET#`, `PUT#`, `CLOSE`) on top of plain Color BASIC. This manual documents its ROM-call interface specifically.
- **HDB-DOS:** a popular modern replacement disk operating system for the CoCo, and a separate thing from the storage hardware it runs on. It can drive SD-card adapters such as CoCoSDC or FujiNet in place of a real floppy drive, while still answering the same ROM calls a program expects. CoCoSDC and FujiNet each support their own alternatives as well, SDC-DOS and DriveWire. The hardware and the DOS running on it are separate choices, not one fixed pairing.
- **WD1793**: the floppy disk controller chip fitted to a real CoCo's disk drive interface. Programs that talk to it directly bypass DECB entirely - see "Why ROM calls, not raw hardware" for why this manual avoids that approach.
- **EOF** (End Of File): the condition of having read every byte a file contains; the point at which a further read has nothing left to return.
- **GDB (GNU Debugger):** a widely used debugger, originally for Unix-style systems. Its remote-serial-protocol wire format is generic enough that XRoar can expose the same protocol for a running emulated CoCo, which is what makes the live-memory-reading technique in this manual possible.
- **Disassembly**: the process of translating raw machine-code bytes back into readable assembly instructions - the reverse of what an assembler does when turning source code into a runnable program.
- **Opcode**: the numeric value that identifies which instruction a particular byte (or sequence of bytes) in machine code represents - `7E`, for instance, is the 6809's `JMP` opcode.

## Appendix A: a complete, ready-to-assemble listing

Everything in the Function reference section above, gathered into one file with no external dependencies - every constant and every routine, in the order an assembler needs to see them. Nothing new is introduced here; it's the same code, collected into one instructive listing rather than split across six sections.

It assembles cleanly on its own, but it's a code module, not a runnable program. There's no `ORG` and no execution entry point, because it's meant to be pasted into a program that supplies both, or `INCLUDE`d from one. Assembling it by itself with no `ORG` places it at address `$0000`, which isn't safe to load into a running CoCo.

See "Using these routines in your own program" below for how this gets combined with an `ORG` and an `END` into something you can run.

**Roughly how much space this adds:** assembled on its own, this block is about 300 bytes - around 20 bytes of scratch RAM, the `RMB` reservations at the top, plus about 280 bytes of routine code.

Treat that as a starting figure for your own `CLEAR` and `ORG` planning in step 9 below, not an exact one for your program: your own code and data, and your assembler's settings, change the final size. Check your assembler's listing or symbol output for the precise assembled address range once you've pasted this in.

```asm
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
```

Before the first call to `FROpen` or `FROpenWrite` in a program, zero `FRIsOpen` once yourself - see the Gotcha note under `FROpen`/`FROpenWrite` above. The assembler's `RMB` directive reserves the space but doesn't guarantee it starts at zero.

## Appendix B: DECB disk error codes

Errors DECB can raise while your program is doing disk I/O, checked against the DECB 1.1 disassembly rather than quoted from a book. None of them come back to your code as a status flag - they all abort straight to BASIC. See "Errors mostly don't come back to you" under Core concepts above.

The first table is DECB's own disk-specific error table, declared directly in its ROM. The second is a small set of other Color BASIC and Extended Color BASIC errors that disk operations can also trigger, which this reference doesn't itself define in full - each one is flagged as such below.

**Disk-specific errors (DECB's own message table):**

| Screen text | Code | What triggers it | Reachable through this manual's routines? |
|---|---|---|---|
| `?BR ERROR` | 27 | Random-file record number is zero, or too large | No - random/direct-file only |
| `?DF ERROR` | 28 | No free directory entry, or no free granule for file data | Yes - can occur while opening, writing, or closing an output file |
| `?OB ERROR` | 29 | Insufficient random/direct-file buffer space: the buffer-end calculation overflows or exceeds the available buffer area | Not reached by these sequential input/output wrappers |
| `?WP ERROR` | 30 | A write reports the write-protect status bit | Yes - any write, including `FRWriteByte` |
| `?FN ERROR` | 31 | Filename fails validation (too long, bad characters, drive number out of range, embedded `.`/`/`) | Not through BASIC's filename-validation path: these wrappers bypass that parser. The caller must provide a valid 11-byte, space-padded filename |
| `?FS ERROR` | 32 | Directory/FAT structure looks wrong on open | Yes - via `FROpen`/`FROpenWrite` |
| `?AE ERROR` | 33 | RENAME destination filename already exists | Not reached through a RENAME operation in these wrappers, which don't implement renaming |
| `?FO ERROR` | 34 | `FIELD` statement's byte range overflows the buffer | No - `FIELD` isn't part of this manual |
| `?SE ERROR` | 35 | `LSET`/`RSET` used on a string that was never `FIELD`ed | No - same reason |
| `?VF ERROR` | 36 | Verify-on-write readback doesn't match what was written (only with `VERIFY ON`) | Indirectly - applies to any write, only if verify mode is on |
| `?ER ERROR` | 37 | Write or input past end of record: exceeding the current record buffer while writing or reading its contents | No - random-file specific |

**Other Color BASIC / Extended Color BASIC errors disk operations can also raise** (handled outside DECB's own table - cited here by the disassembly's own comments, not independently declared in it):

| Screen text | What triggers it | Reachable through this manual's routines? |
|---|---|---|
| `?IO ERROR` | A disk failure that isn't specifically write-protect (drive not ready, a seek or CRC error the controller reports) | Yes - any read or write |
| `?AO ERROR` | The requested file number is already open when `OPEN` is called | Yes - matches this manual's own Troubleshooting table |
| `?FM ERROR` | Bad file mode - opening with an invalid mode character, or a random-file operation on a non-random file | Yes in principle, though this manual's wrappers always pass a valid mode byte themselves |
| **?NE ERROR** | The filename isn't in the directory - raised by the same directory-search code `OPEN` (for input) and `KILL` both fall through into on no match | This is the mechanism behind "OPEN aborts on file not found" above. `SEARCH DIRECTORY`'s own entry point stops before reaching this error, only setting and testing a flag, which is exactly why this manual recommends it for a graceful existence check instead of `OPEN`. |
|  |  |  |

## Using these routines in your own program

Everything above documents what each routine does. This section is the full practical walkthrough - from a blank source file to a program that reads a file and displays its contents.

If you've already written a simple 6809 program that prints something to the screen, and want to know exactly what to change to add disk reading, step 4 below walks through that comparison directly.

**Three different things share this space, and it's worth being able to name each one separately before diving in:**

- **The drive** - which physical (or virtual) disk you mean. DECB tracks this in its own variable, `DCDRV` (`$00EB`); every example below assumes drive 0.
- **The file number** - a small integer, always 1 in this manual, that says which of the currently open files a call like `FRReadByte` means, when more than one could be open. It has nothing to do with which disk the file lives on.
- **The filename** - `MYFILE.TXT`, or whatever - which directory entry, on whichever disk the drive number currently points at, you mean.

None of the routines in this manual let you ask for a drive number. See Core concepts above, including the caveat about the internal close overwriting `DCDRV`.

Every example below assumes drive 0 is already selected. That's normally true right after a cold boot into DECB, but it isn't guaranteed once your own program has been running for a while, or other code has touched `DCDRV`.

Creating a disk image on the PC side, with `decb dskini` below, has no bearing on this at all: it makes an image file and touches nothing in the CoCo's RAM.

If your program can't assume drive 0, close first, then set `DCDRV`, then open - in that order. `FROpen` and `FROpenWrite`'s own internal close, described in Core concepts, would otherwise overwrite `DCDRV` again before the open runs:

```asm
DCDRV   EQU     $00EB

        LBSR    FRClose      ; close whatever was open first - its own internal
                              ; close would otherwise overwrite DCDRV again
        CLR     DCDRV        ; NOW select drive 0 - after the close, not before
        LDX     #Fn_Buffer
        LBSR    FROpen       ; FRIsOpen is clear now, so no second internal close happens
```

#### Filenames on disk versus filenames in your program.

DECB filenames are 8 characters name + 3 characters extension, space-padded, no dot stored anywhere - this manual's routines expect exactly that 11-byte layout in an `FCC` literal:

| Representation | Example |
|---|---|
| Filename on disk | `MYFILE.TXT` |
| Assembly buffer | `FCC "MYFILE TXT"` |

`MYFILE` is 6 characters, padded with 2 spaces to fill the 8-character name field. `TXT` fills the 3-character extension field exactly, with no padding needed.

The dot shown by `DIR`, or typed in a BASIC `OPEN` statement, is never stored. It's only how DECB displays the boundary between the two fields.

These routines don't understand PC-style paths, or a `0:` drive prefix inside the filename. Drive selection is a separate matter, covered above, and isn't part of the 11-byte name.

#### 1. Copy the Appendix listing into your own source file.

These routines are ordinary 6809 subroutines with no dependency on anything outside themselves except the fixed ROM/RAM addresses at the top. Two ways to bring them in, either is fine:

- Paste the whole Appendix block directly into your own `.asm` file, either above or below your own code. `lwasm` resolves forward references in a normal two-pass assemble, so the order between your code and the pasted block doesn't matter for resolving labels.

**Execution is a different matter.** Put the block somewhere your program's own top-to-bottom flow can never run into by accident. Straight after your own final `RTS` is the simplest place, which is exactly where the "after" example below puts it - after `Done`'s `RTS`, before its own `END`.

Every routine in the block is a subroutine: call it with `JSR` or `LBSR` and it returns with `RTS`. Calling one works from anywhere in the file. The placement rule is only there to stop your own code running off its own end and into the block, not to let you call it.

Two more rules: keep the block together in the order it's given, and never put your own code between a label and the instructions that belong to it.

- Save the Appendix block as its own file - `diskio.asm`, say - and bring it in with `lwasm`'s `INCLUDE` directive (`INCLUDE "diskio.asm"`) wherever you would otherwise have pasted it. The same placement rule applies: after your `ORG`, somewhere your own code can't fall into. This keeps the Appendix block out of your source file entirely, which is worth doing once you're using it from more than one program - you update `diskio.asm` in one place, rather than keeping several pasted copies in step.

Either way, these routines and their constants and scratch RAM - the next point - only need to exist once per assembled program, however many places in your own code call them.

#### 2. Watch for name collisions in the scratch RAM.

The labels `FRPos`, `FRStatus`, `FRIsOpen`, `FRFilename`, `FOC_SaveX`, `FOC_SaveA` and `FRSeekTarget` are this module's own private state. Make sure none of them already means something else in your program.

If one does, rename it consistently everywhere it appears in the pasted block. Nothing outside the block refers to these names.

#### Routine lifecycle rules - what's safe to call when:

- Open for input with `FROpen` before reading or seeking, and for output with `FROpenWrite` before writing. These wrappers don't check or block a `FRReadByte` on a file you opened for output, or an `FRWriteByte` on one opened for input - getting the mode right is on you.
- Opening for output replaces the file's existing contents from the start. It isn't append mode, and there's no way with these routines to open a file and add to the end of what is already there.
- Always close an output file with `FRClose` before assuming the data is safely on disk. Closing is what flushes any buffered data and updates the directory entry - it isn't a formality.
- After every `FRReadByte`, check `FRStatus`, not the byte value. Zero is an ordinary data byte that a file can legitimately contain, so it can never mean end-of-file on its own. Only `FRStatus` being nonzero means that.
- These routines share one file slot and a small set of global variables - `FRPos`, `FRStatus`, `FRIsOpen` and `FRFilename`. There's no concept of two files open at once through this interface: opening a second file closes the first. See `FROpen`/`FROpenWrite` above.
- `FRClose` closes every file DECB currently has open, not only one this module opened itself. See the note under `FRClose` above if your program shares file access with other code.

#### 3. Zero `FRIsOpen` once, before your first call.

This is covered as a Gotcha under `FROpen`/`FROpenWrite` above, but it's easy to miss in practice. An `RMB`-reserved byte isn't guaranteed to start at zero, and a stray nonzero value there makes the first open try to close a file that was never open.

Add `CLR FRIsOpen` at the very start of your program, before anything else runs.

#### 4. Call the routines the way a caller would.

If you've already written a simple 6809 program that prints a fixed message to the screen - a typical first assembly program - you already know almost everything needed to make it print a file's contents instead. Here is the exact before and after, so the change is concrete rather than abstract.

**Before: a program that prints a fixed message.** This is a standalone, complete program, ready to assemble as-is - nothing missing, nothing implied:

```asm
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
```

Assemble and run this using steps 6 and 7 below. The "before" example doesn't need the input file from step 5. It prints one fixed line and returns to BASIC - nothing here has touched the disk yet.

**After:** the same program, now printing a file's contents instead of a fixed message. Everything about how printing works is unchanged - it's still `JSR [CHROUT_VEC]` in a loop.

The only change is where the bytes come from. Instead of walking a fixed string in the program itself with `LDA ,X+` / `CMPA #0`, the bytes now come from `FRReadByte`, and `FRStatus` - not a null byte - says when to stop:

```asm
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
```

Side by side, the differences are these:

- The message-printing loop's `LDA ,X+` / `CMPA #0` pair becomes `LBSR FRReadByte` / `TST FRStatus`.
- A one-time `CLR FRIsOpen` and an `LBSR FROpen` go in before the loop starts.
- An `LBSR FRClose` goes in after it ends.
- The `FCC` text literal is replaced by an 11-byte filename.
- The pasted Appendix block replaces the "before" version's own standalone `CHROUT_VEC EQU $A002` line, since the Appendix already declares it and it must not be declared twice.

Everything else is identical - the `ORG`, the `JSR [CHROUT_VEC]` print call itself, the `RTS` and `END` at the end. That's genuinely the whole difference between "prints a message" and "prints a file" at this level.

From here, writing to a file instead of the screen follows the same shape again, with `FROpenWrite` and `FRWriteByte` in place of `FROpen` and `FRReadByte`. See "A complete worked example" above for the full write, close, reopen and read round trip in one place.

#### 5. Create the file the "after" program is going to read.

The "after" program above opens `MYFILE.TXT`, padded to `MYFILE TXT`. That file has to exist before you run it, or `FROpen` will abort straight to BASIC with a real error - see `OPEN DISK FILE`'s documented behaviour above.

Create a plain text file on your PC named `MYFILE.TXT` containing exactly one line:

```text
HELLO FROM A REAL FILE ON DISK
```

Save it as plain ASCII text. UTF-8 with a byte-order mark would add a few extra bytes at the very start, which this reader would print as they are, since it treats every byte literally.

It doesn't matter whether your editor ends the line with `$0A` alone or `$0D` and `$0A` together. `FRReadByte` returns every byte in the file exactly as stored, with no text interpretation at all, so whichever your editor uses simply shows up as one or two extra bytes at the end of the printed output. That's expected, not a fault.

#### 6. Assemble, then build a disk image with both files on it.

With lwasm (see "Which assembler these examples use" above) to produce the program binary, then `decb` (from the ToolShed cross-development package - see References) to build a disk image and put both files on it:

```text
lwasm -9b -o MYPROG.bin MYPROG.asm
decb dskini -3 DEMO.DSK
decb copy -2 -b MYPROG.bin DEMO.DSK,MYPROG.BIN
decb copy -1 -b MYFILE.TXT DEMO.DSK,MYFILE.TXT
decb dir DEMO.DSK
```

All five of these are typed on your PC's own terminal, in the folder holding `MYPROG.asm` and `MYFILE.TXT` - not on the CoCo.

`decb dskini -3 DEMO.DSK` creates a new, empty 35-track disk image called `DEMO.DSK`. The two `decb copy` lines put a copy of each file onto it, and `decb dir` lists what is on the image afterwards, so you can check both files landed before ever touching the CoCo.

The comma in `DEMO.DSK,MYPROG.BIN` separates the host disk-image file, before the comma, from the name to give that file inside the image, after it. They don't have to match, though keeping them the same is easier to follow.

| Option | Meaning |
|---|---|
| `lwasm -9` | Assemble for the plain 6809 |
| `lwasm -b` | Produce DECB `LOADM` binary format |
| `lwasm -o filename` | Choose the output filename |
| `decb dskini -3` | Create a new, blank 35-track disk image |
| `decb copy -2` | Mark the copied file as a machine-language program (DECB file type 2) |
| `decb copy -1` | Mark the copied file as DECB file type 1 ("data") - not a tokenised BASIC program (type 0) or a machine-language file (type 2) |
| `decb copy -b` | Mark the copied file's data as binary, not text |
| `decb copy -r` | Replace the destination file if one by that name already exists on the image |
| `decb copy -l` | Translate line endings during the copy - do **not** use this for either file here, since it would corrupt a binary `.BIN` and change the exact bytes in `MYFILE.TXT` |

`lwasm`'s `-b` and `decb`'s `-b` are two unrelated flags that happen to share a letter. One selects an assembler output format; the other marks a file as binary rather than text on the disk image. Don't read one as implying the other.

#### 7. Mount the image and run the program on the target.

How you mount `DEMO.DSK` as drive 0 depends on what you're running on - an emulator's own disk-image menu, or writing it to a real floppy with the right hardware.

Once it's mounted, the remaining commands are typed at the CoCo's own BASIC prompt, not your PC terminal:

```text
CLEAR 200,10239
LOADM"MYPROG"
EXEC
```

`CLEAR 200,10239` keeps BASIC's own program text and variables below address 10239 (`$27FF`), leaving your machine-language program's memory alone. Step 9 below explains why this matters, and how to choose the second number for your own program. This is the same technique the classic CoCo assembly references teach for interfacing machine code with BASIC - see References below.

`LOADM"MYPROG"` loads the binary from the mounted disk image, and `EXEC` runs it from its entry point.

If everything worked, the screen should show this text, plus whatever line-ending bytes your editor saved at the end of the file. Step 5 covers that: this manual deliberately doesn't prescribe one editor or encoding, so that part of the output isn't pinned to an exact byte count here:

```text
HELLO FROM A REAL FILE ON DISK
```

followed by DECB's own `OK` prompt, confirming the program ran to completion and returned control to BASIC normally.

#### 8. Check the directory and drive assumptions before troubleshooting further.

`decb dir DEMO.DSK` in step 6 already showed you what is on the image from the PC side. `DIR` at the CoCo's own BASIC prompt shows the same thing from the target side.

It's worth running if the program can't find the file: it confirms that the image mounted and that the filename is exactly what you expect. See the filename table above for the padding these routines expect internally - `DIR`'s own display puts the dot back in for you.

#### 9. Before loading these examples from BASIC, use CLEAR to keep BASIC's working memory below your machine-code area.

`CLEAR <string space bytes>,<highest address for BASIC to use>` keeps BASIC's working memory below that address. It doesn't turn ROM, hardware, or unavailable memory into usable program space.

Issue it before `LOADM`, as step 7 does: `CLEAR 200,10239` keeps BASIC below `$27FF`, one byte below `ORG $2800`.

None of this needs Disk BASIC's own `OPEN`, `CLOSE`, `GET#` or `PUT#` keywords at all. Once assembled and loaded, this is a purely machine-language interface. It's callable the same way from a standalone machine-language program, or from a small routine a BASIC program `EXEC`s into.

## Troubleshooting

| Symptom | What to check |
|---|---|
| PC terminal says the command isn't recognised | Whether lwasm/decb are installed and on your `PATH`, and that you're in the folder holding your source/data files |
| PC can't find your source or input file | Which folder you're running the command from - these tools use the current working directory, not a fixed location |
| CoCo says the file can't be found | Is the disk image mounted? Is drive 0 selected? Does the filename match exactly, padding and all - see the filename table above? And did the `decb copy` step succeed? Check with `decb dir` or `DIR`. |
| Program loads a file, but of the wrong type | A `.BIN` extension alone doesn't make a file machine-language. Check it was copied with `decb copy -2 -b`, not just given a `.BIN` name. |
| A real `?AO ERROR` on open | Something else already has this file number open - check you closed whatever was open before opening again |
| Write-protection or a real I/O error | Whether the target media is writable, and whether this storage setup is one of those confirmed to support writing - see "Compatibility notes" above. |
| Program runs but nothing appears on screen | Whether `DEVNUM` really did get back to 0 before you tried to print. Whether the program reached your print code at all - add an early, unconditional print right at the top as a check. And whether it ran at all: did BASIC return to `OK`, or does the machine look hung? |
| Reading never stops - `FRStatus` never goes nonzero | Wrong EOF flag address, or checking the byte value instead of `FRStatus` - see the `CINBFL` note under `FRReadByte` above |
| First `FRReadByte` reports EOF straight away, or the file reads as empty | Either the file genuinely has zero bytes, or `FROpen` opened the wrong one - check the filename padding and the drive - or the file was opened for output by mistake, since `FROpenWrite` truncates it to zero length on open. None of these is a fault in `FRReadByte` itself. |

This isn't a list of everything that can go wrong. It's the set of checks worth doing first, before assuming the deeper explanations elsewhere in this manual are the problem.

## References

### Book

- Spectral Associates (original), revised electronic edition by Walter K. Zydhek. *Disk Basic Unravelled II*. 1999. The source for every ROM address, disassembly excerpt, and calling-convention detail in this manual not independently confirmed via a live debugger. Available from the Color Computer Archive: <https://colorcomputerarchive.com/repo/Documents/Books/Unravelled%20Series/disk-basic-unravelled.pdf>
- William Barden, Jr. *TRS-80 Color Computer Assembly Language Programming*. Radio Shack, 1983 (catalogue number 62-2077). The historical source for the `CLEAR`-based memory-protection technique used in step 7 above - see its Chapter 19, "Program Origin and Interfacing Assembly Language to BASIC". Available from the Internet Archive: https://archive.org/details/Color_Computer_Assembly_Language_Programming_1983_William_Barden_Jr

### Independent cross-check sources (used to confirm addresses without relying on the book alone)

- Sub-Etha Software. "Color BASIC RAM hooks - part 1". 2022. Independently confirms `DEVNUM` at `$006F` and describes the general RAM-hook mechanism this manual's `FRClose` explanation relies on. <https://subethasoftware.com/2022/07/26/color-basic-ram-hooks/>
- Sub-Etha Software. "Color BASIC RAM hooks - part 2". 2022. https://subethasoftware.com/2022/08/02/color-basic-ram-hooks-part-2/

### Direct-hardware disk code (cited for context only - see "Why ROM calls, not raw hardware"; not part of this manual's own approach)

- Glen (nowhereman999). `Disk_Commands.asm` - a WD1793-register-driving CoCo disk driver. https://github.com/nowhereman999/BASIC-To-6809

### Software

- Ciaran Anscomb. *XRoar* - Dragon/CoCo emulator. Its `-gdb` flag is what made the live-debugger verification technique in this manual possible at all.
- *VCC* - CoCo 3 emulator, used throughout to cross-check findings against a second, independent implementation.
- ToolShed - the cross-development package providing `decb`, the disk-image tool used in "Using these routines in your own program" above to build a DECB disk image and copy files onto it from a PC. <https://toolshed.sourceforge.net/ToolShed.html>
- William Astle and contributors. *lwtools* (`lwasm`) - the 6809 cross-assembler every listing in this manual is written for. https://www.lwtools.ca/manual/manual.html

### Primary source

- intangybles. "Six Machines, One Game: Proving the Multi-Port Idea". Amiga Retro Brisbane, 28 August 2026. The write-up of the Beatle Quest CoCo port, whose disk layer is the practical basis for every routine and example above. The port's own source is not published; this manual is the documented form of that disk layer. <https://www.amigaretro.com/projects/six-machines-one-game/>


## About this copy

This is the online copy of the manual, kept as the repository's front page so it can be read without downloading anything. The table of contents above links to every section.

**A PDF of the manual is attached to each [release](../../releases).** It is the portable copy - the same text, with the tables shaded and the fonts as they were authored - and it is the one to keep or print.

**[`code/`](code/) holds every code listing from the manual as its own file**, so a routine can be assembled without retyping it out of the prose. [`code/INDEX.md`](code/INDEX.md) maps each file back to the section it came from. `.asm` is 6809 assembly; `.txt` is everything else, such as the register summaries and the memory map. The same files are attached to each release as a zip.

The listings are taken straight from the manual, so the manual is the thing to correct if something is wrong in them.
