#include "globus_xio.h"
#include "globus_gridftp_server.h"

void
test_res(
    globus_result_t                         res,
    int                                     line)
{
    if(res == GLOBUS_SUCCESS)
    {
        return;
    }
                                                                                
    fprintf(stderr, "ERROR at line:%d: %s\n", 
        line,
        globus_object_printable_to_string(
            globus_error_get(res)));
                                                                                
    globus_assert(0);
}


int
main(
    int                                     argc,
    char **                                 argv)
{
    globus_xio_driver_t                     tcp_driver;
    globus_xio_driver_t                     ftp_driver;
    globus_xio_stack_t                      stack;
    globus_xio_handle_t                     xio_handle;
    globus_xio_target_t                     target;
    globus_result_t                         res;

    globus_module_activate(GLOBUS_XIO_MODULE);

    /*
     *  set up the xio handle
     */
    res = globus_xio_driver_load("tcp", &tcp_driver);
    test_res(res, __LINE__);
    res = globus_xio_driver_load("gssapi_ftp", &ftp_driver);
    test_res(res, __LINE__);
    res = globus_xio_stack_init(&stack, NULL);
    res = globus_xio_stack_push_driver(stack, tcp_driver);
    test_res(res, __LINE__);
    res = globus_xio_stack_push_driver(stack, ftp_driver);
    test_res(res, __LINE__);

    res = globus_xio_server_create(&server, NULL, stack);
    test_res(res, __LINE__);
    res = globus_xio_server_accept(&target, server, NULL);
    test_res(res, __LINE__);

    res = globus_xio_open(&xio_handle, NULL, target);
    test_res(res, __LINE__);

    return 0;
}
