#!/bin/bash

progdir=$(readlink -f $(dirname $0))
rewriterpath=$progdir/../rewriter/examples
scriptdir=$progdir/scripts

if [ $# -lt 1 ]; then
    echo ""
    echo "[USAGE] <program> <binary to patch> [final binary]"
    echo ""
    exit 1
fi
exe=$1
if [ ! -e $exe ]; then
    echo "[Error] binary $exe does not exists, please specify a valid ld.so."
    exit 1
fi
iself=$(file $(readlink -f $exe)|grep -o "ELF")
if [ "$iself" == "" ]; then
    echo "[Error] file $exe is not an ELF executable."
    exit 1
fi
targetexe=$2
if [ "$targetexe" == "" ]; then
    targetexe=$(mktemp)
    echo "final binary name: $targetexe"
fi
r2path=$(command -v r2)
if [ "$r2path" == "" ]; then
    echo "[Error] Please ensure that Radare2 is properly installed."
    exit 1
fi
# Compile to-be-injected binary.
echo "[Generating] xomenable code..."
cd $progdir
make -C ../patch/xomenable/ clean
make -C ../patch/xomenable/
if [ $? -ne 0 ]; then
    echo "[Error] compiling xomenable code, please check your gcc setup."
    cd $OLDPWD
    exit 1
fi
cd $OLDPWD
elf2inject=$progdir/../patch/xomenable/xomenable

addrfile=$(mktemp)
newexe=$(mktemp)

$rewriterpath/xom_enable.py -f $exe -o $newexe

echo "We assume XOM has been added to the ELF binary, so first we remove it"
#
# Removing XOM is done by removing the XOM related segments temporarily. This
# is because these segments are not compatible with radare2, i.e., analysis
# results would not show up. We achieve this by shrinking the phdr but not
# reall removing those segments so that we could later add them back by
# increase the phdr entry number.
#
$scriptdir/adjust_phnum.sh decrease $newexe

$rewriterpath/inject_instrumentation.py -i $elf2inject -f $newexe -o $targetexe

$scriptdir/patch_call_of_injectedbin.sh ldso_mmap syscall:mmap $targetexe \
                                        $elf2inject $exe;
$scriptdir/patch_call_of_injectedbin.sh ldso_mprotect syscall:mprotect \
                                        $targetexe $elf2inject $exe;
$scriptdir/patch_call_of_injectedbin.sh _dl_debug_vdprintf syscall:writev \
                                        $targetexe $elf2inject $exe;

$scriptdir/analyze_mmap_callsites.sh mmap $newexe > $addrfile

$scriptdir/patch_calls_of_origbin.sh $addrfile _wrapper_mmap $targetexe \
                                     $elf2inject; 

echo "We add XOM related segments back to the ELF binary"
$scriptdir/adjust_phnum.sh increase $targetexe

$scriptdir/filling_gap.sh $targetexe
rm $newexe
rm $addrfile

echo "injected executable has been saved as $targetexe"
