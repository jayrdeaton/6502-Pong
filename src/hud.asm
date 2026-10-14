; =============================================================================
;   hud.asm - HUD text/digit-drawing primitives (score, messages, title text)
; =============================================================================
;   Graphics I has no Kernal-compatible 40-column text mode, so all HUD text
;   is drawn tile-by-tile straight into the name table via DrawTile/EraseTile
;   (see src/vdp.asm), not via PrintStr/VideoPutChar. Ported near-verbatim
;   from the same pattern used by the sibling Snake cartridge in this
;   ecosystem.
; =============================================================================

.segment "CART"

; -----------------------------------------------------------------------------
; DrawString
; In:  A = row, X = col, WORK_PTR/WORK_PTR+1 = pointer to a null-terminated
;      string
; Draws each character of the string as consecutive tiles starting at
; (row,col), advancing one column per character. The CP437 font's ASCII-range
; glyphs survive InitVideo's font load into the pattern table untouched, so
; the character code itself IS the tile code.
; -----------------------------------------------------------------------------
DrawString:
  sta MSG_ROW
  stx SCAN_TMP
  lda #0
  sta STR_IDX
@loop:
  ldy STR_IDX
  lda (WORK_PTR),y
  beq @done
  tay
  lda MSG_ROW
  ldx SCAN_TMP
  jsr DrawTile
  inc SCAN_TMP
  inc STR_IDX
  jmp @loop
@done:
  rts

; -----------------------------------------------------------------------------
; ClearRow
; In:  A = row
; Blanks all 32 columns of a row using EraseTile. The loop counter lives in
; zero page rather than X/Y, since EraseTile clobbers both internally.
; -----------------------------------------------------------------------------
ClearRow:
  sta MSG_ROW
  lda #0
  sta SCAN_TMP
@loop:
  lda MSG_ROW
  ldx SCAN_TMP
  jsr EraseTile
  inc SCAN_TMP
  lda SCAN_TMP
  cmp #GRID_COLS
  bne @loop
  rts

; -----------------------------------------------------------------------------
; ValueToDigits2
; In:  A = value (0-99)
; Out: DIGIT_BUF+0 = ASCII tens digit, DIGIT_BUF+1 = ASCII ones digit
; Repeated-subtraction decimal conversion: how many times 10 subtracts out of
; SC_TMP before going negative is the tens digit; the remainder is the ones
; digit. A much simpler 2-digit cousin of Snake's 16-bit 5-digit version.
; -----------------------------------------------------------------------------
ValueToDigits2:
  sta SC_TMP
  ldx #0
@tensLoop:
  lda SC_TMP
  cmp #10
  bcc @tensDone
  sec
  sbc #10
  sta SC_TMP
  inx
  jmp @tensLoop
@tensDone:
  txa
  clc
  adc #'0'
  sta DIGIT_BUF+0
  lda SC_TMP
  clc
  adc #'0'
  sta DIGIT_BUF+1
  rts

; -----------------------------------------------------------------------------
; DrawDigitBuf2
; In:  A = row, X = col
; Draws the 2 ASCII bytes currently in DIGIT_BUF at (row,col) and
; (row,col+1), straight from DIGIT_BUF rather than via DrawString.
; -----------------------------------------------------------------------------
DrawDigitBuf2:
  sta MSG_ROW
  stx SCAN_TMP
  lda DIGIT_BUF+0
  tay
  lda MSG_ROW
  ldx SCAN_TMP
  jsr DrawTile
  inc SCAN_TMP
  lda DIGIT_BUF+1
  tay
  lda MSG_ROW
  ldx SCAN_TMP
  jsr DrawTile
  rts
