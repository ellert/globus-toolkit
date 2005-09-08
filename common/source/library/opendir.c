/*
 * Portions of this file Copyright 1999-2005 University of Chicago
 * Portions of this file Copyright 1999-2005 The University of Southern California.
 *
 * This file or a portion of this file is licensed under the
 * terms of the Globus Toolkit Public License, found at
 * http://www.globus.org/toolkit/download/license.html.
 * If you redistribute this file, with or without
 * modifications, you must include this notice in the file.
 */


#include "globus_common.h"

#ifdef GLOBUS_IMPLEMENT_OPENDIR

#ifdef TARGET_ARCH_NETOS
static
void
globus_l_opendir_callback(
    void *                              io_request_callback)
{
    NAFS_IO_REQUEST_CB *                fs_request;
    DIR *                               dirp;

    fs_request = io_request_callback;
    dirp = (DIR *) fs_request->user_data;

    dirp->error_code = fs_request->error_code;

    tx_semaphore_put(&dirp->sem);
}
/* globus_l_opendir_callback() */
#endif


extern
DIR *
opendir(
    char *                              filename)
{
#ifdef TARGET_ARCH_NETOS
    int                                 rc;
    DIR *                               dirp;
    unsigned int                        mask;
    NAFS_IO_REQUEST_CB                  fs_request;
    int                                 save_errno = 0;

    dirp = calloc(1, sizeof(DIR));
    if (dirp == NULL)
    {
        save_errno = ENOMEM;

        goto out;
    }

    rc = tx_semaphore_create(&dirp->sem, "opendir", 0);
    if (rc != TX_SUCCESS)
    {
        save_errno = ENOMEM;

        goto free_dir_out;
    }
    rc = NAFSinit_io_request_cb(
            &fs_request,
            globus_l_opendir_callback,
            (unsigned int) dirp);
    if (rc != GLOBUS_SUCCESS)
    {
        save_errno = ENOMEM;

        goto free_sem_out;
    }

    mask = NASYSACC_FS_GROUP1_READ|NASYSACC_FS_GROUP2_READ|
           NASYSACC_FS_GROUP3_READ|NASYSACC_FS_GROUP4_READ|
           NASYSACC_FS_GROUP5_READ|NASYSACC_FS_GROUP6_READ|
           NASYSACC_FS_GROUP7_READ|NASYSACC_FS_GROUP8_READ|
           NASYSACC_FS_GROUP1_WRITE|NASYSACC_FS_GROUP2_WRITE|
           NASYSACC_FS_GROUP3_WRITE|NASYSACC_FS_GROUP4_WRITE|
           NASYSACC_FS_GROUP5_WRITE|NASYSACC_FS_GROUP6_WRITE|
           NASYSACC_FS_GROUP7_WRITE|NASYSACC_FS_GROUP8_WRITE;

    rc = NAFSdir_entry_count(
            filename,
            mask,
            &dirp->dir_entry_count,
            &fs_request);

    if (rc != NAFS_SUCCESS)
    {
        save_errno = ENOMEM;

        goto free_sem_out;
    }

    rc = tx_semaphore_get(&dirp->sem, TX_WAIT_FOREVER);

    if (rc != TX_SUCCESS)
    {
        save_errno = ENOMEM;

        goto free_sem_out;
    }
    else if (dirp->error_code != 0)
    {
        switch (dirp->error_code)
        {
            case NAFS_DIR_ENTRY_NOT_FOUND:
                save_errno = ENOENT;
                break;
            case NAFS_NO_READ_PERMISSION:
                save_errno = EPERM;
                break;
            default:
                save_errno = EINVAL;
                break;
        }
        goto free_sem_out;
    }
    
    dirp->entries = calloc(
            dirp->dir_entry_count,
            sizeof(NAFS_DIR_ENTRY_INFO));

    if (dirp->entries == NULL)
    {
        save_errno = ENOMEM;

        goto free_sem_out;
    }

    rc = NAFSinit_io_request_cb(
            &fs_request,
            globus_l_opendir_callback,
            (unsigned int) dirp);
    if (rc != NAFS_SUCCESS)
    {
        save_errno = ENOMEM;

        goto free_dir_entries_out;
    }

    rc = NAFSlist_dir(
            filename,
            mask,
            dirp->entries,
            dirp->dir_entry_count,
            &fs_request);

    if (rc != GLOBUS_SUCCESS)
    {
        save_errno = ENOMEM;

        goto free_dir_entries_out;
    }

    if (save_errno != 0)
    {
free_dir_entries_out:
        free(dirp->entries);
free_sem_out:
        tx_semaphore_delete(&dirp->sem);
free_dir_out:
        free(dirp);
        dirp = NULL;
        errno = save_errno;
    }
out:
    return dirp;
#endif /* TARGET_ARCH_NETOS */
}
#endif /* IMPLEMENT_DIR_FUNCTIONS */
