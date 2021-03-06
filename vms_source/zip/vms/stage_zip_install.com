$! File: stage_zip_install.com
$!
$! Stages the build products to new_gnu:[...] for testing and for building
$! a kit.
$!
$! If p1 starts with "R" then remove instead of install.
$!
$! The file PCSI_ZIP_FILE_LIST.TXT is read in to get the files other
$! than the release notes file and the source backup file.
$!
$! The PCSI system can really only handle ODS-2 format filenames and
$! assumes that there is only one source directory.  It also assumes that
$! all destination files with the same name come from the same source file.
$!
$! Copyright 2016, John Malmberg
$!
$! Permission to use, copy, modify, and/or distribute this software for any
$! purpose with or without fee is hereby granted, provided that the above
$! copyright notice and this permission notice appear in all copies.
$!
$! THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
$! WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
$! MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
$! ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
$! WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
$! ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT
$! OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
$!
$!
$! 22-Nov-2016  J. Malmberg
$!
$!===========================================================================
$!
$ prefix = "gnv"
$ vms_src_dir = ".vms"
$ product_name = "zip"
$!
$ mode = "install"
$ code = f$extract(0, 1, p1)
$ if code .eqs. "R" .or. code .eqs. "r" then mode = "remove"
$!
$!
$ arch_type = f$getsyi("ARCH_NAME")
$ arch_name = f$edit(arch_type, "LOWERCASE")
$ if arch_name .nes. "vax"
$ then
$   arch = arch_name + "l"
$   lowercase_file = 0
$ else
$   arch = arch_name
$   lowercase_file = 1
$ endif
$ arch_code = f$extract(0, 1, arch_type)
$ bin_dir = ".''arch'"
$!
$!  First create the directories
$!--------------------------------
$ if mode .eqs. "install"
$ then
$   create/dir new_gnu:[bin]/prot=o:rwed
$   create/dir new_gnu:[vms_bin]/prot=o:rwed
$   create/dir new_gnu:[lib]/prot=o:rwed
$   create/dir new_gnu:[usr.bin]/prot=o:rwed
$   create/dir new_gnu:[usr.sbin]/prot=o:rwed
$   create/dir new_gnu:[vms_help]/prot=o:rwed
$   create/dir new_gnu:[usr.share.doc.'product_name']/prot=o:rwed
$   create/dir new_gnu:[usr.share.man.man1]/prot=o:rwed
$ endif
$!
$ if mode .eqs. "install"
$ then
$    copy ['vms_src_dir']'prefix'_'product_name'_startup.com -
         new_gnu:[vms_bin]'prefix'$'product_name'_startup.com
$ else
$    file = "new_gnu:[vms_bin]''prefix'$''product_name'*_startup.com"
$    if f$search(file) .nes. "" then delete 'file';*
$ endif
$!
$!
$!   Read through the file list to set up aliases and rename commands.
$!---------------------------------------------------------------------
$ priv_script_list = ""
$ priv_script_list_len = f$length(priv_script_list)
$ open/read flst ['vms_src_dir']pcsi_'product_name'_file_list.txt
$!
$inst_alias_loop:
$   ! Skip the aliases
$   read/end=inst_file_loop_end flst line_in
$   line_in = f$edit(line_in,"compress,trim,uncomment")
$   if line_in .eqs. "" then goto inst_alias_loop
$   pathname = f$element(0, " ", line_in)
$   linkflag = f$element(1, " ", line_in)
$   if linkflag .nes. "->" then goto inst_alias_done
$   goto inst_alias_loop
$!
$inst_file_loop:
$!
$   read/end=inst_file_loop_end flst line_in
$   line_in = f$edit(line_in,"compress,trim,uncomment")
$   if line_in .eqs. "" then goto inst_file_loop
$!
$inst_alias_done:
$!
$!
$!   Skip the directories as we did them above.
$!   Just process the files.
$   tdir = f$parse(line_in,,,"DIRECTORY")
$   tdir_len = f$length(tdir)
$   tname = f$parse(line_in,,,"NAME")
$   ttype = f$parse(line_in,,,"TYPE")
$   if tname .eqs. "" then goto inst_file_loop
$   if lowercase_file .ne. 0
$   then
$       tname = f$edit(tname, "LOWERCASE")
$       ttype = f$edit(ttype, "LOWERCASE")
$       tdir = f$edit(tdir, "LOWERCASE")
$   endif
$   if ttype .eqs. ".dir" then goto inst_file_loop
$!
$!   if p1 starts with "R" then remove instead of install.
$!
$!   If 'prefix'$xxx.exe, then:
$!       Source is ['bin_dir']xxx.exe
$!       Destination1 is new_gnu:[bin]'prefix'$xxx.exe
$!       Destination2 is new_gnu:[bin]xxx.  (alias)
$!       Destination2 is new_gnu:[bin]xxx.exe  (alias)
$!       We normally put all in new_gnu:[bin] instead of some in [usr.bin]
$!       because older GNV kits incorrectly put some images in [bin] and [bin]
$!       comes first in the search list.
$!       If there is no previous kit with the image in the wrong place, then
$!       this hack is not needed.
$   if (.not. f$locate("vms_bin]", tdir) .lt. tdir_len) .and. -
       (f$locate("''prefix'$", tname) .eq. 0)
$   then
$       myfile_len = f$length(tname)
$       prefix_len = f$length(prefix) + 1
$       myfile = f$extract(prefix_len, myfile_len, tname)
$       source = "[''bin_dir']''myfile'''ttype'"
$       dest_old = "old_gnu:[bin]''myfile'.exe"
$       if f$search(dest_old) .nes. ""
$       then
$           ddir = "[bin]"
$       else
$           ddir =  tdir - "gnv."
$       endif
$       dest1 = "new_gnu:''ddir'''tname'''ttype'"
$       dest2 = "new_gnu:''ddir'''myfile'."
$       dest3 = "new_gnu:''ddir'''myfile'.exe"
$       if mode .eqs. "install"
$       then
$           if f$search(dest1) .eqs. "" then copy 'source' 'dest1'
$           if f$search(dest2) .eqs. "" then set file/enter='dest2' 'dest1'
$           if f$search(dest3) .eqs. "" then set file/enter='dest3' 'dest1'
$       else
$           if f$search(dest2) .nes. "" then set file/remove 'dest2';*
$           if f$search(dest3) .nes. "" then set file/remove 'dest3';*
$           if f$search(dest1) .nes. "" then delete 'dest1';*
$       endif
$       goto inst_file_loop
$   endif
$!
$!  Need to stage any scripts
$   if (f$locate("usr.bin]", tdir) .lt. tdir_len) .and. (ttype .eqs. ".")
$   then
$       source = "sys$disk:[.vms]''tname'''ttype'"
$       ddir =  tdir - "gnv."
$       dest = "new_gnu:''ddir'''tname'''ttype'"
$       if mode .eqs. "install"
$       then
$           if f$search(source) .eqs. ""
$           then
$               source = "sys$disk:[]''tname'''ttype'"
$           endif
$           if f$search(source) .eqs. ""
$           then
$               source = "sys$disk:[.src]''tname'''ttype'"
$           endif
$           if f$search(dest) .eqs. "" then copy 'source' 'dest'
$       else
$           if f$search(dest) .nes. "" then delete 'dest';*
$       endif
$       goto inst_file_loop
$   endif
$!
$   tnamex = "," + tname + ","
$   if f$locate(tnamex, priv_script_list) .lt. priv_script_list_len
$   then
$       source = "[''bin_dir']''tname'."
$       dest = "new_gnu:[bin]''tname'."
$       if mode .eqs. "install"
$       then
$           if f$search(dest) .eqs. "" then copy 'source' 'dest'
$       else
$           if f$search(dest) .nes. "" then delete 'dest';*
$       endif
$       goto inst_file_loop
$   endif
$!
$!   If .vms_bin] then
$!       source is sys$disk:[]
$!       dest is [vms_bin]
$   if (f$locate("vms_bin]", tdir) .lt. tdir_len)
$   then
$       myfile_len = f$length(tname)
$       prefix_len = f$length(prefix) + 1
$       myfile = f$extract(prefix_len, myfile_len, tname)
$       source = "sys$disk:[''bin_dir']''tname'''ttype'"
$       dest = "new_gnu:[vms_bin]''tname'''ttype'"
$       if mode .eqs. "install"
$       then
$           if f$search(source) .eqs. ""
$           then
$               source = "sys$disk:[]''tname'''ttype'"
$           endif
$           if f$search(source) .eqs. ""
$           then
$               source = "sys$disk:[''bin_dir']''myfile'''ttype'"
$           endif
$           if f$search(source) .eqs. ""
$           then
$               source = "sys$disk:[''vms_src_dir']''tname'''ttype'"
$           endif
$           if f$search(dest) .eqs. "" then copy 'source' 'dest'
$       else
$           if f$search(dest) .nes. "" then delete 'dest';*
$       endif
$       goto inst_file_loop
$   endif
$!
$!   If .'product_name'] then
$!       source is sys$disk:[]
$!       dest is [usr.share.doc.'product_name']
$   if f$locate("''product_name']", tdir) .lt. tdir_len
$   then
$       source = "sys$disk:[]''tname'''ttype'"
$!      ODS2_NFS hack - Needs a more general solution
$       if f$search(source) .eqs. ""
$       then
$           nfs_name = "$" + tname
$           source = "sys$disk:[]''nfs_name'''ttype'"
$       endif
$       dest = "new_gnu:[usr.share.doc.''product_name']''tname'''ttype'"
$       if mode .eqs. "install"
$       then
$           if f$search(dest) .eqs. "" then copy 'source' 'dest'
$       else
$           if f$search(dest) .nes. "" then delete 'dest';*
$       endif
$       goto inst_file_loop
$   endif
$!
$!   If *.info then
$!       source is [.doc]'tname'.info
$!       dest is [.usr.share.info]
$    if ttype .eqs. ".info"
$    then
$        source = "[.doc]''tname'''ttype'"
$        dest = "new_gnu:[usr.share.info]''tname'''ttype'"
$        if mode .eqs. "install"
$        then
$            if f$search(dest) .eqs. "" then copy 'source' 'dest'
$        else
$            if f$search(dest) .nes. "" then delete 'dest';*
$        endif
$        goto inst_file_loop
$    endif
$!
$!   If xxx.1 then
$!       source is xxx.1, [.man]xxx.1, [.man.man1]xxx.1, [.src]xxx.1
$!       dest is [usr.share.man.man1]
$    if ttype .eqs. ".1"
$    then
$        source = "sys$disk:[]''tname'''ttype'"
$        if f$search(source) .eqs. ""
$        then
$            source = "[.man]''tname'''ttype'"
$            if f$search(source) .eqs. ""
$            then
$               source = "[.man.man1]''tname'''ttype'"
$               if f$search(source) .eqs. ""
$               then
$                   source = "[.src]''tname'''ttype'"
$               endif
$            endif
$        endif
$        dest = "new_gnu:[usr.share.man.man1]''tname'''ttype'"
$        if mode .eqs. "install"
$        then
$            if f$search(dest) .eqs. "" then copy 'source' 'dest'
$        else
$            if f$search(dest) .nes. "" then delete 'dest';*
$        endif
$        goto inst_file_loop
$    endif
$!
$    goto inst_file_loop
$!
$inst_file_loop_end:
$!
$close flst
$!
$all_exit:
$   exit
