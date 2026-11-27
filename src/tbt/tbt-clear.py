#!/usr/bin/env python3
"""jmk-autoplay-hud 0.1.19 (AGPL-3.0, as this package): turn-by-turn clear on the projection session's end, and the
com.jmk.hud.TBT_CLEAR receiver (com/jmk/hud/TbtClear.java), in a baksmali tree of the patched HKMC_GPM or HKMC_DiPO.

    src/tbt/tbt-clear.py <smali tree>        (GPM: the tree with GpmNaviTBTManager; DiPO: the tree with e/u.smali)

GPM (Android Auto; the stock end of a session: GalConnectionManager -> GalConnectionSession.finalizeGal ->
clearSession -> GpmNaviTBTManager.stop(), destroy()):
  - destroy() first calls jmkEnd(): when this manager drew on the cluster (mClaimed, set by claimCluster at the first
    TBT send of a guidance, cleared by onStatus), it runs onStatus(0), the path an inactive navigation status takes:
    releaseGuidance (destination "", TBT_INFO DisplayType 8, sub info cleared, HUD extras and turn list blank) and the
    manager's guidance state reset. stop() alone is not hooked: GalConnectionSession$6 / sessionSendStopGpmNaviTBTManager
    call it when the navigation focus goes to the native navigation, which then draws.
  - claimCluster keeps the drawing manager in jmkLive (cleared in its destroy); jmkClear(Context), for TbtClear, runs
    releaseGuidance on it (the manager state stays, so guidance still running draws again with its next update).
  - GalReceiverService.onCreate registers TbtClear (owner GpmNaviTBTManager).
DiPO (CarPlay; the stock end of a session: ICarPlayServiceListener e/m.onSessionFinalized(transport) -> e/u.disconnected()
= the route state cleared (nT) and the HUD turn list blank, but no TBT_INFO, so the cluster kept the last turn):
  - e/m.onSessionFinalized calls e/u.jmkEnd() after disconnected(): when the last TBT_INFO this analyzer sent was not
    DisplayType 8 (jmkShown, set by jmkMark(I) in front of the one updateTBTInfo send of the route guidance update), it
    sends TbtClear.release (GPM's releaseGuidance cluster calls) and sendHudBlank, under the analyzer's lock.
    Not hooked: e/a.disconnected(I) (the iAP2 listener), which also runs u.disconnected() when the iAP2 session moves
    from Bluetooth (component 4) to the CarPlay channel (component 5) in a wireless session; the CarPlay session
    goes on there.
  - jmkClear(Context), for TbtClear: the same release on u.sNavi (the route state stays).
  - DipoService.onCreate registers TbtClear (owner e/u).
Every anchor must be found exactly once; otherwise nothing is written and the exit status is 1 (the profile keeps its
0.1.18 build). TbtClear.smali itself is added by the caller (src/tbt/build.sh, src/tbt/clear.sh).
"""
import os
import re
import sys

root = sys.argv[1]
if os.path.isfile(os.path.join(root, 'com/google/android/projection/sink/navigation/GpmNaviTBTManager.smali')):
    kind = 'gpm'
elif os.path.isfile(os.path.join(root, 'com/daudio/app/dipo/e/u.smali')):
    kind = 'dipo'
else:
    sys.exit('tbt-clear: neither a GPM nor a DiPO tree: ' + root)
out = {}


def text(rel):
    if rel not in out:
        out[rel] = open(os.path.join(root, rel)).read()
    return out[rel]


def edit(rel, pairs):
    s = text(rel)
    for old, new, n in pairs:
        c = s.count(old)
        if c != n:
            sys.exit('tbt-clear: %s: anchor found %d times (want %d): %r' % (rel, c, n, old[:120]))
        s = s.replace(old, new)
    out[rel] = s


def append(rel, more):
    s = text(rel)
    if not s.endswith('.end method\n'):
        sys.exit('tbt-clear: %s does not end with a method' % rel)
    if ' jmkEnd()V' in s or ' jmkClear(' in s:
        sys.exit('tbt-clear: %s already has the 0.1.19 methods' % rel)
    out[rel] = s + more


if kind == 'gpm':
    G = 'Lcom/google/android/projection/sink/navigation/GpmNaviTBTManager;'
    F = 'com/google/android/projection/sink/navigation/GpmNaviTBTManager.smali'
    edit(F, [
        ('.field private mClaimed:I\n',
         '.field private mClaimed:I\n\n.field private static jmkLive:%s\n' % G, 1),
        # claimCluster: the manager that draws on the cluster is the one a manual clear releases
        ('    const/4 v0, 0x1\n\n    iput v0, p0, %s->mClaimed:I\n\n    iget-object v0, p0, %s->mClusterService' % (G, G),
         '    const/4 v0, 0x1\n\n    iput v0, p0, %s->mClaimed:I\n\n    sput-object p0, %s->jmkLive:%s\n\n    iget-object v0, p0, %s->mClusterService' % (G, G, G, G), 1),
        # destroy (GalConnectionSession.clearSession, from finalizeGal: the projection session's end)
        ('.method public destroy()V\n    .registers 3\n\n',
         '.method public destroy()V\n    .registers 3\n\n    invoke-direct {p0}, %s->jmkEnd()V\n\n' % G, 1),
    ])
    append(F, '''
.method private jmkEnd()V
    .registers 3

    :try_start_jmk
    sget-object v0, {G}->jmkLive:{G}

    if-ne v0, p0, :cond_jmk_live

    const/4 v0, 0x0

    sput-object v0, {G}->jmkLive:{G}

    :cond_jmk_live
    iget v0, p0, {G}->mClaimed:I

    if-eqz v0, :cond_jmk_end

    const-string v0, "JMKHUD"

    const-string v1, "GPM: projection session ended with turn-by-turn on the cluster, releasing it"

    invoke-static {v0, v1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    const/4 v0, 0x0

    invoke-virtual {p0, v0}, {G}->onStatus(I)V
    :try_end_jmk
    .catch Ljava/lang/Throwable; {:try_start_jmk .. :try_end_jmk} :catch_jmk

    :cond_jmk_end
    return-void

    :catch_jmk
    move-exception v0

    return-void
.end method

.method public static jmkClear(Landroid/content/Context;)Z
    .registers 3

    sget-object v0, {G}->jmkLive:{G}

    if-eqz v0, :cond_jmk_none

    iget-object v1, v0, {G}->mClusterService:Lcom/hkmc/cluster/NavigationCluster;

    if-eqz v1, :cond_jmk_none

    invoke-direct {v0}, {G}->releaseGuidance()V

    const/4 v0, 0x1

    return v0

    :cond_jmk_none
    const/4 v0, 0x0

    return v0
.end method
'''.replace('{G}', G))
    edit('com/google/android/projection/service/GalReceiverService.smali', [
        ('    invoke-super {p0}, Lcom/hkmc/app/HKMCService;->onCreate()V\n',
         '    invoke-super {p0}, Lcom/hkmc/app/HKMCService;->onCreate()V\n\n'
         '    const-class v0, %s\n\n'
         '    invoke-static {p0, v0}, Lcom/jmk/hud/TbtClear;->register(Landroid/content/Context;Ljava/lang/Class;)V\n' % G, 1),
    ])
elif kind == 'dipo':
    U = 'Lcom/daudio/app/dipo/e/u;'
    F = 'com/daudio/app/dipo/e/u.smali'
    edit(F, [
        ('.field private mHudType:I\n',
         '.field private mHudType:I\n\n.field private jmkShown:Z\n', 1),
    ])
    # the one TBT_INFO send of the route guidance update (DisplayType 8 = nothing to show, since 0.1.5)
    s = text(F)
    m = re.findall(r'    const/16 v1, 0x8\n\n    (:cond_\w+)\n    invoke-virtual/range \{v0 \.\. v9\}, Lcom/hkmc/cluster/NavigationCluster;->updateTBTInfo\(IIFFIIIII\)V\n', s)
    if len(m) != 1:
        sys.exit('tbt-clear: %s: the route guidance TBT_INFO send found %d times' % (F, len(m)))
    lab = m[0]
    old = '    const/16 v1, 0x8\n\n    %s\n    invoke-virtual/range {v0 .. v9}, Lcom/hkmc/cluster/NavigationCluster;->updateTBTInfo(IIFFIIIII)V\n' % lab
    new = '    const/16 v1, 0x8\n\n    %s\n    invoke-direct {p0, v1}, %s->jmkMark(I)V\n\n    invoke-virtual/range {v0 .. v9}, Lcom/hkmc/cluster/NavigationCluster;->updateTBTInfo(IIFFIIIII)V\n' % (lab, U)
    edit(F, [(old, new, 1)])
    append(F, '''
.method public static jmkClear(Landroid/content/Context;)Z
    .registers 3

    sget-object v0, {U}->sNavi:{U}

    if-nez v0, :cond_jmk_has

    const/4 v0, 0x0

    return v0

    :cond_jmk_has
    monitor-enter v0

    :try_start_jmk
    invoke-direct {v0}, {U}->jmkRelease()V
    :try_end_jmk
    .catchall {:try_start_jmk .. :try_end_jmk} :catchall_jmk

    :goto_jmk
    monitor-exit v0

    const/4 v1, 0x1

    return v1

    :catchall_jmk
    move-exception v1

    goto :goto_jmk
.end method

.method private jmkMark(I)V
    .registers 3

    const/16 v0, 0x8

    if-eq p1, v0, :cond_jmk_off

    const/4 v0, 0x1

    goto :goto_jmk_set

    :cond_jmk_off
    const/4 v0, 0x0

    :goto_jmk_set
    iput-boolean v0, p0, {U}->jmkShown:Z

    return-void
.end method

.method private jmkRelease()V
    .registers 2

    const/4 v0, 0x0

    iput-boolean v0, p0, {U}->jmkShown:Z

    iget-object v0, p0, {U}->Ak:Lcom/hkmc/cluster/NavigationCluster;

    if-eqz v0, :cond_jmk_blank

    invoke-static {v0}, Lcom/jmk/hud/TbtClear;->release(Lcom/hkmc/cluster/NavigationCluster;)V

    :cond_jmk_blank
    invoke-direct {p0}, {U}->sendHudBlank()V

    return-void
.end method

.method public final jmkEnd()V
    .registers 3

    monitor-enter p0

    :try_start_jmk
    iget-boolean v0, p0, {U}->jmkShown:Z

    if-eqz v0, :cond_jmk_done

    const-string v0, "JMKHUD"

    const-string v1, "DiPO: CarPlay session finalized with turn-by-turn on the cluster, releasing it"

    invoke-static {v0, v1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    invoke-direct {p0}, {U}->jmkRelease()V
    :try_end_jmk
    .catchall {:try_start_jmk .. :try_end_jmk} :catchall_jmk

    :cond_jmk_done
    :goto_jmk
    monitor-exit p0

    return-void

    :catchall_jmk
    move-exception v0

    goto :goto_jmk
.end method
'''.replace('{U}', U))
    edit('com/daudio/app/dipo/e/m.smali', [
        ('    invoke-virtual {v0}, Lcom/daudio/app/dipo/e/u;->disconnected()V\n\n    :cond_7b\n',
         '    invoke-virtual {v0}, Lcom/daudio/app/dipo/e/u;->disconnected()V\n\n'
         '    invoke-virtual {v0}, Lcom/daudio/app/dipo/e/u;->jmkEnd()V\n\n    :cond_7b\n', 1),
    ])
    edit('com/daudio/app/dipo/service/DipoService.smali', [
        ('    invoke-super {p0}, Lcom/hkmc/app/HKMCService;->onCreate()V\n',
         '    invoke-super {p0}, Lcom/hkmc/app/HKMCService;->onCreate()V\n\n'
         '    const-class v0, %s\n\n'
         '    invoke-static {p0, v0}, Lcom/jmk/hud/TbtClear;->register(Landroid/content/Context;Ljava/lang/Class;)V\n' % U, 1),
    ])
for rel, s in out.items():
    open(os.path.join(root, rel), 'w').write(s)
print('tbt-clear: %s tree, %d files' % (kind, len(out)))
