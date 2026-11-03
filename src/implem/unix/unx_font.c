/**************************************************************************/
/*                                                                        */
/*    Copyright 2022 OCamlPro                                             */
/*                                                                        */
/*  All rights reserved. This file is distributed under the terms of the  */
/*  GNU Lesser General Public License version 2.1, with the special       */
/*  exception on linking described in the file LICENSE.                   */
/*                                                                        */
/**************************************************************************/

#if defined HAS_X11 || defined HAS_WAYLAND

#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <assert.h>

#include <fontconfig/fontconfig.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_OUTLINE_H

#include "../util.h"
#include "../point.h"
#include "../rect.h"
#include "../polygon.h"
#include "../polygonize.h"
#include "../transform.h"
#include "../font_desc_internal.h"
#include "unx_font_internal.h"
#include "unx_font.h"

static bool _ft_initialized = false;
static FcConfig *_fc_config = NULL;
static FT_Library _ft_library = NULL;

static void
_unx_font_ensure_init(
  void)
{
  if (_ft_initialized) {
    return;
  }

  int error = FT_Init_FreeType(&_ft_library);
  if (error != FT_Err_Ok) {
    return;
  }

  _fc_config = FcInitLoadConfigAndFonts();
  if (_fc_config == NULL) {
    FT_Done_FreeType(_ft_library);
    return;
  }

  _ft_initialized = true;
}

static int
_unx_font_slant(
  font_slant_t s)
{
  switch (s) {
    case SLANT_ROMAN: return FC_SLANT_ROMAN;
    case SLANT_ITALIC: return FC_SLANT_ITALIC;
    case SLANT_OBLIQUE: return FC_SLANT_OBLIQUE;
    default: assert(!"Invalid font slant"); return 0;
  }
}

static
int
_unx_font_weight(
  int32_t w)
{
  w = clip(w, 0, 1000);
  int32_t q = w / 100;
  int32_t r = w % 100;
  switch (q) {
    case 0: return 0;
    case 1: return 0 + r * 40 / 100;
    case 2: return 40 + r * 10 / 100;
    case 3: return 50 + r * 35 / 100;
    case 4: return 85 + r * 15 / 100;
    case 5: return 100 + r * 80 / 100;
    case 6: return 180 + r * 20 / 100;
    case 7: return 200 + r * 5 / 100;
    case 8: return 205 + r * 5 / 100;
    case 9: return 210 + r * 5 / 100;
    case 10: return 215;
    default: assert(!"Bad font weight");
  }
  return -1;
}

unx_font_t *
unx_font_create(
  font_desc_t *fd)
{
  assert(fd != NULL);
  assert(fd->weight >= 0);

  FcPattern *fp = NULL;
  FcPattern *fp_res = NULL;
  FT_Face face = NULL;

  const char *family = fd->family;
  if (family == NULL) {
    family = "Liberation Sans";
  }

  double size = fd->size;
  if (size <= 0.0) {
    size = 8.3;
  }

  // TODO: this should be part of backend init
  _unx_font_ensure_init();

  fp = FcPatternBuild(NULL,
                      FC_FAMILY, FcTypeString, (FcChar8 *)family,
                      FC_SLANT, FcTypeInteger, _unx_font_slant(fd->slant),
                      FC_WEIGHT, FcTypeInteger, _unx_font_weight(fd->weight),
                      FC_SIZE, FcTypeDouble, size,
                      (char *)0);
  if (fp == NULL) {
    goto error;
  }

  // Config-based substitutions
  FcBool bres = FcConfigSubstitute(_fc_config, fp, FcMatchPattern);
  if (bres == FcFalse) {
    goto error;
  }

  // Add default values for missing pattern elements
  // (style, weight, slant, size)
  FcDefaultSubstitute(fp);

  // Get the best matching font
  FcResult res;
  fp_res = FcFontMatch(_fc_config, fp, &res);
  if (fp_res == NULL) {
    goto error;
  }

  // Destroy no longer used objects
  FcPatternDestroy(fp);
  fp = NULL;

  FcValue file;
  res = FcPatternGet(fp_res, FC_FILE, 0, &file);
  if (res != FcResultMatch || file.type != FcTypeString) {
    goto error;
  }

  FcValue index;
  res = FcPatternGet(fp_res, FC_INDEX, 0, &index);
  if (res != FcResultMatch || index.type != FcTypeInteger) {
    goto error;
  }

  int error =
    FT_New_Face(_ft_library, (const char *)file.u.s, index.u.i, &face);
  if (error != FT_Err_Ok) {
    goto error;
  }

  // Destroy no longer used objects
  FcPatternDestroy(fp_res);
  fp_res = NULL;

  error = FT_Select_Charmap(face, FT_ENCODING_UNICODE);
  if (error != FT_Err_Ok) {
    goto error;
  }

  //FT_Set_Char_Size(face, 0, size * 64.0, 72, 72);
  //FT_Set_Char_Size(face, 0, size * 26.6, 72, 72);
  FT_Set_Pixel_Sizes(face, 0, size * 96.0 / 72.0);
  if (error != FT_Err_Ok) {
    goto error;
  }

  unx_font_t *f = (unx_font_t *)calloc(1, sizeof(unx_font_t));
  if (f == NULL) {
    goto error;
  }

  f->ft_face = face;

  return f;

error:
  if (face != NULL) {
    FT_Done_Face(face);
  }
  if (fp_res != NULL) {
    FcPatternDestroy(fp_res);
  }
  if (fp != NULL) {
    FcPatternDestroy(fp);
  }
  return NULL;
}

void
unx_font_destroy(
  unx_font_t *f)
{
  assert(f != NULL);
  assert(f->ft_face != NULL);

  if (f->glyphs != NULL) {
    hashtable_iterator_t *i = ht_get_iterator(f->glyphs);
    if (i != NULL) {
      unx_glyph_t *g = NULL;
      while ((g = (unx_glyph_t *)ht_iterator_next(i)) != NULL) {
        free(g->data);
        free(g);
      }
      ht_free_iterator(i);
    }
    ht_delete(f->glyphs);
  }

  if (f->metrics != NULL) {
    hashtable_iterator_t *i = ht_get_iterator(f->metrics);
    if (i != NULL) {
      unx_metrics_t *m = NULL;
      while ((m = (unx_metrics_t *)ht_iterator_next(i)) != NULL) {
        free(m);
      }
      ht_free_iterator(i);
    }
    ht_delete(f->metrics);
  }

  FT_Done_Face(f->ft_face);
  free(f);
}

bool
unx_font_char_as_poly(
  const unx_font_t *f,
  const transform_t *t,
  uint32_t c,
  point_t *pen, // in/out
  polygon_t *p, // out
  rect_t *bbox) // out
{
  assert(f != NULL);
  assert(f->ft_face != NULL);
  assert(t != NULL);
  assert(pen != NULL);
  assert(p != NULL);
  assert(bbox != NULL);
  assert(c <= 0x10FFFF);

/*
  double a, b, c, d;
  transform_extract_ft(t, &a, &b, &c, &d);
//  FT_Matrix m = { a * 64.0, b * 64.0, c * 64.0, d * 64.0 };
  FT_Matrix m = { 16.0, 16.0, 16.0, 16.0 };
//  FT_Vector ppen = { pen->x * 64.0, pen->y * 64.0 };
//  FT_Vector ppen = { 0.0, 0.0 };
  FT_Set_Transform(_ft_face, &m, NULL / * &ppen * // *);
*/

  int error = FT_Load_Char(f->ft_face, c, FT_LOAD_NO_BITMAP);
  if (error) {
    return false;
  }

  FT_GlyphSlot glyph = f->ft_face->glyph;

  if (glyph->format != FT_GLYPH_FORMAT_OUTLINE) {
    return false;
  }

  for (int ic = 0; ic < glyph->outline.n_contours; ++ic) {

    int itp; // temporary point
    int ilp = glyph->outline.contours[ic]; // last point
    int ifp = (ic == 0) ? 0 : glyph->outline.contours[ic-1]+1; // first point
    int ip = (ic == 0) ? 0 : ifp; // current point

    point_t cp, cp2, np;
    point_t lp = { pen->x + glyph->outline.points[ilp].x / 64.0,
                   pen->y - glyph->outline.points[ilp].y / 64.0 };

    if ((glyph->outline.tags[ifp] & 0x03) == 0x00) {
      if ((glyph->outline.tags[ilp] & 0x03) == 0x00) {
        lp.x = (lp.x + pen->x + glyph->outline.points[ifp].x / 64.0) / 2.0;
        lp.y = (lp.y + pen->y - glyph->outline.points[ifp].y / 64.0) / 2.0;
      }
    }

    transform_apply(t, &lp);

    while (ip <= ilp) {

      switch (glyph->outline.tags[ip] & 0x03) {

        case 0x01: // Point is on the curve
        case 0x03: // should not happen
          lp.x = pen->x + glyph->outline.points[ip].x / 64.0;
          lp.y = pen->y - glyph->outline.points[ip].y / 64.0;
          transform_apply(t, &lp);
          polygon_add_point(p, lp);
          rect_expand(bbox, lp);
          ++ip;
          break;

        case 0x00: // Point is off the curve, second-order control point
          cp.x = pen->x + glyph->outline.points[ip].x / 64.0;
          cp.y = pen->y - glyph->outline.points[ip].y / 64.0;
          itp = ip < ilp ? ip + 1 : ifp;
          np.x = pen->x + glyph->outline.points[itp].x / 64.0;
          np.y = pen->y - glyph->outline.points[itp].y / 64.0;
          if ((glyph->outline.tags[itp] & 0x03) == 0x00) {
            np.x = (np.x + cp.x) / 2.0;
            np.y = (np.y + cp.y) / 2.0;
          } else {
            ++ip;
          }
          transform_apply(t, &cp);
          transform_apply(t, &np);
          quadratic_to_poly(lp, cp, np, p, 2);
          rect_expand(bbox, cp);
          rect_expand(bbox, np);
          lp = np;
          ++ip;
          break;

        case 0x02: // Point is off the curve, third-order control point
          cp.x = pen->x + glyph->outline.points[ip].x / 64.0;
          cp.y = pen->y - glyph->outline.points[ip].y / 64.0;
          itp = ip < ilp ? ip + 1 : ifp;
          cp2.x = pen->x + glyph->outline.points[itp].x / 64.0;
          cp2.y = pen->y - glyph->outline.points[itp].y / 64.0;
          itp = ip + 1 < ilp ? ip + 2 : ifp;
          np.x = pen->x + glyph->outline.points[itp].x / 64.0;
          np.y = pen->y - glyph->outline.points[itp].y / 64.0;
          transform_apply(t, &cp);
          transform_apply(t, &cp2);
          transform_apply(t, &np);
          bezier_to_poly(lp, cp, cp2, np, p, 2);
          rect_expand(bbox, cp);
          rect_expand(bbox, cp2);
          rect_expand(bbox, np);
          lp = np;
          ip += 3;
          break;

        default:
          assert(!"Bad point tag");
          break;
      }
    }

    polygon_end_subpoly(p, true);
  }

  pen->x += f->ft_face->glyph->advance.x / 64.0;
  pen->y += f->ft_face->glyph->advance.y / 64.0;

  return true;
}

static hash_t
_unx_key_hash(
  const void *key)
{
  return *(const uint32_t *)key * 2654435761u;
}

static bool
_unx_key_equal(
  const void *key1,
  const void *key2)
{
  return *(const uint32_t *)key1 == *(const uint32_t *)key2;
}

static bool
_unx_font_render_mask(
  const unx_font_t *f,
  uint32_t c,
  int32_t sx,
  int32_t sy,
  unx_glyph_t *g)
{
  // Same loading as unx_font_char_as_poly, so that both agree
  if (FT_Load_Char(f->ft_face, c, FT_LOAD_NO_BITMAP) != 0) {
    return false;
  }

  FT_GlyphSlot glyph = f->ft_face->glyph;
  if (glyph->format != FT_GLYPH_FORMAT_OUTLINE) {
    return false;
  }

  g->advance = glyph->advance.x / 64.0;

  // Subpixel offset, in 26.6 fixed point; FreeType's y axis goes upwards
  FT_Outline_Translate(&glyph->outline,
                       sx * 64 / FONT_SUBPIXELS, -sy * 64 / FONT_SUBPIXELS);

  if ((FT_Render_Glyph(glyph, FT_RENDER_MODE_NORMAL) != 0) ||
      (glyph->bitmap.pixel_mode != FT_PIXEL_MODE_GRAY)) {
    return false;
  }

  const FT_Bitmap *b = &glyph->bitmap;
  g->width = (int32_t)b->width;
  g->height = (int32_t)b->rows;
  g->pitch = (int32_t)b->width;
  g->left = (int32_t)glyph->bitmap_left;
  g->top = (int32_t)glyph->bitmap_top;
  g->data = NULL;

  if ((g->width > 0) && (g->height > 0)) {
    g->data = (uint8_t *)malloc((size_t)g->width * (size_t)g->height);
    if (g->data == NULL) {
      return false;
    }
    // FreeType rows may be padded, and stored bottom-up (negative pitch)
    for (int32_t r = 0; r < g->height; ++r) {
      const uint8_t *row = (b->pitch >= 0) ?
        b->buffer + (size_t)r * (size_t)b->pitch :
        b->buffer + (size_t)(g->height - 1 - r) * (size_t)(-b->pitch);
      memcpy(g->data + (size_t)r * (size_t)g->width, row, (size_t)g->width);
    }
  }

  return true;
}

bool
unx_font_char_as_mask(
  const unx_font_t *f,
  uint32_t c,
  int32_t sx,
  int32_t sy,
  glyph_mask_t *m)
{
  assert(f != NULL);
  assert(f->ft_face != NULL);
  assert(m != NULL);
  assert(c <= 0x10FFFF);

  // The cache is an implementation detail: the font is logically const
  unx_font_t *mf = (unx_font_t *)f;
  if (mf->glyphs == NULL) {
    mf->glyphs = ht_new(_unx_key_hash, _unx_key_equal, 256);
    if (mf->glyphs == NULL) {
      return false;
    }
  }

  uint32_t key = (c * FONT_SUBPIXELS + (uint32_t)sx) * FONT_SUBPIXELS +
                 (uint32_t)sy;
  unx_glyph_t *g = (unx_glyph_t *)ht_find(mf->glyphs, &key);
  if (g == NULL) {
    g = (unx_glyph_t *)calloc(1, sizeof(unx_glyph_t));
    if (g == NULL) {
      return false;
    }
    g->key = key;
    g->ok = _unx_font_render_mask(f, c, sx, sy, g);
    if (ht_add(mf->glyphs, &g->key, g) == false) {
      free(g->data);
      free(g);
      return false;
    }
  }

  if (g->ok == false) {
    return false;
  }

  m->data = g->data;
  m->width = g->width;
  m->height = g->height;
  m->pitch = g->pitch;
  m->left = g->left;
  m->top = g->top;
  m->advance = g->advance;

  return true;
}

static bool
_unx_font_load_metrics(
  const unx_font_t *f,
  uint32_t c,
  glyph_metrics_t *m)
{
  // Same loading as unx_font_char_as_poly, so that both agree
  if (FT_Load_Char(f->ft_face, c, FT_LOAD_NO_BITMAP) != 0) {
    return false;
  }

  FT_GlyphSlot glyph = f->ft_face->glyph;
  if (glyph->format != FT_GLYPH_FORMAT_OUTLINE) {
    return false;
  }

  m->advance = glyph->advance.x / 64.0;
  m->has_ink = (glyph->outline.n_contours > 0);
  m->left = glyph->metrics.horiBearingX / 64.0;
  m->right = m->left + glyph->metrics.width / 64.0;
  m->top = glyph->metrics.horiBearingY / 64.0;
  m->bottom = m->top - glyph->metrics.height / 64.0;

  return true;
}

bool
unx_font_char_metrics(
  const unx_font_t *f,
  uint32_t c,
  glyph_metrics_t *m)
{
  assert(f != NULL);
  assert(f->ft_face != NULL);
  assert(m != NULL);
  assert(c <= 0x10FFFF);

  // The cache is an implementation detail: the font is logically const
  unx_font_t *mf = (unx_font_t *)f;
  if (mf->metrics == NULL) {
    mf->metrics = ht_new(_unx_key_hash, _unx_key_equal, 256);
    if (mf->metrics == NULL) {
      return _unx_font_load_metrics(f, c, m);
    }
  }

  unx_metrics_t *e = (unx_metrics_t *)ht_find(mf->metrics, &c);
  if (e == NULL) {
    e = (unx_metrics_t *)calloc(1, sizeof(unx_metrics_t));
    if (e == NULL) {
      return _unx_font_load_metrics(f, c, m);
    }
    e->key = c;
    e->ok = _unx_font_load_metrics(f, c, &e->m);
    if (ht_add(mf->metrics, &e->key, e) == false) {
      free(e);
      return _unx_font_load_metrics(f, c, m);
    }
  }

  *m = e->m;
  return e->ok;
}

void
unx_font_metrics(
  const unx_font_t *f,
  double *ascent,
  double *descent)
{
  assert(f != NULL);
  assert(f->ft_face != NULL);
  assert(f->ft_face->size != NULL);
  assert(ascent != NULL);
  assert(descent != NULL);

  *ascent = f->ft_face->size->metrics.ascender / 64.0;
  *descent = -f->ft_face->size->metrics.descender / 64.0;
}

/*
on-curve
quadratic control points (also known as 'conic')
cubic control points

The quadratic control points are grouped with on-curve points on either side
of them to form the three points needed to define a quadratic Bezier spline.

The cubic control points must occur in pairs, and are grouped with on-curve
points on either side to make up the four points needed for a cubic Bezier
spline.

However, there is a short-hand notation for quadratic points only. Where
quadratic points occur next to each other, an on-curve control point is
interpolated between them.

And there is another convention, that if a closed path starts with a quadratic
point, the last point of the path is examined, and if it is quadratic, an
on-curve point is interpolated between them, and the path is taken to start
with that on-curve point; if the last point is not a quadratic control point,
it is itself used for the start point.
*/

#else

const int unx_font = 0;

#endif /* HAS_X11 || HAS_WAYLAND */
