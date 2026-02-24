#ifndef MINIZ_HEADER_FILE_H
#define MINIZ_HEADER_FILE_H

#include <stdlib.h>
#include <time.h>
#include <string.h>

typedef unsigned char mz_uint8;
typedef unsigned short mz_uint16;
typedef unsigned int mz_uint32;
typedef unsigned long long mz_uint64;
typedef int mz_bool;

#define MZ_TRUE (1)
#define MZ_FALSE (0)

typedef enum {
    MZ_ZIP_MODE_INVALID = 0,
    MZ_ZIP_MODE_READING = 1,
    MZ_ZIP_MODE_WRITING = 2,
    MZ_ZIP_MODE_WRITING_HAS_BEEN_FINALIZED = 3
} mz_zip_mode;

typedef struct {
    mz_uint64 m_archive_size;
    mz_uint64 m_central_directory_file_offsets;
    mz_uint32 m_total_files;
    mz_zip_mode m_zip_mode;
    // Simplified for this task
    void *m_pState;
} mz_zip_archive;

mz_bool mz_zip_reader_init_file(mz_zip_archive *pZip, const char *pFilename, mz_uint32 flags);
mz_bool mz_zip_reader_extract_to_file(mz_zip_archive *pZip, mz_uint32 file_index, const char *pDst_filename, mz_uint32 flags);
mz_uint32 mz_zip_reader_get_num_files(mz_zip_archive *pZip);
mz_bool mz_zip_reader_get_filename(mz_zip_archive *pZip, mz_uint32 file_index, char *pFilename, mz_uint32 filename_buf_size);
mz_bool mz_zip_reader_is_file_a_directory(mz_zip_archive *pZip, mz_uint32 file_index);
mz_bool mz_zip_reader_end(mz_zip_archive *pZip);

mz_bool mz_zip_writer_init_file(mz_zip_archive *pZip, const char *pFilename, mz_uint64 size_to_reserve_at_beginning);
mz_bool mz_zip_writer_add_file(mz_zip_archive *pZip, const char *pArchive_name, const char *pSrc_filename, const void *pComment, mz_uint16 comment_size, mz_uint32 level_and_flags);
mz_bool mz_zip_writer_finalize_archive(mz_zip_archive *pZip);
mz_bool mz_zip_writer_end(mz_zip_archive *pZip);

#endif
