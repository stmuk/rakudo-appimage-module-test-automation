#!/usr/bin/env bash
if [ ! "$Prefix" ]; then export Prefix='/rsu'; fi
NPROC_NO=$(( $(nproc) + 1 ))
alias make="$(make -j $NPROC_NO)"
if [ "$CI" ]; then set -e; fi
find_file () { readlink -f  "$(find . -maxdepth 1 -type f -name "$1" | head -n 1)"; }
find_dir () { readlink -f  "$(find . -maxdepth 1 -type d -name "$1" | head -n 1)"; }
APP=perl6
ID=org.perl6.rakudo
ORIG_DIR="$(pwd)"
if [ ! "$P6SCRIPT" ]; then P6SCRIPT=stable; fi
echo "ORIG_DIR=$ORIG_DIR APP=$APP ID=$ID P6SCRIPT=$P6SCRIPT"
#stage_1 () {
if [ "$(echo "$Prefix" | grep -E "^$HOME")" ]; then
  NO_SUDO=1
fi
if [ "$NO_SUDO" ]; then
  if [ -e "$Prefix" ]; then
    rm -rfv "$Prefix";
  fi
  mkdir -v "$Prefix"
  chown -R "$(whoami):$(whoami)" "$Prefix"
  chmod 755 "$Prefix"
else
  if [ -e "$Prefix" ]; then
    sudo rm -rfv "$Prefix";
  fi
  sudo mkdir -v "$Prefix"
  sudo chown -R "$(whoami):$(whoami)" "$Prefix"
  sudo chmod 755 "$Prefix"
fi
chars=$(printf "%s" "$(readlink -f /rsu)" | wc -m )
if [ $(( $chars % 2 )) != 0 ]; then
  echo "Oh no, prefix is the wrong number of characters! needs to be a multiple of 2"
  exit 1;
fi
amount=$(($chars / 2))
replacement=$(perl -e "print './' x $amount")

if [ ! "$BLEAD" ]; then
    TAR_GZ=rakudo-star-latest.tar.gz
    check_tar () { gzip -tv $TAR_GZ; }
    # IF we already have the download, check its integrity, otherwise delete
    if [ -f $TAR_GZ ]; then
        check_tar || rm -fv $TAR_GZ
    fi
    if [ ! -f $TAR_GZ ]; then
        wget http://rakudo.org/downloads/star/$TAR_GZ
    fi
    printf "Checking the compressed file integrity.\n"
    gzip -tv $TAR_GZ
    tar -xf $TAR_GZ || exit
    cd "$(find_dir 'rakudo-star*')" || exit
    perl ./Configure.pl --prefix="$Prefix" --backends=moar --gen-moar || exit
else
    if [ -d 'rakudo' ]; then
        cd 'rakudo' && git pull
    else
        git clone https://github.com/rakudo/rakudo.git || exit
        cd rakudo || exit
    fi
    perl Configure.pl --prefix="$Prefix" --gen-moar --gen-nqp --backends=moar || exit
fi
RAKUDO_DIR=$(basename "$(pwd)" )
export RAKUDO_DIR
make || exit
make install || exit
# Copy the test files a level up for later testing
#cp -r -v ./t ../rakudo-t
cd "$Prefix" || exit
# If Linenoise/Readline is installed this is to generate precomp
# Only copy them over on CI so we don't copy over random junk
if [[ "$CI" || "$COPY_PRECOMP" ]]; then
  rm -rf ~/.perl6/precomp/
  echo "say 'Welcome to Perl 6!'; exit 0;" | RAKUDO_MODULE_DEBUG=1 LD_LIBRARY_PATH="./lib" ./bin/perl6
  if [ "$ALL_MODULES" ]; then
    PATH="$PATH:$Prefix/bin:/share/perl6/site/bin"
    export PATH
    "$Prefix/bin/perl6" "$ORIG_DIR/install_all_modules.p6" "--folder=$LOG_FOLDER"
  fi
  cp -r ~/.perl6/precomp/* "$Prefix/share/perl6/site/precomp" || echo "Didn't find any files to copy. Ignoring return values of cp"
fi
echo "Dumping all found strings that has the original path in it"
find . -type f -print0 | xargs --null -I '{}' strings '{}' | grep "$Prefix"
echo "Replacing path in binaries, replacing '$Prefix' with '$replacement'"
find . -type f -print0 | xargs --null -I '{}' sed -i -e "s|$Prefix|$replacement|g" '{}'
mkdir -p -v usr
move_all_to () { find . -maxdepth 1 -mindepth 1 ! -name "$1" -exec mv {} "$1" \; ;}
# AppImage documentation is bad. We must install into some directory (handpaths get coded into one directory), and then we need to then MOVE them to a new folder usr
# If we don't move everything to usr (even though we didn't do --prefix for that) paths won't match up and it won't start
move_all_to usr
#find . -maxdepth 1 -exec mv * ./usr
echo "Now you need to fix usr/bin/perl6 script"
cp -v "$ORIG_DIR/perl6-$P6SCRIPT" ./usr/bin/perl6
chmod -v +x ./usr/bin/perl6
mkdir -v "$APP.AppDir"
#cd -v "$APP.AppDir"
cp -v "$ORIG_DIR/$ID.desktop" "./$APP.AppDir"
# TODO use `install` instead of mkdir and other things to be more correct
mkdir -p -v ./usr/share/metainfo/
cp -v "$ORIG_DIR/$ID.appdata.xml" ./usr/share/metainfo/
# Ok, everything should be READY by this point XXX move things into place
move_all_to "$APP.AppDir"
#mv -v * "./$APP.AppDir"
# Move the image icon into place
cp -v "$ORIG_DIR/$APP.png" "./$APP.AppDir"

# Download the appimage tool which actually makes the Appimages
wget --tries=5 "https://github.com/probonopd/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
chmod -v a+x appimagetool-x86_64.AppImage
wget --tries=5 "https://github.com/probonopd/AppImageKit/releases/download/continuous/AppRun-x86_64"
chmod -v a+x AppRun-x86_64
mv -v AppRun-x86_64 "$APP.AppDir/AppRun"
# AppImage tools are dumb and refuse to create the appimage, if this happens,
# and it will, try again with -n option to force it
./appimagetool-x86_64.AppImage -v "$APP.AppDir" || ./appimagetool-x86_64.AppImage -v -n "$APP.AppDir"
IMAGE_NAME="$(find_file '*perl6*.AppImage')"
cp -v "$IMAGE_NAME" "$ORIG_DIR"
cp -r "$APP.AppDir" "$ORIG_DIR"
cd "$ORIG_DIR" || exit

if [[ $RETURN_CODE == 0 ]]; then
  echo -n
  if [ "$CI" ]; then
    sudo rm -rf "$Prefix";
  fi
fi
echo "Image built as $IMAGE_NAME"
exit 0
