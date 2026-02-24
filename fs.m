// File: fs.c
// Location: プロジェクト直下

#include "fs.h"
#include <dirent.h>
#include <stdio.h>

void fs_list(const char* path)
{
    DIR* dir = opendir(path);
    if (!dir)
    {
        printf("opendir failed\n");
        return;
    }

    struct dirent* entry;

    while ((entry = readdir(dir)) != NULL)
    {
        if (entry->d_name[0] == '.' &&
           (entry->d_name[1] == '\0' ||
           (entry->d_name[1] == '.' && entry->d_name[2] == '\0')))
        {
            continue;
        }

        printf("%s\n", entry->d_name);
    }

    closedir(dir);
}