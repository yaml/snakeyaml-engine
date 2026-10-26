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
profile and your configured GPG key.
It creates `target/central-publishing/central-bundle.zip` with uploading
disabled, using the Central plugin's `skipUpload` option.

## Release

Verify ownership of `org.yamlstar` in the Central Portal first.
Configure Maven credentials using server ID `central` and configure GPG
signing outside the repository.
Keep credentials out of command arguments and version control.

Run the release yourself:

```bash
make release CENTRAL_NAMESPACE_VERIFIED=org.yamlstar
```

Automatic publication is disabled.
Review and publish the deployment in the Central Portal, then verify all
four artifacts and signatures under `org/yamlstar/snakeyaml-engine/3.2.0`.
Release the parser plugin only after the Engine artifacts are downloadable.
