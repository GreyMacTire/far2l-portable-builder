#!/bin/bash

#Ubuntu 20.04 LTS
#git clone https://github.com/elfmz/far2l.git
#cd far2l
#git checkout v_2.8.0 (или иной тег)
#./build_standalone.sh
#В каталоге far2l/portable будет создан дистрибутив

REPO_DIR=$(pwd)
BUILD_DIR=$REPO_DIR/_build

apt-get install wget libwxgtk3.0-gtk3-dev libx11-dev libxi-dev libxml2-dev libuchardet-dev cmake pkg-config g++ git patchelf makeself dpkg-dev 

#libtree
wget -qO /usr/local/bin/libtree https://github.com/haampie/libtree/releases/latest/download/libtree_x86_64
chmod a+x /usr/local/bin/libtree

mkdir -p $BUILD_DIR

cmake -S $REPO_DIR -B $BUILD_DIR -DADB=no -DUSEWX=no -DARCLITE=no -DNETROCKS=no -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release

cmake --build $BUILD_DIR --target install/strip -- -j$(nproc)

mkdir -p $REPO_DIR/standalone

cp -a $BUILD_DIR/install/* $REPO_DIR/standalone

#Переход в каталог standalone и выполнение команд там
cd $REPO_DIR/standalone


LIB_DIR=lib
LIBC=glibc
LD_FILE=$(dpkg -L libc6 | grep "$(dpkg-architecture -qDEB_BUILD_MULTIARCH)/ld-linux" | xargs basename)
RPATH="\$ORIGIN"

mkdir -p $LIB_DIR

readarray -t files < <(find . -type f -exec sh -c 'file -b {} | grep -q ELF' \; -printf '%P\n')
for file in "${files[@]}"; do
  c=$(awk -F/ '{print NF-1}' <<< $file)
  str=
  if (( $c > 0 )); then
    for (( i=1; i<=$c; i++ )); do str+="../"; done
  fi
  str+="$LIB_DIR"
  echo $file
  strip $file
  ldd $file | awk '/=>/ {print $3}' | xargs -I{} cp -vL {} $LIB_DIR
  patchelf --set-rpath $RPATH/$str $file
  patchelf --print-interpreter $file >/dev/null 2>&1 && patchelf --set-interpreter $str/$LD_FILE $file
done

dpkg -L libc6 | grep 'libnss' | xargs -I{} cp -va {} $LIB_DIR

for file in $LIB_DIR/*; do
  if [ ! -L $file ]; then
    echo $file
    patchelf --set-rpath $RPATH $file
    patchelf --print-interpreter $file >/dev/null 2>&1 && patchelf --set-interpreter $LD_FILE $file
  fi
done

cp -vL $(dpkg -L libc6 | grep "$(dpkg-architecture -qDEB_BUILD_MULTIARCH)/ld-linux") $LIB_DIR

find . ! -path "./$LIB_DIR/*" -type f -exec sh -c 'file -b {} | grep -q ELF' \; -print | sort -f | xargs -I{} libtree -pvv {} | tee libtree.txt

# Создание архива и файла portable-версии

cd $REPO_DIR

mkdir -p $REPO_DIR/portable

makeself --keep-umask --nomd5 --nocrc standalone $REPO_DIR/portable/far2l-portable.run "FAR2L File Manager" ./far2l

tar -cvf $REPO_DIR/portable/far2l-portable.run.tar -C $REPO_DIR/portable far2l-portable.run

tar -cJvf $REPO_DIR/portable/far2l-portable.tar.xz -C $REPO_DIR/standalone .
