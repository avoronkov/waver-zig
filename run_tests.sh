#!/usr/bin/env bash

rc=0
for d in pkg/wav pkg/seq; do
	pushd "$d"
	zig build test --summary all || rc=1
	popd
done
exit "$rc"
