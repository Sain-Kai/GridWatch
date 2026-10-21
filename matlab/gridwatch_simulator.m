function gridwatch_simulator()
% GRIDWATCH_SIMULATOR  MATLAB digital twin for the GridWatch project.
%
% Simulates the ESP32 sensor node and ESP8266 gateway, while sending the
% resulting telemetry to the REAL GridWatch Spring Boot backend over HTTP.
% This is intentionally independent of the physical hardware and Wokwi.
%
% Start the backend first, then run:
%   gridwatch_simulator
%
% Requires MATLAB with webwrite/webread support. No Simulink license is
% required for this mode.

    state = initialState();

    fig = uifigure('Name', 'GridWatch MATLAB Digital Twin', ...
        'Position', [100 80 1180 760], ...
        'Color', [0.06 0.07 0.09], ...
        'CloseRequestFcn', @onClose);

    gl = uigridlayout(fig, [7 4]);
    gl.RowHeight = {34, 34, 34, 34, '1x', 150, 34};
    gl.ColumnWidth = {170, 220, 170, '1x'};
    gl.Padding = [14 14 14 14];
    gl.RowSpacing = 8;
    gl.ColumnSpacing = 10;

    uilabel(gl, 'Text', 'Backend URL', 'FontColor', [0.85 0.88 0.92]);
    urlEdit = uieditfield(gl, 'text', 'Value', state.backendUrl);
    urlEdit.Layout.Row = 1; urlEdit.Layout.Column = 2;

    uilabel(gl, 'Text', 'Node ID', 'FontColor', [0.85 0.88 0.92]);
    nodeEdit = uieditfield(gl, 'numeric', 'Value', state.nodeId, 'Limits', [1 999]);
    nodeEdit.Layout.Row = 1; nodeEdit.Layout.Column = 4;

    uilabel(gl, 'Text', 'Scenario', 'FontColor', [0.85 0.88 0.92]);
    scenarioDrop = uidropdown(gl, 'Items', scenarioNames(), 'Value', state.scenario);
    scenarioDrop.Layout.Row = 2; scenarioDrop.Layout.Column = 2;

    uilabel(gl, 'Text', 'Sample interval (s)', 'FontColor', [0.85 0.88 0.92]);
    intervalEdit = uieditfield(gl, 'numeric', 'Value', state.intervalSec, 'Limits', [0.2 60]);
    intervalEdit.Layout.Row = 2; intervalEdit.Layout.Column = 4;

    uilabel(gl, 'Text', 'ESP-NOW packet loss (%)', 'FontColor', [0.85 0.88 0.92]);
    lossEdit = uieditfield(gl, 'numeric', 'Value', state.packetLossPct, 'Limits', [0 100]);
    lossEdit.Layout.Row = 3; lossEdit.Layout.Column = 2;

    uilabel(gl, 'Text', 'Backend reachable', 'FontColor', [0.85 0.88 0.92]);
    backendCheck = uicheckbox(gl, 'Text', 'ON', 'Value', true, ...
        'FontColor', [0.85 0.88 0.92]);
    backendCheck.Layout.Row = 3; backendCheck.Layout.Column = 4;

    startBtn = uibutton(gl, 'push', 'Text', 'Start simulation', 'ButtonPushedFcn', @startSimulation);
    startBtn.Layout.Row = 4; startBtn.Layout.Column = 1;
    stopBtn = uibutton(gl, 'push', 'Text', 'Stop', 'Enable', 'off', 'ButtonPushedFcn', @stopSimulation);
    stopBtn.Layout.Row = 4; stopBtn.Layout.Column = 2;
    resetBtn = uibutton(gl, 'push', 'Text', 'Reset', 'ButtonPushedFcn', @resetSimulation);
    resetBtn.Layout.Row = 4; resetBtn.Layout.Column = 3;
    sendBtn = uibutton(gl, 'push', 'Text', 'Send one sample', 'ButtonPushedFcn', @sendOne);
    sendBtn.Layout.Row = 4; sendBtn.Layout.Column = 4;

    ax = uiaxes(gl);
    ax.Layout.Row = 5; ax.Layout.Column = [1 4];
    ax.Color = [0.08 0.09 0.12];
    ax.XColor = [0.8 0.82 0.86];
    ax.YColor = [0.8 0.82 0.86];
    ax.GridColor = [0.25 0.27 0.31];
    grid(ax, 'on');
    xlabel(ax, 'Simulation time (s)');
    ylabel(ax, 'Temperature (°C)');
    title(ax, 'Transformer temperature');

    statusArea = uitextarea(gl, 'Editable', 'off', 'Value', {'GridWatch MATLAB simulator ready.'});
    statusArea.Layout.Row = 6; statusArea.Layout.Column = [1 2];
    metricsArea = uitextarea(gl, 'Editable', 'off', 'Value', {'No sample yet.'});
    metricsArea.Layout.Row = 6; metricsArea.Layout.Column = [3 4];

    footer = uilabel(gl, 'Text', 'Backend: localhost:8080  |  NVIDIA/RAG remain REAL backend services  |  Hardware is simulated', ...
        'FontColor', [0.55 0.58 0.63]);
    footer.Layout.Row = 7; footer.Layout.Column = [1 4];

    simTimer = timer('ExecutionMode', 'fixedSpacing', ...
        'Period', state.intervalSec, ...
        'BusyMode', 'drop', ...
        'TimerFcn', @onTick);

    state.simTimer = simTimer;
    state.fig = fig;
    state.urlEdit = urlEdit;
    state.nodeEdit = nodeEdit;
    state.scenarioDrop = scenarioDrop;
    state.intervalEdit = intervalEdit;
    state.lossEdit = lossEdit;
    state.backendCheck = backendCheck;
    state.startBtn = startBtn;
    state.stopBtn = stopBtn;
    state.ax = ax;
    state.statusArea = statusArea;
    state.metricsArea = metricsArea;
    fig.UserData = state;

    updateUi();

    function startSimulation(~, ~)
        s = fig.UserData;
        if strcmp(s.simTimer.Running, 'off')
            applyControls();
            start(s.simTimer);
            s.running = true;
            fig.UserData = s;
            updateUi();
        end
    end

    function stopSimulation(~, ~)
        s = fig.UserData;
        if strcmp(s.simTimer.Running, 'on')
            stop(s.simTimer);
        end
        s.running = false;
        fig.UserData = s;
        updateUi();
    end

    function resetSimulation(~, ~)
        s = fig.UserData;
        wasRunning = strcmp(s.simTimer.Running, 'on');
        if wasRunning, stop(s.simTimer); end
        base = initialState();
        base.simTimer = s.simTimer;
        base.fig = s.fig;
        base.urlEdit = s.urlEdit;
        base.nodeEdit = s.nodeEdit;
        base.scenarioDrop = s.scenarioDrop;
        base.intervalEdit = s.intervalEdit;
        base.lossEdit = s.lossEdit;
        base.backendCheck = s.backendCheck;
        base.startBtn = s.startBtn;
        base.stopBtn = s.stopBtn;
        base.ax = s.ax;
        base.statusArea = s.statusArea;
        base.metricsArea = s.metricsArea;
        fig.UserData = base;
        cla(ax);
        if wasRunning
            start(base.simTimer);
            base.running = true;
            fig.UserData = base;
        end
        updateUi();
    end

    function sendOne(~, ~)
        applyControls();
        onTick([], []);
    end

    function onTick(~, ~)
        if ~isvalid(fig), return; end
        s = fig.UserData;
        applyControls();
        s = fig.UserData;

        s.timeSec = s.timeSec + s.intervalSec;
        [sample, s.model] = gridwatch_model_step(s.model, s.scenario, s.intervalSec);
        sample.nodeId = s.nodeId;
        sample.sequenceId = s.sequenceId;
        s.sequenceId = s.sequenceId + 1;
        sample.buffered = false;
        sample.bufferedAgoMs = 0;

        s.totalGenerated = s.totalGenerated + 1;
        if ~s.backendReachable
            s.gatewayQueue{end+1} = sample;
            s.gatewayQueued = s.gatewayQueued + 1;
            appendLog(s, sprintf('Backend OFFLINE -> gateway queued seq=%d (queue=%d)', sample.sequenceId, numel(s.gatewayQueue)));
        elseif rand * 100 < s.packetLossPct
            s.nodeBuffer{end+1} = sample;
            s.nodeBuffered = s.nodeBuffered + 1;
            appendLog(s, sprintf('ESP-NOW LOSS -> ESP32 buffered seq=%d (node buffer=%d)', sample.sequenceId, numel(s.nodeBuffer)));
        else
            [ok, response, errText] = gridwatch_post_reading(s.backendUrl, sample);
            if ok
                s.backendDelivered = s.backendDelivered + 1;
                s.lastResponse = response;
                appendLog(s, sprintf('LIVE -> backend accepted seq=%d state=%s', sample.sequenceId, sample.classification));
            else
                sample.buffered = false;
                s.gatewayQueue{end+1} = sample;
                s.gatewayQueued = s.gatewayQueued + 1;
                appendLog(s, sprintf('Backend POST failed -> gateway queued seq=%d (%s)', sample.sequenceId, errText));
            end
        end

        % A recovered gateway/backend replays gateway records first.
        if s.backendReachable
            [s, replayLog] = replayQueue(s, 'gateway');
            if ~isempty(replayLog), appendLog(s, replayLog); end
        end

        % Node-side buffered packets become ESP-NOW deliveries once radio is available.
        if s.backendReachable && ~isempty(s.nodeBuffer)
            deliveredCount = 0;
            remaining = {};
            for i = 1:numel(s.nodeBuffer)
                item = s.nodeBuffer{i};
                if rand * 100 < s.packetLossPct
                    remaining{end+1} = item; %#ok<AGROW>
                else
                    item.buffered = true;
                    item.bufferedAgoMs = round(max(0, (s.timeSec - (s.nodeCaptureTime(item.sequenceId))) * 1000));
                    [ok, response, ~] = gridwatch_post_reading(s.backendUrl, item);
                    if ok
                        deliveredCount = deliveredCount + 1;
                        s.lastResponse = response;
                    else
                        remaining{end+1} = item; %#ok<AGROW>
                    end
                end
            end
            s.nodeBuffer = remaining;
            if deliveredCount > 0
                appendLog(s, sprintf('ESP32 replay -> backend delivered %d buffered record(s)', deliveredCount));
            end
        end

        s.sampleTimes(end+1) = s.timeSec;
        s.temperatures(end+1) = sample.tempC;
        s.classifications{end+1} = sample.classification;
        if numel(s.sampleTimes) > 120
            s.sampleTimes = s.sampleTimes(end-119:end);
            s.temperatures = s.temperatures(end-119:end);
            s.classifications = s.classifications(end-119:end);
        end

        fig.UserData = s;
        redraw();
    end

    function [s, logText] = replayQueue(s, queueKind)
        logText = '';
        if strcmp(queueKind, 'gateway')
            q = s.gatewayQueue;
            keep = {};
            delivered = 0;
            for i = 1:numel(q)
                item = q{i};
                item.buffered = true;
                item.bufferedAgoMs = 0;
                [ok, response, ~] = gridwatch_post_reading(s.backendUrl, item);
                if ok
                    delivered = delivered + 1;
                    s.lastResponse = response;
                else
                    keep{end+1} = item; %#ok<AGROW>
                end
            end
            s.gatewayQueue = keep;
            if delivered > 0
                logText = sprintf('Gateway replay -> backend delivered %d record(s); %d remain', delivered, numel(keep));
            end
        end
    end

    function applyControls()
        s = fig.UserData;
        s.backendUrl = strtrim(s.urlEdit.Value);
        s.nodeId = max(1, round(s.nodeEdit.Value));
        s.scenario = s.scenarioDrop.Value;
        newInterval = max(0.2, s.intervalEdit.Value);
        s.packetLossPct = min(100, max(0, s.lossEdit.Value));
        s.backendReachable = s.backendCheck.Value;
        if abs(newInterval - s.intervalSec) > eps
            s.intervalSec = newInterval;
            if strcmp(s.simTimer.Running, 'on')
                stop(s.simTimer);
                s.simTimer.Period = newInterval;
                start(s.simTimer);
            else
                s.simTimer.Period = newInterval;
            end
        end
        fig.UserData = s;
    end

    function redraw()
        s = fig.UserData;
        if isempty(s.sampleTimes), return; end
        plot(ax, s.sampleTimes, s.temperatures, 'LineWidth', 1.8);
        x0 = max(0, s.sampleTimes(1));
        x1 = max(s.sampleTimes(end), 1);
        if ~isfinite(x0) || ~isfinite(x1) || x1 <= x0
            x0 = max(0, x1 - 1);
            x1 = x0 + 1;
        end
        xlim(ax, [x0 x1]);
        lo = min(s.temperatures); hi = max(s.temperatures);
        if ~isfinite(lo) || ~isfinite(hi)
            lo = 0; hi = 1;
        end
        pad = max(2, 0.12 * max(1, hi-lo));
        if hi-pad >= hi+pad
            pad = 1;
        end
        ylim(ax, [lo-pad hi+pad]);
        title(ax, sprintf('Transformer temperature — %s', s.scenario), 'Color', [0.9 0.92 0.95]);
        updateUi();
    end

    function updateUi()
        if ~isvalid(fig), return; end
        s = fig.UserData;
        if strcmp(s.simTimer.Running, 'on')
            s.startBtn.Enable = 'off';
            s.stopBtn.Enable = 'on';
        else
            s.startBtn.Enable = 'on';
            s.stopBtn.Enable = 'off';
        end
        backendText = ternary(s.backendReachable, 'BACKEND ONLINE', 'BACKEND OFFLINE / BUFFERING');
        statusLines = [ ...
            {sprintf('%s', backendText)}, ...
            {sprintf('Scenario: %s', s.scenario)}, ...
            {sprintf('Generated: %d  | backend delivered: %d', s.totalGenerated, s.backendDelivered)}, ...
            {sprintf('Node buffer: %d  | gateway queue: %d', numel(s.nodeBuffer), numel(s.gatewayQueue))}, ...
            {sprintf('Packet loss: %.1f%%', s.packetLossPct)} ...
        ];
        s.statusArea.Value = statusLines;
        if isempty(s.lastResponse)
            s.metricsArea.Value = {'Waiting for backend response...'};
        else
            r = s.lastResponse;
            s.metricsArea.Value = { ...
                sprintf('Last seq: %s', toStringField(r, 'sequenceId')), ...
                sprintf('State: %s', toStringField(r, 'classification')), ...
                sprintf('Health: %s', toStringField(r, 'healthScore')), ...
                sprintf('Temperature: %s °C', toStringField(r, 'tempC')), ...
                sprintf('Report provider: %s', toStringField(r, 'reportProvider')) ...
            };
        end
        fig.UserData = s;
    end

    function appendLog(s, line)
        old = s.statusArea.Value;
        if ischar(old), old = {old}; end
        stamp = datestr(now, 'HH:MM:SS');
        s.statusArea.Value = [old(:); {sprintf('[%s] %s', stamp, line)}];
        if numel(s.statusArea.Value) > 16
            s.statusArea.Value = s.statusArea.Value(end-15:end);
        end
        fig.UserData = s;
    end

    function onClose(~, ~)
        s = fig.UserData;
        try
            if strcmp(s.simTimer.Running, 'on'), stop(s.simTimer); end
            delete(s.simTimer);
        catch
        end
        delete(fig);
    end

    function value = toStringField(s, name)
        if isfield(s, name)
            v = s.(name);
            if isstring(v) || ischar(v)
                value = char(string(v));
            elseif isnumeric(v) || islogical(v)
                value = char(string(v));
            else
                value = 'n/a';
            end
        else
            value = 'n/a';
        end
    end

    function out = ternary(cond, a, b)
        if cond, out = a; else, out = b; end
    end
end

function names = scenarioNames()
    names = {'NORMAL', 'THERMAL_WARNING', 'COOLING_FAILURE', 'CRITICAL_OVERHEAT', ...
        'POSSIBLE_TAMPER', 'TAMPER', 'SENSOR_FAULT'};
end

function s = initialState()
    s.backendUrl = 'http://localhost:8080';
    s.nodeId = 1;
    s.scenario = 'NORMAL';
    s.intervalSec = 1.0;
    s.packetLossPct = 0;
    s.backendReachable = true;
    s.sequenceId = 1;
    s.timeSec = 0;
    s.running = false;
    s.model = struct('tempC', 32, 'ambientC', 27, 'previousTempC', 32, ...
        'fanWorking', true, 'ambientOk', true, 'tamper', false, 'rotationPhase', 0);
    s.sampleTimes = [];
    s.temperatures = [];
    s.classifications = {};
    s.nodeBuffer = {};
    s.gatewayQueue = {};
    s.totalGenerated = 0;
    s.backendDelivered = 0;
    s.gatewayQueued = 0;
    s.nodeBuffered = 0;
    s.lastResponse = struct();
    s.simTimer = [];
    s.fig = [];
    s.urlEdit = [];
    s.nodeEdit = [];
    s.scenarioDrop = [];
    s.intervalEdit = [];
    s.lossEdit = [];
    s.backendCheck = [];
    s.startBtn = [];
    s.stopBtn = [];
    s.ax = [];
    s.statusArea = [];
    s.metricsArea = [];

    % Local helper closure used by the replay calculation. Capture times with
    % an approximate deterministic mapping rather than pretending to know real
    % wall-clock capture time inside a digital twin.
    s.nodeCaptureTime = @(sequenceId) max(0, double(sequenceId - 1));
end
