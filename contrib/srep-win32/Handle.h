// Handle.h -- stub. Faltaba en el checkout de Intensity/srep (el arbol FreeArc grande
// original si lo traia, pero al recortar solo lo necesario para el build Unix se
// quedo afuera). Se incluye desde Synchronization.h bajo #ifdef _WIN32 pero ninguna
// clase de ese archivo (CBaseEvent/ManualEvent/Event/Semaphore/Mutex/Lock) usa un tipo
// "Handle" -- todas usan directamente ::CEvent/::CSemaphore/::CCriticalSection (los
// tipos de bajo nivel de Threads.h/ThreadsWin32.h). Stub vacio, sin riesgo.
#ifndef __WINDOWS_HANDLE_H
#define __WINDOWS_HANDLE_H
#endif
