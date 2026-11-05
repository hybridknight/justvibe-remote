# Publishing the GitHub Wiki

The Markdown files in `docs/wiki/` are the wiki source extracted from the project README. `Home.md` is the landing page and `_Sidebar.md` provides navigation. The README links to the [published GitHub Wiki](https://github.com/hybridknight/justvibe-remote/wiki); keep these source pages in sync with the separate wiki repository.

## First publication

1. After making the repository public, enable **Wikis** in the repository settings.
2. Open the **Wiki** tab, create an initial **Home** page, and save it. GitHub requires an initial page before the wiki repository can be cloned.
3. From the main repository root, clone the separate wiki repository to a sibling folder, copy the prepared pages, and review the changes:

   ```sh
   git clone https://github.com/hybridknight/justvibe-remote.wiki.git ../justvibe-remote.wiki
   cp docs/wiki/*.md ../justvibe-remote.wiki/
   git -C ../justvibe-remote.wiki diff
   git -C ../justvibe-remote.wiki status --short
   ```

4. Publish the reviewed pages:

   ```sh
   git -C ../justvibe-remote.wiki add -- '*.md'
   git -C ../justvibe-remote.wiki commit -m "Extract README documentation into wiki"
   git -C ../justvibe-remote.wiki push
   ```

5. Check the Home page, sidebar, page links, and links to the main repository. The README links to the published wiki; keep its page links aligned with the wiki filenames.

The copy replaces matching filenames in the wiki checkout; review any existing wiki edits before publishing. Other wiki files are left intact. These instructions do not change repository visibility or publish anything automatically.

## Keeping pages current

Edit `docs/wiki/` in the main repository, then copy the reviewed pages into the wiki checkout and commit and push there. Pull existing wiki changes before copying; reconcile any edits made through GitHub with these source files first. Keep technical references in `docs/` and plugin documentation with their plugins.

Page links use extensionless wiki slugs (for example, `Getting-started`). In a local checkout, open the matching `.md` file. Links to source files use the main repository’s `main` branch so they continue to work when the pages are copied to the separate wiki repository.

See [GitHub’s instructions for adding or editing wiki pages](https://docs.github.com/en/communities/documenting-your-project-with-wikis/adding-or-editing-wiki-pages).
