#!/usr/bin/env python

import argparse
import os
import subprocess

_DESCRIPTION = """
Generate the Sources/SwiftSourceKit/UIDs.swift from UIDs.py in the main Swift
repository.
Requires swift to be checked out next to the stress tester like this:
  workspace/
    swift/
    swift-stress-tester/
      SourceKitStressTester/
"""

def parse_args():
  """
  Only used to display the help message for now/
  """
  parser = argparse.ArgumentParser(
    formatter_class=argparse.RawDescriptionHelpFormatter,
    description=_DESCRIPTION
  )

  return parser.parse_args()

def generate_uids_file():
  package_dir = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
  workspace_dir = os.path.dirname(os.path.dirname(package_dir))
  swift_dir = os.path.join(workspace_dir, "swift")
  gyb_exec = os.path.join(swift_dir, "utils", "gyb")


  swift_source_kit_sources_dir = os.path.join(
    package_dir,
    "Sources",
    "SwiftSourceKit"
  )

  subprocess.call([
    gyb_exec,
    os.path.join(swift_source_kit_sources_dir, "UIDs.swift.gyb"),
    "--line-directive=",
    "-o", os.path.join(swift_source_kit_sources_dir, "UIDs.swift"),
  ])

def main():
  args = parse_args()
  generate_uids_file()


if __name__ == "__main__":
  main()
