; =============================================================================
;   vdp.asm - TMS9918 Graphics I mode setup and drawing primitives
; =============================================================================
;   Port protocol (from 6502.inc, verified against the live BIOS source):
;     Set VRAM write address: addr_lo -> VC_REG, then (addr_hi | $40) -> VC_REG
;     Write a VDP register:   data    -> VC_REG, then (reg#   | $80) -> VC_REG
;
;   THE VDP IS ITSELF AN IRQ SOURCE. Reading its status port resets the same
;   two-byte write-latch that address-set and register-set writes depend on.
;   An interrupt landing between the two bytes of a VC_REG write (or between
;   an address-set and the data write that follows it) desyncs every VDP
;   write after that point, scrambling the screen - invisible in headless
;   turbo-speed testing but routine at real frame rates. Every VDP write
;   sequence in this file is wrapped in PHP / SEI ... PLP (not raw SEI/CLI,
;   which doesn't compose when one protected routine calls another - nesting
;   PHP/SEI/PLP is safe, nesting raw SEI/CLI is not).
; =============================================================================

.segment "CART"

; -----------------------------------------------------------------------------
; VdpWriteReg - write one VDP mode register
; In: A = value, X = register number (0-7)
; -----------------------------------------------------------------------------
VdpWriteReg:
  php
  sei
  sta VC_REG
  txa
  ora #$80
  sta VC_REG
  plp
  rts

; -----------------------------------------------------------------------------
; VdpSetAddr - set the VRAM read/write pointer
; In: A = address low byte, X = address high byte
; -----------------------------------------------------------------------------
VdpSetAddr:
  php
  sei
  sta VC_REG
  txa
  ora #$40
  sta VC_REG
  plp
  rts

; -----------------------------------------------------------------------------
; ComputeOffset - compute row*32+col into OFFSET_LO/OFFSET_HI
; In: A = row (0-23), X = col (0-31)
; Clobbers: A, Y
; -----------------------------------------------------------------------------
ComputeOffset:
  sta OFFSET_LO
  stz OFFSET_HI
  ldy #5
@shift:
  asl OFFSET_LO
  rol OFFSET_HI
  dey
  bne @shift
  txa
  clc
  adc OFFSET_LO
  sta OFFSET_LO
  bcc @done
  inc OFFSET_HI
@done:
  rts

; -----------------------------------------------------------------------------
; VdpSetOffsetAddr - point the VRAM write pointer at name-table offset
; OFFSET_LO/OFFSET_HI (name table base is $0000, so address == offset)
; -----------------------------------------------------------------------------
VdpSetOffsetAddr:
  lda OFFSET_LO
  ldx OFFSET_HI
  jmp VdpSetAddr        ; tail call - VdpSetAddr's rts returns to our caller

; -----------------------------------------------------------------------------
; DrawTile - draw a tile code into the name table at (row,col)
; In: A = row, X = col, Y = tile code
;
; Also atomic end-to-end (not just the address-set half): an interrupt
; landing between the address-set and the data write is only harmless if
; nothing else touches the VDP in between, which we can't assume - same
; reasoning as VdpWriteReg above.
; -----------------------------------------------------------------------------
DrawTile:
  php
  sei
  phy
  jsr ComputeOffset
  jsr VdpSetOffsetAddr
  ply
  tya
  sta VC_DATA
  plp
  rts

; -----------------------------------------------------------------------------
; EraseTile - draw TILE_BLANK at (row,col)
; In: A = row, X = col
; -----------------------------------------------------------------------------
EraseTile:
  ldy #TILE_BLANK
  jmp DrawTile

; -----------------------------------------------------------------------------
; ClearScreen - fill all 768 name-table cells (32x24) with TILE_BLANK
; -----------------------------------------------------------------------------
ClearScreen:
  php
  sei
  lda #$00
  ldx #$00
  jsr VdpSetAddr
  ldx #0
  ldy #3
@nameLoop:
  lda #TILE_BLANK
  sta VC_DATA
  inx
  bne @nameLoop
  dey
  bne @nameLoop
  plp
  rts

; -----------------------------------------------------------------------------
; WriteTilePatterns - copy the four custom 8x8 patterns into VRAM
; -----------------------------------------------------------------------------
WriteTilePatterns:
  php
  sei
  lda #<PAT_PADDLE_ADDR
  ldx #>PAT_PADDLE_ADDR
  jsr VdpSetAddr
  ldy #0
@p:
  lda TilePaddleData,y
  sta VC_DATA
  iny
  cpy #8
  bne @p

  lda #<PAT_BALL_ADDR
  ldx #>PAT_BALL_ADDR
  jsr VdpSetAddr
  ldy #0
@b:
  lda TileBallData,y
  sta VC_DATA
  iny
  cpy #8
  bne @b

  lda #<PAT_WALL_ADDR
  ldx #>PAT_WALL_ADDR
  jsr VdpSetAddr
  ldy #0
@w:
  lda TileWallData,y
  sta VC_DATA
  iny
  cpy #8
  bne @w

  lda #<PAT_FRAME_ADDR
  ldx #>PAT_FRAME_ADDR
  jsr VdpSetAddr
  ldy #0
@f:
  lda TileFrameData,y
  sta VC_DATA
  iny
  cpy #8
  bne @f
  plp
  rts

; -----------------------------------------------------------------------------
; DrawWalls - draw the top and bottom walls across all 32 columns. Unlike a
; bordered game there are NO side walls: columns 0 and 31 on the playable
; rows stay blank, since that's where the ball exits to score.
; -----------------------------------------------------------------------------
DrawWalls:
  stz SCAN_TMP
@loop:
  lda #FIELD_TOP_WALL
  ldx SCAN_TMP
  ldy #TILE_WALL
  jsr DrawTile

  lda #FIELD_BOTTOM_WALL
  ldx SCAN_TMP
  ldy #TILE_WALL
  jsr DrawTile

  inc SCAN_TMP
  lda SCAN_TMP
  cmp #GRID_COLS
  bne @loop
  rts

; -----------------------------------------------------------------------------
; DrawBoxFrame - draw a TILE_FRAME outline around the win-overlay box
; -----------------------------------------------------------------------------
DrawBoxFrame:
  stz SCAN_TMP
@topBottom:
  lda SCAN_TMP
  clc
  adc #BOX_LEFT
  tax
  lda #BOX_TOP
  ldy #TILE_FRAME
  jsr DrawTile

  lda SCAN_TMP
  clc
  adc #BOX_LEFT
  tax
  lda #(BOX_TOP+BOX_HEIGHT-1)
  ldy #TILE_FRAME
  jsr DrawTile

  inc SCAN_TMP
  lda SCAN_TMP
  cmp #BOX_WIDTH
  bne @topBottom

  stz SCAN_TMP
@sides:
  lda SCAN_TMP
  clc
  adc #BOX_TOP
  ldx #BOX_LEFT
  ldy #TILE_FRAME
  jsr DrawTile

  lda SCAN_TMP
  clc
  adc #BOX_TOP
  ldx #(BOX_LEFT+BOX_WIDTH-1)
  ldy #TILE_FRAME
  jsr DrawTile

  inc SCAN_TMP
  lda SCAN_TMP
  cmp #BOX_HEIGHT
  bne @sides
  rts

; -----------------------------------------------------------------------------
; ClearBoxInterior - blank the win-overlay box's interior (excludes its
; 1-tile frame border)
; -----------------------------------------------------------------------------
ClearBoxInterior:
  php
  sei
  lda #1
  sta SCAN_TMP
@rowLoop:
  lda SCAN_TMP
  clc
  adc #BOX_TOP
  ldx #(BOX_LEFT+1)
  jsr ComputeOffset
  jsr VdpSetOffsetAddr
  ldy #0
@colLoop:
  lda #TILE_BLANK
  sta VC_DATA
  iny
  cpy #(BOX_WIDTH-2)
  bne @colLoop

  inc SCAN_TMP
  lda SCAN_TMP
  cmp #(BOX_HEIGHT-1)
  bne @rowLoop
  plp
  rts

; -----------------------------------------------------------------------------
; InitGraphicsI - switch the VDP into Graphics I mode and build the screen
; -----------------------------------------------------------------------------
InitGraphicsI:
  lda HW_PRESENT
  and #HW_VID
  bne @haveVideo

  lda #<NoVideoMsg
  ldy #>NoVideoMsg
  jsr PrintStr
@haltLoop:
  bra @haltLoop            ; plain 65C02 has no WAI - spin forever instead

@haveVideo:
  php                      ; outer critical section for the whole setup -
  sei                      ; covers the inline register/color-table writes
                            ; below that aren't wrapped by a called routine
  lda #$80
  ldx #1
  jsr VdpWriteReg          ; blank, 16K, Graphics I
  lda #$00
  ldx #0
  jsr VdpWriteReg
  lda #$00
  ldx #2
  jsr VdpWriteReg          ; name table @ $0000
  lda #$0C
  ldx #3
  jsr VdpWriteReg          ; color table @ $0300
  lda #$01
  ldx #4
  jsr VdpWriteReg          ; pattern table @ $0800
  lda #$0E
  ldx #5
  jsr VdpWriteReg          ; sprite attrs @ $0700 (unused)
  lda #$01
  ldx #6
  jsr VdpWriteReg          ; sprite patterns @ $0800
  lda #TMS_BLACK
  ldx #7
  jsr VdpWriteReg          ; backdrop

  ; disable the sprite list
  lda #$00
  ldx #$07
  jsr VdpSetAddr
  lda #$D0
  sta VC_DATA

  ; color table: fill all 32 groups with COLOR_TEXT, then punch in our 4
  lda #$00
  ldx #$03
  jsr VdpSetAddr
  ldy #32
@colorLoop:
  lda #COLOR_TEXT
  sta VC_DATA
  dey
  bne @colorLoop

  lda #<($0300+16)
  ldx #>($0300+16)
  jsr VdpSetAddr
  lda #COLOR_PADDLE
  sta VC_DATA

  lda #<($0300+17)
  ldx #>($0300+17)
  jsr VdpSetAddr
  lda #COLOR_BALL
  sta VC_DATA

  lda #<($0300+18)
  ldx #>($0300+18)
  jsr VdpSetAddr
  lda #COLOR_WALL
  sta VC_DATA

  lda #<($0300+19)
  ldx #>($0300+19)
  jsr VdpSetAddr
  lda #COLOR_FRAME
  sta VC_DATA

  jsr WriteTilePatterns
  jsr ClearScreen
  jsr DrawWalls            ; top+bottom only - no side walls, ball exits there

  lda #$C0
  ldx #1
  jsr VdpWriteReg          ; unblank
  plp
  rts

NoVideoMsg:
  .byte CHAR_CR, CHAR_LF, "NO VIDEO CARD DETECTED", CHAR_CR, CHAR_LF, $00
