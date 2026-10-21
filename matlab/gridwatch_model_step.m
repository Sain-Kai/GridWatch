function [sample, model] = gridwatch_model_step(model, scenario, dt)
% GRIDWATCH_MODEL_STEP Advance the GridWatch physical/digital model by dt seconds.
%
% The thresholds deliberately mirror the ESP32 firmware logic:
%   expectedTemp = 30 + 0.6*max(0, ambient-25)
%   warning if deviation > 8 C OR rise rate > 1.5 C/s
%   critical at >= 90 C
%   FSR tamper threshold 2500 with IR1 corroboration

    if nargin < 3 || isempty(dt), dt = 1; end
    dt = max(0.01, dt);

    model.previousTempC = model.tempC;

    switch upper(strtrim(scenario))
        case 'NORMAL'
            model.ambientOk = true;
            model.ambientC = 27 + 0.3*sin(0.08*model.rotationPhase);
            target = model.ambientC + 4.5;
            model.tempC = model.tempC + 0.25*(target-model.tempC)*dt;
            model.fanWorking = true;
            ir1 = 1; fsr = 350;

        case 'THERMAL_WARNING'
            model.ambientOk = true;
            model.ambientC = 27;
            % Sustained high temperature without requiring a fast rise > 1.5 C/s.
            target = 70;
            model.tempC = model.tempC + (target-model.tempC)*(1-exp(-dt/12));
            model.fanWorking = true;
            ir1 = 1; fsr = 450;

        case 'COOLING_FAILURE'
            model.ambientOk = true;
            model.ambientC = 27;
            target = 96;
            model.tempC = model.tempC + (target-model.tempC)*(1-exp(-dt/8));
            model.fanWorking = false;
            ir1 = 1; fsr = 450;

        case 'CRITICAL_OVERHEAT'
            model.ambientOk = true;
            model.ambientC = 27;
            target = 102;
            model.tempC = model.tempC + (target-model.tempC)*(1-exp(-dt/6));
            model.fanWorking = false;
            ir1 = 1; fsr = 450;

        case 'POSSIBLE_TAMPER'
            model.ambientOk = true;
            model.ambientC = 27;
            target = 35;
            model.tempC = model.tempC + 0.2*(target-model.tempC)*dt;
            model.fanWorking = true;
            ir1 = 0; fsr = 1200;

        case 'TAMPER'
            model.ambientOk = true;
            model.ambientC = 27;
            target = 35;
            model.tempC = model.tempC + 0.2*(target-model.tempC)*dt;
            model.fanWorking = true;
            ir1 = 0; fsr = 3000;

        case 'SENSOR_FAULT'
            model.ambientOk = false;
            model.ambientC = 25;
            model.tempC = 40;
            model.fanWorking = true;
            ir1 = 1; fsr = 350;

        otherwise
            error('Unknown GridWatch scenario: %s', scenario);
    end

    model.rotationPhase = model.rotationPhase + dt;
    riseRate = (model.tempC - model.previousTempC)/dt;
    expectedTemp = 30 + 0.6*max(0, model.ambientC - 25);
    deviation = model.tempC - expectedTemp;

    % Classification mirrors the safety precedence in the ESP32 node.
    fanVerified = false;
    % In Mode 1 the fan driver can be simulated even though the current
    % physical build keeps its real driver disabled. This allows the
    % COOLING_FAILURE scenario to exercise the complete diagnostic path.
    fanDriverEnabled = strcmpi(strtrim(scenario), 'COOLING_FAILURE');
    if fanDriverEnabled && model.fanWorking
        fanVerified = true;
    end

    if isnan(model.tempC) || model.tempC < -10 || model.tempC > 250
        classification = 'SENSOR_FAULT';
    elseif model.tempC >= 90
        classification = 'CRITICAL_OVERHEAT';
    elseif ~model.ambientOk
        classification = 'SENSOR_FAULT';
    elseif fanDriverEnabled && ~fanVerified && strcmpi(strtrim(scenario), 'COOLING_FAILURE')
        classification = 'COOLING_FAILURE';
    elseif ir1 == 0
        if fsr > 2500
            classification = 'TAMPER';
        else
            classification = 'POSSIBLE_TAMPER';
        end
    elseif deviation > 8 || riseRate > 1.5
        % Fan driver is intentionally disabled in the current hardware build,
        % matching the project's FAN_DRIVER_ENABLED=0 state. Therefore a
        % thermal concern is reported as THERMAL_WARNING rather than falsely
        % claiming a verified fan or a cooling failure.
        classification = 'THERMAL_WARNING';
    else
        classification = 'NORMAL';
    end

    health = gridwatch_health_score(classification, deviation, riseRate);

    sample = struct( ...
        'nodeId', 1, ...
        'sequenceId', 1, ...
        'tempC', model.tempC, ...
        'tempRiseRate', riseRate, ...
        'ambientC', model.ambientC, ...
        'ir1', ir1, ...
        'ir2', double(round(0.5 + 0.5*sin(2*pi*model.rotationPhase))) , ...
        'fsrValue', fsr, ...
        'fanVerified', fanVerified, ...
        'fanDriverEnabled', fanDriverEnabled, ...
        'ambientSensorOk', model.ambientOk, ...
        'classification', classification, ...
        'healthScore', health, ...
        'buffered', false, ...
        'bufferedAgoMs', 0);
end

function health = gridwatch_health_score(state, deviation, riseRate)
    if strcmp(state, 'SENSOR_FAULT'), health = 0; return; end
    if strcmp(state, 'CRITICAL_OVERHEAT'), health = 15; return; end
    thermalRisk = max(0, min(40, 2*max(0, deviation)));
    coolingRisk = 0;
    if strcmp(state, 'COOLING_FAILURE'), coolingRisk = 25; end
    tamperRisk = 0;
    if strcmp(state, 'TAMPER'), tamperRisk = 20; elseif strcmp(state, 'POSSIBLE_TAMPER'), tamperRisk = 8; end
    riseRisk = 10 * (riseRate > 1.5);
    health = max(0, min(100, round(100 - thermalRisk - coolingRisk - tamperRisk - riseRisk)));
end
