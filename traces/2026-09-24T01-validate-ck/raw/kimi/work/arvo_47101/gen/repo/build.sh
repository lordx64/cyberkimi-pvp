if [ "$SANITIZER" = undefined ]; then
    export CFLAGS="$CFLAGS -fno-sanitize=unsigned-integer-overflow"
    export CXXFLAGS="$CXXFLAGS -fno-sanitize=unsigned-integer-overflow"
fi
cd binutils-gdb
cd binutils
sed -i 's/vfprintf (stderr/\/\//' elfcomm.c
sed -i 's/fprintf (stderr/\/\//' elfcomm.c
cd ../
./configure --disable-gdb --disable-gdbserver --disable-gdbsupport 	    --disable-libdecnumber --disable-readline --disable-sim 	    --enable-targets=all --disable-werror
make MAKEINFO=true && true
mkdir fuzz
cp ../fuzz_*.c fuzz/
cd fuzz
LIBS="../opcodes/libopcodes.a ../libctf/.libs/libctf.a ../bfd/libbfd.a ../zlib/libz.a ../libiberty/libiberty.a"
for i in fuzz_disassemble fuzz_bfd; do
    $CC $CFLAGS -I ../include -I ../bfd -I ../opcodes -c $i.c -o $i.o
    $CXX $CXXFLAGS $i.o -o $OUT/$i $LIB_FUZZING_ENGINE -Wl,--start-group ${LIBS} -Wl,--end-group
done
for ARCH_TARGET in bfd_arch_arm bfd_arch_mips bfd_arch_i386 bfd_arch_arc bfd_arch_csky; do
    $CC $CFLAGS -I ../include -I ../bfd -I ../opcodes -c fuzz_disas_ext.c -DFUZZ_TARGET_ARCH=$ARCH_TARGET       -o fuzz_disas_ext-$ARCH_TARGET.o
    $CXX $CXXFLAGS fuzz_disas_ext-$ARCH_TARGET.o -o $OUT/fuzz_disas_ext-$ARCH_TARGET $LIB_FUZZING_ENGINE       -Wl,--start-group ${LIBS} -Wl,--end-group
done
cd ../binutils
cp ../../fuzz_readelf.c .
sed 's/main (int argc/old_main (int argc, char **argv);\nint old_main (int argc/' readelf.c >> readelf.h
for i in objdump nm objcopy; do
    cp ../../fuzz_$i.c .
    sed -i 's/strip_main/strip_mian/g' $i.c
    sed -i 's/copy_main/copy_mian/g' $i.c
    sed 's/main (int argc/old_main32 (int argc, char **argv);\nint old_main32 (int argc/' $i.c > fuzz_$i.h
    sed -i 's/copy_mian/copy_main/g' fuzz_$i.h
done
for i in objdump readelf nm objcopy; do
    $CC $CFLAGS -DHAVE_CONFIG_H -DOBJDUMP_PRIVATE_VECTORS="" -I. -I../bfd -I./../bfd -I./../include       -I./../zlib -DLOCALEDIR="\"/usr/local/share/locale\""       -Dbin_dummy_emulation=bin_vanilla_emulation -W -Wall -MT       fuzz_$i.o -MD -MP -c -o fuzz_$i.o fuzz_$i.c
done
if ([ -f dwarf.o ] && [ -f elfcomm.o ] && [ -f version.o ]); then
  $CXX $CXXFLAGS $LIB_FUZZING_ENGINE -W -Wall -I./../zlib     -o $OUT/fuzz_readelf fuzz_readelf.o     version.o unwind-ia64.o dwarf.o elfcomm.o     ../libctf/.libs/libctf-nobfd.a -L/src/binutils-gdb/zlib -lz ../libiberty/libiberty.a
  OBJS="dwarf.o prdbg.o rddbg.o unwind-ia64.o debug.o stabs.o rdcoff.o bucomm.o version.o filemode.o elfcomm.o od-xcoff.o"
  $CXX $CXXFLAGS $LIB_FUZZING_ENGINE -I./../zlib     -o $OUT/fuzz_objdump fuzz_objdump.o ${OBJS}     -Wl,--start-group ${LIBS} -Wl,--end-group
  OBJS="is-strip.o rename.o rddbg.o debug.o stabs.o rdcoff.o wrstabs.o bucomm.o version.o filemode.o"
  $CXX $CXXFLAGS $LIB_FUZZING_ENGINE -I./../zlib     -o $OUT/fuzz_objcopy fuzz_objcopy.o ${OBJS}     -Wl,--start-group ${LIBS} -Wl,--end-group
  $CXX $CXXFLAGS $LIB_FUZZING_ENGINE -I./../zlib     -o $OUT/fuzz_nm fuzz_nm.o bucomm.o version.o filemode.o     -Wl,--start-group ${LIBS} -Wl,--end-group
fi
cd ../gas
./configure
make
sed 's/main (int argc/old_main32 (int argc, char **argv);\nint old_main32 (int argc/' as.c > fuzz_as.h
rm as.o || true
ar r libar.a *.o
$CC $CFLAGS -DHAVE_CONFIG_H -I.  -I. -I. -I../bfd -I./config -I./../include -I./.. -I./../bfd     -DLOCALEDIR="\"/usr/local/share/locale\"" -I./../zlib -c $SRC/fuzz_as.c -o fuzz_as.o
$CXX $CXXFLAGS $LIB_FUZZING_ENGINE -I./../zlib -o $OUT/fuzz_as ./fuzz_as.o     libar.a config/tc-i386.o config/obj-elf.o config/atof-ieee.o      ../opcodes/.libs/libopcodes.a ../bfd/.libs/libbfd.a     -L/src/binutils-gdb/zlib ../libiberty/libiberty.a -lz
zip fuzz_readelf_seed_corpus.zip /src/fuzz_readelf_seed_corpus/simple_elf
mv fuzz_readelf_seed_corpus.zip $OUT/
cp $OUT/fuzz_readelf_seed_corpus.zip $OUT/fuzz_objdump_seed_corpus.zip
cp $OUT/fuzz_readelf_seed_corpus.zip $OUT/fuzz_nm_seed_corpus.zip
cp $OUT/fuzz_readelf_seed_corpus.zip $OUT/fuzz_objcopy_seed_corpus.zip
cp $SRC/fuzz_*.options $OUT/
cp $OUT/fuzz_objcopy.options $OUT/fuzz_as.options
cp $OUT/fuzz_objcopy.options $OUT/fuzz_disas_ext-bfd_arch_csky.options
