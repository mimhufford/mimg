window        : Window_Info;
watcher       : File_Watcher;
images        : [..]Simp.Texture;
current_index := 0;
directory     := "images";

main :: () {
    #if OS == .WINDOWS {
        Windows :: #import "Windows";
        Windows.SetProcessDPIAware();
        Windows.timeBeginPeriod(1);
    }

    init(*watcher, watcher_event);
    if !add_directories(*watcher, directory) {
        print("ERROR: Couldn't watch directory '%'", directory);
        return;
    }

    window.window = create_window(window.width, window.height, "mimg");
    window.width, window.height = Simp.get_render_dimensions(window.window);
    Simp.set_render_target(window.window);

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

    image := images[current_index];
    Simp.set_shader_for_images(*image);

    // // maintain aspect ratio of image
    max_w := cast(float)window.width;
    max_h := cast(float)window.height;
    ratio := min(max_w / image.width, max_h / image.height);
    w := image.width * ratio;
    h := image.height * ratio;
    x := (max_w - w) * 0.5;
    y := (max_h - h) * 0.5;
    Simp.immediate_quad(x, y, x + w, y + h, WHITE);

    Simp.swap_buffers(window.window);
}

watcher_event :: (watcher: *File_Watcher(void), change: *File_Change, user_data: *void) {
    load_images();
}

load_images :: () {
    array_reset(*images);
    
    for file_list(directory) {
        image := array_add(*images);
        success := Simp.texture_load_from_file(image, it);
        assert(success);
    }

    // @TODO: try to maintain the currently viewing image
    //
    //        e.g. a b [c] d
    //
    //        if Image b is deleted we don't want this:
    //             a c [d]
    //
    //        instead, we want this:
    //             a [c] d
    //
    //        Maybe react to the Watcher events and mirror those changes in the array

    // we need to clamp the current_index in case an image was
    // deleted from the directory while viewing the last image 
    current_index = min(current_index, images.count - 1);
}

Window_Info :: struct {
    window: Window_Type;
    width  := 960;
    height := 600;
    dirty  := true;
    quit   := false;
}

WHITE :: Vector4.{1, 1, 1, 1};

Simp  :: #import "Simp";
Input :: #import "Input";
#import "Math";
#import "Basic";
#import "File_Watcher";
#import "File_Utilities";
#import "Window_Creation";