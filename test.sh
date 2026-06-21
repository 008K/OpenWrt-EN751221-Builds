#!/bin/bash

# PASSWORD env variable is needed

curl -fsSL https://raw.githubusercontent.com/cjdelisle/embedded-tools/refs/heads/master/remote_test.js \
	-o /tmp/remote_test.js

DEVICES=(
	"smartfiber_xp8421_b"
	"./openwrt/bin/targets/econet/en751221/openwrt-econet-en751221-smartfiber_xp8421-b-squashfs-tclinux.trx"
	"chinamobile_gs3101"
	"./openwrt/bin/targets/econet/en751221/openwrt-econet-en751221-chinamobile_gs3101-squashfs-tclinux.trx"
)

rm /tmp/tests_failed.txt 2>/dev/null

for (( i=0; i<${#DEVICES[@]}; i+=2 )); do
	DEVICE="${DEVICES[i]}"
	FILE="${DEVICES[i+1]}"
	echo "Testing device: $DEVICE with file: $FILE"
	node /tmp/remote_test.js \
		http://econet-linux.pkt.wiki:8889 \
		"$DEVICE" \
		"$FILE" || echo "TEST FAILED ON $DEVICE" >> /tmp/tests_failed.txt
done

if [ -e /tmp/tests_failed.txt ]; then
	cat /tmp/tests_failed.txt >&2
	exit 1
else
	echo "ALL TESTS PASSED"
	exit 0
fi
