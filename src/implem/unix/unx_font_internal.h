/**************************************************************************/
/*                                                                        */
/*    Copyright 2022 OCamlPro                                             */
/*                                                                        */
/*  All rights reserved. This file is distributed under the terms of the  */
/*  GNU Lesser General Public License version 2.1, with the special       */
/*  exception on linking described in the file LICENSE.                   */
/*                                                                        */
/**************************************************************************/

#ifndef __UNX_FONT_INTERNAL_H
#define __UNX_FONT_INTERNAL_H

#include <stdint.h>
#include <stdbool.h>

#include <ft2build.h>
#include FT_FREETYPE_H

#include "../font_internal.h"
#include "../font.h"
#include "../hashtable.h"

/* Glyph masks, as cached in a font */
typedef struct unx_glyph_t {
  uint32_t key;     /* character and subpixel offset */
  bool ok;          /* whether FreeType could render it */
  uint8_t *data;
  int32_t width;
  int32_t height;
  int32_t pitch;
  int32_t left;
  int32_t top;
  double advance;
} unx_glyph_t;

/* Glyph metrics, as cached in a font */
typedef struct unx_metrics_t {
  uint32_t key;     /* character */
  bool ok;          /* whether FreeType could load it */
  glyph_metrics_t m;
} unx_metrics_t;

typedef struct unx_font_t {

  /* Common to all fonts */
  font_t base;

  /* Specific to FreeType fonts */
  FT_Face ft_face;

  /* Rendered glyph masks (unx_glyph_t), by character and subpixel
     offset; created on first use */
  hashtable_t *glyphs;

  /* Glyph metrics (unx_metrics_t), by character; created on first use */
  hashtable_t *metrics;

} unx_font_t;

#endif /* __UNX_FONT_INTERNAL_H */
