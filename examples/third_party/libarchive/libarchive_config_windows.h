/* config.h for Windows native cc_library examples. */
#define __LIBARCHIVE_CONFIG_H_INCLUDED 1

#define HAVE_INT16_T 1
#define HAVE_INT32_T 1
#define HAVE_INT64_T 1
#define HAVE_INTMAX_T 1
#define HAVE_UINT8_T 1
#define HAVE_UINT16_T 1
#define HAVE_UINT32_T 1
#define HAVE_UINT64_T 1
#define HAVE_UINTMAX_T 1

#define SIZEOF_SHORT 2
#define SIZEOF_INT 4
#define SIZEOF_LONG 4
#define SIZEOF_LONG_LONG 8
#define SIZEOF_UNSIGNED_SHORT 2
#define SIZEOF_UNSIGNED 4
#define SIZEOF_UNSIGNED_LONG 4
#define SIZEOF_UNSIGNED_LONG_LONG 8

#define HAVE_BCRYPT_H 1
#define HAVE_CTYPE_H 1
#define HAVE_DIRECT_H 1
#define HAVE_ERRNO_H 1
#define HAVE_FCNTL_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_IO_H 1
#define HAVE_LIMITS_H 1
#define HAVE_PROCESS_H 1
#define HAVE_STDARG_H 1
#define HAVE_STDINT_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_TIME_H 1
#define HAVE_WCHAR_H 1
#define HAVE_WINCRYPT_H 1
#define HAVE_WINDOWS_H 1
#define HAVE_ZLIB_H 1

#define HAVE_BCRYPT 1
#define HAVE_LIBZ 1

#define HAVE_CHMOD 1
#define HAVE_DECL_EXTATTR_NAMESPACE_USER 0
#define HAVE_DECL_INT64_MAX 1
#define HAVE_DECL_INT64_MIN 1
#define HAVE_DECL_SIZE_MAX 1
#define HAVE_DECL_SSIZE_MAX 0
#define HAVE_DECL_STRERROR_R 0
#define HAVE_DECL_UINT32_MAX 1
#define HAVE_DECL_UINT64_MAX 1
#define HAVE_DECL_UINTMAX_MAX 1
#define HAVE_DECL_XATTR_NOFOLLOW 0
#define HAVE_FSTAT 1
#define HAVE_FTRUNCATE 1
#define HAVE_GETPID 1
#define HAVE_LOCALTIME_S 1
#define HAVE_LSTAT 1
#define HAVE_MEMMOVE 1
#define HAVE_MEMSET 1
#define HAVE_MKDIR 1
#define HAVE_READ 1
#define HAVE_SELECT 1
#define HAVE_STAT 1
#define HAVE_STRCHR 1
#define HAVE_STRDUP 1
#define HAVE_STRERROR 1
#define HAVE_STRRCHR 1
#define HAVE_TIME 1
#define HAVE_UMASK 1
#define HAVE_WCSCPY 1
#define HAVE_WCSLEN 1
#define HAVE_WMEMCMP 1
#define HAVE_WMEMCPY 1
#define HAVE_WRITE 1
#define HAVE__GET_TIMEZONE 1

#define HAVE_STRUCT_STAT_ST_MTIME 1
#define HAVE_STRUCT_STAT_ST_SIZE 1

#define ICONV_CONST

#ifndef _SSIZE_T_DEFINED
typedef __int64 ssize_t;
#define _SSIZE_T_DEFINED
#endif

#ifndef _PID_T_
typedef int pid_t;
#define _PID_T_
#endif

#ifndef _MODE_T_DEFINED
typedef int mode_t;
#define _MODE_T_DEFINED
#endif

#ifndef _UID_T_DEFINED
typedef int uid_t;
#define _UID_T_DEFINED
#endif

#ifndef _GID_T_DEFINED
typedef int gid_t;
#define _GID_T_DEFINED
#endif

#ifndef _ID_T_DEFINED
typedef int id_t;
#define _ID_T_DEFINED
#endif

#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0601
#endif

#ifndef _WIN32
#error libarchive_config_windows.h is only intended for Windows builds.
#endif
