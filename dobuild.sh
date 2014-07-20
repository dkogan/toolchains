#!/bin/zsh

set -e -x

sudo apt-get build-dep -y --no-install-recommends gcc-4.9


function killdeps {
    dpkg -l gcc-4.9-build-deps && sudo apt-get -y -f remove gcc-4.9-build-deps
}



rm -rf gcc-4.9-*(/) || true

for arch (armel mipsel armhf) {

        local gccdir
        gccdir=(gcc-4.9-*(/N[1]))
        [[ -n "$gccdir" ]] && rm -rf $gccdir

        apt-get source gcc-4.9

        gccdir=(gcc-4.9-*(/N[1]))
        [[ -z "$gccdir" ]] && \
            (echo "ERROR! No gcc source found; don't know what to do. Giving up"; \
             false)

        pushd $gccdir

        for patchfile in ../patches/*; do
            patch -d debian < $patchfile
        done

        DEB_TARGET_ARCH=$arch DEB_CROSS_NO_BIARCH=yes with_deps_on_target_arch_pkgs=yes dpkg-buildpackage -d -T control

        # install deps
        killdeps
        export DEB_TARGET_GNU_TYPE=$( dpkg-architecture -a${arch} -qDEB_HOST_GNU_TYPE -f 2>/dev/null )
        sudo apt-get -y -f --no-install-recommends install libc6-dev:${arch} linux-libc-dev:${arch} libgcc1:${arch} gcc-4.9-base:${arch} binutils-${DEB_TARGET_GNU_TYPE}
        sudo mk-build-deps -t 'apt-get -y --no-install-recommends' -i -r debian/control
        dpkg -l gcc-4.9-build-deps >& /dev/null || \
                                      {echo "ERROR: couldn't install gcc dependencies for arch $arch. Skipping arch";
                                       continue}

        # make new version to indicate that this is my customized build
        # need to make this non-interactive
        local CURRENT_VER=`dpkg-parsechangelog | awk '/Version/ {print $2; exit}'`
        test -n "$CURRENT_VER" # make sure version was parsed
        export DEBEMAIL=dima@secretsauce.net
        export DEBFULLNAME='Dima Kogan'
        dch -v ${CURRENT_VER}"dima1" 'New snapshot'
        dch -r ''

        DEB_BUILD_OPTIONS=parallel=4 DEB_TARGET_ARCH=$arch DEB_CROSS_NO_BIARCH=yes with_deps_on_target_arch_pkgs=yes dpkg-buildpackage -us -uc -b

        killdeps
        popd
}
