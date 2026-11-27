import React from 'react';
import { Check, GitBranch, Pin, Play, ShieldAlert, Terminal } from 'lucide-react';
import { Spinner, Stage, States } from '../../stageshow/kit/index.ts';
import './FizzDeckLook.css';

/* -----------------------------
 * Tile 1: Workbench & AI Ledger
 * ----------------------------- */
const HEATMAP_LEVELS = [
  0, 1, 2, 0, 1, 3, 2, 1, 0, 2, 3, 4,
  1, 0, 2, 1, 0, 2, 3, 2, 1, 0, 1, 3,
  2, 1, 0, 1, 2, 1, 4, 3, 2, 1, 2, 3,
  0, 2, 3, 2, 1, 0, 2, 4, 3, 2, 4, 4,
];

const WORKBENCH_INITIAL = { focused: false, commits: 535 };
const WORKBENCH_POSTER = { focused: true, commits: 535 };

async function workbenchScript(a) {
  await a.set({ focused: false });
  await a.wait(220);
  await a.move('heatdot');
  await a.wait(200);
  a.mark('callout');
  await a.set({ focused: true });
  await a.wait(2200);
  await a.move('rest-wb');
  await a.wait(200);
  await a.set({ focused: false });
}

export function WorkbenchTileStage({ copy }) {
  return (
    <div className="fzs-tile-stage">
      <Stage
        width={360}
        height={360}
        initial={WORKBENCH_INITIAL}
        poster={WORKBENCH_POSTER}
        script={workbenchScript}
        play="hover"
        fidelity="realistic"
        greys="cool"
        accent="#6438ff"
        cursor={{ at: 'rest-wb', idle: false }}
      >
        {(state) => (
          <>
            <div className="fzs-card-sheet" aria-hidden="true">
              <div className="fzs-card-head">
                <span className="fzs-card-title">{copy.title}</span>
                <span className="fzs-card-meta">{copy.streak}</span>
              </div>

              <div className="fzs-wb-kpi">
                <strong>{state.commits}</strong>
                <span>{copy.commitsUnit}</span>
              </div>

              <div className="fzs-heatmap-wrap">
                <div className="fzs-callout" data-show={state.focused ? 'true' : 'false'}>
                  <i />
                  <span>{copy.calloutDate}</span>
                  <strong>{copy.calloutCount}</strong>
                </div>
                <div className="fzs-heatmap-grid">
                  {HEATMAP_LEVELS.map((lv, idx) => {
                    const isTarget = idx === 46;
                    return (
                      <span
                        key={idx}
                        className="fzs-dot"
                        data-lv={lv}
                        data-focus={isTarget && state.focused ? 'true' : 'false'}
                        data-target={isTarget ? 'heatdot' : undefined}
                      />
                    );
                  })}
                </div>
              </div>

              <div className="fzs-cost-row">
                <div className="fzs-donut-box">
                  <svg viewBox="0 0 80 80" width="84" height="84">
                    <circle cx="40" cy="40" r="32" fill="none" stroke="rgba(17,17,17,0.06)" strokeWidth="7.5" />
                    {/* DeepSeek 48% */}
                    <circle
                      cx="40"
                      cy="40"
                      r="32"
                      fill="none"
                      stroke="#10b981"
                      strokeWidth="7.5"
                      strokeDasharray="96 201"
                      strokeDashoffset="0"
                      transform="rotate(-90 40 40)"
                    />
                    {/* Codex 29% */}
                    <circle
                      cx="40"
                      cy="40"
                      r="32"
                      fill="none"
                      stroke="#3b82f6"
                      strokeWidth="7.5"
                      strokeDasharray="58 201"
                      strokeDashoffset="-97"
                      transform="rotate(-90 40 40)"
                    />
                    {/* Claude 15% */}
                    <circle
                      cx="40"
                      cy="40"
                      r="32"
                      fill="none"
                      stroke="#d97706"
                      strokeWidth="7.5"
                      strokeDasharray="30 201"
                      strokeDashoffset="-156"
                      transform="rotate(-90 40 40)"
                    />
                    {/* AGY 8% */}
                    <circle
                      cx="40"
                      cy="40"
                      r="32"
                      fill="none"
                      stroke="#6438ff"
                      strokeWidth="7.5"
                      strokeDasharray="15 201"
                      strokeDashoffset="-186"
                      transform="rotate(-90 40 40)"
                    />
                  </svg>
                  <div className="fzs-donut-center">
                    <b>~$10.1</b>
                    <small>{copy.costTitle}</small>
                  </div>
                </div>

                <div className="fzs-legend">
                  {copy.legend.map((item, i) => {
                    const colors = ['#10b981', '#3b82f6', '#d97706', '#6438ff'];
                    return (
                      <div className="fzs-legend-item" key={item.name}>
                        <i style={{ background: colors[i] }} />
                        <span>{item.name}</span>
                        <em>{item.pct}</em>
                      </div>
                    );
                  })}
                </div>
              </div>
            </div>
            <span
              data-target="rest-wb"
              style={{ position: 'absolute', left: 290, top: 290, width: 12, height: 12 }}
            />
          </>
        )}
      </Stage>
    </div>
  );
}

/* -----------------------------
 * Tile 2: In-place Git Loop
 * ----------------------------- */
const GIT_INITIAL = { checked: false, status: 'idle' };
const GIT_POSTER = { checked: true, status: 'idle' };

async function gitScript(a) {
  await a.set({ checked: true, status: 'idle' });
  await a.wait(180);
  await a.move('git-commit-btn', { x: 0.85, y: 0.6 });
  await a.wait(180);
  await a.click();
  await a.set({ status: 'working' });
  await a.wait(700);
  a.mark('pushed');
  await a.set({ status: 'done' });
  await a.wait(2100);
  await a.move('rest-git');
  await a.wait(200);
  await a.set({ status: 'idle' });
}

export function GitLoopTileStage({ copy }) {
  return (
    <div className="fzs-tile-stage">
      <Stage
        width={360}
        height={360}
        initial={GIT_INITIAL}
        poster={GIT_POSTER}
        script={gitScript}
        play="hover"
        fidelity="realistic"
        greys="cool"
        accent="#6438ff"
        cursor={{ at: 'rest-git', idle: false }}
      >
        {(state) => (
          <>
            <div className="fzs-card-sheet" aria-hidden="true">
              <div className="fzs-git-top">
                <span className="fzs-branch-chip">
                  <GitBranch size={12} />
                  {copy.branch}
                </span>
                <span className="fzs-card-meta">ahead 1</span>
              </div>

              <div className="fzs-diff-card">
                <div className="fzs-diff-file">
                  <span className="fzs-stage-check" data-checked={state.checked ? 'true' : 'false'}>
                    {state.checked && <Check size={10} strokeWidth={3} />}
                  </span>
                  <span>{copy.file}</span>
                  <span className="fzs-diff-delta">+18 −4</span>
                </div>
                <div className="fzs-diff-code">
                  <div className="fzs-diff-hunk">{copy.hunk}</div>
                  <div className="fzs-diff-del">{copy.delLine}</div>
                  <div className="fzs-diff-add">{copy.addLine}</div>
                </div>
              </div>

              <div className="fzs-commit-bar">
                <div className="fzs-commit-input">{copy.commitPlaceholder}</div>
                <div className="fzs-git-actions">
                  <span className="fzs-staged-note">{copy.stagedLabel}</span>
                  <button
                    type="button"
                    tabIndex={-1}
                    className="fzs-glass-btn"
                    data-target="git-commit-btn"
                    data-cursor="hand"
                    data-state={state.status}
                  >
                    {state.status === 'working' && <Spinner size={11} />}
                    {state.status === 'done' && <Check size={12} strokeWidth={2.5} />}
                    <States
                      value={state.status}
                      states={{
                        idle: copy.btnIdle,
                        working: copy.btnPushing,
                        done: copy.btnDone,
                      }}
                    />
                  </button>
                </div>
              </div>
            </div>
            <span
              data-target="rest-git"
              style={{ position: 'absolute', left: 300, top: 300, width: 12, height: 12 }}
            />
          </>
        )}
      </Stage>
    </div>
  );
}

/* -----------------------------
 * Tile 3: Services & Port Guard
 * ----------------------------- */
const SERVICES_INITIAL = { status: 'conflict' };
const SERVICES_POSTER = { status: 'conflict' };

async function servicesScript(a) {
  await a.set({ status: 'conflict' });
  await a.wait(180);
  await a.move('port-btn', { x: 0.85, y: 0.6 });
  await a.wait(180);
  await a.click();
  await a.set({ status: 'stopping' });
  await a.wait(720);
  a.mark('running');
  await a.set({ status: 'running' });
  await a.wait(2100);
  await a.move('rest-srv');
  await a.wait(200);
  await a.set({ status: 'conflict' });
}

export function ServicesTileStage({ copy }) {
  return (
    <div className="fzs-tile-stage">
      <Stage
        width={360}
        height={360}
        initial={SERVICES_INITIAL}
        poster={SERVICES_POSTER}
        script={servicesScript}
        play="hover"
        fidelity="realistic"
        greys="cool"
        accent="#6438ff"
        cursor={{ at: 'rest-srv', idle: false }}
      >
        {(state) => {
          const isRunning = state.status === 'running';
          return (
            <>
              <div className="fzs-card-sheet" aria-hidden="true">
                <div className="fzs-card-head">
                  <span className="fzs-card-title">{copy.panelTitle}</span>
                  <span className="fzs-card-meta">:4770</span>
                </div>

                <div className="fzs-conflict-box" data-resolved={isRunning ? 'true' : 'false'}>
                  <div className="fzs-conflict-head">
                    <span className="fzs-status-pill" data-live={isRunning ? 'true' : 'false'}>
                      <i className="fzs-pulse-dot" data-live={isRunning ? 'true' : 'false'} />
                      {isRunning ? copy.readyState : copy.conflictPill}
                    </span>
                    <ShieldAlert size={13} color={isRunning ? '#167b40' : '#b45309'} />
                  </div>
                  <div className="fzs-conflict-detail">{copy.conflictDetail}</div>
                  <button
                    type="button"
                    tabIndex={-1}
                    className="fzs-port-btn"
                    data-target="port-btn"
                    data-cursor="hand"
                    data-state={state.status}
                  >
                    {state.status === 'stopping' ? (
                      <Spinner size={11} />
                    ) : (
                      <Play size={10} fill="currentColor" strokeWidth={1.6} />
                    )}
                    <States
                      value={state.status}
                      states={{
                        conflict: copy.btnStopStart,
                        stopping: copy.btnStopping,
                        running: copy.btnRunning,
                      }}
                    />
                  </button>
                </div>

                <div className="fzs-scripts-list">
                  <div className="fzs-script-row">
                    <Terminal size={12} color="#555" />
                    <span className="fzs-script-cmd">{copy.scriptDev}</span>
                    <span className="fzs-script-pin">
                      <Pin size={9} style={{ display: 'inline', verticalAlign: '-1px', marginRight: 3 }} />
                      {copy.pinned}
                    </span>
                    <span className="fzs-script-state" data-live={isRunning ? 'true' : 'false'}>
                      {isRunning ? ':4770' : copy.idleState}
                    </span>
                  </div>
                  <div className="fzs-script-row">
                    <Terminal size={12} color="#555" />
                    <span className="fzs-script-cmd">{copy.scriptTest}</span>
                    <span className="fzs-script-pin">{copy.pinned}</span>
                    <span className="fzs-script-state">{copy.idleState}</span>
                  </div>
                </div>
              </div>
              <span
                data-target="rest-srv"
                style={{ position: 'absolute', left: 300, top: 300, width: 12, height: 12 }}
              />
            </>
          );
        }}
      </Stage>
    </div>
  );
}
