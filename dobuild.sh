#!/bin/zsh

set -x

export DEB_BUILD_OPTIONS=parallel=4


local failed
local -a arches
arches=(armel armhf mips mipsel powerpc arm64)


function killdeps {
    dpkg -l gcc-4.9-build-deps >& /dev/null && sudo apt-get -y -f remove gcc-4.9-build-deps
}

function resetarch {
    local arch=$1

    killdeps
    sudo apt-get purge -y $(dpkg -l "*:$arch" | awk '/^ii/ {print $2}')
    sudo dpkg --remove-architecture $arch

    export DEB_TARGET_GNU_TYPE=$( dpkg-architecture -a${arch} -qDEB_HOST_GNU_TYPE -f 2>/dev/null )
    sudo apt-get -y -f remove binutils-${DEB_TARGET_GNU_TYPE}
}

function resetarches_all {
    typeset -U arches_to_clean
    arches_to_clean=(`dpkg --print-foreign-architectures` $arches[@])
    for arch ($arches_to_clean[@]) {
        resetarch $arch
    }
}

function buildarch {

    local arch=$1
    failed=1

    sudo dpkg --add-architecture $arch

    local gccdir
    gccdir=(gcc-4.9-*(/N[1]))
    [[ -n "$gccdir" ]] && rm -rf $gccdir

    apt-get source gcc-4.9 || return

    gccdir=(gcc-4.9-*(/N[1]))
    [[ -z "$gccdir" ]] && \
        {echo "ERROR! No gcc source found; don't know what to do. Giving up"; \
         exit}

    pushd $gccdir

    ( cd debian;
      QUILT_PATCHES=../../patches quilt push -a
    ) || {echo "ERROR! Couldn't apply patches Giving up"; \
          exit}

    DEB_TARGET_ARCH=$arch DEB_CROSS_NO_BIARCH=yes with_deps_on_target_arch_pkgs=yes dpkg-buildpackage -d -T control || return

    # install deps
    killdeps
    export DEB_TARGET_GNU_TYPE=$( dpkg-architecture -a${arch} -qDEB_HOST_GNU_TYPE -f 2>/dev/null )
    sudo apt-get -y -f --no-install-recommends install libc6-dev:${arch} linux-libc-dev:${arch} libgcc1:${arch} gcc-4.9-base:${arch} binutils-${DEB_TARGET_GNU_TYPE} || return
    sudo mk-build-deps -t 'apt-get -y --no-install-recommends' -i -r debian/control || return
    dpkg -l gcc-4.9-build-deps >& /dev/null || \
                                  {echo "WARNING: couldn't install gcc dependencies for arch $arch. Skipping arch";
                                   return}


    # I tweak the source name so that each arch generates a different Debian upload
    perl -p -i -e "s/^gcc-4.9\S*/gcc-4.9-$arch/ if $. == 1" debian/changelog
    perl -p -i -e "s/^Source:\s*gcc-4.9\S*/Source: gcc-4.9-$arch/" debian/control

    # And now I build
    DEB_TARGET_ARCH=$arch DEB_CROSS_NO_BIARCH=yes with_deps_on_target_arch_pkgs=yes dpkg-buildpackage -us -uc -b || return

    killdeps || return

    failed=0
}




# I start with a blank slate
resetarches_all

# now get the dependencies
for arch ($arches[@]) {
        sudo dpkg --add-architecture $arch
    }
sudo apt-get update
sudo apt-get build-dep -y --no-install-recommends gcc-4.9

# and clear stuff out again
resetarches_all

# Now build one at a time
for arch ($arches[@]) {
        buildarch $arch
        popd

        ((failed)) && echo "WARNING: Failed to build arch $arch; skipping"
        resetarch $arch
}

return true
