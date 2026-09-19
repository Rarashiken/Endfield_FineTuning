#!/usr/bin/env bash
# 为 ntoskrnl.exe 实现 PsGetProcessExitStatus
#
# 背景:ACE 反作弊会调用它,Wine 未实现 -> 每次运行都有一个 ACE 后台线程 abort:
#   wine: Call from ... to unimplemented function ntoskrnl.exe.PsGetProcessExitStatus, aborting
# 上游 patches/README.md 记录了这个残留但未修("A stub would silence it")。
#
# 实现方式不是空壳:struct _EPROCESS 里已缓存 PROCESS_BASIC_INFORMATION,
# 其首字段就是 ExitStatus,直接返回即可(运行中的进程为 STILL_ACTIVE)。
#
# 用法: apply-psgetprocessexitstatus.sh <wine源码根目录>
set -euo pipefail
W="${1:?用法: $0 <wine-src>}"
C="$W/dlls/ntoskrnl.exe/ntoskrnl.c"
S="$W/dlls/ntoskrnl.exe/ntoskrnl.exe.spec"
[ -f "$C" ] && [ -f "$S" ] || { echo "ERROR: 不是 wine 源码树: $W"; exit 1; }

if grep -q "PsGetProcessExitStatus" "$C"; then
  echo "  已应用过,跳过"; exit 0
fi

# 1) 在 PsGetProcessSessionId 之后插入实现
python3 - "$C" <<'PY'
import sys,re
p=sys.argv[1]; s=open(p,encoding='utf-8',errors='surrogateescape').read()
anchor = re.search(r'(/\*+\n \*           PsGetProcessSessionId.*?\n\}\n)', s, re.S)
if not anchor:
    anchor = re.search(r'(ULONG WINAPI PsGetProcessSessionId\( PEPROCESS process \)\n\{.*?\n\}\n)', s, re.S)
assert anchor, "找不到插入锚点 PsGetProcessSessionId"
impl = '''
/*********************************************************************
 *           PsGetProcessExitStatus    (NTOSKRNL.@)
 *
 * Endfield_FineWine: ACE anti-cheat calls this; Wine left it a stub, which
 * aborts the calling (ACE background) thread on every run.  _EPROCESS already
 * caches PROCESS_BASIC_INFORMATION, whose ExitStatus field is exactly what
 * this returns (STILL_ACTIVE for a live process).
 */
NTSTATUS WINAPI PsGetProcessExitStatus( PEPROCESS process )
{
    TRACE("%p -> %#lx\\n", process, (ULONG)process->info.ExitStatus);
    return process->info.ExitStatus;
}
'''
s = s[:anchor.end(1)] + impl + s[anchor.end(1):]
open(p,'w',encoding='utf-8',errors='surrogateescape').write(s)
print("  ntoskrnl.c: 已插入实现")
PY

# 2) .spec:stub -> stdcall
python3 - "$S" <<'PY'
import sys
p=sys.argv[1]; L=open(p,encoding='utf-8',errors='surrogateescape').read().split('\n')
hit=False
for i,l in enumerate(L):
    if l.strip()=='@ stub PsGetProcessExitStatus':
        L[i]='@ stdcall PsGetProcessExitStatus(ptr)'; hit=True; break
assert hit, "找不到 '@ stub PsGetProcessExitStatus'"
open(p,'w',encoding='utf-8',errors='surrogateescape').write('\n'.join(L))
print("  ntoskrnl.exe.spec: stub -> stdcall")
PY
echo "  ✓ PsGetProcessExitStatus 已实现"
