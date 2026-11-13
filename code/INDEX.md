# CoCo disk ROM calls - code listings

Every code listing from the manual, one file each.

The manual is the work; these are here so a routine can be assembled without retyping it. **They are generated from it - correct the manual, not these.**

`.asm` is 6809 assembly, `.txt` is everything else (memory maps, tables, BASIC fragments).

| file | from | manual line | lines |
|---|---|---|---|
| `core_concepts.asm` | Core concepts | 109 | 5 |
| `which_assembler_these_examples_use.txt` | Which assembler these examples use | 178 | 1 |
| `fropen_fropenwrite.txt` | `FROpen` / `FROpenWrite` - open a file for input or output | 235 | 21 |
| `fropen_fropenwrite.asm` | `FROpen` / `FROpenWrite` - open a file for input or output | 271 | 72 |
| `frreadbyte.txt` | `FRReadByte` - read one byte, advance position, detect EOF | 350 | 10 |
| `frreadbyte.asm` | `FRReadByte` - read one byte, advance position, detect EOF | 375 | 21 |
| `frwritebyte.txt` | `FRWriteByte` - write one byte to the open output file | 403 | 4 |
| `frwritebyte.asm` | `FRWriteByte` - write one byte to the open output file | 422 | 9 |
| `frclose.txt` | `FRClose` - close the currently open file | 440 | 3 |
| `frclose.asm` | `FRClose` - close the currently open file | 459 | 8 |
| `frexists.txt` | `FRExists` - check whether a filename exists | 482 | 7 |
| `frexists.asm` | `FRExists` - check whether a filename exists | 506 | 28 |
| `frseek.txt` | `FRSeek` - move to an absolute byte offset | 541 | 8 |
| `frseek.asm` | `FRSeek` - move to an absolute byte offset | 571 | 23 |
| `a_complete_worked_example.asm` | A complete worked example: write, close, reopen, read back | 611 | 137 |
| `appendix_a.asm` | Appendix A: a complete, ready-to-assemble listing | 802 | 189 |
| `using_these_routines_in_your_own_program.asm` | Using these routines in your own program | 1048 | 7 |
| `call_the_routines_the_way_a_caller_would_1.asm` | 4. Call the routines the way a caller would. | 1116 | 20 |
| `call_the_routines_the_way_a_caller_would_2.asm` | 4. Call the routines the way a caller would. | 1145 | 31 |
| `create_the_file_the_after_program_is_going_to_read.txt` | 5. Create the file the "after" program is going to read. | 1197 | 1 |
| `assemble_then_build_a_disk_image_with_both_files_on_it.txt` | 6. Assemble, then build a disk image with both files on it. | 1209 | 5 |
| `mount_the_image_and_run_the_program_on_the_target_1.txt` | 7. Mount the image and run the program on the target. | 1243 | 3 |
| `mount_the_image_and_run_the_program_on_the_target_2.txt` | 7. Mount the image and run the program on the target. | 1255 | 1 |
