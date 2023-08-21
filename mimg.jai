window        : Window_Info;
watcher       : *File_Watcher;
images        : [..]Image;
current_index := 0;
view_mode     := View_Mode.Gallery;

main :: () {
    initialise_window();

    // @TODO: accept directory as command line argument

    while !window.quit {
        process_window_events();
        if watcher process_changes(watcher);
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

        if it.type == .DRAG_AND_DROP_FILES {
            for it.files {
                if is_directory(it) {
                    open_directory(it);
                    break;
                }
            }
        }

        if it.type == .KEYBOARD && it.key_pressed {
            if it.key_code == {
                case .ESCAPE;       handle_escape();
                case .ENTER;        handle_return();
                case .DELETE;       delete_current_image();
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

    if watcher {
        if #complete view_mode == {
            case .Image;
                draw_image(images[current_index], 0, 0, xx window.width, xx window.height);
            case .Gallery;
                rows, cols := calculate_rows_and_cols_for_count(images.count);
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
    } else {
        // @TODO: draw message about dropping a directory onto the window
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

calculate_rows_and_cols_for_count :: (count: int) -> int, int {
    rows := cast(int)(sqrt(cast(float)count));
    cols := cast(int)(ceil(cast(float)count / rows));
    return rows, cols;
}

move_cursor_left :: () {
    current_index = max(current_index - 1, 0);
}

move_cursor_right :: () {
    current_index = min(current_index + 1, images.count - 1);
}

move_cursor_up :: () {
    _, cols := calculate_rows_and_cols_for_count(images.count);
    if current_index - cols >= 0 current_index -= cols;
}

move_cursor_down :: () {
    _, cols := calculate_rows_and_cols_for_count(images.count);
    current_index = min(current_index + cols, images.count - 1);
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

delete_current_image :: () {
    #if OS == .WINDOWS {
        #import "Windows";
        #import "Windows_Utf8";
        op : SHFILEOPSTRUCTW;
        op.wFunc = FO_DELETE;
        op.pFrom = utf8_to_wide(tprint("%\0\0", images[current_index].path));
        op.fFlags = .FOF_ALLOWUNDO;
        result := SHFileOperationW(*op);
    } else {
        // @TODO: move to bin instead of hard delete
        file_delete(images[current_index].path);
    }
}

initialise_window :: () {
    #if OS == .WINDOWS {
        #import "Windows";
        SetProcessDPIAware();
        timeBeginPeriod(1);
    }

    window.window = create_window(window.width, window.height, "mimg");
    window.width, window.height = Simp.get_render_dimensions(window.window);
    Simp.set_render_target(window.window);

    #if OS == .WINDOWS {
        DragAcceptFiles(window.window, cast(BOOL)true);
    } else {
        // @TODO: accept drag and drop
    }
}

open_directory :: (directory: string) {
    if watcher {
        deinit(watcher);
        free(watcher);
    }

    watcher = New(File_Watcher(void));
    init(watcher, handle_directory_event);

    if !add_directories(watcher, directory) {
        print("ERROR: Couldn't watch directory '%'", directory);
        exit(1);
    }

    array_reset(*images);

    for file_list(directory) {
        load_image(it);
    }
}

handle_directory_event :: (watcher: *File_Watcher(void), change: *File_Change, user_data: *void) {
    current_path_before_change := copy_string(images[current_index].path);

    if change.events & .REMOVED || change.events & .MOVED_FROM {
        for images {
            path := tprint("%", change.full_path);
            path_overwrite_separators(path);
            if it.path == path {
                remove it;
                print("Removed '%'\n", path);
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
    path_overwrite_separators(path);
    image.path = copy_string(path);
    success := Simp.texture_load_from_file(*image.texture, path);
    if !success {
        print("ERROR: failed to load '%'\n", path);
        images.count -= 1;
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
#import "File";
#import "Sort";
#import "Basic";
#import "String";
#import "System";
#import "File_Watcher";
#import "File_Utilities";
#import "Window_Creation";