
discard """
    action: "reject"
    valgrind: true
    cmd: "nim c -r $file"
    matrix: "-d:release; --verbose"
"""

import ../src/llex

var ls = initWithFile("nimlua/test.lua")
assert true

