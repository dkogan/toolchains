#!/bin/zsh

set -x
set -e

sudo apt-get build-dep --no-install-recommends gcc-4.9
apt-get source gcc-4.9
cd gcc-4.9-*(/)

for patchfile in ../patches/*; do
    patch -d debian < $patchfile
done

DEB_TARGET_ARCH=armel DEB_CROSS_NO_BIARCH=yes with_deps_on_target_arch_pkgs=yes dpkg-buildpackage -d -T control


# something with deps
# sudo mk-build-deps -t 'apt-get -y --no-install-recommends' -i -r debian/control


DEB_BUILD_OPTIONS=parallel=4 DEB_TARGET_ARCH=armel DEB_CROSS_NO_BIARCH=yes with_deps_on_target_arch_pkgs=yes dpkg-buildpackage -us -uc -b
