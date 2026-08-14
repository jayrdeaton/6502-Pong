; =============================================================================
;   rng.asm — 8-bit Galois LFSR pseudo-random generator
; =============================================================================
;   Same proven LFSR as the sibling Snake cartridge. RNG_STATE must never be
;   seeded to 0 — a Galois LFSR at all-zero is a fixed point it can never
;   leave (every subsequent shift/eor still lands on 0). Guaranteeing a
;   non-zero seed is the CALLER's responsibility (done once in screens.asm's
;   WaitForModeSelect), not this file's.
; =============================================================================

.segment "CART"

; -----------------------------------------------------------------------------
; AdvanceRng — step the LFSR one bit (maximal-length, period 255)
; -----------------------------------------------------------------------------
AdvanceRng:
  lda RNG_STATE
  lsr a
  bcc @noeor
  eor #$B4
@noeor:
  sta RNG_STATE
  rts

; -----------------------------------------------------------------------------
; RollDirection — hand back one fresh pseudo-random byte
; Out: A = fresh pseudo-random byte
;   Callers extract dx sign from bit 0 and reduce other bits into a small
;   range themselves for dy — this routine just supplies the raw byte.
; -----------------------------------------------------------------------------
RollDirection:
  jsr AdvanceRng
  lda RNG_STATE
  rts
