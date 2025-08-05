#!/usr/bin/env bash
set -e

for i in examples/*.pelia; do
	echo "===> $i"
	./zig-out/bin/waver-zig "$i"
done
