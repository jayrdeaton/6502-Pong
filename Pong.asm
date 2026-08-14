; =============================================================================
;   Pong.asm — cartridge entry point and main loop
; =============================================================================
;   Classic Pong for the AC6502 family, built as a standalone ROM cartridge
;   (6502-CRT template). Boots directly, no BASIC. One-player (vs a CPU
;   paddle) and two-player local modes, chosen on the title screen.
;
;   Controls: joystick, either port, to move, with WASD (P1) / arrow keys
;   (P2) as a keyboard fallback -- see src/input.asm. Up/down navigates
;   the title screen's mode select, and the A button (or space) confirms
;   it, pauses/resumes during play, and restarts after game over.
; =============================================================================

.setcpu "65C02"

.include "6502.inc"
.include "src/zeropage.inc"

.segment "CART"

.include "src/tiles.asm"
.include "src/vdp.asm"
.include "src/rng.asm"
.include "src/sound.asm"
.include "src/input.asm"
.include "src/hud.asm"
.include "src/screens.asm"
.include "src/physics.asm"

; =============================================================================
;   CartReset — cartridge entry point
; =============================================================================
CartReset:
  ldx #$ff
  txs                            ; Reset the stack pointer
  jsr KernalInit                 ; Initialize all detected hardware

  jsr Beep                       ; Startup beep (skips silently if no SID)
  cli                             ; Enable interrupts

  jsr InitVideo                  ; side effect: loads CP437 font into VRAM,
                                   ; which InitGraphicsI below depends on

  lda #0
  jsr SetIOMode                   ; video/local keyboard -- Chrin's SOURCE
                                    ; follows IO_MODE too, not just Chrout's
                                    ; destination, so keyboard fallback
                                    ; (DrainKeyboardCombined/Split, both of
                                    ; which call Chrin) would silently read
                                    ; from the serial port instead of the
                                    ; local keyboard if this were left at
                                    ; serial mode, the stale setting from
                                    ; before Pong had a keyboard fallback

  jsr InitGraphicsI               ; also draws the top/bottom walls and blanks the screen
  jsr DrawTitleScreen
  jsr WaitForModeSelect           ; blocks until up/down + A select a mode, seeds RNG_STATE

  jsr NewGame

; -----------------------------------------------------------------------------
; MainLoop
; -----------------------------------------------------------------------------
MainLoop:
  jsr PollInput

  lda GAME_STATE
  cmp #STATE_PLAYING
  bne @notPlaying
  lda FIRE_EDGE
  beq @doTick
  lda #STATE_PAUSED
  sta GAME_STATE
  jsr DrawPauseMessage
  jmp @delay
@doTick:
  jsr Tick
  jmp @delay

@notPlaying:
  cmp #STATE_PAUSED
  bne @notPaused
  lda FIRE_EDGE
  beq @delay
  lda #STATE_PLAYING
  sta GAME_STATE
  lda #23
  jsr ClearRow
  jmp @delay

@notPaused:
  cmp #STATE_GAMEOVER
  bne @delay
  lda FIRE_EDGE
  beq @delay
  jsr DrawTitleScreen
  jsr WaitForModeSelect
  jsr NewGame

@delay:
  lda CUR_DELAY
  ldx #0
  jsr SysDelay
  jmp MainLoop

; =============================================================================
;   IRQ / NMI handlers — cartridge owns the vectors, so it must supply these.
;   Both just dispatch through the RAM vectors KernalInit already configured
;   (default keyboard-scanning IRQ handler, no-op NMI).
; =============================================================================

IrqTrampoline:
  jmp (IRQ_PTR)

NmiTrampoline:
  jmp (NMI_PTR)

; =============================================================================
;   CPU Vectors — cart owns $FFFA-$FFFF
; =============================================================================

.segment "VECTORS"

.word   NmiTrampoline
.word   CartReset
.word   IrqTrampoline
