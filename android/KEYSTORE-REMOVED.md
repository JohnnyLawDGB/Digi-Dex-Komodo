# The committed keystore was removed on 2026-10-11

`android/app/key.jks` and `android/key.properties` were committed to this **public** repository
in `53632202` ("add test key") and removed on 2026-10-11.

**Treat that key as permanently compromised.** Deleting the files removes them from the working
tree, not from git history — anyone can still recover them from `53632202`. Nothing here undoes
the exposure; it only stops the next reader finding a live-looking keystore in the tree.

**It signs nothing that ships.** Verified 2026-10-11:

| | SHA-256 | Status |
| --- | --- | --- |
| This removed keystore | `19:AE:22:49:F1:83:99:AE:…` | legacy `io.digibyte.dex` build, never published by us |
| The DigiByte DEX upload key | `7A:DE:BB:DD:62:52:31:5D:…` | different key, never committed, gitignored, enforced by `tool/release_android.sh` |

Every build on Play internal testing (`me.digiscope.wallet`, versionCodes 398608 through 407145)
is signed by the second key, which is not in any repository. Play App Signing is enabled, so
Google holds the app signing key and the upload key is resettable from Play Console.

No rotation is required for the removed key: the legacy app is dead and we do not publish it.

The gradle build reads `key.properties` behind an `exists()` guard, so its absence changes nothing.
