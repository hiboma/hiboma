# VirtualBox

## Shared Folders

### sf_write_end -> sf_reg_write_aux -> vboxCallWrite を追ってみる

TODO: ioctl から HostServices に繋げるコードがよくわからない

 * vboxCallWrite 
   * Additions/common/VBoxGuestLib/VBoxGuestR0LibSharedFolders.c
     * ___VBoxGuestR0Lib___ = ゲストOSの Ring 0 (特権モード) で呼び出すライブラリ
   * ___SHFL_FN_WRITE___ は src/VBox/HostServices/SharedFolders/service.cpp の ___svcCall___ で case 分で分岐に参照される
     * SHFL_FN_WRITE の場合 svcCall は vbfsWrite を呼び出す
       * vbfsWrite はホストOSのシステムコール呼び出しに繋がる。説明は後述
       * ということでホスト側の動作は HostServices/SharedFolders を追えばおk
     * `static DECLCALLBACK(void) svcCall (void *, VBOXHGCMCALLHANDLE callHandle, uint32_t u32ClientID, void *pvClient, uint32_t u32Function, uint32_t cParms, VBOXHGCMSVCPARM paParms[])` 
       * なげーよ

```c 
DECLVBGL(int) vboxCallWrite(PVBSFCLIENT pClient, PVBSFMAP pMap, SHFLHANDLE hFile,
                            uint64_t offset, uint32_t *pcbBuffer, uint8_t *pBuffer, bool fLocked)
{
    int rc = VINF_SUCCESS;

    VBoxSFWrite data;

    // SHFL_FN_ を作る。大事
    //#define VBOX_INIT_CALL(a, b, c)          \
    //    LogFunc(("%s, u32ClientID=%d\n", "SHFL_FN_" # b, \
    //            (c)->ulClientID)); \
    //    (a)->result      = VINF_SUCCESS;     \
    //    (a)->u32ClientID = (c)->ulClientID;  \
    //    (a)->u32Function = SHFL_FN_##b;      \
    //    (a)->cParms      = SHFL_CPARMS_##b
    //
    // SHFL_FN_WRITE (SharedFolder_Function_Write) を呼ぶ
    VBOX_INIT_CALL(&data.callInfo, WRITE, pClient);

    data.root.type                      = VMMDevHGCMParmType_32bit;
    data.root.u.value32                 = pMap->root;

    data.handle.type                    = VMMDevHGCMParmType_64bit;
    data.handle.u.value64               = hFile;
    data.offset.type                    = VMMDevHGCMParmType_64bit;
    data.offset.u.value64               = offset;
    data.cb.type                        = VMMDevHGCMParmType_32bit;
    data.cb.u.value32                   = *pcbBuffer;
    data.buffer.type                    = (fLocked) ? VMMDevHGCMParmType_LinAddr_Locked_In : VMMDevHGCMParmType_LinAddr_In;
    data.buffer.u.Pointer.size          = *pcbBuffer;
    data.buffer.u.Pointer.u.linearAddr  = (uintptr_t)pBuffer;

    rc = VbglHGCMCall (pClient->handle, &data.callInfo, sizeof (data));

/*    Log(("VBOXSF: VBoxSF::vboxCallWrite: "
         "VbglHGCMCall rc = %#x, result = %#x\n", rc, data.callInfo.result));
*/
    if (RT_SUCCESS (rc))
    {   
        rc = data.callInfo.result;
        *pcbBuffer = data.cb.u.value32;
    }   
    return rc; 
}
```

 * VbglHGCMCall
   * src/VBox/Additions/common/VBoxGuestLib/HGCM.cpp
     * ___HGCM___ = ___Host-Guest Communication Manager___
     * ___Vbgl___ = ___Virtual Box Guest Lib___

```c
DECLVBGL(int) VbglHGCMCall (VBGLHGCMHANDLE handle, VBoxGuestHGCMCallInfo *pData, uint32_t cbData)
{
    int rc = VINF_SUCCESS;

    VBGL_HGCM_ASSERTMsg(cbData >= sizeof (VBoxGuestHGCMCallInfo) + pData->cParms * sizeof (HGCMFunctionParameter),
                        ("cbData = %d, cParms = %d (calculated size %d)\n", cbData, pData->cParms, sizeof (VBoxGuestHGCMCallInfo) + pData->cParms * sizeof (VBoxGuestHGCMCallInfo)));

    rc = vbglDriverIOCtl (&handle->driver, VBOXGUEST_IOCTL_HGCM_CALL(cbData), pData, cbData);

    return rc; 
}
```

 * vbglDriverIOCtl
   * src/VBox/Additions/common/VBoxGuestLib/SysHlp.cpp
   
```c
int vbglDriverIOCtl (VBGLDRIVER *pDriver, uint32_t u32Function, void *pvData, uint32_t cbData)
{
    Log(("vbglDriverIOCtl: pDriver: %p, Func: %x, pvData: %p, cbData: %d\n", pDriver, u32Function, pvData, cbData));

# ifdef RT_OS_WINDOWS
    KEVENT Event;

    KeInitializeEvent (&Event, NotificationEvent, FALSE);

    /* Have to use the IoAllocateIRP method because this code is generic and
     * must work in any thread context.
     * The IoBuildDeviceIoControlRequest, which was used here, does not work
     * when APCs are disabled, for example.
     */
    PIRP irp = IoAllocateIrp (pDriver->pDeviceObject->StackSize, FALSE);

    Log(("vbglDriverIOCtl: irp %p, IRQL = %d\n", irp, KeGetCurrentIrql()));

    if (irp == NULL)
    {
        Log(("vbglDriverIOCtl: IRP allocation failed!\n"));
        return VERR_NO_MEMORY;
    }

    /*
     * Setup the IRP_MJ_DEVICE_CONTROL IRP.
     */

    PIO_STACK_LOCATION nextStack = IoGetNextIrpStackLocation (irp);

    nextStack->MajorFunction = IRP_MJ_DEVICE_CONTROL;
    nextStack->MinorFunction = 0;
    nextStack->DeviceObject = pDriver->pDeviceObject;
    nextStack->Parameters.DeviceIoControl.OutputBufferLength = cbData;
    nextStack->Parameters.DeviceIoControl.InputBufferLength = cbData;
    nextStack->Parameters.DeviceIoControl.IoControlCode = u32Function;
    nextStack->Parameters.DeviceIoControl.Type3InputBuffer = pvData;

    irp->AssociatedIrp.SystemBuffer = pvData; /* Output buffer. */
    irp->MdlAddress = NULL;

    /* A completion routine is required to signal the Event. */
    IoSetCompletionRoutine (irp, vbglDriverIOCtlCompletion, &Event, TRUE, TRUE, TRUE);

    NTSTATUS rc = IoCallDriver (pDriver->pDeviceObject, irp);

    if (NT_SUCCESS (rc))
    {
        /* Wait the event to be signalled by the completion routine. */
        KeWaitForSingleObject (&Event,
                               Executive,
                               KernelMode,
                               FALSE,
                               NULL);

        rc = irp->IoStatus.Status;

        Log(("vbglDriverIOCtl: wait completed IRQL = %d\n", KeGetCurrentIrql()));
    }

    IoFreeIrp (irp);

    if (rc != STATUS_SUCCESS)
        Log(("vbglDriverIOCtl: ntstatus=%x\n", rc));

    if (NT_SUCCESS(rc))
        return VINF_SUCCESS;
    if (rc == STATUS_INVALID_PARAMETER)
        return VERR_INVALID_PARAMETER;
    if (rc == STATUS_INVALID_BUFFER_SIZE)
        return VERR_OUT_OF_RANGE;
    return VERR_VBGL_IOCTL_FAILED;

# elif defined (RT_OS_OS2)
    if (    pDriver->u32Session
        &&  pDriver->u32Session == g_VBoxGuestIDC.u32Session)
        return g_VBoxGuestIDC.pfnServiceEP(pDriver->u32Session, u32Function, pvData, cbData, NULL);

    Log(("vbglDriverIOCtl: No connection\n"));
    return VERR_WRONG_ORDER;

# else
    // windows 以外はここ
    return VBoxGuestIDCCall(pDriver->pvOpaque, u32Function, pvData, cbData, NULL);
# endif
}
```

 * VBoxGuestIDCCall
   * src/VBox/Additions/common/VBoxGuest/VBoxGuestID-unix.c.h
     * VBoxGuest-linux.c が #include してる
   * ___IDC___ = ___Inter Driver Communication___
   
```c
/**
 * Perform an IDC call.
 *
 * @returns VBox error code.
 * @param   pvSession           Opaque pointer to the session.
 * @param   iCmd                Requested function.
 * @param   pvData              IO data buffer.
 * @param   cbData              Size of the data buffer.
 * @param   pcbDataReturned     Where to store the amount of returned data.
 */
DECLEXPORT(int) VBOXCALL VBoxGuestIDCCall(void *pvSession, unsigned iCmd, void *pvData, size_t cbData, size_t *pcbDataReturned)
{
    PVBOXGUESTSESSION pSession = (PVBOXGUESTSESSION)pvSession;
    LogFlow(("VBoxGuestIDCCall: %pvSession=%p Cmd=%u pvData=%p cbData=%d\n", pvSession, iCmd, pvData, cbData));
    AssertPtrReturn(pSession, VERR_INVALID_POINTER);
    AssertMsgReturn(pSession->pDevExt == &g_DevExt,
                    ("SC: %p != %p\n", pSession->pDevExt, &g_DevExt), VERR_INVALID_HANDLE);

    return VBoxGuestCommonIOCtl(iCmd, &g_DevExt, pSession, pvData, cbData, pcbDataReturned);
}
```

 * VBoxGuestCommonIOCtl
   * src/VBox/Additions/common/VBoxGuest/VBoxGuest.cpp
   * ioctl で ゲストOSからホストOS との通信をする関数
   * iFunction ででかい分岐が連なる

```c
/**
 * Common IOCtl for user to kernel and kernel to kernel communication.
 *
 * This function only does the basic validation and then invokes
 * worker functions that takes care of each specific function.
 *
 * @returns VBox status code.
 *
 * @param   iFunction           The requested function.
 * @param   pDevExt             The device extension.
 * @param   pSession            The client session.
 * @param   pvData              The input/output data buffer. Can be NULL depending on the function.
 * @param   cbData              The max size of the data buffer.
 * @param   pcbDataReturned     Where to store the amount of returned data. Can be NULL.
 */
int VBoxGuestCommonIOCtl(unsigned iFunction, PVBOXGUESTDEVEXT pDevExt, PVBOXGUESTSESSION pSession,
                         void *pvData, size_t cbData, size_t *pcbDataReturned)
{
```

 * この先が謎??? ioctl から ホストOS のプロセスの呼び出し???

### HostServices

ホストOS側のVirtualBoxVM プロセスで実行されるユーザランドのコード。 Not Kernel

 * src/VBox/HostServices/SharedFolders/vbsf.h に ホストOSが svcCall で呼び出すAPIが定義されている
 * ホストOSの VirtualBoxVMプロセスが呼び出すシステムコールの抽象化ラッパー
   * ホストOSのプラットフォームによって呼び出すべきシステムコールが違うので抽象化をかます必要がある

```c
// ...

int vbsfCreate (SHFLCLIENTDATA *pClient, SHFLROOT root, SHFLSTRING *pPath, uint32_t cbPath, SHFLCREATEPARMS *pParms);

int vbsfClose (SHFLCLIENTDATA *pClient, SHFLROOT root, SHFLHANDLE Handle);

int vbsfRead(SHFLCLIENTDATA *pClient, SHFLROOT root, SHFLHANDLE Handle, uint64_t offset, uint32_t *pcbBuffer, uint8_t *pBuffer);
int vbsfWrite(SHFLCLIENTDATA *pClient, SHFLROOT root, SHFLHANDLE Handle, uint64_t offset, uint32_t *pcbBuffer, uint8_t *pBuffer);
int vbsfLock(SHFLCLIENTDATA *pClient, SHFLROOT root, SHFLHANDLE Handle, uint64_t offset, uint64_t length, uint32_t flags);
int vbsfUnlock(SHFLCLIENTDATA *pClient, SHFLROOT root, SHFLHANDLE Handle, uint64_t offset, uint64_t length, uint32_t flags);
int vbsfRemove(SHFLCLIENTDATA *pClient, SHFLROOT root, SHFLSTRING *pPath, uint32_t cbPath, uint32_t flags);
int vbsfRename(SHFLCLIENTDATA *pClient, SHFLROOT root, SHFLSTRING *pSrc, SHFLSTRING *pDest, uint32_t flags);
int vbsfDirList(SHFLCLIENTDATA *pClient, SHFLROOT root, SHFLHANDLE Handle, SHFLSTRING *pPath, uint32_t flags, uint32_t *pcbBuffer, uint8_t *pBuffer, uint32_t *pIndex, uint32_t *pcFiles);
int vbsfFileInfo(SHFLCLIENTDATA *pClient, SHFLROOT root, SHFLHANDLE Handle, uint32_t flags, uint32_t *pcbBuffer, uint8_t *pBuffer);
int vbsfQueryFSInfo(SHFLCLIENTDATA *pClient, SHFLROOT root, SHFLHANDLE Handle, uint32_t flags, uint32_t *pcbBuffer, uint8_t *pBuffer);
int vbsfSetFSInfo(SHFLCLIENTDATA *pClient, SHFLROOT root, SHFLHANDLE Handle, uint32_t flags, uint32_t *pcbBuffer, uint8_t *pBuffer);
int vbsfFlush(SHFLCLIENTDATA *pClient, SHFLROOT root, SHFLHANDLE Handle);
int vbsfDisconnect(SHFLCLIENTDATA *pClient);
int vbsfQueryFileInfo(SHFLCLIENTDATA *pClient, SHFLROOT root, SHFLHANDLE Handle, uint32_t flags, uint32_t *pcbBuffer, uint8_t *pBuffer);
int vbsfReadLink(SHFLCLIENTDATA *pClient, SHFLROOT root, SHFLSTRING *pPath, uint32_t cbPath, uint8_t *pBuffer, uint32_t cbBuffer);
int vbsfSymlink(SHFLCLIENTDATA *pClient, SHFLROOT root, SHFLSTRING *pNewPath, SHFLSTRING *pOldPath, SHFLFSOBJINFO *pInfo);

#endif /* __VBSF__H */
```

### vbsfCreate

ホストOSがUNIX系OSなら、最終的に open(2) を呼び出すはず

 * vbfsOpenFile か vbsfOpenDir に続く
   * vbsfOpenFile から RTFileOpen を呼び出す
     * ___RT___ = RunTime ?
  
```c
// include/iprt/mangling.h
# define RTFileOpen                                     RT_MANGLER(RTFileOpen)

// include/VBox/VBoxGuestMangling.h
#define RT_MANGLER(symbol)   VBoxGuest_##symbol

// include/VBox/SUPDrvMangling.h
#define RT_MANGLER(symbol)   VBoxHost_##symbol

// 最終的に VBoxGuest_RTFileOpen, VBoxHOST_RTFileOpen のシンボルに変換される?
```

 * src/VBox/Runtime 以下にプラットフォームごとのディレクトリが見つかる
   * src/VBox/Runtime/r3/posix/fileio-posix.cpp に POSIX な RTFileOpen実装がある
   * (ホストOSのプロセスとして) open(2) を呼び出している

```c
RTR3DECL(int) RTFileOpen(PRTFILE pFile, const char *pszFilename, uint64_t fOpen)
{
    // ....

    /*
     * Open/create the file.
     */
    char const *pszNativeFilename;
    rc = rtPathToNative(&pszNativeFilename, pszFilename, NULL);
    if (RT_FAILURE(rc))
        return (rc);

    int fh = open(pszNativeFilename, fOpenMode, fMode);
    int iErr = errno;
```    

ということで RT_MANGLER を見つけたら src/VBox/Runtime/ 以下の実装を追えばおk

#### IPRT って何?

```
IPRT, a portable runtime library which abstracts file access, threading, string manipulation, etc. 
Whenever VirtualBox accesses host operating features, it does so through this library for cross-platform portability.

http://www.virtualbox.org/manual/ch10.html
```
