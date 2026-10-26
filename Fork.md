# YAMLStar SnakeYAML Engine fork

This fork starts at canonical upstream tag `snakeyaml-engine-3.2`:

- Repository: https://codeberg.org/snakeyaml/snakeyaml-engine
- Annotated tag object: `3bfec70d567e632d282866107840cb85c98fc063`
- Source commit: `8a670d3f78ebfd3c60fe6ea16f5ea94f0b2c611b`
- Fork coordinate: `org.yamlstar:snakeyaml-engine:3.2.0`

The Java implementation, package names, Apache 2.0 license, and upstream
attribution are retained.
Initial changes cover build and publication ownership only.
The project that previously used Engine 2.7 must validate the upgrade to 3.2.
Builds check formatting and licenses without rewriting source files.

## Build

Makes installs Maven and Java under `.cache/`.

```bash
make test
make install
make bundle
```

`bundle` signs the main JAR, sources, Javadoc, and POM using Maven's release
profile and the GPG key specified in `~/.yamlstar-secrets.yaml`.
It creates `target/central-publishing/central-bundle.zip` with uploading
disabled, using the Central plugin's `skipUpload` option.

## Release

Verify ownership of `org.yamlstar` in the Central Portal first.
The release command reads `java.token` (falling back to `central.token`) and
`gpg.key-id` from `~/.yamlstar-secrets.yaml`, using the same credential format
as YAMLStar.
It also reads the optional `gpg.passphrase`.
The signing key must be available to GPG.
No Maven settings file or Maven-home override is needed.

Run the release yourself:

```bash
make release v=3.2.0
```

The requested version must match `pom.xml`.
Use `3.2.1`, `3.2.2`, and later patch versions for additional fork releases
based on upstream `3.2`.
Update the POM version, SCM tag, and Makefile version before each release,
and record the exact upstream base in the release notes.
When adopting upstream `3.3`, start the fork's new line at `3.3.0`.
The parser plugin pins its Engine dependency, so adopting a newer fork
version also requires a plugin release with rebuilt native libraries.

`CENTRAL_TOKEN`, `GPG_KEY_ID`, and `GPG_PASSPHRASE` environment variables can
override file values.
`YS_SECRETS_FILE` selects an alternative secrets file.
The helper passes credentials through environment variables and temporary
Maven settings containing only variable references.

Automatic publication is disabled.
Review and publish the deployment in the Central Portal, then verify all
four artifacts and signatures under `org/yamlstar/snakeyaml-engine/3.2.0`.
Release the parser plugin only after the Engine artifacts are downloadable.
