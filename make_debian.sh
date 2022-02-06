#!/bin/sh
# ebusd - daemon for communication with eBUS heating systems.
# Copyright (C) 2014-2022 John Baier <ebusd@ebusd.eu>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

keepbuilddir=
if [ "x$1" = "x--keepbuilddir" ]; then
  keepbuilddir=1
  shift
fi
reusebuilddir=
if [ "x$1" = "x--reusebuilddir" ]; then
  reusebuilddir=1
  shift
fi

echo "*************"
echo " prepare"
echo "*************"
echo
tags=`git fetch -t`
if [ -n "$tags" ]; then
  echo "tags were updated:"
  echo $tags
  echo "git pull is recommended. stopped."
  exit 1
fi
VERSION=`head -n 1 VERSION`
ARCH=`dpkg --print-architecture`
BUILD="build-$ARCH"
RELEASE="ebusd-$VERSION"
PACKAGE="${RELEASE}_${ARCH}"
if [ -n "$reusebuilddir" ]; then
  echo "reusing build directory $BUILD"
else
  if [ -n "$keepbuilddir" ]; then
    ./autogen.sh $@ || exit 1
  fi
  rm -rf "$BUILD"
fi
mkdir -p "$BUILD" || exit 1
cd "$BUILD" || exit 1
if [ -z "$reusebuilddir" ]; then
  (tar cf - -C .. "--exclude=./$BUILD" --exclude=./.* "--exclude=*.o" "--exclude=*.a" .| tar xf -) || exit 1
fi

echo
echo "*************"
echo " build"
echo "*************"
echo
if [ -n "$reusebuilddir" ] || [ -z "$keepbuilddir" ]; then
  ./autogen.sh $@ || exit 1
fi
make DESTDIR="$PWD/$RELEASE" install-strip || exit 1
extralibs=
mqtt=
ldd $RELEASE/usr/bin/ebusd | egrep -q libmosquitto.so.0
if [ $? -eq 0 ]; then
  extralibs=', libmosquitto0'
  PACKAGE="${PACKAGE}_mqtt0"
  mqtt=1
else
  ldd $RELEASE/usr/bin/ebusd | egrep -q libmosquitto.so.1
  if [ $? -eq 0 ]; then
    extralibs=', libmosquitto1'
    PACKAGE="${PACKAGE}_mqtt1"
    mqtt=1
  fi
fi

if [ -n "$RUNTEST" ]; then
  echo
  echo "*************"
  echo " test"
  echo "*************"
  echo
  testdie() {
    echo "test failed"
    exit 1
  }
  ($RELEASE/usr/bin/ebusd -f -c src/lib/ebus/test -d /dev/null --checkconfig -i 10fe0900040000803e/ | egrep "received update-read broadcast test QQ=10: 0\.25$") || testdie
  if [ "$RUNTEST" = "full" ]; then
    (cd src/lib/ebus/test && make >/dev/null && ./test_filereader && ./test_data && ./test_message && ./test_symbol) || testdie
  fi
fi

echo
echo "*************"
echo " pack"
echo "*************"
echo
mkdir -p $RELEASE/DEBIAN $RELEASE/etc/logrotate.d || exit 1
if [ -n "$mqtt" ]; then
  mkdir -p $RELEASE/etc/ebusd || exit 1
  cp contrib/etc/ebusd/mqtt*.cfg $RELEASE/etc/ebusd/ || exit 1
fi
cp contrib/etc/logrotate.d/ebusd $RELEASE/etc/logrotate.d/ || exit 1
cp ChangeLog.md $RELEASE/DEBIAN/changelog || exit 1
cat <<EOF > $RELEASE/DEBIAN/control
Package: ebusd
Version: $VERSION
Section: net
Priority: required
Architecture: $ARCH
Maintainer: John Baier <ebusd@ebusd.eu>
Homepage: https://github.com/john30/ebusd
Bugs: https://github.com/john30/ebusd/issues
Depends: libstdc++6 (>= 4.8.1), libc6, libgcc1$extralibs
Recommends: logrotate
Description: eBUS daemon.
 ebusd is a daemon for handling communication with eBUS devices connected to a
 2-wire bus system.
EOF
cat <<EOF > $RELEASE/DEBIAN/dirs
/etc/default
/etc/init.d
/etc/logrotate.d
/lib/systemd/system
/usr/bin
EOF
cat <<EOF > $RELEASE/DEBIAN/conffiles
/etc/default/ebusd
EOF
if [ -n "$mqtt" ]; then
  echo '/etc/ebusd' >> $RELEASE/DEBIAN/dirs
  for i in contrib/etc/ebusd/mqtt*.cfg; do
    echo "${i##contrib}" >> $RELEASE/DEBIAN/conffiles
  done
fi
cat <<EOF > $RELEASE/DEBIAN/postinst
#!/bin/sh
if [ -d /run/systemd/system ]; then
  start='systemctl start ebusd'
  autostart='systemctl enable ebusd'
else
  start='service ebusd start'
  autostart='update-rc.d ebusd defaults'
fi
echo "Instructions:"
echo "1. Edit /etc/default/ebusd if necessary"
echo "   (especially if your device is not /dev/ttyUSB0)"
echo "2. Start the daemon with '\$start'"
echo "3. Check the log file /var/log/ebusd.log"
echo "4. Make the daemon autostart with '\$autostart'"
EOF
chmod 755 $RELEASE/DEBIAN/postinst

dpkg -b $RELEASE || exit 1
mv $RELEASE.deb "../${PACKAGE}.deb" || exit 1

echo
echo "*************"
echo " cleanup"
echo "*************"
echo
cd ..
if [ -n "$keepbuilddir" ]; then
  echo "keeping build directory $BUILD"
else
  rm -rf "$BUILD"
fi

echo
echo "Package created: ${PACKAGE}.deb"
echo
echo "Info:"
dpkg --info "${PACKAGE}.deb"
echo
echo "Content:"
dpkg -c "${PACKAGE}.deb"
