window        : Window_Info;
watcher       : File_Watcher;
images        : [..]Image;
current_index := 0;
directory     := "images";
view_mode     := View_Mode.Gallery;

main :: () {
    start_directory_watcher();
    initialise_window();
    load_images();

    while !window.quit {
        process_window_events();
        process_changes(*watcher);
        draw_one_frame();
        sleep_milliseconds(10);
        reset_temporary_storage();
    }
}

process_window_events :: () {
    Input.update_window_events();

    for Input.get_window_resizes() {
        Simp.update_window(it.window);

        if it.window == window.window {
            window.width  = it.width;
            window.height = it.height;
        }
    }

    for Input.events_this_frame {
        if it.type == .QUIT then window.quit = true;
        if it.type == .KEYBOARD && it.key_pressed {
            if it.key_code == {
                case .ESCAPE;       handle_escape(); 
                case .ENTER;        handle_return();
                case .ARROW_LEFT;   move_cursor_left();
                case .ARROW_RIGHT;  move_cursor_right();
                case .ARROW_DOWN;   move_cursor_down();
                case .ARROW_UP;     move_cursor_up();
            }
        }
    }
}

draw_one_frame :: () {
    Simp.clear_render_target(.1, .1, .1, 1);

    if #complete view_mode == {
        case .Image;
            draw_image(images[current_index], 0, 0, xx window.width, xx window.height);
        case .Gallery;
            rows := cast(int)(sqrt(cast(float)images.count));
            cols := cast(int)(ceil(cast(float)images.count / rows));
            w := window.width / cols;
            h := window.height / rows;

            // @TODO: draw something nicer than a big white background
            {
                x := cast(float)(current_index % cols);
                y := cast(float)(current_index / cols);
                Simp.set_shader_for_color();
                Simp.immediate_quad(x*w, window.height-(y+1)*h, x*w + w, window.height-(y+1)*h + h, WHITE);
            }

            for images {
                x := cast(float)(it_index % cols);
                y := cast(float)(it_index / cols);
                draw_image(it, x*w, window.height-(y+1)*h, x*w + w, window.height-(y+1)*h + h);
            }
    }

    Simp.swap_buffers(window.window);
}

draw_image :: (using image: Image, x0: float, y0: float, x1: float, y1: float) {
    // maintain aspect ratio of image
    max_w := x1 - x0;
    max_h := y1 - y0;
    ratio := min(max_w / texture.width, max_h / texture.height);
    w := texture.width * ratio;
    h := texture.height * ratio;
    x := x0 + (max_w - w) * 0.5;
    y := y0 + (max_h - h) * 0.5;
    Simp.set_shader_for_images(*texture);
    Simp.immediate_quad(x, y, x + w, y + h, WHITE);
}

move_cursor_left :: () {
    current_index = max(current_index - 1, 0);
}

move_cursor_right :: () {
    current_index = min(current_index + 1, images.count - 1);
}

move_cursor_up :: () {
    rows := cast(int)(sqrt(cast(float)images.count));
    current_index = max(current_index - rows - 1, 0);
}

move_cursor_down :: () {
    rows := cast(int)(sqrt(cast(float)images.count));
    current_index = min(current_index + rows + 1, images.count - 1);
}

handle_return :: () {
    if view_mode == .Gallery {
        view_mode = .Image;
    }
}

handle_escape :: () {
    if view_mode == .Image {
        view_mode = .Gallery;
    } else {
        window.quit = true;
    }
}

initialise_window :: () {
    #if OS == .WINDOWS {
        Windows :: #import "Windows";
        Windows.SetProcessDPIAware();
        Windows.timeBeginPeriod(1);
    }

    window.window = create_window(window.width, window.height, "mimg");
    window.width, window.height = Simp.get_render_dimensions(window.window);
    Simp.set_render_target(window.window);
}

start_directory_watcher :: () {
    init(*watcher, handle_directory_event);
    if !add_directories(*watcher, directory) {
        print("ERROR: Couldn't watch directory '%'", directory);
        exit(1);
    }
}

handle_directory_event :: (watcher: *File_Watcher(void), change: *File_Change, user_data: *void) {
    current_path_before_change := copy_string(images[current_index].path);

    if change.events & .REMOVED || change.events & .MOVED_FROM {
        for images {
            if it.path == change.full_path {
                remove it;
                print("Removed '%'\n", change.full_path);
            }
        }
    }

    if change.events & .ADDED || change.events & .MOVED_TO {
        load_image(change.full_path);
        print("Added '%'\n", change.full_path);
    }

    // sort the images based on the file name to (roughly) match the file explorer
    quick_sort(images, (a, b) => compare(a.path, b.path));

    // try to keep the previously viewed image selected
    for images {
        if it.path == current_path_before_change {
            current_index = it_index;
            break;
        }
    }

    // if the image we were viewing was deleted, and was the last image, make sure we stay in bounds
    current_index = min(current_index, images.count - 1);
}

load_image :: (path: string) {
    image := array_add(*images);
    image.path = copy_string(path);
    success := Simp.texture_load_from_file(*image.texture, path);
    assert(success);
}

load_images :: () {
    for file_list(directory) {
        load_image(it);
    }
}

Image :: struct {
    path    : string;
    texture : Simp.Texture;
}

Window_Info :: struct {
    window : Window_Type;
    width  := 960;
    height := 600;
    quit   := false;
}

View_Mode :: enum {
    Image;
    Gallery;
}

WHITE :: Vector4.{1, 1, 1, 1};

Simp  :: #import "Simp";
Input :: #import "Input";
#import "Math";
#import "Sort";
#import "Basic";
#import "String";
#import "File_Watcher";
#import "File_Utilities";
#import "Window_Creation";