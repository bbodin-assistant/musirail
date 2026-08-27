# Android releases

The CI workflow publishes an unsigned-for-production debug APK for every push
and pull request. Tagged releases require the maintainer's Android signing key.

## Configure signing once

Keep the original keystore backed up outside GitHub and outside this
repository. Add these repository Actions secrets:

- `ANDROID_KEYSTORE_BASE64`: the complete keystore encoded with
  `base64 -w 0 release.keystore`
- `ANDROID_KEYSTORE_ALIAS`: the key alias
- `ANDROID_KEYSTORE_PASSWORD`: the keystore/key password

The workflow reconstructs the keystore only inside the temporary runner and
passes its path and credentials through Godot's Android signing environment
variables. Keystores and `.jks` files are ignored and rejected by the public
tree check.

## Publish

1. Confirm the `main` branch CI is green.
2. Update user-facing release notes if necessary.
3. Create and push a semantic version tag:

   ```bash
   git tag -s v0.1.0 -m "Musirail v0.1.0"
   git push origin v0.1.0
   ```

4. The release workflow derives Android's version name from the tag and uses
   the workflow run number as the monotonically increasing version code.
5. It builds and verifies the signed APK, writes a SHA-256 checksum, creates a
   build-provenance attestation, and attaches the APK and checksum to the
   matching GitHub Release.

Never replace the signing key after users install a release. Android requires
the same key for future updates using the same package identifier.
