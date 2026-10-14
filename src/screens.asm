; =============================================================================
;   screens.asm - Pong title/mode-select, new-game/serve, win and pause UI
; =============================================================================

.segment "CART"

; -----------------------------------------------------------------------------
; DrawTitleScreen - draw the title/mode-select screen in Graphics I. Always
; a full wipe and redraw, never layered on top of whatever was there before
; (the same discipline NewGame follows) - this runs both at initial boot
; (over an already-blank screen) and again after a game over (over a live
; win-overlay box and final board state), and only clearing at the latter
; call site would leave this routine unsafe to call from anywhere else.
; Every line's starting column is (32-length)/2 for exact centering.
; -----------------------------------------------------------------------------
DrawTitleScreen:
  jsr ClearScreen
  jsr DrawWalls

  lda #<TitleText
  sta WORK_PTR
  lda #>TitleText
  sta WORK_PTR+1
  lda #6
  ldx #12                      ; "P O N G" is 7 chars: (32-7)/2 = 12
  jsr DrawString

  ; paddle-and-ball decoration, rows 9-11: a short 3-tall bar near each
  ; edge of the row with the ball tile between them at the middle row
  lda #9
  ldx #4
  ldy #TILE_PADDLE
  jsr DrawTile
  lda #10
  ldx #4
  ldy #TILE_PADDLE
  jsr DrawTile
  lda #11
  ldx #4
  ldy #TILE_PADDLE
  jsr DrawTile

  lda #9
  ldx #27
  ldy #TILE_PADDLE
  jsr DrawTile
  lda #10
  ldx #27
  ldy #TILE_PADDLE
  jsr DrawTile
  lda #11
  ldx #27
  ldy #TILE_PADDLE
  jsr DrawTile

  lda #10
  ldx #16
  ldy #TILE_BALL
  jsr DrawTile

  lda #<OnePlayerMsg
  sta WORK_PTR
  lda #>OnePlayerMsg
  sta WORK_PTR+1
  lda #12
  ldx #11                      ; both option lines share a left-aligned
  jsr DrawString                ; start column so the cursor lines up

  lda #<TwoPlayerMsg
  sta WORK_PTR
  lda #>TwoPlayerMsg
  sta WORK_PTR+1
  lda #13
  ldx #11
  jsr DrawString

  lda #<ControlsMsg
  sta WORK_PTR
  lda #>ControlsMsg
  sta WORK_PTR+1
  lda #16
  ldx #2                       ; "UP/DOWN: SELECT   A: CONFIRM" is 28 chars: (32-28)/2 = 2
  jmp DrawString

; -----------------------------------------------------------------------------
; DrawMenuCursor - draw a ">" beside the option GAME_MODE currently selects
; (MODE_1P = row 12/"ONE PLAYER", MODE_2P = row 13/"TWO PLAYERS"), erasing
; both possible positions first so it can never leave a stale second cursor
; behind regardless of which way the selection just changed.
; -----------------------------------------------------------------------------
DrawMenuCursor:
  lda #12
  ldx #9
  jsr EraseTile
  lda #13
  ldx #9
  jsr EraseTile

  lda GAME_MODE
  cmp #MODE_1P
  bne @row13
  lda #12
  ldx #9
  ldy #'>'
  jmp DrawTile
@row13:
  lda #13
  ldx #9
  ldy #'>'
  jmp DrawTile

; -----------------------------------------------------------------------------
; WaitForModeSelect - a real up/down-navigable menu, not a direct-select
; key: up always highlights ONE PLAYER (the top option), down always
; highlights TWO PLAYERS (the bottom option) - with only two options,
; "which one am I choosing" is unambiguous from the direction alone, so
; there's no separate cursor-position state to track beyond GAME_MODE
; itself. The A button confirms whichever is currently highlighted.
; Increments RNG_STATE once per loop iteration while waiting (reaction-time
; entropy for seeding), then folds in RTC-based entropy if a clock is
; fitted, then guarantees RNG_STATE is never left at exactly 0 (a Galois
; LFSR fixed point). Same technique as the sibling Snake cartridge's
; title-wait loop.
; -----------------------------------------------------------------------------
WaitForModeSelect:
  stz RNG_STATE
  stz GAME_MODE                ; default highlight: ONE PLAYER
  jsr DrawMenuCursor
@loop:
  inc RNG_STATE
  jsr PollMenuInput

  lda MENU_DIR
  cmp #DIR_UP
  bne @notUp
  lda #MODE_1P
  sta GAME_MODE
  jsr DrawMenuCursor
@notUp:
  lda MENU_DIR
  cmp #DIR_DOWN
  bne @notDown
  lda #MODE_2P
  sta GAME_MODE
  jsr DrawMenuCursor
@notDown:

  lda FIRE_EDGE
  beq @loop

  lda HW_PRESENT
  and #HW_RTC
  beq @noRtc
  jsr RtcReadTime               ; A=hours, X=minutes, Y=seconds
  eor RNG_STATE
  sta RNG_STATE
  txa
  eor RNG_STATE
  sta RNG_STATE
  tya
  eor RNG_STATE
  sta RNG_STATE
@noRtc:
  lda RNG_STATE
  bne @nonzero
  lda #$2A
  sta RNG_STATE
@nonzero:
  rts

; -----------------------------------------------------------------------------
; NewGame - reset for a fresh game (also used when restarting after a game
; over, back through the title/mode-select flow). Does not touch GAME_MODE -
; whichever mode was already selected stays selected. Always a full wipe and
; redraw, never an incremental one: a sibling cartridge in this ecosystem had
; a real bug where a partial restart-redraw left stale content on screen.
; -----------------------------------------------------------------------------
NewGame:
  stz P1_SCORE
  stz P2_SCORE
  stz NEXT_P1
  stz NEXT_P2              ; DIR_NONE - KernalInit does not zero this range,
  stz CPU_TICK               ; so a cold boot could otherwise start with a
                              ; stale/garbage decision-parity or direction

  jsr ClearScreen
  jsr DrawWalls

  lda #((PADDLE_MIN_Y+PADDLE_MAX_Y)/2)
  sta P1_Y
  sta P2_Y

  stz SCAN_TMP
@drawPaddles:
  lda P1_Y
  clc
  adc SCAN_TMP
  ldx #P1_X
  ldy #TILE_PADDLE
  jsr DrawTile

  lda P2_Y
  clc
  adc SCAN_TMP
  ldx #P2_X
  ldy #TILE_PADDLE
  jsr DrawTile

  inc SCAN_TMP
  lda SCAN_TMP
  cmp #PADDLE_HEIGHT
  bne @drawPaddles

  jsr UpdateHud
  jsr ServeBall

  lda #STATE_PLAYING
  sta GAME_STATE
  rts

; -----------------------------------------------------------------------------
; ServeBall - reset the ball to center court with a fresh pseudo-random
; direction, undoing any speed escalation from the previous rally. Called
; from NewGame and, once per point scored, from physics.asm's Tick.
; -----------------------------------------------------------------------------
ServeBall:
  lda #BALL_START_X
  sta BALL_X
  lda #BALL_START_Y
  sta BALL_Y
  stz HIT_COUNT
  lda #BASE_DELAY
  sta CUR_DELAY

  jsr RollDirection
  and #1
  bne @dxRight
  lda #$FF
  sta BALL_DX
  jmp @pickDy
@dxRight:
  lda #1
  sta BALL_DX

@pickDy:
  jsr RollDirection
  and #3
  cmp #0
  beq @dyUp
  cmp #1
  beq @dyFlat
  lda #1                        ; 2 or 3 -> down (slight bias, fine for a serve angle)
  sta BALL_DY
  jmp @drawBall
@dyUp:
  lda #$FF
  sta BALL_DY
  jmp @drawBall
@dyFlat:
  stz BALL_DY

@drawBall:
  lda BALL_Y
  ldx BALL_X
  ldy #TILE_BALL
  jsr DrawTile
  rts

; -----------------------------------------------------------------------------
; DrawWinOverlay - draw the win screen: a bordered box on top of the final
; board state, same overlay technique as the sibling Snake cartridge's
; game-over screen. Does not change GAME_STATE itself - the caller
; (physics.asm's Tick) owns that transition.
; -----------------------------------------------------------------------------
DrawWinOverlay:
  jsr DrawBoxFrame
  jsr ClearBoxInterior

  lda #<GameOverMsg
  sta WORK_PTR
  lda #>GameOverMsg
  sta WORK_PTR+1
  lda #(BOX_TOP+1)
  ldx #11                       ; "GAME OVER" is 9 chars, box interior is 18 wide: 7+(18-9)/2 = 11
  jsr DrawString

  lda GAME_MODE
  cmp #MODE_1P
  beq @mode1P
  jmp @mode2P

@mode1P:
  lda P1_SCORE
  cmp #WIN_SCORE
  bcc @cpuWon
  lda #<YouWinMsg
  sta WORK_PTR
  lda #>YouWinMsg
  sta WORK_PTR+1
  jmp @drawWinner1P
@cpuWon:
  lda #<CpuWinsMsg
  sta WORK_PTR
  lda #>CpuWinsMsg
  sta WORK_PTR+1
@drawWinner1P:
  lda #(BOX_TOP+2)
  ldx #12                       ; "YOU WIN!"/"CPU WINS" both 8 chars: 7+(18-8)/2 = 12
  jsr DrawString
  jmp @score

@mode2P:
  lda P1_SCORE
  cmp #WIN_SCORE
  bcc @p2Won
  lda #<Player1WinsMsg
  sta WORK_PTR
  lda #>Player1WinsMsg
  sta WORK_PTR+1
  jmp @drawWinner2P
@p2Won:
  lda #<Player2WinsMsg
  sta WORK_PTR
  lda #>Player2WinsMsg
  sta WORK_PTR+1
@drawWinner2P:
  lda #(BOX_TOP+2)
  ldx #9                        ; "PLAYER 1/2 WINS" both 13 chars: 7+(18-13)/2 = 9
  jsr DrawString

@score:
  lda #<P1LabelMsg
  sta WORK_PTR
  lda #>P1LabelMsg
  sta WORK_PTR+1
  lda #(BOX_TOP+4)
  ldx #9                        ; "P1: NN  P2: NN" (14 chars) centered: 7+(18-14)/2 = 9
  jsr DrawString

  lda P1_SCORE
  jsr ValueToDigits2
  lda #(BOX_TOP+4)
  ldx #13                       ; right after "P1: " (4 chars, starts col 9)
  jsr DrawDigitBuf2

  lda #<P2LabelMsg
  sta WORK_PTR
  lda #>P2LabelMsg
  sta WORK_PTR+1
  lda #(BOX_TOP+4)
  ldx #15                       ; right after the P1 digits (2 chars, starts col 13)
  jsr DrawString

  lda P2_SCORE
  jsr ValueToDigits2
  lda #(BOX_TOP+4)
  ldx #21                       ; right after "  P2: " (6 chars, starts col 15)
  jsr DrawDigitBuf2

  lda #<PressATitleMsg
  sta WORK_PTR
  lda #>PressATitleMsg
  sta WORK_PTR+1
  lda #(BOX_TOP+6)
  ldx #8                        ; "PRESS A - TITLE" is 16 chars: BOX_LEFT(6)+(20-16)/2 = 8
  jsr DrawString

  jmp Sound_Win

; -----------------------------------------------------------------------------
; DrawPauseMessage - draw a short paused prompt at row 23, just below the
; bottom wall. Matches the sibling Snake cartridge's pause message.
; -----------------------------------------------------------------------------
DrawPauseMessage:
  lda #<PauseMsg
  sta WORK_PTR
  lda #>PauseMsg
  sta WORK_PTR+1
  lda #23
  ldx #8                        ; "PAUSED - PRESS A" is 16 chars: (32-16)/2 = 8
  jmp DrawString

; =============================================================================
;   String data
; =============================================================================

TitleText:
  .byte "P O N G", $00

OnePlayerMsg:
  .byte "ONE PLAYER", $00

TwoPlayerMsg:
  .byte "TWO PLAYERS", $00

ControlsMsg:
  .byte "UP/DOWN: SELECT   A: CONFIRM", $00

GameOverMsg:
  .byte "GAME OVER", $00

YouWinMsg:
  .byte "YOU WIN!", $00

CpuWinsMsg:
  .byte "CPU WINS", $00

Player1WinsMsg:
  .byte "PLAYER 1 WINS", $00

Player2WinsMsg:
  .byte "PLAYER 2 WINS", $00

P1LabelMsg:
  .byte "P1: ", $00

P2LabelMsg:
  .byte "  P2: ", $00

PressATitleMsg:
  .byte "PRESS A - TITLE", $00

PauseMsg:
  .byte "PAUSED - PRESS A", $00
