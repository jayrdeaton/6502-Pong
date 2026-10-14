; =============================================================================
;   zeropage.inc - Pong zero-page variables and game constants
; =============================================================================
;   Zero page $3A-$FF is free for a program that has taken the machine over
;   (see SECTION 1 of 6502.inc). 6502.cfg defines no RAM/BSS segment, so
;   every variable below is a fixed-address equate (:=), not a
;   .zeropage/.bss allocation. No RAM arrays needed outside zero page:
;   Pong (unlike Snake) has no ring buffers or occupancy grid to track.
; =============================================================================

; --- Game state constants ---
STATE_TITLE     = 0
STATE_PLAYING   = 1
STATE_PAUSED    = 2
STATE_GAMEOVER  = 3

MODE_1P         = 0   ; vs CPU
MODE_2P         = 1   ; two human players

DIR_NONE        = 0
DIR_UP          = 1
DIR_DOWN        = 2

; --- Zero page variables ---
GAME_STATE      := $3A   ; STATE_*
GAME_MODE       := $3B   ; MODE_1P / MODE_2P
P1_Y            := $3C   ; left paddle top row (paddle spans P1_Y..P1_Y+3)
P2_Y            := $3D   ; right paddle top row
BALL_X          := $3E
BALL_Y          := $3F
BALL_DX         := $40   ; two's complement: $01 = +1 (right), $FF = -1 (left)
BALL_DY         := $41   ; $01 = +1 (down), $FF = -1 (up), $00 = flat
P1_SCORE        := $42   ; 0-99 in practice (WIN_SCORE caps play well under that)
P2_SCORE        := $43
RNG_STATE       := $44   ; 8-bit LFSR state (never 0)
NEXT_P1         := $45   ; DIR_NONE/DIR_UP/DIR_DOWN, buffered each poll
NEXT_P2         := $46   ; DIR_NONE/DIR_UP/DIR_DOWN (2P mode only; CPU drives P2 in 1P)
HIT_COUNT       := $47   ; paddle hits so far this rally (speed escalation)
CUR_DELAY       := $48   ; current SysDelay centiseconds value, floors at MIN_DELAY
NEW_BALL_X      := $49   ; scratch: candidate ball position this tick
NEW_BALL_Y      := $4A
OFFSET_LO       := $4B   ; scratch: row*32+col VRAM name-table offset
OFFSET_HI       := $4C
SCAN_TMP        := $4D   ; scratch loop counter
SCAN_TMP2       := $4E   ; scratch loop counter (nested loops)
DIGIT_BUF       := $4F   ; 2 bytes, $4F-$50: ASCII tens/ones digits of a score
WORK_PTR        := $51   ; 2 bytes, $51-$52: string pointer for DrawString
STR_IDX         := $53   ; scratch: string/loop index for text-drawing routines
MSG_ROW         := $54   ; scratch: row argument for DrawString/ClearRow
START_PRESSED   := $55   ; set by PollInput when fire/space/joy-fire is down this poll
PREV_FIRE       := $56   ; START_PRESSED as of the previous poll (edge detection)
FIRE_EDGE       := $57   ; set only on the poll fire first goes down (see input.asm)
JOY_STATE       := $58   ; scratch: last raw ReadJoystick1/2 byte (combined where applicable)
JOY_STATE2      := $59   ; scratch: raw ReadJoystick2 byte, for split single-port polling
                          ; (PollJoy2 in gameplay's 2P mode / 1P-mode OR-into-P1 combine)
AI_TARGET       := $5A   ; scratch: CPU AI's desired direction this decision tick
CPU_TICK        := $5B   ; scratch: alternates each Tick, gates CPU AI's reaction speed
MENU_DIR        := $5C   ; set by PollMenuInput each poll: DIR_NONE/DIR_UP/DIR_DOWN
SC_TMP          := $5D   ; scratch: working copy of a score during digit conversion

; --- Keyboard fallback (6502-Lib's shared core/input.asm; see src/input.asm) ---
KB_DIR          := $5E   ; DrainKeyboardCombined output, title menu only (WASD-or-arrows)
KB_DIR_P1       := $5F   ; DrainKeyboardSplit output: last WASD direction seen this drain
KB_DIR_P2       := $60   ; DrainKeyboardSplit output: last arrow-key direction seen this drain
KB_FIRE         := $61   ; shared by both drain routines: 1 if space seen this drain, else 0
P1_KB_HOLD_TTL  := $62   ; gameplay: P1's keyboard hold-decay countdown (see PollInput)
P1_KB_HOLD_DIR  := $63   ; gameplay: P1's last-known WASD direction, valid while TTL nonzero
P2_KB_HOLD_TTL  := $64   ; gameplay: P2's keyboard hold-decay countdown (see PollInput)
P2_KB_HOLD_DIR  := $65   ; gameplay: P2's last-known arrow-key direction, valid while TTL nonzero
KB_FIRE_P1      := $66   ; required by 6502-Lib's DrainKeyboardSplit contract (space-only
                          ; edge); Pong doesn't act on this separately from KB_FIRE, since
                          ; it has one shared fire/start/pause action, not per-player fire
KB_FIRE_P2      := $67   ; required by 6502-Lib's DrainKeyboardSplit contract (enter-only
                          ; edge); same "unused, just satisfying the contract" as KB_FIRE_P1

; --- Playfield / paddle / ball constants ---
GRID_COLS         = 32
GRID_ROWS         = 24
FIELD_TOP_WALL    = 1    ; row of the top wall
FIELD_BOTTOM_WALL = 22   ; row of the bottom wall
FIELD_TOP         = 2    ; first playable row (paddle/ball travel)
FIELD_BOTTOM      = 21   ; last playable row

PADDLE_HEIGHT   = 4
P1_X            = 2      ; left paddle column
P2_X            = 29     ; right paddle column
PADDLE_MIN_Y    = 2       ; topmost legal paddle-top row
PADDLE_MAX_Y    = 18      ; bottommost legal paddle-top row (21-4+1)

BALL_START_X    = 16
BALL_START_Y    = 11

BASE_DELAY      = 8      ; starting SysDelay centiseconds (~80ms/tick)
MIN_DELAY       = 3      ; fastest allowed (~30ms/tick), speed escalation floor
WIN_SCORE       = 11

; --- Overlay box geometry (win screen), same shape as Snake's game-over box ---
BOX_LEFT        = 6
BOX_TOP         = 8
BOX_WIDTH       = 20
BOX_HEIGHT      = 8
