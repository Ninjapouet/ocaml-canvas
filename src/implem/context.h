/**************************************************************************/
/*                                                                        */
/*    Copyright 2022 OCamlPro                                             */
/*                                                                        */
/*  All rights reserved. This file is distributed under the terms of the  */
/*  GNU Lesser General Public License version 2.1, with the special       */
/*  exception on linking described in the file LICENSE.                   */
/*                                                                        */
/**************************************************************************/

#ifndef __CONTEXT_H
#define __CONTEXT_H

#include <stdint.h>
#include <stdbool.h>

#include "target.h"
#include "pixmap.h"

#include "rect.h"
#include "polygon.h"
#include "transform.h"
#include "draw_style.h"
#include "list.h"
#include "state.h" // for shadow_t

typedef struct context_t context_t;

context_t *
context_create(
  int32_t width,
  int32_t height);

// Creates a context from a pixmap
// The data pointer is transfered to the context
// (thus removed from the pixmap); if you kept
// a copy, do NOT free it !
context_t *
context_create_from_pixmap(
  pixmap_t *pixmap);

context_t *
context_create_onscreen(
  target_t *target,
  int32_t width,
  int32_t height);

void
context_destroy(
  context_t *c);

bool
context_resize(
  context_t *c,
  int32_t width,
  int32_t height);

void
context_present(
  context_t *c);

bool
context_clip(
  context_t *c,
  list_t *clip_path,
  const transform_t *transform);

void
context_clear_clip(
  context_t *c);

void
context_render_polygon(
  context_t *c,
  const polygon_t *p,
  const rect_t *bbox,
  draw_style_t draw_style,
  double global_alpha,
  const shadow_t *shadow,
  composite_operation_t compose_op,
  bool non_zero,
  const transform_t *transform);

/* Fast paths for the common cases of user interfaces. Both draw with a
   solid color, without shadow, with a composite operation that only
   affects the drawn area, and return false when the context cannot
   handle the request, in which case the caller falls back on
   context_render_polygon. */

/* Fills the axis-aligned rectangle (x1, y1) - (x2, y2), in device
   coordinates, with exact area coverage on its edges */
bool
context_fill_rect(
  context_t *c,
  double x1,
  double y1,
  double x2,
  double y2,
  color_t_ color,
  double global_alpha,
  composite_operation_t compose_op);

/* Draws the 8-bit coverage mask [mask] of size [width] x [height] (rows
   of [pitch] bytes) with its top left corner at (x, y) */
bool
context_fill_mask(
  context_t *c,
  const uint8_t *mask,
  int32_t width,
  int32_t height,
  int32_t pitch,
  int32_t x,
  int32_t y,
  color_t_ color,
  double global_alpha,
  composite_operation_t compose_op);

void
context_blit(
  context_t *dc,
  int32_t dx,
  int32_t dy,
  const context_t *sc,
  int32_t sx,
  int32_t sy,
  int32_t width,
  int32_t height,
  double global_alpha,
  const shadow_t *shadow,
  composite_operation_t compose_op,
  const transform_t *transform);

color_t_
context_get_pixel(
  const context_t *c,
  int32_t x,
  int32_t y);

void
context_put_pixel(
  context_t *c,
  int32_t x,
  int32_t y,
  color_t_ color);

pixmap_t
context_get_pixmap(
  const context_t *c,
  int32_t sx,
  int32_t sy,
  int32_t width,
  int32_t height);

void
context_put_pixmap(
  context_t *c,
  int32_t dx,
  int32_t dy,
  const pixmap_t *sp,
  int32_t sx,
  int32_t sy,
  int32_t width,
  int32_t height);

bool
context_export_png(
  const context_t *c,
  const char *filename); // as UTF-8

bool
context_import_png(
  context_t *c,
  int32_t x,
  int32_t y,
  const char *filename); // as UTF-8

#endif /* __CONTEXT_H */
