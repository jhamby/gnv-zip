$! File: build_gnv.com
$!
$! Procedure to build zip_project on VMS.
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
$!
$!=========================================================================
$!
$ product_name = "zip"
$!
$ if p1 .eqs. "CLEAN" .or. P1 .eqs. "REALCLEAN"
$ then
$  file = "sys$disk:[.vms]clean_''product_name'.com"
$  if f$search(file) .nes. ""
$  then
$      @'file' 'p1'
$  else
$      write sys$output "### ''file' not found for cleanup"
$  endif
$  exit
$ endif
$!
$ start_time = f$cvtime()
$!
$ if (f$getsyi("HW_MODEL") .lt. 1024)
$ then
$   arch = "VAX"
$   psize = "32"
$   ccopts = "CCOPTS=/NAMES=(AS_IS,TRUNC)/show=(expan,inclu)"
$   ! New stuff for the beta
$   do_lzma = ""
$   if f$search("sys$disk:[...]$p$pmd8.c") .eqs. "" then do_ppmd = "NOPPMD"
$   if f$search("sys$disk:[...]$L$z$F$ind.c") .eqs. ""
$   then
$       do_lzma = "NOLZMA"
$   endif
$ else
$   arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$!   psize = "64"
$!   ccopts = "CCOPTS=/NAMES=(AS_IS,TRUNC)/POINTER_SIZE=64/show=(expan,inclu)"
$!  zip build procedure does not support 64 bit pointers yet.
$   psize = "32"
$   ccopts = "CCOPTS=/NAMES=(AS_IS,TRUNC)/show=(expan,inclu)"
$   local_zip="_USE_STD_STAT"
$   ! New stuff for the beta
$   if f$search("sys$disk:[]aes_wg.dir") .nes. ""
$   then
$       do_aes = "AES_WG=1"
$   endif
$   if f$search("sys$disk:[...]LzFind.c") .eqs. ""
$   then
$       do_lzma = "NOLZMA"
$   endif
$   if f$search("sys$disk:[...]Ppmd8.c") .eqs. "" then do_ppmd = "NOPPMD"
$ endif
$!
$!
$!
$ define lib_bzip2 gnv$gnu:[usr.lib]libbz2_'psize'.olb
$!
$ define/user sys$output nla0:
$ define/user sys$error nla0:
$ search sys$disk:[]fileio.c "fileio.c - Zip 3.1"
$ search_sev = '$severity'
$ if search_sev .eq. 1
$ then
$    define/user sys$output nla0:
$    define/user sys$error nla0:
$    search sys$disk:[]fileio.c "__USING_STD_STAT"
$    search_sev = '$severity'
$    if search_sev .ne. 1
$    then
$       copy sys$disk:[]fileio.c_beta sys$disk:[]fileio.c
$    endif
$ else
$    define/user sys$output nla0:
$    define/user sys$error nla0:
$    search sys$disk:[]fileio.c "__USING_STD_STAT"
$    search_sev = '$severity'
$    if search_sev .ne. 1
$    then
$       copy sys$disk:[]fileio.c_src sys$disk:[]fileio.c
$    endif
$ endif
$!
$! Run the build procedure if needed.
$!-----------------------------------
$ if f$search("sys$disk:[...]*.exe") .eqs. ""
$ then
$   @[.vms]build_zip.com "IZ_BZIP2=gnv$gnu:[usr.include]" -
     LIST 'ccopts' 'do_lzma' 'do_ppmd' 'do_aes'
$!
$   OLD_VERIFY = f$verify( 0)
$   @[.vms]zip_verb.com
$ endif
$!
$!
$ if f$trnlnm("new_gnu") .eqs. ""
$ then
$   write sys$output "new_gnu: not defined, can not stage"
$   exit
$ endif
$!
$!
$! Need to stage the files in a rooted new_gnu directory
$! This is both for doing additional testing and for setting
$! up for an install.
$! ----------------------------------------------------------
$ write sys$output "Removing previously staged files"
$ @[.vms]stage_'product_name'_install.com remove
$ write sys$output "Staging files to new_gnu:[...]"
$ @[.vms]stage_'product_name'_install.com
$!
$!
$! Now need to sanity check if we can build a PCSI kit.
$! The GNV_PCSI_PRODUCER* logical names are used so that
$! you must set them to make your kit name different
$! from other kits that have been produced.
$ gnv_pcsi_prod = f$trnlnm("GNV_PCSI_PRODUCER")
$ gnv_pcsi_prod_fn = f$trnlnm("GNV_PCSI_PRODUCER_FULL_NAME")
$ stage_root = f$trnlnm("STAGE_ROOT")
$ if (gnv_pcsi_prod .eqs. "") .or. -
     (gnv_pcsi_prod_fn .eqs. "") .or. -
     (stage_root .eqs. "")
$ then
$   if gnv_pcsi_prod .eqs. ""
$   then
$       msg = "GNV_PCSI_PRODUCER not defined, can not build a PCSI kit."
$       write sys$output msg
$   endif
$   if gnv_pcsi_prod_fn .eqs. ""
$   then
$     msg = "GNV_PCSI_PRODUCER_FULL_NAME not defined, can not build a PCSI kit."
$       write sys$output msg
$   endif
$   if stage_root .eqs. ""
$   then
$       write sys$output "STAGE_ROOT not defined, no place to put kits"
$   endif
$   exit
$ endif
$!
$!
$ @[.vms]pcsi_product_'product_name'.com
$!
$exit
