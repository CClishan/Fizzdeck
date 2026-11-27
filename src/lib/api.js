export async function request(url, body) {
  const response = await fetch(url, body
    ? {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    }
    : undefined);
  const data = await response.json().catch(() => ({ ok: false, message: '响应解析失败' }));
  if (!response.ok || data.ok === false) {
    const error = new Error(data.message || '请求失败');
    error.payload = data;
    throw error;
  }
  return data;
}

export const api = {
  state: () => request('/api/state'),
  rescan: () => request('/api/rescan'),
  orphans: () => request('/api/orphans'),
  project: (path) => request(`/api/project?path=${encodeURIComponent(path)}`),
  sessions: (path) => request(`/api/sessions?path=${encodeURIComponent(path)}`),
  logs: (path) => request(`/api/logs?path=${encodeURIComponent(path)}`),
  doc: (path, file) => request(`/api/doc?path=${encodeURIComponent(path)}&file=${encodeURIComponent(file)}`),
  folders: (dir, depth) => request('/api/folders', { dir, depth }),
  pickFolder: () => request('/api/pick-folder', {}),
  addRoot: (add) => request('/api/roots', { add }),
  removeRoot: (remove) => request('/api/roots', { remove }),
  action: (path, action) => request('/api/action', { path, action }),
  star: (path, starred) => request('/api/star', { path, starred }),
  meta: (path, patch) => request('/api/meta', { path, ...patch }),
  test: (path) => request('/api/test', { path }),
  testRun: (path) => request(`/api/test-run?path=${encodeURIComponent(path)}`),
  remove: (path, mode, confirm) => request('/api/remove', { path, mode, confirm }),
  git: (path, action, branch) => request('/api/git', { path, action, branch }),
  sessionAction: (path, action, id) => request('/api/session', { path, action, id }),
};
