SBT:=./sbt
SRC:=src/main/java
CC:=cc
STRIP:=strip -x
TARGET:=target
LIBNAME:=libzstdjava.so

all: zstd

ZSTD_VERSION:=1.1.2
ZSTD_GIT_REPO_URL:=https://github.com/facebook/zstd

ZSTD_OUT:=$(TARGET)/zstd-$(ZSTD_VERSION)-$(OS_ARCH)
ZSTD_ARCHIVE:=$(TARGET)/zstd-$(ZSTD_VERSION).tar.gz
ZSTD_CC:=common/entropy_common.c common/error_private.c common/fse_decompress.c common/xxhash.c common/zstd_common.c decompress/zstd_decompress.c decompress/huf_decompress.c compress/fse_compress.c compress/huf_compress.c compress/zstd_compress.c dictBuilder/divsufsort.c dictBuilder/zdict.c legacy/zstd_v01.c legacy/zstd_v02.c legacy/zstd_v03.c legacy/zstd_v04.c legacy/zstd_v05.c legacy/zstd_v06.c legacy/zstd_v07.c
ZSTD_SRC_DIR:=$(TARGET)/zstd-$(ZSTD_VERSION)/lib
ZSTD_SRC:=$(addprefix $(ZSTD_SRC_DIR)/,$(ZSTD_CC))

ZSTD_UNPACKED:=$(TARGET)/zstd-unpacked.log

ZSTD_OBJ:=$(addprefix $(ZSTD_OUT)/,$(patsubst %.c,%.o,$(ZSTD_CC))) # ZstdNative.o)

CFLAGS:=$(CFLAGS) -O3 -Wall -Wextra -Wcast-qual -Wcast-align -Wshadow -Wstrict-aliasing=1 -Wswitch-enum -Wdeclaration-after-statement -Wstrict-prototypes -Wundef -Wpointer-arith -I$(ZSTD_SRC_DIR) -I$(ZSTD_SRC_DIR)/common -I$(ZSTD_SRC_DIR)/dictBuilder -I$(ZSTD_SRC_DIR)/legacy -DZSTD_LEGACY_SUPPORT=1 
LINKFLAGS:=-shared 

ifeq ($(OS_NAME),SunOS)
	TAR:= gtar
else
	TAR:= tar
endif

$(ZSTD_ARCHIVE):
	@mkdir -p $(@D)
	curl -L -o$@ https://github.com/facebook/zstd/archive/v$(ZSTD_VERSION).tar.gz

$(ZSTD_UNPACKED): $(ZSTD_ARCHIVE)
	$(TAR) xvfz $< -C $(TARGET)
	touch $@

jni-header: $(ZSTD_UNPACKED) $(SRC)/org/xerial/zstd/ZstdNative.h

$(TARGET)/jni-classes/org/xerial/zstd/ZstdNative.class: $(SRC)/org/xerial/zstd/ZstdNative.java
	@mkdir -p $(TARGET)/jni-classes
	$(JAVAC) -source 1.8 -target 1.8 -d $(TARGET)/jni-classes -sourcepath $(SRC) $<

$(SRC)/org/xerial/zstd/ZstdNative.h: $(TARGET)/jni-classes/org/xerial/zstd/ZstdNative.class
	$(JAVAH) -force -classpath $(TARGET)/jni-classes -o $@ org.xerial.zstd.ZStdNative

$(ZSTD_OUT)/%.o: $(ZSTD_SRC_DIR)/%.c
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) -c $< -o $@

$(ZSTD_OUT)/$(LIBNAME): $(ZSTD_OBJ)
	$(CC) $(CFLAGS) -o $@ $+ $(LINKFLAGS)
	cp $@ /tmp/$(@F)
	$(STRIP) /tmp/$(@F)
	mv /tmp/$(@F) $@

clean-native:
	rm -rf $(ZSTD_OUT)

clean:
	rm -rf $(TARGET)

NATIVE_DIR:=src/main/resources/org/xerial/zstd/native/$(OS_NAME)/$(OS_ARCH)
NATIVE_TARGET_DIR:=$(TARGET)/classes/org/xerial/zstd/native/$(OS_NAME)/$(OS_ARCH)
NATIVE_DLL:=$(NATIVE_DIR)/$(LIBNAME)

zstd-jar-version:=zstd-java-$(shell perl -npe "s/version in ThisBuild\s+:=\s+\"(.*)\"/\1/" version.sbt | sed -e "/^$$/d")

native: $(NATIVE_DLL)
zstd: native $(TARGET)/$(zstd-jar-version).jar

native-all: win32 win64 mac64 native-arm linux32 linux64 linux-ppc64 linux-aarch64

$(NATIVE_DLL): $(ZSTD_UNPACKED) $(ZSTD_OUT)/$(LIBNAME)
	@mkdir -p $(@D)
	cp $(ZSTD_OUT)/$(LIBNAME) $@
	@mkdir -p $(NATIVE_TARGET_DIR)
	cp $(ZSTD_OUT)/$(LIBNAME) $(NATIVE_TARGET_DIR)/$(LIBNAME)

package: $(TARGET)/$(zstd-jar-version).jar

$(TARGET)/$(zstd-jar-version).jar:
	$(SBT) package

test: $(NATIVE_DLL)
	$(SBT) test

DOCKER_RUN_OPTS:=--rm

win32: jni-header
	./docker/dockcross-windows-x86 -a $(DOCKER_RUN_OPTS) bash -c 'make clean-native native CROSS_PREFIX=i686-w64-mingw32.static- OS_NAME=Windows OS_ARCH=x86'

win64: jni-header
	./docker/dockcross-windows-x64 -a $(DOCKER_RUN_OPTS) bash -c 'make clean-native native CROSS_PREFIX=x86_64-w64-mingw32.static- OS_NAME=Windows OS_ARCH=x86_64'

# deprecated
mac32: jni-header
	$(MAKE) native OS_NAME=Mac OS_ARCH=x86

mac64: jni-header
	docker run -it $(DOCKER_RUN_OPTS) -v $$PWD:/workdir -e CROSS_TRIPLE=x86_64-apple-darwin multiarch/crossbuild make clean-native native OS_NAME=Mac OS_ARCH=x86_64

linux32: jni-header
	docker run $(DOCKER_RUN_OPTS) -ti -v $$PWD:/work xerial/centos5-linux-x86_64-pic bash -c 'make clean-native native OS_NAME=Linux OS_ARCH=x86'

linux64: jni-header
	docker run $(DOCKER_RUN_OPTS) -ti -v $$PWD:/work xerial/centos5-linux-x86_64-pic bash -c 'make clean-native native OS_NAME=Linux OS_ARCH=x86_64'

freebsd64:
	$(MAKE) native OS_NAME=FreeBSD OS_ARCH=x86_64

# For ARM
native-arm: linux-arm linux-armv6 linux-armv7 linux-android-arm

linux-arm: jni-header
	./docker/dockcross-armv5 -a $(DOCKER_RUN_OPTS) bash -c 'make clean-native native CROSS_PREFIX=arm-linux-gnueabi- OS_NAME=Linux OS_ARCH=arm'

linux-armv6: jni-header
	./docker/dockcross-armv6 -a $(DOCKER_RUN_OPTS) bash -c 'make clean-native native CROSS_PREFIX=arm-linux-gnueabihf- OS_NAME=Linux OS_ARCH=armv6'

linux-armv7: jni-header
	./docker/dockcross-armv7 -a $(DOCKER_RUN_OPTS) bash -c 'make clean-native native CROSS_PREFIX=arm-linux-gnueabihf- OS_NAME=Linux OS_ARCH=armv7'

linux-android-arm: jni-header
	./docker/dockcross-android-arm -a $(DOCKER_RUN_OPTS) bash -c 'make clean-native native CROSS_PREFIX=/usr/arm-linux-androideabi/bin/arm-linux-androideabi- OS_NAME=Linux OS_ARCH=android-arm'

linux-ppc64: jni-header
	./docker/dockcross-ppc64 -a $(DOCKER_RUN_OPTS) bash -c 'make clean-native native CROSS_PREFIX=powerpc64le-linux-gnu- OS_NAME=Linux OS_ARCH=ppc64'

linux-aarch64: jni-header
	./docker/dockcross-aarch64 -a $(DOCKER_RUN_OPTS) bash -c 'make clean-native native CROSS_PREFIX=aarch64-linux-gnu- OS_NAME=Linux OS_ARCH=aarch64'

javadoc:
	$(SBT) doc

install-m2:
	$(SBT) publishM2
