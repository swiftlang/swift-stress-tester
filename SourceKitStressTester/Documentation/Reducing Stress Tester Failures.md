# Reducing Stress Tester Failures

If the SourceKit stress tester job fails, this guide describes how to generate reduced and actionable bug reports from those failures.

1. Acquire a Swift toolchain that contains the failure. Usually the easiest way to do this is to wait a few days until a Swift open source toolchain is published with that failure. All upcoming steps assume that `/Library/Developer/Toolchains/swift-latest.xctoolchain` points to a Swift toolchain with the issue to reproduce. If you built a toolchain locally, adjust the steps as necessary.
2. Install the SourceKit stress tester into the toolchain by running `Utilities/install-stress-tester-to-toolchain.sh`
3. Reproduce the stress tester failure locally by running `Utilities/run-stress-tester-locally.py`, specifying `--project`, `--file-filter`, `--rewrite-modes` and `--offset-filter` from the failure mentioned in the CI failure log.
  - If this does not reproduce the failure, try removing `--offset-filter` since the failure might be caused by dependencies between the requests on the file, but it’s pretty rare.
4. This should reproduce the stress tester failure locally and you should see a crashlog of SourceKitService in Console. It might print the same failure multiple times but the most important thing is, that the log contains an entry with `Reproduce with: \nsk-stress-test ...`. Copy the `sk-stress-test-command`
5. Run the `sk-stress-test` command locally (`sk-stress-test` was installed to `/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/sk-stress-test` by step 2).
  - You can add `--print-actions` to get a better idea about the requests that `sk-stress-test` is performing.
6. Add `--print-requests` to the `sk-stress-test` invocation and let it run until you see something like `sourcekit: [1:connection-event-handler:9731: 0.0000] Connection interrupt`. Copy the request YAML and save it to `/tmp/req.yml`
7. Run this request standalone using `/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/sourcekit-lsp debug run-sourcekitd-request --request-file /tmp/req.yml`
  - If this does not reproduce the failure, the previous requests executed by `sk-stress-test` are needed to hit it. Extracting all of them (`split -p '^{' input.txt` is a good command) and then pass them to `sourcekit-lsp debug run-sourcekitd-request` by passing `--request-file` multiple times.
8. If a single request hits the failure and it is a crash, `/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/sourcekit-lsp debug reduce --request-file /tmp/req.yml` can automatically reduce the majority of the failure, a few manual reduction steps usually help towards the end. Otherwise you have to reduce it manually. The `--position` parameter to `sourcekit-lsp debug run-sourcekitd-request` can override the position in the request so you don’t have to do offset calculations.
9. Build `sourcekitd-test` locally and create a lit test that reproduces the failure. Depending on the crash, it might be possible to reproduce the failure with `swift-frontend` alone.
10. Depending on the failure, bisect the `swift` repository to find the commit that introduced the failure or determine the likely cause of the failure by looking at the git history between the last successful and the first failing stress tester run.
11. File an issue with the lit test at https://github.com/swiftlang/swift and attach the `found by stress tester` label.
12. Add an XFail for this issue to https://github.com/swiftlang/swift-source-compat-suite/blob/main/sourcekit-xfails.json. The original failure from the CI log has a template for the XFail.
