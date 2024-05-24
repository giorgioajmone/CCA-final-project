#!/bin/bash
# head -n -1 test/build/$1.hex > mem.vmh
if [[ $OSTYPE == 'darwin'* ]]; then
	echo 'macOS'
	sed '$ d' _unused/test/build/$1.hex > mem.vmh
else
	head -n -1 _unused/test/build/$1.hex > mem.vmh
fi
python3 _unused/tools/arrange_mem.py