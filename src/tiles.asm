; =============================================================================
;   tiles.asm - Graphics I tile codes, colors, and custom 8x8 tile patterns
; =============================================================================
;   Same approach as the Snake cartridge: each custom tile code lives in its
;   own color group (group = code>>3) so it gets an independent fg/bg pair
;   without disturbing the CP437 text glyphs used by the HUD and messages.
; =============================================================================

TILE_BLANK      = $20    ; reused CP437 space glyph, untouched
TILE_PADDLE     = $80    ; color group 16
TILE_BALL       = $88    ; color group 17
TILE_WALL       = $90    ; color group 18
TILE_FRAME      = $98    ; color group 19, win-overlay box border

COLOR_PADDLE    = (TMS_WHITE     << 4) | TMS_BLACK
COLOR_BALL      = (TMS_LT_YELLOW << 4) | TMS_BLACK
COLOR_WALL      = (TMS_GRAY      << 4) | TMS_DK_BLUE
COLOR_FRAME     = (TMS_LT_YELLOW << 4) | TMS_LT_YELLOW
COLOR_TEXT      = (TMS_WHITE     << 4) | TMS_BLACK   ; default fill for all other groups

; Pattern-table destinations ($0800 base + code*8, per InitVideo's font load)
PATTERN_BASE    = $0800
PAT_PADDLE_ADDR = PATTERN_BASE + (TILE_PADDLE*8)
PAT_BALL_ADDR   = PATTERN_BASE + (TILE_BALL*8)
PAT_WALL_ADDR   = PATTERN_BASE + (TILE_WALL*8)
PAT_FRAME_ADDR  = PATTERN_BASE + (TILE_FRAME*8)

.segment "CART"

; 8x8 bitmaps, MSB = leftmost pixel, 1 = ink

TilePaddleData:
  .byte %11111111
  .byte %11111111
  .byte %11111111
  .byte %11111111
  .byte %11111111
  .byte %11111111
  .byte %11111111
  .byte %11111111

TileBallData:
  .byte %00111100
  .byte %01111110
  .byte %11111111
  .byte %11111111
  .byte %11111111
  .byte %11111111
  .byte %01111110
  .byte %00111100

TileWallData:
  .byte %11111111
  .byte %11111111
  .byte %11111111
  .byte %11111111
  .byte %11111111
  .byte %11111111
  .byte %11111111
  .byte %11111111

TileFrameData:
  .byte %11111111
  .byte %11111111
  .byte %11111111
  .byte %11111111
  .byte %11111111
  .byte %11111111
  .byte %11111111
  .byte %11111111
