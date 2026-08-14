.segment "CART"

; =============================================================================
;   input.asm — joystick-first, keyboard-fallback polling
; =============================================================================
;   Built on 6502-Lib's shared core/input.asm (PollJoyCombined/PollJoy1/
;   PollJoy2/DrainKeyboardCombined/DrainKeyboardSplit — see that file for the
;   primitives themselves). This file only composes them into Pong's own
;   MENU_DIR/NEXT_P1/NEXT_P2/START_PRESSED, per the shared priority rule:
;   joystick first — if the joystick shows ANY direction this poll, use ONLY
;   the joystick's direction(s) this poll and don't consult the keyboard at
;   all; only fall back to the keyboard's drained result when the joystick
;   shows NOTHING this poll (including when no GPIO card is fitted at all).
;   The fire/A button is OR'd independently of that direction priority:
;   joystick A held OR keyboard space seen this drain, either one sets
;   START_PRESSED.
;
;   A cartridge owns the whole shell while it's running, so keyboard input
;   here can't collide with a BASIC prompt the way it could in a full-system
;   UI — the concern that originally motivated joystick-only design doesn't
;   apply to a cartridge. Two players sharing one keyboard use the standard
;   split: WASD is the physical left-hand cluster (P1), arrow keys are the
;   physical right-hand cluster (P2), so their hands don't collide.
;
;   Two separate polling routines, not one, because they mean different
;   things by "combine the joysticks":
;     - PollMenuInput (title/mode-select): joystick 1 and 2 are OR'd
;       together — whoever is holding a controller can navigate, since no
;       player has been assigned to a port yet — and keyboard fallback is
;       DrainKeyboardCombined (WASD or arrows, whichever was pressed most
;       recently, no player distinction, since there's no player split yet
;       either).
;     - PollInput (gameplay): joystick 1 always drives P1. Joystick 2
;       drives P2 only in 2P mode; in 1P mode physics.asm's CpuAI owns
;       NEXT_P2, and joystick 2 is instead OR'd into P1's input too, so a
;       single-player controller works from either port (same reasoning
;       as the sibling Snake cartridge). Combining both ports for P1 in
;       2P mode would be wrong — it would let either player move the
;       other's paddle — so 2P mode keeps them strictly separate. Keyboard
;       fallback is DrainKeyboardSplit: WASD drives P1's fallback ONLY,
;       arrow keys drive P2's fallback ONLY, unconditionally — never
;       combined/either-or, for the same "don't let one player move the
;       other's paddle" reason. Unlike joystick 2, arrow keys are never
;       OR'd into P1 in 1P mode: WASD is always P1's keyboard fallback,
;       arrows are always P2's, full stop; in 1P mode that just means
;       arrow keys are inert (P2 has no human player to fall back for).
;
;   Pong's paddle stops moving when nothing is pressed (unlike Snake/
;   LightCycles, which always advance forward every tick). Chrin delivers
;   discrete buffered characters, not a live "is this key down" state, and
;   it's unconfirmed whether this platform's keyboard hardware auto-repeats
;   a held key into Chrin's buffer. To feel like a held key without
;   depending on that, PollInput layers a short per-player hold-decay
;   counter (P1_KB_HOLD_TTL/P2_KB_HOLD_TTL + P1_KB_HOLD_DIR/P2_KB_HOLD_DIR,
;   zeropage.inc) on top of DrainKeyboardSplit's single-shot result: a fresh
;   direction refreshes the TTL to KB_HOLD_TTL_INIT ticks and is remembered;
;   with nothing fresh, the remembered direction keeps counting as "held"
;   for movement until the TTL counts down to 0. This bookkeeping runs
;   every tick regardless of joystick state (so Chrin never backs up and
;   the TTL stays accurate), but is only ever *applied* to NEXT_P1/NEXT_P2
;   on a tick where that player's joystick showed nothing — joystick still
;   wins outright the instant it's touched.
; =============================================================================

.include "../../6502-Lib/core/input.asm"

; Keyboard hold-decay window (PollInput only — see header above). At
; BASE_DELAY (~80ms/tick) 4 ticks is ~320ms of bridged gap; at MIN_DELAY
; (~30ms/tick, the speed-escalation floor) it's ~120ms. Long enough to
; ride out a dropped or slow typematic character between polls, short
; enough that a single tap doesn't feel like it holds the paddle for a
; noticeably long time after release.
KB_HOLD_TTL_INIT = 4

; -----------------------------------------------------------------------------
; PollMenuInput — title/mode-select screen only. Combines joystick 1 and 2
; for up/down (MENU_DIR), with WASD/arrow-key keyboard fallback (whichever
; was pressed most recently) when the joystick shows nothing. A button OR
; space bar sets START_PRESSED, edge-detected into FIRE_EDGE same as
; PollInput. No sticky state: MENU_DIR reflects only what's resolved THIS
; poll (no hold-decay here — the menu doesn't need "feels held", only
; gameplay's paddle does).
; -----------------------------------------------------------------------------
PollMenuInput:
  stz MENU_DIR
  stz START_PRESSED

  jsr PollJoyCombined         ; JOY_STATE = both ports OR'd, or $FF if idle/no GPIO
  jsr DrainKeyboardCombined    ; KB_DIR = last direction this drain, KB_FIRE = space seen

  lda JOY_STATE
  and #(JOY_UP | JOY_DOWN)
  cmp #(JOY_UP | JOY_DOWN)
  beq @useKeyboardDir          ; neither bit is 0 (pressed) -> joystick shows nothing

  ; joystick shows a direction this poll: use ONLY the joystick, don't
  ; consult the keyboard at all this poll
  lda JOY_STATE
  and #JOY_UP
  bne @notUp
  lda #DIR_UP
  sta MENU_DIR
@notUp:
  lda JOY_STATE
  and #JOY_DOWN
  bne @notDown
  lda #DIR_DOWN
  sta MENU_DIR
@notDown:
  jmp @fireCheck

@useKeyboardDir:
  lda KB_DIR
  cmp #KB_DIR_NONE
  beq @fireCheck
  sta MENU_DIR

@fireCheck:
  lda JOY_STATE
  and #JOY_A
  beq @setFire                 ; A pressed (bit=0)
  lda KB_FIRE
  beq @doneDrain                ; neither joystick A nor keyboard space this drain
@setFire:
  lda #1
  sta START_PRESSED

@doneDrain:
  stz FIRE_EDGE
  lda PREV_FIRE
  bne @noEdge
  lda START_PRESSED
  beq @noEdge
  inc FIRE_EDGE
@noEdge:
  lda START_PRESSED
  sta PREV_FIRE
  rts

; -----------------------------------------------------------------------------
; PollInput — gameplay only. Joystick 1 always drives P1; joystick 2 drives
; P2 in 2P mode, or is OR'd into P1 in 1P mode (see header) — this joystick
; routing is unchanged from before keyboard fallback existed. WASD/arrow-key
; fallback (with hold-decay, see header) layers on top per player, only
; applied on a tick where that player's joystick shows nothing. NEXT_P1/
; NEXT_P2 are sticky "last known direction" — only overwritten when a
; joystick bit or a valid keyboard hold is actually seen this poll, never
; reset to DIR_NONE — Tick (physics.asm) reads them each tick to move the
; paddles.
; -----------------------------------------------------------------------------
PollInput:
  stz START_PRESSED

  jsr PollJoy1                 ; JOY_STATE = joystick1, or $FF if idle/no GPIO

  lda GAME_MODE
  cmp #MODE_2P
  beq @p1JoyOnly                ; 2P mode: keep the ports strictly separate

  jsr PollJoy2                  ; 1P mode: OR joystick 2 into P1 too, so a
  lda JOY_STATE2                 ; single-player controller works from
  and JOY_STATE                  ; either port
  sta JOY_STATE

@p1JoyOnly:
  jsr DrainKeyboardSplit        ; KB_DIR_P1 (WASD), KB_DIR_P2 (arrows), KB_FIRE
                                  ; drained every tick regardless of joystick
                                  ; state, so Chrin never backs up

  lda JOY_STATE
  and #(JOY_UP | JOY_DOWN)
  cmp #(JOY_UP | JOY_DOWN)
  beq @p1JoyEmpty                ; neither bit is 0 (pressed) -> joystick empty

  ; --- P1: joystick has a direction this poll -- use it exclusively ---
  lda JOY_STATE
  and #JOY_UP
  bne @p1jNotUp
  lda #DIR_UP
  sta NEXT_P1
@p1jNotUp:
  lda JOY_STATE
  and #JOY_DOWN
  bne @p1jNotDown
  lda #DIR_DOWN
  sta NEXT_P1
@p1jNotDown:
  ; still run keyboard bookkeeping so P1's TTL stays accurate for when the
  ; joystick lets go, but don't apply the result to NEXT_P1 this poll
  lda KB_DIR_P1
  cmp #KB_DIR_NONE
  bne @p1jFreshKb
  lda P1_KB_HOLD_TTL
  beq @p1FireCheck
  dec P1_KB_HOLD_TTL
  jmp @p1FireCheck
@p1jFreshKb:
  sta P1_KB_HOLD_DIR
  lda #KB_HOLD_TTL_INIT
  sta P1_KB_HOLD_TTL
  jmp @p1FireCheck

@p1JoyEmpty:
  ; --- P1: joystick shows nothing this poll -- keyboard hold-decay decides ---
  lda KB_DIR_P1
  cmp #KB_DIR_NONE
  bne @p1kFreshKb
  lda P1_KB_HOLD_TTL
  beq @p1FireCheck              ; already expired -> NEXT_P1 stays as-is (sticky)
  dec P1_KB_HOLD_TTL             ; still valid THIS tick (checked before decrementing)
  lda P1_KB_HOLD_DIR
  sta NEXT_P1
  jmp @p1FireCheck
@p1kFreshKb:
  sta P1_KB_HOLD_DIR
  lda #KB_HOLD_TTL_INIT
  sta P1_KB_HOLD_TTL
  lda P1_KB_HOLD_DIR
  sta NEXT_P1

@p1FireCheck:
  ; fire is independent of direction priority: joystick A OR keyboard space
  lda JOY_STATE
  and #JOY_A
  beq @p1SetFire
  lda KB_FIRE
  beq @p1NoFire
@p1SetFire:
  lda #1
  sta START_PRESSED
@p1NoFire:

  lda GAME_MODE
  cmp #MODE_2P
  bne @doneDrain                ; 1P mode: CpuAI owns NEXT_P2 and its keyboard
                                  ; fallback -- arrow keys stay inert here

  jsr PollJoy2                  ; 2P mode: fresh read, ports strictly separate

  lda JOY_STATE2
  and #(JOY_UP | JOY_DOWN)
  cmp #(JOY_UP | JOY_DOWN)
  beq @p2JoyEmpty

  ; --- P2: joystick2 has a direction this poll -- use it exclusively ---
  lda JOY_STATE2
  and #JOY_UP
  bne @p2jNotUp
  lda #DIR_UP
  sta NEXT_P2
@p2jNotUp:
  lda JOY_STATE2
  and #JOY_DOWN
  bne @p2jNotDown
  lda #DIR_DOWN
  sta NEXT_P2
@p2jNotDown:
  lda KB_DIR_P2
  cmp #KB_DIR_NONE
  bne @p2jFreshKb
  lda P2_KB_HOLD_TTL
  beq @p2FireCheck
  dec P2_KB_HOLD_TTL
  jmp @p2FireCheck
@p2jFreshKb:
  sta P2_KB_HOLD_DIR
  lda #KB_HOLD_TTL_INIT
  sta P2_KB_HOLD_TTL
  jmp @p2FireCheck

@p2JoyEmpty:
  ; --- P2: joystick2 shows nothing this poll -- keyboard hold-decay decides ---
  lda KB_DIR_P2
  cmp #KB_DIR_NONE
  bne @p2kFreshKb
  lda P2_KB_HOLD_TTL
  beq @p2FireCheck
  dec P2_KB_HOLD_TTL
  lda P2_KB_HOLD_DIR
  sta NEXT_P2
  jmp @p2FireCheck
@p2kFreshKb:
  sta P2_KB_HOLD_DIR
  lda #KB_HOLD_TTL_INIT
  sta P2_KB_HOLD_TTL
  lda P2_KB_HOLD_DIR
  sta NEXT_P2

@p2FireCheck:
  lda JOY_STATE2
  and #JOY_A
  beq @p2SetFire
  lda KB_FIRE
  beq @doneDrain
@p2SetFire:
  lda #1
  sta START_PRESSED

@doneDrain:
  ; Edge-detect the A button/space: FIRE_EDGE is set only on the poll it
  ; first goes down, so a held button (which reads as continuously down
  ; every poll) doesn't repeatedly re-trigger pause/resume/restart every
  ; tick.
  stz FIRE_EDGE
  lda PREV_FIRE
  bne @noEdge
  lda START_PRESSED
  beq @noEdge
  inc FIRE_EDGE
@noEdge:
  lda START_PRESSED
  sta PREV_FIRE
  rts
