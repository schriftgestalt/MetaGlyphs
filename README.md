# MetaGlyphs for Glyphs 4

Draw glyphs with MetaPost code directly in Glyphs 4. The plugin generates
outlines from your code, using each layer’s width and font metrics.

## Getting started

- Download the complete ZIP file and unpack it, or clone the repository.
    Double click the MetaGlyphs.glyphsPlugin file. Confirm the dialog that appears in Glyphs.
    Restart Glyphs
- Open a glyph and select **MetaGlyphs** in the Edit View’s left sidebar.
- Enter MetaPost code in the **Glyph** tab. Changes are saved in the font and
  the preview updates as you type. Undo and Redo are supported.

The **Messages** area below the tabs shows compilation and outline-import
errors, including the compiler’s error details. You can select and copy
the message.

The plugin includes MetaPost for Intel and Apple Silicon Macs; a separate TeX
installation is not needed.

Try this to draw an oval with a counter:

```metapost
fill fullcircle xscaled (w-100u) yscaled h shifted (w/2,h/2);
unfill fullcircle xscaled (w-220u) yscaled (h-120u) shifted (w/2,h/2);
```

Enter only the drawing code—the plugin adds `beginfig`, `endfig`, and `end`.
The same code is used for every layer of the glyph, with that layer’s metrics.
The generated outlines are used for preview and output; the layer’s width and
anchors are preserved. Clear the Glyph tab to stop generating that glyph.

## Available variables

Coordinates use font units, with the baseline at zero and positive Y upward.

| Variable | Value |
| --- | --- |
| `w` | Current layer width |
| `h`, `capheight` | Cap height |
| `d` | Depth below the baseline (negative of the descender metric) |
| `ascender`, `descender`, `xheight` | Layer metrics |
| `upm` | Font units per em |
| `u` | `upm / 1000` |
| axis tag | the axis value |

Changing these variables in your code affects the drawing, without changing
the font’s stored metrics.

## Shared code and imports

Use the **Global** tab for definitions shared by your glyphs. This code runs
before each glyph’s drawing code.

The two tabs store code separately in `font.userData["metaFont"]` and
`glyph.userData["metaFont"]`. Global code runs after the layer variables above
are assigned and before `beginfig`. For example, define a helper in **Global**:

```metapost
vardef oval(expr dx, dy) =
  fullcircle xscaled dx yscaled dy shifted (w/2, h/2)
enddef;
```

Then use it in **Glyph**:

```metapost
fill oval(w-100u, h);
unfill oval(w-220u, h-120u);
```

You can also load a MetaPost file with `input filename.mp;`. Save the font
first and place the imported file beside it. Click **↺** after editing
imported files to regenerate the outlines.
a
Subfolders and quoted filenames with spaces are supported, for example
`input "helpers/shared shapes.mp";`. Nested imports use the saved font’s folder
as their base too; for a `.glyphspackage`, this is the package’s containing
folder. Keep helper files to definitions and setup, without a terminating
`end`. Generated files and logs stay in a private temporary folder. Global
edits invalidate all glyph layers, and both editors support Undo/Redo.

## Supported drawing

The plugin supports fills, cubic curves, circular and elliptical pen strokes,
and white `unfill` cutouts. Overlapping shapes are combined in drawing order.

Clipping, dashed strokes, text/labels, and colored painting are not supported.
Use MetaPost syntax; MetaFont raster operations and complete `.mf` font drivers
are not supported. If compilation fails, the layer’s existing shapes are
preserved.

For the language reference and tutorials, see the
[MetaPost website](https://tug.org/metapost.html).

## MetaPost copyright and license

This plugin bundles MetaPost 3.00 from TeX Live 2026. MetaPost was originally
written by John Hobby; the CWEB version was written by Taco Hoekwater and is
maintained by Luigi Scarso and the MetaPost team.

The MetaPost source code and the bundled `mpost.mp` and `plain.mp` macro files
are in the public domain. The MetaPost executable also includes code licensed
under the [GNU Lesser General Public License, version 3 or later](https://www.gnu.org/licenses/lgpl-3.0.html),
and is therefore covered by that license. MetaPost is provided without warranty.
See the [upstream MetaPost distribution](https://ctan.org/pkg/metapost) for
source and license information.

This notice applies to the bundled engine and its components. It does not
place the plugin itself under the GPL or LGPL.

If you redistribute the plugin with MetaPost, retain its notices, include the
GPL and LGPL license texts and required component licenses, and provide
compliant access to the complete corresponding source for the exact engine
binary and its covered dependencies. A general upstream homepage link alone
is not sufficient. See the [redistribution requirements](MetaGlyphs/MetaGlyphs/MetaPost/REDISTRIBUTION.md)
and [source information](MetaGlyphs/MetaGlyphs/MetaPost/SOURCE.txt).
