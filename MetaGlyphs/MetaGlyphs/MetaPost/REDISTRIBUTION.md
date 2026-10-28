# Redistributing the bundled MetaPost engine

These requirements apply when distributing the plugin with the MetaPost
executable. The plugin invokes MetaPost as a separate command-line program;
these notices do not place the plugin itself under the GPL or LGPL.

## License texts and notices

Keep the engine’s copyright, attribution, license, and warranty notices.
Include the full GPL v3 (`COPYING`) and LGPL v3 (`COPYING.LESSER`) license texts
with the engine. Both texts are needed because LGPL v3 incorporates GPL v3
with additional permissions.

The executable also contains third-party components. Include their applicable
copyright notices and license texts, and comply with their terms. A binary
that links only to macOS system libraries can still contain third-party code
linked statically; checking its dynamic dependencies alone is not sufficient.
See `SOURCE.txt` for the components reported by this executable.

## Corresponding source

Provide the complete corresponding source for the exact engine binary being
distributed, including covered dependencies, applicable patches, and the
scripts needed to build it. A version label or a link to an upstream homepage
alone does not meet this requirement.

For releases distributed by download, a practical route under GPL v3 section
6(d) is to provide equivalent access to the corresponding source at no
additional charge, with clear directions beside the binary download. The
source may be hosted separately, including by a third party, but you remain
responsible for keeping the required source available. A different permitted
distribution method must satisfy its own conditions under section 6.

Record the exact source archives or revisions, dependency sources, patches,
and build scripts used for the binary. Update that record whenever replacing
the engine. If modifying covered code, identify the changes and their dates,
and retain the applicable license terms for that code.

## Recipients’ rights

Do not impose terms that restrict recipients’ rights under the engine’s
licenses. Separate terms for the plugin must respect those rights in the
covered components. These requirements do not themselves require publication
of the plugin’s own source code.

## Release status

The full license texts (`COPYING` and `COPYING.LESSER`) have not yet been
added to this folder. Obtain unmodified copies from GNU using the links below
and include them with the engine before publishing a binary release.

These instructions are not a complete source distribution. Matching source
access and component notices also remain to be verified as described in
`SOURCE.txt`. Do not present the general upstream links as a complete source
offer.

References:

- [GNU GPL v3, sections 4–6](https://www.gnu.org/licenses/gpl-3.0.html)
- [GNU LGPL v3](https://www.gnu.org/licenses/lgpl-3.0.html)
- [GNU FAQ: separate programs and aggregation](https://www.gnu.org/licenses/gpl-faq.en.html#MereAggregation)
