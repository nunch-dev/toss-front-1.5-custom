#!/bin/bash
set -euo pipefail
umask 077
directory="${1:?supply a new empty TLS directory}"
openssl_bin="${OPENSSL_BIN:-/opt/homebrew/opt/openssl@3/bin/openssl}"
[[ -d "$directory" && ! -L "$directory" ]]
for name in ca server wrong-host; do
    for extension in key pem der csr; do
        [[ ! -e "$directory/$name.$extension" && ! -L "$directory/$name.$extension" ]]
    done
done
"$openssl_bin" req -x509 -newkey rsa:2048 -noenc -days 1 \
    -keyout "$directory/ca.key" -out "$directory/ca.pem" \
    -subj "/CN=PLF02WH disposable test CA" \
    -addext basicConstraints=critical,CA:TRUE,pathlen:0 \
    -addext keyUsage=critical,keyCertSign,cRLSign
"$openssl_bin" x509 -in "$directory/ca.pem" -outform DER -out "$directory/ca.der"
for name in server wrong-host; do
    if [[ "$name" == server ]]; then
        subject="/CN=127.0.0.1"
        alternative="subjectAltName=IP:127.0.0.1"
    else
        subject="/CN=wrong.test"
        alternative="subjectAltName=DNS:wrong.test"
    fi
    "$openssl_bin" req -new -newkey rsa:2048 -noenc \
        -keyout "$directory/$name.key" -out "$directory/$name.csr" \
        -subj "$subject" -addext "$alternative" \
        -addext basicConstraints=critical,CA:FALSE \
        -addext keyUsage=critical,digitalSignature,keyEncipherment \
        -addext extendedKeyUsage=serverAuth
    "$openssl_bin" x509 -req -in "$directory/$name.csr" -days 1 \
        -CA "$directory/ca.pem" -CAkey "$directory/ca.key" \
        -copy_extensions copy -out "$directory/$name.pem"
    "$openssl_bin" verify -CAfile "$directory/ca.pem" -purpose sslserver "$directory/$name.pem"
done
"$openssl_bin" verify -CAfile "$directory/ca.pem" -verify_ip 127.0.0.1 "$directory/server.pem"
