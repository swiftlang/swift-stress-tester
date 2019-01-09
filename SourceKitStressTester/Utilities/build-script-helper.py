#!/usr/bin/env python

"""
  This source file is part of the Swift.org open source project

  Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
  Licensed under Apache License v2.0 with Runtime Library Exception

  See https://swift.org/LICENSE.txt for license information
  See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

  ------------------------------------------------------------------------------
  This is a wrapper around the relocated build-script-helper.py (now at
  ../../build-script-helper.py) which allows it to be used by old versions of
  the main swift repo's build-script.py.

  It has been left here to ease the transition to the new helper script; it
  should eventually be removed.
"""

from __future__ import print_function

import os

def main():
  print("(Using swift-stress-tester build compatibility shim...)")
  impl_script = ImplScript(__file__)
  impl_main = impl_script.get_local('main')
  impl_main(['--package-dir', impl_script.package_dir])

class ImplScript(object):
  def __init__(self, file_path):
    # if file_path = <base>/<package>/<ignored>/<scriptname>, then sets...
    #
    # Local variables:
    #
    #   script_name = <scriptname>
    #   utilities_path = <base>/<package>/<ignored> (temporary)
    #   repo_path = <base> (temporary)
    #   impl_path = <base>/<scriptname>
    #
    # Attributes:
    #
    #   self.package_dir = <package>
    #   self.locals = locals after performing exec(impl_path)

    utilities_path, script_name = os.path.split(file_path)
    repo_path, self.package_dir = os.path.split(os.path.dirname(utilities_path))
    impl_path = os.path.join(repo_path, script_name)

    self.locals = dict(
                      __file__=impl_path,
                      __name__='__exec__',
                      __package__=None
                      )
    exec(open(impl_path).read(), self.locals)

  def get_local(self, name):
    return self.locals[name]

if __name__ == '__main__':
  main()
