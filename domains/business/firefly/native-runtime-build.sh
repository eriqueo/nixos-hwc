#!/bin/sh
# Temporary same-PHP rebuild for ABI-correct libxml2/curl fixes.
# Remove when upstream supplies the exact apps with qualified linked libraries.
set -eu
export SOURCE_DATE_EPOCH=1793577600
mkdir -p /build /native/usr/lib/x86_64-linux-gnu /native/usr/bin /native/usr/local/bin /native/usr/local/sbin
cd /build
# Buildah's network=none can leave /etc/hosts empty. Bind only the local test
# server name; external networking remains unavailable in this build namespace.
if ! getent ahostsv4 localhost >/dev/null; then
  printf '127.0.0.1 localhost\n' >> /etc/hosts
fi
getent ahostsv4 localhost >/dev/null
# The build stage inherits a serving INI with environment interpolation. Nested
# upstream test subprocesses use the compiled default INI search path, so isolate
# that serving configuration here too. The final image retains its original INI.
if [ -d /usr/local/etc/php ]; then
  mv /usr/local/etc/php /build/serving-php-ini
fi
build_library() {
  archive=$1; directory=$2; shift 2
  mkdir "$directory"
  tar xf "/sources/$archive" -C "$directory" --strip-components=1
  cd "$directory"
  ./configure --prefix=/usr --libdir=/usr/lib/x86_64-linux-gnu "$@"
  make -j4
  make check
  make install
  ldconfig
  cd /build
}
build_library ngtcp2.tar.xz ngtcp2 --enable-lib-only --with-openssl
build_library libxml2.tar.xz libxml2 --with-legacy --with-python=no
mkdir curl
cd curl
tar xf /sources/curl.tar.xz --strip-components=1
./configure --prefix=/usr --libdir=/usr/lib/x86_64-linux-gnu --with-openssl --with-gssapi --with-libssh2 --with-nghttp2 --with-nghttp3 --with-ngtcp2 --with-librtmp --enable-ldap --enable-ldaps --enable-versioned-symbols
make -j4
make test TFLAGS=-j4
make install
ldconfig
cd /build
mkdir php
cd php
tar xf /sources/php.tar.xz --strip-components=1
# Keep the donor's configuration rather than maintaining a second option list.
configure_options=$(/usr/local/bin/php-config --configure-options)
configure_options=${configure_options%% build_alias=*}
# Intentional word splitting: php-config emits configure arguments.
./configure $configure_options
make -j4
# make test inherits the serving image's php.ini (including environment-based
# lexer settings). Run the full upstream harness with its own development INI.
NO_INTERACTION=1 REPORT_EXIT_STATUS=1 sapi/cli/php -n run-tests.php -n -c php.ini-development -d extension_dir=/build/php/modules -d extension=sodium -j4
cp sapi/cli/php /native/usr/local/bin/php
cp sapi/fpm/php-fpm /native/usr/local/sbin/php-fpm
cp /usr/bin/curl /native/usr/bin/curl
for library in libxml2.so.16 libcurl.so.4 libngtcp2.so.16 libngtcp2_crypto_ossl.so.0; do
  cp -L "/usr/lib/x86_64-linux-gnu/$library" "/native/usr/lib/x86_64-linux-gnu/$library"
done
mkdir -p /native/usr/share/hwc-firefly-native
cp /sources/manifest.json /native/usr/share/hwc-firefly-native/sources.json
