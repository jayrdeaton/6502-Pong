; =============================================================================
;   sound.asm — non-blocking sound effects
; =============================================================================
;   Beep is guaranteed safe (self-no-ops with no SID card fitted) but blocks
;   the CPU for its full ~300ms tone duration — fine for a one-off like
;   Sound_Win, but unusable for a per-tick hit/bounce/score sound (it would
;   freeze the whole game for a beat every time). Sound_PaddleHit,
;   Sound_WallBounce, and Sound_Score instead drive SidPlayNote/SidSilence
;   directly: both are plain register writes with no delay loop, so they
;   return to the caller immediately. The SID's own envelope hardware keeps
;   ringing the note out in real time after that — gating off right away
;   just starts the (already short, full-sustain) release phase, it doesn't
;   cut the sound short. All SID routines self-no-op with no SID fitted, and
;   none of this touches the VDP, so no php/sei protection is needed here.
; =============================================================================

.segment "CART"

; -----------------------------------------------------------------------------
; Sound_PaddleHit — short mid-high blip when the ball hits a paddle
; -----------------------------------------------------------------------------
Sound_PaddleHit:
  lda #0
  ldx #<SID_NOTE_A4
  ldy #>SID_NOTE_A4
  jsr SidPlayNote
  jsr SidSilence
  rts

; -----------------------------------------------------------------------------
; Sound_WallBounce — short lower-pitched blip when the ball hits a wall
; -----------------------------------------------------------------------------
Sound_WallBounce:
  lda #0
  ldx #<SID_NOTE_A3
  ldy #>SID_NOTE_A3
  jsr SidPlayNote
  jsr SidSilence
  rts

; -----------------------------------------------------------------------------
; Sound_Score — short distinct blip when a point is scored
; -----------------------------------------------------------------------------
Sound_Score:
  lda #0
  ldx #<SID_NOTE_E5
  ldy #>SID_NOTE_E5
  jsr SidPlayNote
  jsr SidSilence
  rts

; -----------------------------------------------------------------------------
; Sound_Win — one-time end-of-game fanfare (called at most once per game,
; when a player reaches WIN_SCORE) — not a hot path, so a short blocking
; arpeggio via SidPlayNote + SysDelay is fine here.
; -----------------------------------------------------------------------------
Sound_Win:
  lda #0
  ldx #<SID_NOTE_C5
  ldy #>SID_NOTE_C5
  jsr SidPlayNote
  lda #8
  ldx #0
  jsr SysDelay
  jsr SidSilence

  lda #0
  ldx #<SID_NOTE_E5
  ldy #>SID_NOTE_E5
  jsr SidPlayNote
  lda #8
  ldx #0
  jsr SysDelay
  jsr SidSilence

  lda #0
  ldx #<SID_NOTE_G5
  ldy #>SID_NOTE_G5
  jsr SidPlayNote
  lda #16
  ldx #0
  jsr SysDelay
  jsr SidSilence
  rts
