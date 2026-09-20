#!/usr/bin/env python3
"""构建修复,不是功能补丁。

CrossOver Preview 20260821 的 dlls/winemac.drv/cocoa_app.m 用 @[] 字面量直接初始化
一个 static 变量,而 Objective-C 的容器字面量不是编译期常量:

    static NSArray<NSString *> *whitelistedAUMIDs = @[ ... ];
    error: initializer element is not a compile-time constant

CrossOver 26.3 在同一处用的是 dispatch_once,是正确的。这里退回那个写法。
与本项目的补丁无关 —— 是 preview 自身的回归,即使不打任何补丁也编不过。
"""
import sys, pathlib
p = pathlib.Path(sys.argv[1]) / "dlls/winemac.drv/cocoa_app.m"
s = p.read_text()
old = """        static NSArray<NSString *> *whitelistedAUMIDs = @[
            @"Valve.Steam.Client",                 /* CW Hack 22310 */
            @"RockstarGames.SocialClub.UI.Final",  /* CW Hack 23655 */
        ];
"""
new = """        static NSArray<NSString *> *whitelistedAUMIDs;
        static dispatch_once_t whitelistOnce;
        dispatch_once(&whitelistOnce, ^{
            whitelistedAUMIDs = [@[
                @"Valve.Steam.Client",                 /* CW Hack 22310 */
                @"RockstarGames.SocialClub.UI.Final",  /* CW Hack 23655 */
            ] retain];
        });
"""
if "whitelistOnce" in s:
    print("  已修复,跳过"); sys.exit(0)
assert s.count(old) == 1, f"锚点出现 {s.count(old)} 次"
p.write_text(s.replace(old, new, 1))
print("  已修复 cocoa_app.m 的 static 初始化")
