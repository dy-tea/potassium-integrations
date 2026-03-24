--!nocheck

function import(...)
    return (load("import").value)(...)
end

type Variant = {
    platform: string,
    edition: string
}

local data_dir_path: string = path.persist_dir("balatro")
local love_dir_path: string = path.join(data_dir_path, "love")
local game_dir_path: string = path.join(data_dir_path, "Balatro.love")
local version_file_path = path.join(data_dir_path, "love_version")
local sdl2_compat_file_path = path.join(data_dir_path, "sdl2_compat")

local function is_game_installed(): boolean
    return fs.exists(game_dir_path)
end

local function set_installed_love_version(name: string)
    fs.write_file(version_file_path, name):await()
end

local function get_installed_love_version(): string
    if not fs.exists(version_file_path) then
        return ""
    end
    return str.from_bytes(fs.read_file(version_file_path):await())
end

local function get_love_versions(): {}
    -- github api keeps ratelimiting me so this is the easier way
    return {"11.5", "11.4", "11.3", "11.2", "11.1", "11.0"}
end

local function get_love_filename(name: string): string
    return `love-{name}-x86_64.AppImage`
end

local __settings = nil

local function import_settings()
    if not __settings then
        local versions = get_love_versions()
        __settings = import("settings")({
            game = "balatro",
            layout = {
                game = {
                    title = "Game",
                    entries = {
                        wayland = {
                            title = "Use Wayland",
                            entry = {
                                format = "switch",
                                default = true
                            }
                        },
                        love2d = {
                            title = "LÖVE Version",
                            entry = {
                                format = "enum",
                                values = versions,
                                default = versions[1]
                            }
                        }
                    }
                }
            }
        })
    end

    return __settings
end

return {
    version = 1,

    game = {
        get_launch_info = function(variant: Variant): nil | {}
            local settings = import_settings()

            if variant.platform ~= "x86_64-linux" then
               return nil
            end

            -- get love version
            local love_version = get_installed_love_version()
            if love_version == "" then
                return nil
            end

            -- ensure game is installed
            if not is_game_installed() then
                return nil
            end

            -- set args
            local args = {game_dir_path}

            -- set env
            local env = { LD_PRELOAD = path.join(sdl2_compat_file_path, "usr", "lib", "libSDL2-2.0.so.0") }
            local use_wayland = settings.get_property("game.wayland")
            if use_wayland then
                env["SDL_VIDEODRIVER"] = "wayland"
            else
                env["SDL_VIDEODRIVER"] = "x11"
            end

            return {
                status = "normal",
                binary = path.join(love_dir_path, get_love_filename(love_version)),
                args = args,
                env = env
            }
        end,

        get_actions_pipeline = function(variant: Variant): nil | {}
            local settings = import_settings()

            -- install LÖVE if needed
            local requested_love_version = settings.get_property("game.love2d")
            local installed_love_version = get_installed_love_version()
            if requested_love_version == "none" then
                return nil
            end
            if installed_love_version ~= requested_love_version then
                local on_update = function(updater, current, total)
                    updater({
                        current = current,
                        total = total,
                        format = `{current} / {total} MB`
                    })
                end
                return {
                    title = "Update Runner",
                    pipeline = {
                        {
                            title = "Install LÖVE",
                            perform = function(updater)
                                -- download
                                local handle = downloader.create()
                                local filename = get_love_filename(requested_love_version)
                                local output_file = path.join(love_dir_path, filename)
                                local task = downloader.download(handle, {
                                    url = `https://github.com/love2d/love/releases/download/{requested_love_version}/{filename}`,
                                    output_file = output_file,
                                    on_update = function(current, total)
                                        on_update(updater, current, total)
                                    end
                                })
                                downloader.wait(task)
                                downloader.close(handle)

                                -- update installed ver
                                set_installed_love_version(requested_love_version)

                                -- set as executable
                                process.exec("chmod", {"+x", output_file})
                            end
                        },
                        {
                            title = "Install sdl2-compat",
                            perform = function(updater)
                                -- parse sdl2-compat url from html response
                                local sdl2_compat_url = nil
                                local resp = http.fetch("https://packages.cachyos.org/package/extra/x86_64/sdl2-compat"):await()
                                if resp.is_ok then
                                    local body = resp.body:as_string()
                                    sdl2_compat_url = body:match('href="(https://archlinux%.cachyos%.org/repo/extra/os/x86_64/sdl2%-compat[^"]+%.pkg%.tar%.zst)"')
                                    if not sdl2_compat_url then
                                        error("Failed to parse sdl2-compat url")
                                    end
                                else
                                    error("Failed to fetch sdl2-compat url")
                                end


                                -- download
                                local handle = downloader.create()
                                local output_file = path.join(path.temp_dir(), "sdl2.tar.zst")
                                local task = downloader.download(handle, {
                                    url = sdl2_compat_url,
                                    output_file = output_file,
                                    on_update = function(current, total)
                                        on_update(updater, current, total)
                                    end
                                })
                                downloader.wait(task)
                                downloader.close(handle)

                                -- extract
                                local arch = archive.open(output_file)
                                archive.extract(arch, sdl2_compat_file_path)
                                archive.close(arch)
                            end
                        }
                    }
                }
            end

            -- skip game install if not required
            if is_game_installed() then
                return nil
            end

            -- download and patch game
            return {
                title = "Install Game",
                pipeline = {
                    {
                        title = "Download Game Files",
                        perform = function(updater)
                            local handle = downloader.create()
                            local task = downloader.download(handle, {
                                url = "https://archive.org/download/balatro_202512/Balatro.love",
                                output_file = game_dir_path,
                                on_update = function(current, total)
                                    updater({
                                        current = current,
                                        total = total,
                                        format = `{current} / {total} MB`
                                    })
                                end
                            })
                            downloader.wait(task)
                            downloader.close(handle)
                        end
                    }
                }
            }
        end,
    },

    settings = {
        get_property = function(name: string): any
            local settings = import_settings()
            return settings.get_property(name)
        end,

        set_property = function(name: string, value: any)
            local settings = import_settings()
            settings.set_property(name, value)
        end,

        get_layout = function(variant: Variant)
            local settings = import_settings()
            return settings.get_layout(variant)
        end
    }
}
