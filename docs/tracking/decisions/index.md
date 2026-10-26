# Decision records

| Record | Decision and consequence |
| --- | --- |
| [0001-hub-capability-projection.md](0001-hub-capability-projection.md) | Linked clients read a reduced data-plane projection rather than receive management credentials. |
| [0002-optional-lab-registration.md](0002-optional-lab-registration.md) | Optional policy services register into core-owned slots; startup activation remains synchronous. |
| [0003-native-test-executables.md](0003-native-test-executables.md) | Native model tests run as Swift executables rather than depending on unavailable test runtimes. |
| [0004-self-hosted-macos-runner.md](0004-self-hosted-macos-runner.md) | The `macos` job runs only on the self-hosted Mac CI runner; every outside contributor's fork run needs the maintainer's approval, a runner-side hook refuses untrusted jobs as a second layer, and the account exposure and public-log residue are accepted. |
