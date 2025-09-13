package snake

import rl "vendor:raylib"
import "core:fmt"
import "core:math"

// const
WINDOW_SIZE     :: 500
GRID_WIDTH      :: 20
CANVAS_SIZE     :: GRID_WIDTH * CELL_SIZE
CELL_SIZE       :: 8
TICK_RATE       :: .13
MAX_SNAKE_SIZE  :: GRID_WIDTH * GRID_WIDTH
SHAKE_DURATION  :: 1.0

// timer
tick_timer: f32 = TICK_RATE
shake_timer:f32 = SHAKE_DURATION

// typedef
Vec2i       :: #type [2]int
Assets      :: #type struct {
    // textures
    food_img: rl.Texture2D,
    head_img: rl.Texture2D,
    body_img: rl.Texture2D,
    tail_img: rl.Texture2D,
    // sounds
    crash_sound: rl.Sound,
    eat_sound:   rl.Sound
}

// directions
UP              : Vec2i : {0, -1}
DOWN            : Vec2i : {0, 1}
LEFT            : Vec2i : {-1, 0}
RIGTH           : Vec2i : {1, 0}

// direction
move_direction: Vec2i

// snake body parts array
snake: [MAX_SNAKE_SIZE]Vec2i
snake_length: int

// position of the head
snake_head: ^Vec2i

// game over bool (default init is false)
game_over: bool

// food position
food_pos: Vec2i

// assets
assets: Assets

// high score
Score :: #type struct {
    name    : string,
    score   : int
}

high_scores : [10]Score
high_score_printed: bool
is_shaking: bool
start_shake: f32

place_food :: proc() {
    occupied: [GRID_WIDTH][GRID_WIDTH] bool;

    for i in 0..<snake_length {
        occupied[snake[i].x][snake[i].y] = true;
    }


    free_cells := make([dynamic]Vec2i, context.temp_allocator);
    for x in 0..<GRID_WIDTH {
        for y in 0..<GRID_WIDTH {
            if (!occupied[x][y]) {
                append(&free_cells, Vec2i { x, y });
            }
        }
    }

    if len(free_cells) > 0 {
        food_pos = free_cells[rl.GetRandomValue(0, i32(len(free_cells) - 1))];
    }
}

init_game :: proc() {
    start_head_position := Vec2i { GRID_WIDTH / 2, GRID_WIDTH / 2 };
    snake[0] = start_head_position;
    snake[1] = start_head_position - {0, 1};
    snake[2] = start_head_position - {0, 2};
    snake_length = 3;
    snake_head = &snake[0];
    move_direction = {0, 1};
    game_over = false;
    high_score_printed = false
    place_food();
}

load_assets :: proc() {
    using assets

    food_img = rl.LoadTexture("./snake-assets/food.png");
    head_img = rl.LoadTexture("./snake-assets/head.png");
    tail_img = rl.LoadTexture("./snake-assets/tail.png");
    body_img = rl.LoadTexture("./snake-assets/body.png");

    eat_sound = rl.LoadSound("./snake-assets/eat.wav")
    crash_sound = rl.LoadSound("./snake-assets/crash.wav")
}

clear_assets :: proc() {
    using assets

    rl.UnloadTexture(food_img)
    rl.UnloadTexture(head_img)
    rl.UnloadTexture(tail_img)
    rl.UnloadTexture(body_img)
    rl.UnloadSound(eat_sound)
    rl.UnloadSound(crash_sound)
}

compute_rotation :: proc(direction: Vec2i) -> f32 {
    switch (direction) {
        case UP    : return 270.0 
        case DOWN  : return 90.0
        case LEFT  : return 180.0
        case       : return 0.0
    }
}

draw_snake :: proc() {
    using assets

    rotation :f32
    direction:Vec2i

    for i in 0..<(snake_length) {
        sprite: rl.Texture2D
        if (i == 0) {
            sprite = head_img
            direction = move_direction
        } else if i == (snake_length - 1) {
            sprite = tail_img
            direction = snake[i - 1] - snake[i]
        } else {
            sprite = body_img
            direction = snake[i - 1] - snake[i]
        }
        rotation = compute_rotation(direction) // more efficiency
        // rotation = math.atan2(f32(direction.y), f32(direction.x)) * math.DEG_PER_RAD // more useful if i need a lot of continuos angles
        // rl.DrawTextureEx(sprite, {f32(snake[i].x), f32(snake[i].y)} * CELL_SIZE, rotation, 0.5, rl.WHITE)

        // usign Pro to center the rotation in the square
        // *src* is a sub rect of the texture (useful with spritesheets)
        src := rl.Rectangle {
            0, // origin sprite rec x
            0, // origin sprite rec y
            f32(sprite.width),
            f32(sprite.height)
        }
        // *dst* rappresent where on the screen we want to draw 
        dst := rl.Rectangle {
            f32(snake[i].x) * CELL_SIZE + 0.5 * CELL_SIZE,
            f32(snake[i].y) * CELL_SIZE + 0.5 * CELL_SIZE,
            CELL_SIZE,
            CELL_SIZE
        }

        // *origin* (by default is 0) is the vec2 position of where the central axis will be 

        rl.DrawTexturePro(sprite, src, dst, {CELL_SIZE, CELL_SIZE} * 0.5, rotation, rl.WHITE)
    } 
}

update_scores :: proc() {
score := snake_length - 3
    name  := "fabio"

    pos := -1
    for i in 0..<10 {
        if score > high_scores[i].score {
            pos = i
            break
        }
    }
    if pos == -1 {
        return
    }

    for j := 8; j >= pos; j -= 1 {
        high_scores[j+1] = high_scores[j]
    }

    high_scores[pos] = Score{name = name, score = score}
}

game_over_screen :: proc() {
    rl.DrawText("Game Over!", 4, 4, 13, rl.RED)
    rl.DrawText("Press Enter to play again\nor Esc to quit", 4, 26, 7, rl.BLACK)
    rl.DrawText("High Scores:", 50, 50, 8, rl.RED)
    for i in 0..<10 {
        score: cstring = fmt.caprint(high_scores[i].name, high_scores[i].score);
        rl.DrawText(score, 63, i32(50 + (10 * (i + 1))), 1, rl.BLACK)
    }
}

shake_screen :: proc(camera: ^rl.Camera2D) {
    // @static offset : [2]f32 = {10.0, 10.0}
    @static rotation: f32 = 1.0
    camera^.rotation = rotation
    rotation *= -1
}

main :: proc() {
    // enable vsync
    rl.SetConfigFlags({.VSYNC_HINT});

    rl.InitWindow(WINDOW_SIZE, WINDOW_SIZE, "Snake");
    rl.InitAudioDevice()

    using assets;
    // set starting pos
    init_game();

    // loading assets
    load_assets()

    // camera
    camera := rl.Camera2D {
        zoom = f32(WINDOW_SIZE) / CANVAS_SIZE,
    }
    
    for (!rl.WindowShouldClose()) {
        // input management
        #partial switch (rl.GetKeyPressed()) {
            case rl.KeyboardKey.W : if ( move_direction != DOWN  ) { move_direction = UP    };
            case rl.KeyboardKey.S : if ( move_direction != UP    ) { move_direction = DOWN  }; 
            case rl.KeyboardKey.A : if ( move_direction != RIGTH ) { move_direction = LEFT  };
            case rl.KeyboardKey.D : if ( move_direction != LEFT  ) { move_direction = RIGTH };
        }

        if game_over {
            shake_timer -= rl.GetFrameTime()
            if shake_timer <= 0 {
                is_shaking = false
                if rl.IsKeyPressed(rl.KeyboardKey.ENTER) {
                    shake_timer = SHAKE_DURATION
                    init_game();
                }
            } else {
                shake_screen(&camera)
            }
        } else {
            // timer impl
            tick_timer -= rl.GetFrameTime(); // returns the delta time
        }

        if (tick_timer <= 0) {
            next_part_pos := snake_head^
            snake_head^ += move_direction;

            if (snake_head^).x < 0 || (snake_head^).y < 0 ||
            (snake_head^).x >= GRID_WIDTH || (snake_head^).y >= GRID_WIDTH {
                rl.PlaySound(crash_sound)
                is_shaking = true
                game_over = true;
            }

            for i in 1..<snake_length {
                buf := snake[i];
                // game over on auto hit
                if buf == snake_head^ && buf != snake[1] {
                    rl.PlaySound(crash_sound)
                    is_shaking = true
                    game_over = true;
                }
                snake[i] = next_part_pos;
                next_part_pos = buf;
            }

            if snake_head^ == food_pos {
                rl.PlaySound(eat_sound)
                snake_length += 1;
                snake[snake_length - 1] = next_part_pos;
                place_food();
            }

            tick_timer += TICK_RATE;
        }
        rl.BeginDrawing();
        rl.ClearBackground({76, 53, 85, 255});
        rl.BeginMode2D(camera);
        rl.DrawTextureEx(food_img, {f32(food_pos.x), f32(food_pos.y)} * CELL_SIZE, 0, 0.5, rl.WHITE)

        draw_snake()

        score: cstring = fmt.caprint("SCORE:", (snake_length - 3));
        rl.DrawText(score, 100, 10, 5, rl.GREEN)

        if (game_over) {
            if (!is_shaking) {
                if (!high_score_printed) {
                    update_scores()
                    high_score_printed = true
                }
                camera.rotation = 0.0
                game_over_screen()
            }
        }

        rl.EndMode2D();
        rl.EndDrawing();

        // freeing the mem of the dyn array allocated with this alloc
        // it's just to be sure since it's emptied automatically every "frame" 
        // (loop of the main proc)
        free_all(context.temp_allocator);
    }

    clear_assets()
    rl.CloseAudioDevice()
    rl.CloseWindow();


}