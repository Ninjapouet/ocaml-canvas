/**************************************************************************/
/*                                                                        */
/*    Copyright 2022 OCamlPro                                             */
/*                                                                        */
/*  All rights reserved. This file is distributed under the terms of the  */
/*  GNU Lesser General Public License version 2.1, with the special       */
/*  exception on linking described in the file LICENSE.                   */
/*                                                                        */
/**************************************************************************/

#ifndef __FONT_H
#define __FONT_H

#include <stdint.h>
#include <stdbool.h>

#include "point.h"
#include "rect.h"
#include "polygon.h"
#include "transform.h"
#include "font_desc.h"

typedef struct font_t font_t;

/* Metrics of a glyph, in pixels, relative to the pen position on the
   baseline. Distances to the left and below are negative. */
typedef struct glyph_metrics_t {
  double advance; /* horizontal advance of the pen */
  bool has_ink;   /* false for glyphs that draw nothing (e.g. space) */
  double left;    /* abscissa of the left side of the ink */
  double right;   /* abscissa of the right side of the ink */
  double top;     /* ordinate of the top of the ink (upwards) */
  double bottom;  /* ordinate of the bottom of the ink (upwards) */
} glyph_metrics_t;

font_t *
font_create(
  font_desc_t *fd);

void
font_destroy(
  font_t *f);

/* Font cache: creating a font (font lookup, file loading) is costly,
   so fonts are shared, and kept for a while after their last use.
   font_acquire returns a font that matches [fd], creating it if
   needed; each call must be paired with a call to font_release. */
font_t *
font_acquire(
  const font_desc_t *fd);

void
font_release(
  font_t *f);

bool
font_matches(
  const font_t *f,
  const font_desc_t *fd);

bool
font_char_as_poly(
  const font_t *f,
  const transform_t *t,
  uint32_t c,
  point_t *pen, // in/out
  polygon_t *p, // out
  rect_t *bbox); // out

bool
font_char_as_poly_outline(
  const font_t *f,
  const transform_t *t,
  uint32_t c,
  double w,
  point_t *pen, // in/out
  polygon_t *p, // out
  rect_t *bbox); // out

/* Metrics of the glyph of character [c], as drawn by font_char_as_poly;
   false if the font cannot draw it (font_char_as_poly does not move the
   pen either in this case) */
bool
font_char_metrics(
  const font_t *f,
  uint32_t c,
  glyph_metrics_t *m); // out

/* Coverage mask of a glyph, rendered with its origin at a subpixel
   offset of (sx, sy) / FONT_SUBPIXELS pixel from an integer position.
   The top left corner of the mask lies at (left, -top) from that
   integer position (device pixels, downwards). */

#define FONT_SUBPIXELS 4

typedef struct glyph_mask_t {
  const uint8_t *data; /* coverage, 0..255, owned by the font */
  int32_t width;
  int32_t height;
  int32_t pitch;       /* bytes per row */
  int32_t left;
  int32_t top;
  double advance;      /* horizontal advance of the pen */
} glyph_mask_t;

/* Mask of the glyph of character [c], as font_char_as_poly would draw it
   without transform; false if the backend cannot render it this way, in
   which case the caller falls back on font_char_as_poly. The mask stays
   valid as long as the font. */
bool
font_char_as_mask(
  const font_t *f,
  uint32_t c,
  int32_t sx,
  int32_t sy,
  glyph_mask_t *m); // out

/* Ascent and descent of the font, in pixels, both positive */
void
font_metrics(
  const font_t *f,
  double *ascent, // out
  double *descent); // out

#endif /* __FONT_H */
