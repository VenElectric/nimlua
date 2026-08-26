# Package

version       = "0.1.0"
author        = "venduplicate"
description   = "A new awesome nimble package"
license       = "MIT"
srcDir        = "src"
bin           = @["kuu"]


# Dependencies

requires "nim >= 2.0.4","puppy"

before install:
  echo "before install hook ran"