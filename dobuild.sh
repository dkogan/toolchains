#!/bin/zsh

set -x

export DEB_BUILD_OPTIONS=parallel=4


sudo apt-get build-dep -y --no-install-recommends gcc-4.9

local failed

function killdeps {
    dpkg -l gcc-4.9-build-deps >& /dev/null && sudo apt-get -y -f remove gcc-4.9-build-deps
}

function buildarch {

    local arch=$1
    failed=1

    local gccdir
    gccdir=(gcc-4.9-*(/N[1]))
    [[ -n "$gccdir" ]] && rm -rf $gccdir

    apt-get source gcc-4.9 || return

    gccdir=(gcc-4.9-*(/N[1]))
    [[ -z "$gccdir" ]] && \
        {echo "ERROR! No gcc source found; don't know what to do. Giving up"; \
         exit}

    pushd $gccdir

    for patchfile in ../patches/*; do
        patch -d debian < $patchfile || \
            {echo "ERROR! Couldn't apply patches Giving up"; \
             exit}
    done

    DEB_TARGET_ARCH=$arch DEB_CROSS_NO_BIARCH=yes with_deps_on_target_arch_pkgs=yes dpkg-buildpackage -d -T control || return

    # install deps
    dpkg --add-architecture $arch
    killdeps
    export DEB_TARGET_GNU_TYPE=$( dpkg-architecture -a${arch} -qDEB_HOST_GNU_TYPE -f 2>/dev/null )
    sudo apt-get -y -f --no-install-recommends install libc6-dev:${arch} linux-libc-dev:${arch} libgcc1:${arch} gcc-4.9-base:${arch} binutils-${DEB_TARGET_GNU_TYPE} || return
    sudo mk-build-deps -t 'apt-get -y --no-install-recommends' -i -r debian/control || return
    dpkg -l gcc-4.9-build-deps >& /dev/null || \
                                  {echo "WARNING: couldn't install gcc dependencies for arch $arch. Skipping arch";
                                   return}

    # make new version to indicate that this is my customized build
    # need to make this non-interactive
    local CURRENT_VER=`dpkg-parsechangelog | awk '/Version/ {print $2; exit}'`
    test -n "$CURRENT_VER" || return # make sure version was parsed
    export DEBEMAIL=dima@secretsauce.net
    export DEBFULLNAME='Dima Kogan'
    dch -v ${CURRENT_VER}"dima1" 'New snapshot' || return
    dch -r '' || return

    DEB_TARGET_ARCH=$arch DEB_CROSS_NO_BIARCH=yes with_deps_on_target_arch_pkgs=yes dpkg-buildpackage -us -uc -b || return

    killdeps || return

    failed=0
}



rm -rf gcc-4.9-*(/) || true

for arch (armel armhf mips mipsel powerpc) {
        buildarch $arch
        popd

        ((failed)) && echo "WARNING: Failed to build arch $arch; skipping"
        killdeps
    }
