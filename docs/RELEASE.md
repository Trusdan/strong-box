# Release checklist

How to cut a Strongbox release, for example `v0.1.0`. **The maintainer creates the tag and the GitHub release.** Contributors and agents prepare everything up to step 7 in a pull request, and never tag, publish or push to `main`.

A release has **two zips**:

| Zip | Contents | For |
| --- | --- | --- |
| `strongbox-<version>.zip` | `addons/strongbox/` and `LICENSE` | every game |
| `strongbox-wyrd-bridge-<version>.zip` | `addons/strongbox_wyrd/` and `LICENSE` | games that also use Wyrd (optional) |

**Neither zip contains `addons/wyrd/`.** That folder is a test-only copy of Wyrd (pinned in `tools/wyrd-pin.env`), and a game gets Wyrd from Wyrd's own releases. Nor do the zips contain `example/`, `tests/`, `docs/`, `tools/` or the dev `project.godot`.

## Before the tag (in a pull request)

1. **CI is green on `main`.** All of `test`, `test-windows` and `test-core-only` pass. The `test` job includes the API-docs, editor-load, content-hygiene and Wyrd pin checks.
2. **Versions are bumped.** Both addons carry the release version in two places each:
   - `addons/strongbox/plugin.cfg` (`version="…"`) and `addons/strongbox/VERSION`;
   - `addons/strongbox_wyrd/plugin.cfg` (`version="…"`) and `addons/strongbox_wyrd/VERSION`.

   `tests/test_smoke.gd` fails if the core's two differ.
3. **`CHANGELOG.md` is updated.** Move "Unreleased" to the new version with today's date, and keep the "Before 1.0" list current.
4. **The API docs are regenerated.** Run `tools/gen_api_docs.sh` and commit `docs/api/`. `tools/gen_api_docs.sh --check` must print "docs/api/ is up to date."
5. **The example runs.** Open the project in Godot (the pinned version, `tools/pins.env`) and press F5. Check that:
   - **Rest in bed** saves;
   - room changes autosave;
   - the chest, coin, lever and a dropped crate persist across rooms;
   - **Load** restores an earlier save, and **Delete** removes a slot;
   - the Debugger shows no errors.
6. **The README quick start still works** in an empty project of the minimum Godot version (4.7).
7. **The pull request is merged** into `main`, with CI green on the merge commit.

## The tag and the release (maintainer only)

8. **Tag** the merge commit on `main`:

   ```bash
   git tag -a v0.1.0 -m "Strongbox 0.1.0"
   git push origin v0.1.0
   ```

9. **Build the two zips from the tag**, so nothing uncommitted can slip in:

   ```bash
   git archive --format=zip -o strongbox-0.1.0.zip v0.1.0 addons/strongbox LICENSE
   git archive --format=zip -o strongbox-wyrd-bridge-0.1.0.zip v0.1.0 addons/strongbox_wyrd LICENSE
   ```

10. **Check the zips:**

    ```bash
    unzip -Z1 strongbox-0.1.0.zip | grep -v -E '^(addons/strongbox/|LICENSE$|addons/$)'                    # prints nothing
    unzip -Z1 strongbox-wyrd-bridge-0.1.0.zip | grep -v -E '^(addons/strongbox_wyrd/|LICENSE$|addons/$)'   # prints nothing
    for z in strongbox-*.zip; do unzip -Z1 "$z"; done | grep -c '^addons/wyrd/'                           # prints 0
    unzip -p strongbox-0.1.0.zip addons/strongbox/VERSION                                                  # prints 0.1.0
    ```

    Then unzip the core zip into an empty Godot 4.7 project and follow the README's Install and Quick start.
11. **Create the GitHub release** for the tag:
    - title "Strongbox 0.1.0";
    - the version's `CHANGELOG.md` section as the notes;
    - both zips attached, with the bridge zip marked as optional and for Wyrd users only.
12. **After the release:** add a new "Unreleased" heading to `CHANGELOG.md` in the next pull request.
