#!/bin/bash -e -u -x
# -e / set -e / set -o errexit - exit immediately if a command exits with a non-zero status
# -u / set -u / set -o nounset - treat unset variables as an error when substituting
# -x / set -x / set -o xtrace  - print commands and their arguments as they are executed
set -o pipefail     # the return value of a pipeline is the status of the last command to exit with a non-zero status

workdir=$(mktemp -d)            # path must be absolute, must be writable for current user
echo "current working directory: ${workdir}"
depsdir="${workdir%/}/ext"      # all dependencies will be placed here
cd ${workdir}

# download Qt from Git repository
qt_branch=5.15               # Qt version to use
git clone https://code.qt.io/qt/qt5.git
cd qt5
git checkout ${qt_branch}
perl init-repository --module-subset=qtbase,qtmacextras,qtsvg,qttools,qttranslations
# detect minimum macOS version required by Qt and use this value while building all other stuff
min_macos_ver=10.14
# leave Qt sources for a while... some dependencies must be build before building Qt itself
cd ..

# download and build OpenSSL
openssl_ver=OpenSSL_1_1_1-stable  # OpenSSL version to use
curl -L https://github.com/openssl/openssl/archive/${openssl_ver}.tar.gz | tar xz

cd openssl-${openssl_ver}

./config no-comp no-deprecated no-dynamic-engine no-tests no-zlib --openssldir=/etc/ssl --prefix=${depsdir} -mmacosx-version-min=${min_macos_ver}
make -j$(sysctl -n hw.ncpu)
make install_sw

cd ..

# so, Qt dependencies are satisfied now, time to build Qt
cd qt5

qtbuilddir="../build-qt"
mkdir ${qtbuilddir} && cd ${qtbuilddir}
${workdir}/qt5/configure -prefix "${depsdir}" -opensource -confirm-license -release -appstore-compliant -c++std c++14 -no-pch -I "${depsdir}/include" -L "${depsdir}/lib" -make libs -no-compile-examples -no-dbus -no-icu -qt-pcre -system-zlib -ssl -openssl-linked -no-cups -qt-libpng -qt-libjpeg -no-feature-testlib -no-feature-concurrent
make -j$(sysctl -n hw.ncpu)
make install

cd ${workdir}

# download and build Boost
boost_ver=1.76.0                # Boost version to use

boost_ver_u=${boost_ver//./_}
curl -L https://boostorg.jfrog.io/artifactory/main/release/${boost_ver}/source/boost_${boost_ver_u}.tar.bz2 | tar xj

cd boost_${boost_ver_u}

./bootstrap.sh
./b2 --prefix=${depsdir} --with-system variant=release link=static cxxflags="-std=c++17 -mmacosx-version-min=${min_macos_ver}" install

cd ..

# download CMake and Ninja
cmake_ver=3.21.0-rc2                # CMake version to use
curl -L https://github.com/Kitware/CMake/releases/download/v${cmake_ver}/cmake-${cmake_ver}-macos-universal.tar.gz | tar xz
cmakedir=$(ls | grep cmake)
cmake="${workdir}/${cmakedir}/CMake.app/Contents/bin/cmake"

ninja_ver=1.10.2                # Ninja version to use
curl -O -J -L https://github.com/ninja-build/ninja/releases/download/v${ninja_ver}/ninja-mac.zip
unzip -d "${depsdir}/bin" ninja-mac.zip

# download and build libtorrent

git clone --recurse-submodules https://github.com/blahdy/libtorrent.git

cd libtorrent
# I build static library, something was changed and now linker produce few warnings during qBittorrent building,
# so apply patch to fix these warnings. I don't know is they are critical or not, but I just don't like them.
# this fix is just "quick fix" or workaround, so merge request was not submitted to the developers.
curl -L -s "https://www.dropbox.com/s/ym7fegg4f3hwwnt/lt-static-link-warning-fix.patch?dl=1" | patch -p1

${cmake} -B build -G Ninja -Wno-dev -DCMAKE_PREFIX_PATH=${depsdir} -DCMAKE_CXX_STANDARD=17 -DCMAKE_CXX_EXTENSIONS=OFF -DCMAKE_OSX_DEPLOYMENT_TARGET=${min_macos_ver} -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -Ddeprecated-functions=OFF -DCMAKE_INSTALL_PREFIX=${depsdir}
${cmake} --build build
${cmake} --install build

cd ..

# download and build qBittorrent - some magic comes here :)
# download the sources
qbt_branch=master               # qBittorrent version to use, use latest development version

curl -L https://github.com/blahdy/qBittorrent/archive/{$qbt_branch}.tar.gz | tar xz

cd qBittorrent-${qbt_branch}

# I don't like the way how official qBittorrent app is packaged for macOS, so I do it in my own way.
# I didn't suggest any patches used there to qBittorrent developers/maintainers, because I'm not Apple
# developer and strictly don't know the "true" methods, and these changes were made in my own opinion.
# patches are completely optional.
# first patch disables Qt translations deployment, I'll do it later.
curl -L -s "https://www.dropbox.com/s/pnri68xsdhu5rej/qbt-no-predef-qt-stuff-cmake.patch?dl=1" | patch -p1

# cmake doesn't understand qmake' placeholders in Info.plist, so change them
perl -pi -e "s/\@EXECUTABLE\@/\\$\\{MACOSX_BUNDLE_EXECUTABLE_NAME\\}/g" dist/mac/Info.plist
perl -pi -e "s/\\$\\{MACOSX_DEPLOYMENT_TARGET\\}/${min_macos_ver}/g" dist/mac/Info.plist

${cmake} -B build -G Ninja -DCMAKE_PREFIX_PATH=${depsdir} -DCMAKE_CXX_STANDARD=17 -DCMAKE_CXX_EXTENSIONS=OFF -DCMAKE_OSX_DEPLOYMENT_TARGET=${min_macos_ver} -DCMAKE_BUILD_TYPE=Release
${cmake} --build build

# next part of this script is part from my another script used to build my own projects for macOS.
# I was to lazy to rename/remove variables :), so that in slightly different style.
QT_ROOT="${depsdir}"
APP_NAME="qBittorrent"

# deploy Qt' libraries for an app
cd build
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
out_file="$PWD/qbittorrent-${qbt_branch}-macosx.dmg"
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

# move created .dmg file to user's Downloads directory, it is writable everywhere
mv "$out_file" "$HOME/Downloads/"

cd ${workdir}

# download and build qBittorrent - some magic comes here :)
# download the sources
qbt_branch=masters               # qBittorrent version to use, use latest development version

curl -L https://github.com/blahdy/qBittorrent/archive/{$qbt_branch}.tar.gz | tar xz

cd qBittorrent-${qbt_branch}

# I don't like the way how official qBittorrent app is packaged for macOS, so I do it in my own way.
# I didn't suggest any patches used there to qBittorrent developers/maintainers, because I'm not Apple
# developer and strictly don't know the "true" methods, and these changes were made in my own opinion.
# patches are completely optional.
# first patch disables Qt translations deployment, I'll do it later.
curl -L -s "https://www.dropbox.com/s/pnri68xsdhu5rej/qbt-no-predef-qt-stuff-cmake.patch?dl=1" | patch -p1

# better HiDPI support
curl -L -s "https://www.dropbox.com/s/2crekp814e5m2vj/hidpi-hacks-new.patch?dl=1" | patch -p1

# cmake doesn't understand qmake' placeholders in Info.plist, so change them
perl -pi -e "s/\@EXECUTABLE\@/\\$\\{MACOSX_BUNDLE_EXECUTABLE_NAME\\}/g" dist/mac/Info.plist
perl -pi -e "s/\\$\\{MACOSX_DEPLOYMENT_TARGET\\}/${min_macos_ver}/g" dist/mac/Info.plist

${cmake} -B build -G Ninja -DCMAKE_PREFIX_PATH=${depsdir} -DCMAKE_CXX_STANDARD=17 -DCMAKE_CXX_EXTENSIONS=OFF -DCMAKE_OSX_DEPLOYMENT_TARGET=${min_macos_ver} -DCMAKE_BUILD_TYPE=Release
${cmake} --build build

# next part of this script is part from my another script used to build my own projects for macOS.
# I was to lazy to rename/remove variables :), so that in slightly different style.
QT_ROOT="${depsdir}"
APP_NAME="qBittorrent"

# deploy Qt' libraries for an app
cd build
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
out_file="$PWD/qbittorrent-${qbt_branch}-macosx.dmg"
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

# move created .dmg file to user's Downloads directory, it is writable everywhere
mv "$out_file" "$HOME/Downloads/"

# cleanup
cd "${workdir}/.."
rm -rf "${workdir}"
