$! File: ZIP_CLI_TEST.COM
$!
$! This is designed to be run as a spawned subprocess to not make
$! changes in the local clitables
$!
$ if f$type(zip) .eqs. "STRING" then delete/sym/global zip
$ if f$search("new_gnu:[vms_bin]gnv$zip_cli.exe") .eqs. ""
$ then
$   write sys$output "ZIP images have not been staged!"
$   exit 42
$ endif
$ set command new_gnu:[vms_bin]zip_verb.cld
$ zip /help
