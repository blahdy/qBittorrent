#!/bin/bash

workdir=$(mktemp -d)            # path must be absolute, must be writable for current user
echo "current working directory: ${workdir}"
depsdir="${workdir%/}/ext"      # all dependencies will be placed here
cd ${workdir}

# download Qt from Git repository
qt_branch=5.15                  # Qt version to use
git clone https://code.qt.io/qt/qt5.git
cd qt5
git checkout ${qt_branch}
perl init-repository --module-subset=qtbase,qtmacextras,qtsvg,qttools,qttranslations
# detect minimum macOS version required by Qt and use this value while building all other stuff
min_macos_ver=$(grep QMAKE_MACOSX_DEPLOYMENT_TARGET qtbase/mkspecs/common/macx.conf | grep -Eo -e '\d+\.\d+')
# leave Qt sources for a while... some dependencies must be build before building Qt itself
cd ..

# download and build OpenSSL
openssl_ver=OpenSSL_1_1_1-stable  # OpenSSL version to use
curl -L https://github.com/openssl/openssl/archive/${openssl_ver}.tar.gz | tar xz
[[ $? -eq 0 ]] || exit 1

cd openssl-${openssl_ver}

./config no-comp no-deprecated no-dynamic-engine no-tests no-zlib --openssldir=/etc/ssl --prefix=${depsdir} -mmacosx-version-min=${min_macos_ver}
[[ $? -eq 0 ]] || exit 1
make -j$(sysctl -n hw.ncpu) || exit 1
make install_sw || exit 1

cd ..

# so, Qt dependencies are satisfied now, time to build Qt
cd qt5
# apply few my patches to customize build process and decrease build time.
# these patches are completely optional, but without second one some configure options can't be set,
# so they must be removed, and this will increase build time
curl -L -s "https://www.dropbox.com/s/qkfdq5mz7lersy6/qt-no-assistant.patch?dl=1" | patch -p1 -d qttools

qtbuilddir="../build-qt"
mkdir ${qtbuilddir} && cd ${qtbuilddir}
${workdir}/qt5/configure -prefix "${depsdir}" -opensource -confirm-license -release -appstore-compliant -c++std c++14 -no-pch -I "${depsdir}/include" -L "${depsdir}/lib" -make libs -no-compile-examples -no-dbus -no-icu -qt-pcre -system-zlib -ssl -openssl-linked -no-cups -qt-libpng -qt-libjpeg -no-feature-testlib -no-feature-sql -no-feature-concurrent
[[ $? -eq 0 ]] || exit 1
make -j$(sysctl -n hw.ncpu) || exit 1
make install || exit 1

cd ${workdir}

# download and build Boost
boost_ver=1.72.0                # Boost version to use

boost_ver_u=${boost_ver//./_}
curl -L https://dl.bintray.com/boostorg/release/${boost_ver}/source/boost_${boost_ver_u}.tar.bz2 | tar xj
[[ $? -eq 0 ]] || exit 1

cd boost_${boost_ver_u}

./bootstrap.sh
[[ $? -eq 0 ]] || exit 1
./b2 --prefix=${depsdir} --with-system variant=release link=static cxxflags="-std=c++14 -mmacosx-version-min=${min_macos_ver}" install
[[ $? -eq 0 ]] || exit 1

cd ..

# download and build libtorrent
# I decided to build libtorrent with CMake, because on macOS it can't be built using autotools
# and I'm not familiar with Boost.Build and couldn't get it work "out of the box".
# not every developer has CMake installed, so download (but not install!) it if required.
if [[ -f "/Applications/CMake.app/Contents/bin/cmake" ]]
then
  cmake="/Applications/CMake.app/Contents/bin/cmake"
else
  cmake_ver=3.17.0
  curl -L https://github.com/Kitware/CMake/releases/download/v${cmake_ver}/cmake-${cmake_ver}-Darwin-x86_64.tar.gz | tar xz
  cmakedir=$(ls | grep cmake)
  cmake="${workdir}/${cmakedir}/CMake.app/Contents/bin/cmake"
fi
[[ -f "${cmake}" ]] || exit 1

lt_branch=RC_1_2                # libtorrent version to use, use latest development version from 1.2.x versions

curl -L https://github.com/blahdy/libtorrent/archive/${lt_branch}.tar.gz | tar xz
[[ $? -eq 0 ]] || exit 1

cd libtorrent-${lt_branch}
# I build static library, something was changed and now linker produce few warnings during qBittorrent building,
# so apply patch to fix these warnings. I don't know is they are critical or not, but I just don't like them.
# this fix is just "quick fix" or workaround, so merge request was not submitted to the developers.
curl -L -s "https://www.dropbox.com/s/ym7fegg4f3hwwnt/lt-static-link-warning-fix.patch?dl=1" | patch -p1

mkdir build && cd build
${cmake} -DCMAKE_PREFIX_PATH=${depsdir} -DCMAKE_CXX_STANDARD=14 -DCMAKE_CXX_EXTENSIONS=OFF -DCMAKE_OSX_DEPLOYMENT_TARGET=${min_macos_ver} -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -Ddeprecated-functions=OFF -DCMAKE_INSTALL_PREFIX=${depsdir} ..
make VERBOSE=1 -j4 || exit 1
make install || exit 1

cd ../..

# download and build qBittorrent - some magic comes here :)
# download the sources
qbt_branch=master               # qBittorrent version to use, use latest development version

curl -L -s https://github.com/blahdy/qBittorrent/archive/{$qbt_branch}.tar.gz | tar xz
[[ $? -eq 0 ]] || exit 1

cd qBittorrent-${qbt_branch}

# as so as it is impossible (or pretty hard) to get work autotools build system on macOS,
# there are only 2 options what to use to build qBittorrent: CMake and qmake.
# I don't like CMake in general, moreover it is pretty hard to use with Qt, especially from custom path.
# thereby I decided to use "Qt's native build system" - qmake. it is maybe not so convenient in case of
# qBittorrent build configuration, but developers envisaged it and created special file for "user configuration".
# so, download my recommended project configuration (conf.pri)
curl -O -J -L -s "https://www.dropbox.com/s/apfv9ofhhftderj/conf.pri?dl=1"
# Note: exactly the same config can be used to build qBittorrent in QtCreator.

# I don't like the way how official qBittorrent app is packaged for macOS, so I do it in my own way.
# I didn't suggest any patches used there to qBittorrent developers/maintainers, because I'm not Apple
# developer and strictly don't know the "true" methods, and these changes were made in my own opinion.
# patches are completely optional.
# first patch disables Qt translations deployment, I'll do it later.
curl -L -s "https://www.dropbox.com/s/d6sdrvz2zpjnywn/qbt-no-predef-qt-stuff.patch?dl=1" | patch -p1

# better HiDPI support
curl -L -s "https://www.dropbox.com/s/2crekp814e5m2vj/hidpi-hacks-new.patch?dl=1" | patch -p1

# next part of this script is part from my another script used to build my own projects for macOS.
# I was to lazy to rename/remove variables :), so that in slightly different style.
QT_ROOT="${depsdir}"
APP_NAME="qBittorrent"
SRC_PATH="$PWD"

build_dir="$SRC_PATH/../build-qbt"
rm -rf "$build_dir"
mkdir "$build_dir"
cd "$build_dir"

$QT_ROOT/bin/qmake -config release -r "$SRC_PATH/qbittorrent.pro"
make -j$(sysctl -n hw.ncpu)
[[ $? == 0 ]] || exit 1

# deploy Qt' libraries for an app
cd src
mv qbittorrent.app "$APP_NAME.app"
$QT_ROOT/bin/macdeployqt "$APP_NAME.app"

# deploy Qt' translations
tr_path="$PWD/$APP_NAME.app/Contents/Resources/translations"
[[ -d "$tr_path" ]] || mkdir "$tr_path"
pushd "$QT_ROOT/translations" > /dev/null
langs=$(ls -1 qt_*.qm | grep -v help | sed 's/qt_\(.*\)\.qm/\1/g')
for lang in $langs
do
  lang_files=$(ls -1 qt*_$lang.qm)
  $QT_ROOT/bin/lconvert -o "$tr_path/qt_$lang.qm" $lang_files
done
popd > /dev/null

# update generated qt.conf
echo "Translations = Resources/translations" >> "$APP_NAME.app/Contents/Resources/qt.conf"

# create .dmg file, there magic becomes :)
codesign --deep --force --verify --verbose --sign "-" "$APP_NAME.app"
out_file="$build_dir/../qbittorrent-${qbt_branch}-macosx.dmg"
if [[ $(which dmgbuild) ]]
then
  # use 'dmgbuild' utility: https://pypi.org/project/dmgbuild/
  curl -O -J -L -s "https://www.dropbox.com/s/q315bjd96umlxm0/settings.py?dl=1"
  dmgbuild -s "settings.py" -D app="$APP_NAME.app" "$APP_NAME" "$out_file"
else
  # use 'hdiutil' available on each macOS
  hdiutil create -srcfolder "$APP_NAME.app" -nospotlight -layout NONE -fs HFS+ "$APP_NAME.dmg"
  # this is very strange, but much better compression is achieved only after image conversion ...
  hdiutil convert "$APP_NAME.dmg" -format UDBZ -o "$out_file"
fi

[[ -f "$out_file" ]] || exit 1
# move created .dmg file to user's Downloads directory, it is writable everywhere
mv "$out_file" "$HOME/Downloads/"

cd ${workdir}

# download and build qBittorrent - some magic comes here :)
# download the sources
qbt_branch=masters               # qBittorrent version to use, use latest development version

curl -L -s https://github.com/blahdy/qBittorrent/archive/{$qbt_branch}.tar.gz | tar xz
[[ $? -eq 0 ]] || exit 1

cd qBittorrent-${qbt_branch}

# as so as it is impossible (or pretty hard) to get work autotools build system on macOS,
# there are only 2 options what to use to build qBittorrent: CMake and qmake.
# I don't like CMake in general, moreover it is pretty hard to use with Qt, especially from custom path.
# thereby I decided to use "Qt's native build system" - qmake. it is maybe not so convenient in case of
# qBittorrent build configuration, but developers envisaged it and created special file for "user configuration".
# so, download my recommended project configuration (conf.pri)
curl -O -J -L -s "https://www.dropbox.com/s/apfv9ofhhftderj/conf.pri?dl=1"
# Note: exactly the same config can be used to build qBittorrent in QtCreator.

# I don't like the way how official qBittorrent app is packaged for macOS, so I do it in my own way.
# I didn't suggest any patches used there to qBittorrent developers/maintainers, because I'm not Apple
# developer and strictly don't know the "true" methods, and these changes were made in my own opinion.
# patches are completely optional.
# first patch disables Qt translations deployment, I'll do it later.
curl -L -s "https://www.dropbox.com/s/d6sdrvz2zpjnywn/qbt-no-predef-qt-stuff.patch?dl=1" | patch -p1

# better HiDPI support
curl -L -s "https://www.dropbox.com/s/2crekp814e5m2vj/hidpi-hacks-new.patch?dl=1" | patch -p1

# next part of this script is part from my another script used to build my own projects for macOS.
# I was to lazy to rename/remove variables :), so that in slightly different style.
QT_ROOT="${depsdir}"
APP_NAME="qBittorrent"
SRC_PATH="$PWD"

build_dir="$SRC_PATH/../build-qbt"
rm -rf "$build_dir"
mkdir "$build_dir"
cd "$build_dir"

$QT_ROOT/bin/qmake -config release -r "$SRC_PATH/qbittorrent.pro"
make -j$(sysctl -n hw.ncpu)
[[ $? == 0 ]] || exit 1

# deploy Qt' libraries for an app
cd src
mv qbittorrent.app "$APP_NAME.app"
$QT_ROOT/bin/macdeployqt "$APP_NAME.app"

# deploy Qt' translations
tr_path="$PWD/$APP_NAME.app/Contents/Resources/translations"
[[ -d "$tr_path" ]] || mkdir "$tr_path"
pushd "$QT_ROOT/translations" > /dev/null
langs=$(ls -1 qt_*.qm | grep -v help | sed 's/qt_\(.*\)\.qm/\1/g')
for lang in $langs
do
  lang_files=$(ls -1 qt*_$lang.qm)
  $QT_ROOT/bin/lconvert -o "$tr_path/qt_$lang.qm" $lang_files
done
popd > /dev/null

# update generated qt.conf
echo "Translations = Resources/translations" >> "$APP_NAME.app/Contents/Resources/qt.conf"

# create .dmg file, there magic becomes :)
codesign --deep --force --verify --verbose --sign "-" "$APP_NAME.app"
out_file="$build_dir/../qbittorrent-${qbt_branch}-macosx.dmg"
if [[ $(which dmgbuild) ]]
then
  # use 'dmgbuild' utility: https://pypi.org/project/dmgbuild/
  curl -O -J -L -s "https://www.dropbox.com/s/q315bjd96umlxm0/settings.py?dl=1"
  dmgbuild -s "settings.py" -D app="$APP_NAME.app" "$APP_NAME" "$out_file"
else
  # use 'hdiutil' available on each macOS
  hdiutil create -srcfolder "$APP_NAME.app" -nospotlight -layout NONE -fs HFS+ "$APP_NAME.dmg"
  # this is very strange, but much better compression is achieved only after image conversion ...
  hdiutil convert "$APP_NAME.dmg" -format UDBZ -o "$out_file"
fi

[[ -f "$out_file" ]] || exit 1
# move created .dmg file to user's Downloads directory, it is writable everywhere
mv "$out_file" "$HOME/Downloads/"

# cleanup
cd "${workdir}/.."
rm -rf "${workdir}"
