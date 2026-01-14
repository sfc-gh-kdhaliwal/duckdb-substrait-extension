# Upgrading DuckDB Version

## Steps

1. Test the build against the target DuckDB version:

```sh
./build_extension_docker_local_optimized.sh v1.5.0 ./output_test linux amd64
```

2. If the build succeeds, update the `duckdb` submodule:

```sh
cd duckdb
git fetch --tags
git checkout v1.5.0
cd ..
```

3. Update the `extension-ci-tools` submodule to match:

```sh
cd extension-ci-tools
git fetch origin
git checkout <matching-commit>
cd ..
```

4. Stage, commit, and tag:

```sh
git add duckdb extension-ci-tools
git commit -m "Upgrade DuckDB to v1.5.0"
git tag -a v1.5.0 -m "Release v1.5.0"
```

5. Download artifacts from Github Action
On every commit pushed to github, the following action should trigger builds for all three OS archs: https://github.com/sfc-gh-kdhaliwal/duckdb-substrait-extension/actions/workflows/build-extension.yml


## Build Script Options

```
./build_extension_docker_local_optimized.sh [DUCKDB_VERSION] [OUTPUT_DIR] [PLATFORM] [ARCHITECTURE]
```

- `PLATFORM`: `linux`, `darwin`, or `all`
- `ARCHITECTURE`: `amd64`, `arm64`, or `all`
