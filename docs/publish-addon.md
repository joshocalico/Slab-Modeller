# Publish an addon build

Use the **Build drop-in addon** GitHub Actions workflow to produce an installable addon for Godot 4.7. The workflow runs on branch pushes, pull requests, `v*` tags, and manual dispatches.

## Download a development build

1. Push the implementation and workflow to GitHub.
2. Open **Actions → Build drop-in addon** and select the successful run for that commit.
3. Download the **slab-addon** artifact and extract the artifact wrapper.
4. Extract the enclosed `slab-addon.zip` into your Godot project root.
5. Restart Godot and enable **Slab** in **Project Settings → Plugins**.

The project must contain `addons/slab/plugin.cfg`. Do not put the artifact wrapper ZIP into the project. The build includes both editor/debug and release/export libraries for Windows x64, Linux x64, and universal macOS. Linux builds use Ubuntu 22.04. macOS binaries include Intel and Apple Silicon code and are ad-hoc signed, not notarized. Android, iOS, Web, and Windows/Linux ARM are not included.

## Publish a version

1. Set the plugin version in `project/addons/slab/plugin.cfg` and commit it with the release changes.
2. Create and push a tag beginning with `v`, such as `v0.1.0`.
3. Wait for every build, kernel test, and packaging job to pass.
4. Open the draft GitHub release created for that tag. It contains `slab-addon.zip` and `SHA256SUMS`.
5. Test the ZIP in a fresh Godot project on the supported systems, add release notes, then publish the draft.

Native kernel tests run for both configurations on each runner. The packaging tests check archive layout and reject missing or unexpected binaries. These checks do not replace opening the addon in Godot on each supported platform.

CI uses `ci/build_profile.json` to compile the Godot C++ classes used by Slab and their base classes. When adding a C++ dependency on another Godot class, add it to that profile. The profile does not restrict classes available to GDScript.

## Package binaries locally

1. Collect the six built runtime files in a staging directory. Preserve the macOS framework directories. The filenames must match `project/addons/slab/slab.gdextension`.
2. Run `python3 scripts/slab-package --binaries /path/to/staging --output /path/to/slab-addon.zip` from the checkout.

The script includes tracked addon files and the MIT license under `addons/slab/`. It excludes demo scenes, the docs website, object files, and test executables. Keep the staging directory limited to runtime libraries. Missing or empty libraries stop packaging before an existing ZIP is replaced.
