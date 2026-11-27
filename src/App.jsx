import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { RefreshCw, ServerCrash } from 'lucide-react';
import { Sidebar } from '@/components/Sidebar.jsx';
import { AddProjectsModal, CommandPalette, SettingsModal, Toasts } from '@/components/Dialogs.jsx';
import { Spinner } from '@/components/Fizz.jsx';
import { api } from '@/lib/api.js';
import { Cleanup } from '@/views/Cleanup.jsx';
import { Library } from '@/views/Library.jsx';
import { ProjectDetail } from '@/views/ProjectDetail.jsx';
import { Workbench } from '@/views/Workbench.jsx';

const VIEW_KEY = 'fizzdeck.view';
const APPEARANCE_KEY = 'fizzdeck.appearance';
const SIDEBAR_KEY = 'fizzdeck.sidebar.collapsed';

const VIEWS = new Set(['workbench', 'library', 'cleanup']);
const APPEARANCE_VALUES = new Set(['system', 'light', 'dark']);

function initialView() {
  const saved = localStorage.getItem(VIEW_KEY);
  return VIEWS.has(saved) ? saved : 'workbench';
}

function initialAppearance() {
  const saved = localStorage.getItem(APPEARANCE_KEY);
  return APPEARANCE_VALUES.has(saved) ? saved : 'system';
}

export function App() {
  const [state, setState] = useState(null);
  const [orphans, setOrphans] = useState(null);
  const [view, setView] = useState(initialView);
  const [selectedPath, setSelectedPath] = useState(null);
  const [requestedTab, setRequestedTab] = useState(null);
  const [libraryQuery, setLibraryQuery] = useState({});
  const [collapsed, setCollapsed] = useState(() => localStorage.getItem(SIDEBAR_KEY) === '1');
  const [appearance, setAppearance] = useState(initialAppearance);
  const [paletteOpen, setPaletteOpen] = useState(false);
  const [addOpen, setAddOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [toasts, setToasts] = useState([]);
  const [busy, setBusy] = useState({});
  const [testRuns, setTestRuns] = useState({});
  const [sessionsVersion, setSessionsVersion] = useState(0);
  const [loadFailed, setLoadFailed] = useState(false);
  const [scanning, setScanning] = useState(false);
  const toastId = useRef(0);
  const connectionFailed = useRef(false);

  const toast = useCallback((text, bad = false) => {
    if (!text) return;
    const id = toastId.current + 1;
    toastId.current = id;
    setToasts((current) => [...current, { id, text, bad }]);
    window.setTimeout(() => {
      setToasts((current) => current.filter((item) => item.id !== id));
    }, 3200);
  }, []);

  const copy = useCallback(async (text) => {
    try {
      await navigator.clipboard.writeText(String(text ?? ''));
      toast('已复制');
    } catch {
      toast('复制失败', true);
    }
  }, [toast]);

  const load = useCallback(async () => {
    try {
      const snapshot = await api.state();
      setState(snapshot);
      setLoadFailed(false);
      connectionFailed.current = false;
      return snapshot;
    } catch (error) {
      setLoadFailed(true);
      if (!connectionFailed.current) {
        toast(error.message || '本地服务未连接', true);
        connectionFailed.current = true;
      }
      return null;
    }
  }, [toast]);

  const loadOrphans = useCallback(async () => {
    try {
      setOrphans(await api.orphans());
    } catch {
      // Session-history metrics are optional; the dashboard remains usable without them.
    }
  }, []);

  useEffect(() => {
    load();
    loadOrphans();
    const timer = window.setInterval(() => {
      if (!document.hidden) load();
    }, 20000);
    const onVisibility = () => {
      if (!document.hidden) load();
    };
    document.addEventListener('visibilitychange', onVisibility);
    return () => {
      window.clearInterval(timer);
      document.removeEventListener('visibilitychange', onVisibility);
    };
  }, [load, loadOrphans]);

  useEffect(() => {
    const media = window.matchMedia('(prefers-color-scheme: dark)');
    const apply = () => {
      const dark = appearance === 'dark' || (appearance === 'system' && media.matches);
      document.documentElement.classList.toggle('dark', dark);
    };
    apply();
    media.addEventListener?.('change', apply);
    localStorage.setItem(APPEARANCE_KEY, appearance);
    return () => media.removeEventListener?.('change', apply);
  }, [appearance]);

  useEffect(() => {
    localStorage.setItem(SIDEBAR_KEY, collapsed ? '1' : '0');
  }, [collapsed]);

  const projects = useMemo(() => (state?.projects || []).map((project) => ({
    ...project,
    portState: state?.portStatus?.[project.path] || 'no-preview',
  })), [state]);

  const selectedProject = projects.find((project) => project.path === selectedPath) || null;

  useEffect(() => {
    if (selectedPath && state && !projects.some((project) => project.path === selectedPath)) {
      setSelectedPath(null);
      setRequestedTab(null);
    }
  }, [projects, selectedPath, state]);

  const rescan = useCallback(async (quiet = false) => {
    setScanning(true);
    try {
      const snapshot = await api.rescan();
      setState(snapshot);
      setLoadFailed(false);
      connectionFailed.current = false;
      if (!quiet) toast(`扫描完成 ${snapshot.scan?.durationMs ?? 0}ms`);
      loadOrphans();
      return snapshot;
    } catch (error) {
      toast(error.message, true);
      return null;
    } finally {
      setScanning(false);
    }
  }, [loadOrphans, toast]);

  const navigate = useCallback((next) => {
    setView(next);
    localStorage.setItem(VIEW_KEY, next);
    setSelectedPath(null);
    setRequestedTab(null);
    setPaletteOpen(false);
  }, []);

  const openProject = useCallback((path, tab = null) => {
    setSelectedPath(path);
    setRequestedTab(tab);
    setPaletteOpen(false);
  }, []);

  const openLibrary = useCallback((query = {}) => {
    setLibraryQuery({ ...query });
    navigate('library');
  }, [navigate]);

  const openAdd = useCallback(() => {
    setPaletteOpen(false);
    setAddOpen(true);
  }, []);

  const openSettings = useCallback(() => {
    setPaletteOpen(false);
    setSettingsOpen(true);
  }, []);

  const launch = useCallback(async (project) => {
    if (busy[project.path] === 'launch') return;
    setBusy((current) => ({ ...current, [project.path]: 'launch' }));
    try {
      const result = await api.action(project.path, 'launch');
      toast(result.message);
      const deadline = Date.now() + 60000;
      const tick = async () => {
        const snapshot = await api.state().catch(() => null);
        if (snapshot) {
          setState((current) => (current
            ? { ...current, portStatus: snapshot.portStatus, disk: snapshot.disk || current.disk }
            : snapshot));
          if (snapshot.portStatus?.[project.path] === 'running') {
            setBusy((current) => ({ ...current, [project.path]: null }));
            const run = snapshot.projects.find((item) => item.path === project.path)?.run || project.run;
            toast(`${project.displayName} 已就绪${run?.port ? ` · localhost:${run.port}` : ''}`);
            return;
          }
        }
        if (Date.now() > deadline) {
          setBusy((current) => ({ ...current, [project.path]: null }));
          toast(`${project.displayName} 60 秒内未就绪，查看 dev 日志`, true);
          return;
        }
        window.setTimeout(tick, 1500);
      };
      window.setTimeout(tick, 1200);
    } catch (error) {
      setBusy((current) => ({ ...current, [project.path]: null }));
      toast(error.message, true);
    }
  }, [busy, toast]);

  const stop = useCallback(async (project) => {
    if (busy[project.path] === 'stop') return;
    setBusy((current) => ({ ...current, [project.path]: 'stop' }));
    try {
      const result = await api.action(project.path, 'stop');
      toast(result.message);
      window.setTimeout(load, 700);
    } catch (error) {
      toast(error.message, true);
    } finally {
      setBusy((current) => ({ ...current, [project.path]: null }));
    }
  }, [busy, load, toast]);

  const star = useCallback(async (project) => {
    const next = !project.starred;
    setState((current) => (current ? {
      ...current,
      projects: current.projects.map((item) => (
        item.path === project.path ? { ...item, starred: next } : item
      )),
    } : current));
    try {
      await api.star(project.path, next);
    } catch (error) {
      setState((current) => (current ? {
        ...current,
        projects: current.projects.map((item) => (
          item.path === project.path ? { ...item, starred: !next } : item
        )),
      } : current));
      toast(error.message, true);
    }
  }, [toast]);

  const meta = useCallback(async (project, patch) => {
    setState((current) => (current ? {
      ...current,
      projects: current.projects.map((item) => (
        item.path === project.path ? { ...item, ...patch } : item
      )),
    } : current));
    try {
      await api.meta(project.path, patch);
    } catch (error) {
      toast(error.message, true);
      load();
    }
  }, [load, toast]);

  const reveal = useCallback(async (project) => {
    try {
      const result = await api.action(project.path, 'reveal');
      toast(result.message);
    } catch (error) {
      toast(error.message, true);
    }
  }, [toast]);

  const remove = useCallback(async (project, mode, confirmName) => {
    try {
      const result = await api.remove(project.path, mode, confirmName);
      toast(result.message);
      setSelectedPath(null);
      setRequestedTab(null);
      await rescan(true);
    } catch (error) {
      toast(error.message, true);
    }
  }, [rescan, toast]);

  const pollTest = useCallback((project) => {
    const tick = async () => {
      try {
        const result = await api.testRun(project.path);
        setTestRuns((current) => ({ ...current, [project.path]: result }));
        if (result.status === 'running') {
          window.setTimeout(tick, 1500);
        } else if (result.status === 'passed') {
          toast(`${project.displayName} 测试通过`);
        } else if (result.status === 'failed') {
          toast(`${project.displayName} 测试失败`, true);
        }
      } catch (error) {
        toast(error.message, true);
      }
    };
    window.setTimeout(tick, 900);
  }, [toast]);

  const test = useCallback(async (project) => {
    if (testRuns[project.path]?.status === 'running') return;
    setTestRuns((current) => ({
      ...current,
      [project.path]: { status: 'running', output: '启动中…', command: project.test?.command },
    }));
    try {
      const result = await api.test(project.path);
      toast(`开始 ${result.run.command}`);
      setTestRuns((current) => ({
        ...current,
        [project.path]: { ...result.run, output: '测试运行中…' },
      }));
      pollTest(project);
    } catch (error) {
      setTestRuns((current) => ({ ...current, [project.path]: { status: 'idle' } }));
      toast(error.message, true);
    }
  }, [pollTest, testRuns, toast]);

  useEffect(() => {
    if (!selectedPath || !selectedProject?.test || testRuns[selectedPath]) return undefined;
    let cancelled = false;
    api.testRun(selectedPath).then((result) => {
      if (!cancelled) setTestRuns((current) => ({ ...current, [selectedPath]: result }));
    }).catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [selectedPath, selectedProject, testRuns]);

  const resumeSession = useCallback(async (project, session) => {
    try {
      const result = await api.sessionAction(project.path, 'resume', session.id);
      toast(result.message);
      setSessionsVersion((value) => value + 1);
      load();
    } catch (error) {
      const fallback = error.payload?.fallbackCommand;
      if (fallback) {
        navigator.clipboard.writeText(fallback).catch(() => {});
        toast(`${error.message}，已复制恢复命令`, true);
      } else {
        toast(error.message, true);
      }
    }
  }, [load, toast]);

  const endSession = useCallback(async (project, session) => {
    try {
      const result = await api.sessionAction(project.path, 'end', session.id);
      toast(result.message);
      setSessionsVersion((value) => value + 1);
      load();
    } catch (error) {
      toast(error.message, true);
    }
  }, [load, toast]);

  const batchStar = useCallback(async (paths) => {
    const results = await Promise.allSettled(paths.map((path) => api.star(path, true)));
    const succeeded = new Set(paths.filter((path, index) => results[index].status === 'fulfilled'));
    if (succeeded.size) {
      setState((current) => (current ? {
        ...current,
        projects: current.projects.map((project) => (
          succeeded.has(project.path) ? { ...project, starred: true } : project
        )),
      } : current));
    }
    if (succeeded.size === paths.length) toast(`已星标 ${paths.length} 个项目`);
    else toast(`已星标 ${succeeded.size} / ${paths.length} 个项目`, true);
  }, [toast]);

  const batchGroup = useCallback(async (paths, group) => {
    const results = await Promise.allSettled(paths.map((path) => api.meta(path, { group })));
    const succeeded = new Set(paths.filter((path, index) => results[index].status === 'fulfilled'));
    if (succeeded.size) {
      setState((current) => (current ? {
        ...current,
        projects: current.projects.map((project) => (
          succeeded.has(project.path) ? { ...project, group } : project
        )),
      } : current));
    }
    if (succeeded.size === paths.length) toast(`已移动到「${group}」`);
    else toast(`已移动 ${succeeded.size} / ${paths.length} 个项目`, true);
  }, [toast]);

  const batchFetch = useCallback(async (paths) => {
    setBusy((current) => {
      const next = { ...current };
      for (const path of paths) next[path] = 'fetch';
      return next;
    });
    try {
      const results = await Promise.allSettled(paths.map((path) => api.git(path, 'fetch')));
      const failed = results.filter((result) => result.status === 'rejected').length;
      if (failed) toast(`${paths.length - failed} 个已同步，${failed} 个失败`, true);
      else toast(`已同步 ${paths.length} 个项目`);
      await rescan(true);
    } finally {
      setBusy((current) => {
        const next = { ...current };
        for (const path of paths) delete next[path];
        return next;
      });
    }
  }, [rescan, toast]);

  useEffect(() => {
    const handler = (event) => {
      const mod = event.metaKey || event.ctrlKey;
      if (mod && event.key.toLowerCase() === 'k') {
        event.preventDefault();
        setAddOpen(false);
        setSettingsOpen(false);
        setPaletteOpen((current) => !current);
        return;
      }
      if (paletteOpen || addOpen || settingsOpen) return;
      if (mod && event.ctrlKey && event.key.toLowerCase() === 's') {
        event.preventDefault();
        setCollapsed((current) => !current);
      } else if (mod && event.key === '1') {
        event.preventDefault();
        navigate('workbench');
      } else if (mod && event.key === '2') {
        event.preventDefault();
        openLibrary({});
      } else if (mod && event.key === '3') {
        event.preventDefault();
        navigate('cleanup');
      } else if (mod && event.key === '0') {
        event.preventDefault();
        navigate('workbench');
      } else if (mod && event.key.toLowerCase() === 'r') {
        event.preventDefault();
        rescan();
      } else if (mod && event.key === ',') {
        event.preventDefault();
        setSettingsOpen(true);
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [addOpen, navigate, openLibrary, paletteOpen, rescan, settingsOpen]);

  const sidebarView = selectedProject ? 'project' : view;

  return (
    <div className="fizz-app">
      <Sidebar
        projects={projects}
        view={sidebarView}
        selectedPath={selectedPath}
        onView={navigate}
        onOpenProject={openProject}
        onPalette={() => setPaletteOpen(true)}
        onAdd={openAdd}
        onSettings={openSettings}
        collapsed={collapsed}
        onToggleCollapsed={() => setCollapsed((current) => !current)}
        disk={state?.disk}
      />

      <main className="fizz-main">
        {!state ? (
          <div className="fizz-boot">
            <div className="fizz-boot-card">
              {loadFailed ? <ServerCrash size={26} /> : <Spinner size={24} />}
              <strong>{loadFailed ? '无法连接本地服务' : '正在读取本地项目'}</strong>
              <span>{loadFailed ? '确认 FizzDeck 服务已启动，然后重试。' : '扫描 Git、AI 会话和磁盘状态…'}</span>
              {loadFailed ? (
                <button type="button" className="fizz-btn primary" onClick={load}>
                  <RefreshCw size={12} />重试
                </button>
              ) : null}
            </div>
          </div>
        ) : selectedProject ? (
          <ProjectDetail
            key={selectedProject.path}
            project={selectedProject}
            running={selectedProject.portState === 'running'}
            busy={busy[selectedProject.path]}
            testRun={testRuns[selectedProject.path]}
            requestedTab={requestedTab}
            sessionsVersion={sessionsVersion}
            onResumeSession={resumeSession}
            onEndSession={endSession}
            onLaunch={launch}
            onStop={stop}
            onCopy={copy}
            onReveal={reveal}
            onMeta={meta}
            onStar={star}
            onRemove={remove}
            onTest={test}
            toast={toast}
          />
        ) : view === 'library' ? (
          <Library
            projects={projects}
            initialQuery={libraryQuery}
            onOpenProject={openProject}
            onToggleStar={star}
            onBatchStar={batchStar}
            onBatchGroup={batchGroup}
            onBatchFetch={batchFetch}
            onCopy={copy}
            onRescan={() => rescan()}
            onAdd={openAdd}
          />
        ) : view === 'cleanup' ? (
          <Cleanup
            projects={projects}
            orphans={orphans}
            onOpenProject={openProject}
            onCopy={copy}
          />
        ) : (
          <Workbench
            projects={projects}
            disk={state.disk}
            testRuns={testRuns}
            onOpenProject={openProject}
            onResume={resumeSession}
            onOpenLibrary={openLibrary}
            onOpenCleanup={() => navigate('cleanup')}
          />
        )}
      </main>

      <CommandPalette
        open={paletteOpen}
        onClose={() => setPaletteOpen(false)}
        projects={projects}
        selectedProject={selectedProject}
        onView={navigate}
        onOpenProject={openProject}
        onAdd={openAdd}
        onSettings={openSettings}
        onRescan={() => rescan()}
        onLaunch={launch}
        onStop={stop}
        onReveal={reveal}
        onCopy={copy}
        onStar={star}
        onTest={test}
        onResumeSession={resumeSession}
      />

      {addOpen ? (
        <AddProjectsModal
          roots={state?.roots || []}
          onClose={() => setAddOpen(false)}
          onChanged={() => rescan(true)}
          toast={toast}
        />
      ) : null}

      {settingsOpen ? (
        <SettingsModal
          appearance={appearance}
          onAppearance={setAppearance}
          state={state}
          projects={projects}
          onClose={() => setSettingsOpen(false)}
        />
      ) : null}

      {scanning ? <div className="fizz-scan-indicator"><Spinner size={12} />正在扫描</div> : null}
      <Toasts toasts={toasts} />
    </div>
  );
}
