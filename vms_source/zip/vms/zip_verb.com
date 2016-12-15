$! zip_verb.com - build the zip_verb.cld from the zip.cld.
$!
$! The CLD file needed to modify a DCL command table is different
$! from the CLD file needed to build the product by specifying an image.
$!
$! So read in the [.vms]zip.cld and generate a zip_verb.cld.
$!
$! 23-Nov-2016 - J. Malmberg
$!
$outfile = "sys$disk:[]zip_verb.cld"
$infile = "[.vms]zip_cli.cld"
$open/read cld 'infile'
$create 'outfile'
$open/append cldv 'outfile'
$loop:
$read cld/end=loop_end line_in
$if f$locate("Verb", line_in) .lt. f$length(line_in)
$then
$    write cldv line_in
$    write cldv "    image gnv$gnu:[vms_bin]gnv$zip_cli"
$    goto loop
$endif
$write cldv line_in
$goto loop
$loop_end:
$close cldv
$close cld
