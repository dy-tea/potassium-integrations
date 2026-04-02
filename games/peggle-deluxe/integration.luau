--!nocheck

function import(...)
	return (load("import").value)(...)
end

type Variant = {
    platform: string,
    edition: string
}

local data_dir_path: string = path.persist_dir("peggle-deluxe")
local game_dir_path: string = path.join(data_dir_path, "Peggle Deluxe")
local exe_path: string = path.join(game_dir_path, "Peggle.exe")

local function is_game_installed(): boolean
	return fs.exists(exe_path)
end

local __settings = nil
local __components = nil

local function import_settings()
    if not __settings then
        __settings = import("settings")({
            game = "peggle_deluxe",
            layout = {}
        })
    end

    return __settings
end

local function import_components()
    if not __components then
        local settings = import_settings()

        __components = import("components").components({
            game = "peggle_deluxe",
            settings = {
                get_property = settings.get_property,
                set_property = settings.set_property
            }
        })

    end

    return __components
end

return {
    version = 1,

    game = {
        get_launch_info = function(variant: Variant): nil | {}
            if not is_game_installed() then
                return nil
            end

            local components = import_components()

            return components.game.wrap_launch_info({
                binary = exe_path,
            })
        end,

        get_actions_pipeline = function(variant: Variant): nil | {}
            local components = import_components()

            local pipeline = components.game.get_actions_pipeline(variant)
            if pipeline then
                return pipeline
            end

            if is_game_installed() then
                return nil
            end

            local archive_path: string = path.join(path.temp_dir(), "PeggleDeluxe.tar.gz")

            return {
                title = "Install Peggle Deluxe",

                pipeline = {
                    {
                        title = "Download Game files",

                        perform = function(updater)
                            local handle = downloader.create()

                            local task = downloader.download(handle, {
                                url = "https://archive.org/download/peggle-deluxe_202604/PeggleDeluxe.tar.gz",
                                output_file = archive_path,
                                continue_download = true,

                                on_update = function(current: number, total: number)
                                    updater({
                                        current = current,
                                        total = total,

                                        format = function()
                                            local current = math.floor(current / 1000 * 100) / 100
                                            local total = math.floor(total / 1000 * 100) / 100

                                            return `Downloaded {current} MB / {total} MB`
                                        end
                                    })
                                end
                            })

                            downloader.wait(task)
                            downloader.close(handle)
                        end
                    },

                    {
                        title = "Extract Game files",

                        perform = function(updater)
                            local handle = archive.open(archive_path, "tar")

                            archive.extract(handle, data_dir_path, function(current: number, total: number)
                                local current = math.floor(current / 1000 * 100) / 100
                                local total = math.floor(total / 1000 * 100) / 100

                                return `Downloaded {current} MB / {total} MB`
                            end)

                            archive.close(handle)
                            fs.remove(archive_path):await()
                        end
                    }
                }
            }
        end,

        settings = {
            get_property = function(name: string): any
                local settings = import_settings()
                return settings.get_property(name)
            end,

            set_property = function(name: string, value: any)
                local settings = import_settings()
                settings.set_property(name, value)
            end,

            get_layout = function(variant: Variant): {}
                local components = import_components()
                return components.settings.get_layout(variant)
            end
        }
    }
}
