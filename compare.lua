-- Compare the contents of matching files between two directories.

-- Colors for pretty printing stats
local RESET = "\27[0m"
local RED = "\27[31m"
local GREEN = "\27[38;2;0;255;0m"

-- Usage
if not arg[1] then
    print("Compare files with matching filenames between directories")
    print("Usage: lua compare.lua directory_name_1 directory_name_2")
    os.exit(0)
end

-- Given a directory name, return a table where
-- table[filename] = nil, essentially an array
function table_of_filenames(directory)
    -- Quote the directory path for the shell so spaces or special
    -- characters don't break the command
    dir_ls = string.format("ls -1 %q", directory)
    results = io.popen(dir_ls)      -- popen returns a file handle, so we can use its iterator later
    filenames = {}
    for line in results:lines() do
        filenames[line] = true
    end
    return filenames
end

-- Helper to print a table
function print_table(table)
    for key, value in pairs(table) do
        print(key, value)
    end
end


-- Return whether the contents of our_dir_name/filename and test_dir_name/filename are the same
function check_file_match(filename, our_dir_name, test_dir_name)
    file1_name = our_dir_name.."/"..filename
    file2_name = test_dir_name.."/"..filename
    file1_handle = io.open(file1_name)
    file2_handle = io.open(file2_name)
    file1_contents = file1_handle:read("*a")
    file2_contents = file2_handle:read("*a")
    if (file1_contents == file2_contents) then
        return true
    else
        print(RED .. file1_name .. RESET .. " and " .. RED .. file2_name .. RESET .. " don't match")
        return false
    end
end


-- Return directory file matching stats.
function check_directories_match(directory_1, directory_2)
    -- successful:  The number of files where the filename exists in both directory_1 and directory_2,
    --              and their contents match.
    -- failed:      The number of files where the filename exists in both directory_1 and directory_2,
    --              and their contents DO NOT match.
    -- didnt_test:  The number of files in directory_1 that don't exist in directory_2.

    local successful = 0
    local failed = 0
    local didnt_test = 0

    local dir_1 = table_of_filenames(directory_1)
    local dir_2 = table_of_filenames(directory_2)

    for key, value in pairs(dir_1) do
        if dir_2[key] ~= nil then
            local is_match = check_file_match(key, directory_1, directory_2)
            if (is_match == true) then
                successful = successful + 1
            else
                failed = failed + 1
            end
        else
            didnt_test = didnt_test + 1
            print(RED .. key.. RESET .. " doesn't exist in " .. RED .. directory_2)
        end
    end

    return successful, failed, didnt_test
end 


-- Main script, grab command line arguments that
-- represent directories and run the comparison
local successful, failed, skipped = check_directories_match(arg[1], arg[2])
local success_rate = successful / (successful + failed)
print(string.format(GREEN .. "%.2f%%" .. RESET .. " of tests passed (%d/%d)", success_rate * 100, successful, successful + failed))
if skipped ~= 0 then
    print(string.format("%d files skipped", skipped))
end