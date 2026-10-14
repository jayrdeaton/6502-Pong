.segment "CART"

; =============================================================================
;   physics.asm - paddle movement, ball movement/collision/scoring, CPU AI
; =============================================================================
;   Tick is the heart of the game and walks through, in order, every tick:
;     1. paddle movement (P1 always; P2 from a human or from CpuAI)
;     2. compute the ball's candidate next position
;     3. top/bottom wall bounce (may revise the candidate)
;     4. paddle bounce, checked against the (possibly wall-revised) candidate
;     5. scoring, only if step 4 didn't just register a bounce
;     6. commit-and-draw the ball at its final candidate position
;   Steps 3 and 4 are independent checks applied in sequence (not mutually
;   exclusive) so a ball can bounce off a wall and a paddle in the very same
;   tick near a corner. Scoring uses a strict less-than/greater-than test
;   past each paddle's column, one step past the <=/>= test paddle collision
;   uses at the column itself - that gap is what gives a ball that reaches a
;   paddle's column without hitting it (a miss) one more tick to visibly sail
;   past the edge before the point registers.
;
;   Both paddles are unconditionally erased-old/drawn-new every tick, even on
;   ticks where they didn't move - a sibling cartridge in this ecosystem was
;   bitten by stale trailing tiles when it tried to skip redraws
;   conditionally, and the extra DrawTile/EraseTile calls are cheap.
;
;   SCAN_TMP/SCAN_TMP2 are reused for several unrelated things across this
;   routine (old paddle row, erase/draw loop counters, paddle-hit row offset,
;   the hit-this-tick flag) - safe because each use fully completes before
;   the next one starts, but worth flagging since the names alone don't say
;   what they hold at any given point.
; =============================================================================

; -----------------------------------------------------------------------------
; UpdateHud - redraw both players' scores and their static labels on the HUD
; row. Called by NewGame (screens.asm) to draw the initial "0"/"0", and again
; here by Tick whenever a score changes.
; -----------------------------------------------------------------------------
UpdateHud:
  lda #<P1Label
  sta WORK_PTR
  lda #>P1Label
  sta WORK_PTR+1
  lda #0
  ldx #2
  jsr DrawString

  lda P1_SCORE
  jsr ValueToDigits2
  lda #0
  ldx #6
  jsr DrawDigitBuf2

  lda #<P2Label
  sta WORK_PTR
  lda #>P2Label
  sta WORK_PTR+1
  lda #0
  ldx #24
  jsr DrawString

  lda P2_SCORE
  jsr ValueToDigits2
  lda #0
  ldx #28
  jsr DrawDigitBuf2
  rts

; -----------------------------------------------------------------------------
; CpuAI - steers NEXT_P2 toward the ball. Only called when GAME_MODE ==
; MODE_1P (Tick gates the call, but this checks again defensively). Only
; recomputes its decision on every OTHER call (bit 0 of CPU_TICK) - this
; halves the CPU's effective reaction speed relative to a human who reacts
; every tick, which is what makes it beatable, especially on sharp angles.
;
; Because a decision only happens every other tick but the paddle still
; moves every tick on that stale decision, one "decision cycle" always
; moves the paddle 2 rows, never 1 - so an exact BALL_Y == AI_TARGET
; alignment test can permanently overshoot a single-row target every
; cycle and oscillate forever without ever landing on it exactly. Fixed
; with a 3-row deadband (AI_TARGET-1 .. AI_TARGET+1 counts as "aligned")
; instead of exact equality - wide enough that a 2-row swing can't jump
; over it, and still narrow enough that the ball stays within the
; paddle's 4-row catch range once the AI settles.
; -----------------------------------------------------------------------------
CpuAI:
  lda GAME_MODE
  cmp #MODE_1P
  bne @done                      ; belt-and-suspenders - Tick already gates this call

  inc CPU_TICK
  lda CPU_TICK
  and #1
  bne @done                      ; odd tick: skip deciding, leave NEXT_P2 as it was

  lda P2_Y
  clc
  adc #1                         ; reference point: roughly the paddle's vertical center
  sta AI_TARGET

  lda BALL_Y
  cmp AI_TARGET
  bcc @ballAbove                 ; BALL_Y < AI_TARGET: ball is above the paddle's center
  sec
  sbc AI_TARGET                  ; A = BALL_Y - AI_TARGET, >= 0 here
  cmp #2
  bcc @aligned                   ; within [AI_TARGET, AI_TARGET+1] - close enough
  lda #DIR_DOWN
  sta NEXT_P2
  bra @done
@ballAbove:
  lda AI_TARGET
  sec
  sbc BALL_Y                     ; A = AI_TARGET - BALL_Y, > 0 here
  cmp #2
  bcc @aligned                   ; within [AI_TARGET-1, AI_TARGET) - close enough
  lda #DIR_UP
  sta NEXT_P2
  bra @done
@aligned:
  lda #DIR_NONE
  sta NEXT_P2
@done:
  rts

; -----------------------------------------------------------------------------
; Tick - advances the game exactly one step. No inputs.
; -----------------------------------------------------------------------------
Tick:

; -----------------------------------------------------------------------------
; Step 1: paddle movement. P1 always moves from NEXT_P1. In 1P mode, NEXT_P2
; is first recomputed by CpuAI (which only reacts every other tick); in 2P
; mode NEXT_P2 is whatever PollInput last set from joystick2/arrow keys.
; Either way P2 then moves from NEXT_P2 exactly like P1 moves from NEXT_P1.
; -----------------------------------------------------------------------------
  lda GAME_MODE
  cmp #MODE_1P
  bne @p2Ready
  jsr CpuAI
@p2Ready:

; --- P1 paddle: clamp-move, then erase old / draw new 4-cell column ---
  lda P1_Y
  sta SCAN_TMP                    ; remember the old top row for the erase below

  lda NEXT_P1
  cmp #DIR_UP
  bne @p1CheckDown
  lda P1_Y
  cmp #PADDLE_MIN_Y
  beq @p1Redraw                   ; already at the clamp - no further move
  dec P1_Y
  bra @p1Redraw
@p1CheckDown:
  lda NEXT_P1
  cmp #DIR_DOWN
  bne @p1Redraw
  lda P1_Y
  cmp #PADDLE_MAX_Y
  beq @p1Redraw
  inc P1_Y

@p1Redraw:
  lda #0
  sta SCAN_TMP2
@p1EraseLoop:
  lda SCAN_TMP
  clc
  adc SCAN_TMP2
  ldx #P1_X
  jsr EraseTile
  inc SCAN_TMP2
  lda SCAN_TMP2
  cmp #PADDLE_HEIGHT
  bne @p1EraseLoop

  lda #0
  sta SCAN_TMP2
@p1DrawLoop:
  lda P1_Y
  clc
  adc SCAN_TMP2
  ldx #P1_X
  ldy #TILE_PADDLE
  jsr DrawTile
  inc SCAN_TMP2
  lda SCAN_TMP2
  cmp #PADDLE_HEIGHT
  bne @p1DrawLoop

; --- P2 paddle: identical shape, mirrored column/state ---
  lda P2_Y
  sta SCAN_TMP

  lda NEXT_P2
  cmp #DIR_UP
  bne @p2CheckDown
  lda P2_Y
  cmp #PADDLE_MIN_Y
  beq @p2Redraw
  dec P2_Y
  bra @p2Redraw
@p2CheckDown:
  lda NEXT_P2
  cmp #DIR_DOWN
  bne @p2Redraw
  lda P2_Y
  cmp #PADDLE_MAX_Y
  beq @p2Redraw
  inc P2_Y

@p2Redraw:
  lda #0
  sta SCAN_TMP2
@p2EraseLoop:
  lda SCAN_TMP
  clc
  adc SCAN_TMP2
  ldx #P2_X
  jsr EraseTile
  inc SCAN_TMP2
  lda SCAN_TMP2
  cmp #PADDLE_HEIGHT
  bne @p2EraseLoop

  lda #0
  sta SCAN_TMP2
@p2DrawLoop:
  lda P2_Y
  clc
  adc SCAN_TMP2
  ldx #P2_X
  ldy #TILE_PADDLE
  jsr DrawTile
  inc SCAN_TMP2
  lda SCAN_TMP2
  cmp #PADDLE_HEIGHT
  bne @p2DrawLoop

; -----------------------------------------------------------------------------
; Step 2: compute the ball's candidate next position. BALL_DX/BALL_DY are
; two's-complement +-1 (DY may also be 0 when flat), so a plain CLC/ADC does
; the right signed add - ball coordinates stay well inside the 0-31/0-23
; range, so there's no overflow case to worry about.
; -----------------------------------------------------------------------------
  lda BALL_X
  clc
  adc BALL_DX
  sta NEW_BALL_X

  lda BALL_Y
  clc
  adc BALL_DY
  sta NEW_BALL_Y

; -----------------------------------------------------------------------------
; Step 3: top/bottom wall collision. If the candidate row would put the ball
; on or past a wall row, invert BALL_DY and recompute NEW_BALL_Y from the
; ball's CURRENT (not candidate) Y using the now-inverted delta - this makes
; the ball actually bounce away this same tick instead of re-colliding with
; the same wall again next tick.
; -----------------------------------------------------------------------------
  lda NEW_BALL_Y
  cmp #FIELD_TOP_WALL
  bcc @wallHit                    ; NEW_BALL_Y < FIELD_TOP_WALL
  beq @wallHit                    ; NEW_BALL_Y == FIELD_TOP_WALL
  cmp #FIELD_BOTTOM_WALL
  bcs @wallHit                    ; NEW_BALL_Y >= FIELD_BOTTOM_WALL
  bra @wallDone

@wallHit:
  lda BALL_DY
  beq @wallRecompute              ; DY==0 shouldn't happen approaching a wall; leave it be
  cmp #$01
  bne @wallWasNeg
  lda #$FF
  sta BALL_DY
  bra @wallRecompute
@wallWasNeg:
  lda #$01
  sta BALL_DY
@wallRecompute:
  lda BALL_Y
  clc
  adc BALL_DY
  sta NEW_BALL_Y
  jsr Sound_WallBounce
@wallDone:

; -----------------------------------------------------------------------------
; Step 4: paddle collision, checked after wall bouncing above is resolved -
; a ball can bounce off a wall and a paddle in the very same tick near a
; corner, and that's fine; the two checks are independent. Reaching a
; paddle's column without landing on one of its 4 rows is a MISS, not a
; bounce: nothing is inverted, and the ball falls through to the scoring
; check in step 5 exactly as if no paddle were there.
;
; The two paddle blocks below are mirror images of each other. Branches
; inside the left-paddle block target @paddleDone with JMP (it's on the far
; side of the whole right-paddle block, out of BRA/Bcc range); the
; right-paddle block sits immediately before @paddleDone so its own exits
; can just branch there directly.
; -----------------------------------------------------------------------------
  stz SCAN_TMP2                   ; hit-this-tick flag; step 5 below skips scoring if set

  lda BALL_DX
  cmp #$FF
  beq @leftPaddleCheck
  jmp @checkRightPaddle

@leftPaddleCheck:
  lda NEW_BALL_X
  cmp #(P1_X+1)
  bcc @p1CheckRow                 ; NEW_BALL_X <= P1_X
  jmp @paddleDone                 ; not at the paddle's column yet
@p1CheckRow:
  lda NEW_BALL_Y
  cmp P1_Y
  bcc @p1Miss                     ; above the paddle's top row - miss
  sec
  sbc P1_Y
  cmp #PADDLE_HEIGHT
  bcs @p1Miss                     ; below the paddle's bottom row - miss
  sta SCAN_TMP                    ; offset within the paddle, 0-3, top row first
  lda #$01
  sta BALL_DX                     ; bounce away from the paddle: now moving right
  lda SCAN_TMP
  cmp #2
  bcc @p1BounceUp
  lda #$01
  sta BALL_DY                     ; hit the lower half of the paddle - bounce down
  bra @p1BounceDone
@p1BounceUp:
  lda #$FF
  sta BALL_DY                     ; hit the upper half of the paddle - bounce up
@p1BounceDone:
  lda BALL_X
  clc
  adc BALL_DX
  sta NEW_BALL_X                  ; recompute so the ball moves away this same tick
  inc HIT_COUNT
  jsr Sound_PaddleHit
  lda CUR_DELAY
  cmp #MIN_DELAY
  beq @p1DelayFloor
  dec CUR_DELAY
@p1DelayFloor:
  lda #1
  sta SCAN_TMP2                   ; a hit happened this tick - step 5 skips scoring
  jmp @paddleDone
@p1Miss:
  jmp @paddleDone

@checkRightPaddle:
  lda BALL_DX
  cmp #$01
  bne @paddleDone                 ; defensive: BALL_DX should only ever be $01 or $FF
  lda NEW_BALL_X
  cmp #P2_X
  bcs @p2CheckRow                 ; NEW_BALL_X >= P2_X
  bra @paddleDone                 ; not at the paddle's column yet
@p2CheckRow:
  lda NEW_BALL_Y
  cmp P2_Y
  bcc @paddleDone                 ; above the paddle's top row - miss
  sec
  sbc P2_Y
  cmp #PADDLE_HEIGHT
  bcs @paddleDone                 ; below the paddle's bottom row - miss
  sta SCAN_TMP
  lda #$FF
  sta BALL_DX                     ; bounce away from the paddle: now moving left
  lda SCAN_TMP
  cmp #2
  bcc @p2BounceUp
  lda #$01
  sta BALL_DY
  bra @p2BounceDone
@p2BounceUp:
  lda #$FF
  sta BALL_DY
@p2BounceDone:
  lda BALL_X
  clc
  adc BALL_DX
  sta NEW_BALL_X
  inc HIT_COUNT
  jsr Sound_PaddleHit
  lda CUR_DELAY
  cmp #MIN_DELAY
  beq @p2DelayFloor
  dec CUR_DELAY
@p2DelayFloor:
  lda #1
  sta SCAN_TMP2

@paddleDone:

; -----------------------------------------------------------------------------
; Step 5: scoring, but only if step 4 did NOT just register a paddle hit
; this tick (SCAN_TMP2 is the hit-this-tick flag set above). Note the strict
; </> here versus the <=/>= paddle collision used above at the same column -
; a miss that merely reached the column needs one more tick to actually
; cross the edge before it counts as a score.
; -----------------------------------------------------------------------------
  lda SCAN_TMP2
  beq @checkScoring
  jmp @commitBall
@checkScoring:

  lda NEW_BALL_X
  cmp #P1_X
  bcc @p2Scores                   ; NEW_BALL_X < P1_X - missed the left paddle
  jmp @checkRightScore
@p2Scores:
  inc P2_SCORE
  jsr Sound_Score
  jsr UpdateHud
  lda BALL_Y
  ldx BALL_X
  jsr EraseTile                   ; erase the ball's OLD position - it never reached NEW_BALL_*
  lda P2_SCORE
  cmp #WIN_SCORE
  bcc @p2NotWin
  lda #STATE_GAMEOVER
  sta GAME_STATE
  jsr DrawWinOverlay
  rts
@p2NotWin:
  jsr ServeBall
  rts

@checkRightScore:
  lda NEW_BALL_X
  cmp #(P2_X+1)
  bcs @p1Scores                   ; NEW_BALL_X > P2_X - missed the right paddle
  jmp @commitBall
@p1Scores:
  inc P1_SCORE
  jsr Sound_Score
  jsr UpdateHud
  lda BALL_Y
  ldx BALL_X
  jsr EraseTile
  lda P1_SCORE
  cmp #WIN_SCORE
  bcc @p1NotWin
  lda #STATE_GAMEOVER
  sta GAME_STATE
  jsr DrawWinOverlay
  rts
@p1NotWin:
  jsr ServeBall
  rts

; -----------------------------------------------------------------------------
; Step 6: no score this tick - commit the candidate position. Reached from
; every non-scoring path above (straight flight, a wall bounce, a paddle
; bounce, or a miss that hasn't crossed the edge yet), always using whatever
; NEW_BALL_X/NEW_BALL_Y ended up being after any bounce recompute above.
; -----------------------------------------------------------------------------
@commitBall:
  lda BALL_Y
  ldx BALL_X
  jsr EraseTile

  lda NEW_BALL_X
  sta BALL_X
  lda NEW_BALL_Y
  sta BALL_Y

  lda BALL_Y
  ldx BALL_X
  ldy #TILE_BALL
  jsr DrawTile
  rts

; =============================================================================
;   Data - HUD label strings (null-terminated, drawn via DrawString)
; =============================================================================
P1Label:
  .byte "P1:", 0
P2Label:
  .byte "P2:", 0
