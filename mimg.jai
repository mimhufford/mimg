window        : Window_Info;
watcher       : File_Watcher;
images        : [..]Image;
current_index := 0;
directory     := "images";

main :: () {
    start_directory_watcher();
    initialise_window();
    load_images();

    while !window.quit {
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

            if it.type == {
              case .KEYBOARD;
                if it.key_pressed && it.key_code == .ESCAPE then window.quit = true;
                if it.key_pressed && it.key_code == .ARROW_LEFT   then current_index = max(current_index - 1, 0);
                if it.key_pressed && it.key_code == .ARROW_RIGHT  then current_index = min(current_index + 1, images.count - 1);
            }
        }

        process_changes(*watcher);

        if window.dirty {
            window.dirty = false;
            draw_one_frame();
            sleep_milliseconds(1);
        }
        else
        {
            window.dirty = true;
            sleep_milliseconds(10);
        }

        reset_temporary_storage();
    }
}

draw_one_frame :: () {
    Simp.clear_render_target(.1, .1, .1, 1);

    draw_image(images[current_index], 0, 0, xx window.width, xx window.height);

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
    dirty  := true;
    quit   := false;
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