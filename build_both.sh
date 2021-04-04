#!/bin/bash -e -u -x
# -e / set -e / set -o errexit - exit immediately if a command exits with a non-zero status
# -u / set -u / set -o nounset - treat unset variables as an error when substituting
# -x / set -x / set -o xtrace  - print commands and their arguments as they are executed
set -o pipefail     # the return value of a pipeline is the status of the last command to exit with a non-zero status

workdir=$(mktemp -d)            # path must be absolute, must be writable for current user
echo "current working directory: ${workdir}"
depsdir="${workdir%/}/ext"      # all dependencies will be placed here
mkdir ${workdir}/ext
cd ${workdir}
min_macos_ver=10.14
brew install qt@5 openssl cmake ninja boost

# download and build libtorrent

git clone --recurse-submodules https://github.com/blahdy/libtorrent.git

cd libtorrent
OPENSSL_ROOT_DIR=/usr/local/opt/openssl
OPENSSL_LIBRARIES=/usr/local/opt/openssl/lib
cmake -Wno-dev -B build -G Ninja -DCMAKE_PREFIX_PATH=${depsdir} -DCMAKE_CXX_STANDARD=17 -DCMAKE_CXX_EXTENSIONS=OFF -DCMAKE_OSX_DEPLOYMENT_TARGET=${min_macos_ver} -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -Ddeprecated-functions=OFF -DCMAKE_INSTALL_PREFIX=${depsdir} -DOPENSSL_ROOT_DIR=/usr/local/opt/openssl -DOPENSSL_LIBRARIES=/usr/local/opt/openssl/lib
cmake --build build
cmake --install build

cd ..

# download and build qBittorrent - some magic comes here :)
# download the sources
qbt_branch=master               # qBittorrent version to use, use latest development version

curl -L https://github.com/blahdy/qBittorrent/archive/{$qbt_branch}.tar.gz | tar xz

cd qBittorrent-${qbt_branch}

mkdir build && cd build

cmake -DCMAKE_PREFIX_PATH="$HOME/tmp/qbt/ext" -DCMAKE_CXX_STANDARD=17 -DCMAKE_CXX_EXTENSIONS=OFF -DCMAKE_OSX_DEPLOYMENT_TARGET=10.14 -DCMAKE_BUILD_TYPE=Release -DOPENSSL_ROOT_DIR=/usr/local/opt/openssl -DOPENSSL_LIBRARIES=/usr/local/opt/openssl/lib -DQt5_DIR=$(brew --prefix qt5)/lib/cmake/Qt5 ..
make -j$(sysctl -n hw.ncpu)

# next part of this script is part from my another script used to build my own projects for macOS.
# I was to lazy to rename/remove variables :), so that in slightly different style.
QT_ROOT="/usr/local/opt/qt5"

$QT_ROOT/bin/macdeployqt "qbittorrent.app"

# deploy Qt' translations
tr_path="$PWD/qbittorrent.app/Contents/Resources/translations"
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
echo "Translations = Resources/translations" >> "qbittorrent.app/Contents/Resources/qt.conf"

# create .dmg file, there magic becomes :)
codesign --deep --force --verify --verbose --sign "-" "qbittorrent.app"
out_file="$PWD/qbittorrent-${qbt_branch}-macosx.dmg"
if [[ $(which dmgbuild) ]]
then
  # use 'dmgbuild' utility: https://pypi.org/project/dmgbuild/
  curl -O -J -L -s "https://www.dropbox.com/s/q315bjd96umlxm0/settings.py?dl=1"
  dmgbuild -s "settings.py" -D app="qbittorrent.app" "qbittorrent" "$out_file"
else
  # use 'hdiutil' available on each macOS
  hdiutil create -srcfolder "qbittorrent.app" -nospotlight -layout NONE -fs HFS+ "qbittorrent.dmg"
  # this is very strange, but much better compression is achieved only after image conversion ...
  hdiutil convert "qbittorrent.dmg" -format UDBZ -o "$out_file"
fi

# move created .dmg file to user's Downloads directory, it is writable everywhere
mv "$out_file" "$HOME/Downloads/"

cd ${workdir}

# download and build qBittorrent - some magic comes here :)
# download the sources
qbt_branch=masters               # qBittorrent version to use, use latest development version

curl -L https://github.com/blahdy/qBittorrent/archive/{$qbt_branch}.tar.gz | tar xz

cd qBittorrent-${qbt_branch}

mkdir build && cd build

cmake -DCMAKE_PREFIX_PATH="$HOME/tmp/qbt/ext" -DCMAKE_CXX_STANDARD=17 -DCMAKE_CXX_EXTENSIONS=OFF -DCMAKE_OSX_DEPLOYMENT_TARGET=10.14 -DCMAKE_BUILD_TYPE=Release -DOPENSSL_ROOT_DIR=/usr/local/opt/openssl -DOPENSSL_LIBRARIES=/usr/local/opt/openssl/lib -DQt5_DIR=$(brew --prefix qt5)/lib/cmake/Qt5 ..
make -j$(sysctl -n hw.ncpu)

# deploy Qt' libraries for an app
$QT_ROOT/bin/macdeployqt "qbittorrent.app"

# deploy Qt' translations
tr_path="$PWD/qbittorrent.app/Contents/Resources/translations"
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
echo "Translations = Resources/translations" >> "qbittorrent.app/Contents/Resources/qt.conf"

# create .dmg file, there magic becomes :)
codesign --deep --force --verify --verbose --sign "-" "qbittorrent.app"
out_file="$PWD/qbittorrent-${qbt_branch}-macosx.dmg"
if [[ $(which dmgbuild) ]]
then
  # use 'dmgbuild' utility: https://pypi.org/project/dmgbuild/
  curl -O -J -L -s "https://www.dropbox.com/s/q315bjd96umlxm0/settings.py?dl=1"
  dmgbuild -s "settings.py" -D app="qbittorrent.app" "qbittorrent" "$out_file"
else
  # use 'hdiutil' available on each macOS
  hdiutil create -srcfolder "qbittorrent.app" -nospotlight -layout NONE -fs HFS+ "qbittorrent.dmg"
  # this is very strange, but much better compression is achieved only after image conversion ...
  hdiutil convert "qbittorrent.dmg" -format UDBZ -o "$out_file"
fi

# move created .dmg file to user's Downloads directory, it is writable everywhere
mv "$out_file" "$HOME/Downloads/"

# cleanup
cd "${workdir}/.."
rm -rf "${workdir}"
