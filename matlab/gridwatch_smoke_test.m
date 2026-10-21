function results = gridwatch_smoke_test(baseUrl)
% GRIDWATCH_SMOKE_TEST Exercise the real GridWatch backend using MATLAB.
%
% Usage:
%   results = gridwatch_smoke_test();
%   results = gridwatch_smoke_test('http://localhost:8080');
%
% This test intentionally sends synthetic ESP32-like telemetry to the real
% Spring Boot backend. It validates API ingestion, persistence, RAG/NVIDIA
% generation, duplicate protection, and Q&A.

    if nargin < 1 || isempty(baseUrl), baseUrl = 'http://localhost:8080'; end
    baseUrl = regexprep(strtrim(baseUrl), '/+$', '');
    addpath(fileparts(mfilename('fullpath')));

    results = struct('passed', false, 'health', [], 'llmStatus', [], ...
        'scenarioRows', [], 'duplicateCheck', [], 'incidentReport', [], 'qa', []);

    fprintf('\n=== GridWatch MATLAB smoke test ===\n');
    fprintf('Backend: %s\n\n', baseUrl);

    [ok, health, err] = gridwatch_get(baseUrl, '/api/health');
    assert(ok, 'Health check failed: %s', err);
    results.health = health;
    fprintf('[PASS] /api/health\n');

    [ok, llm, err] = gridwatch_get(baseUrl, '/api/llm-status');
    assert(ok, 'LLM status failed: %s', err);
    results.llmStatus = llm;
    fprintf('[PASS] /api/llm-status | NVIDIA configured=%s | embeddings=%s\n', ...
        mat2str(llm.nvidiaKeyConfigured), string(llm.embeddingProvider));

    scenarios = {'NORMAL','THERMAL_WARNING','COOLING_FAILURE','CRITICAL_OVERHEAT','POSSIBLE_TAMPER','TAMPER','SENSOR_FAULT'};
    rows = repmat(struct('scenario','','ok',false,'id',NaN,'classification','','provider',''), 1, numel(scenarios));

    seqBase = uint32(70000 + randi(10000));
    for i = 1:numel(scenarios)
        scenario = scenarios{i};
        payload = scenarioPayload(scenario, 1, double(seqBase+i));
        [ok, response, err] = gridwatch_post_reading(baseUrl, payload);
        rows(i).scenario = scenario;
        rows(i).ok = ok;
        if ok
            rows(i).id = response.id;
            rows(i).classification = string(response.classification);
            if isfield(response, 'reportProvider') && ~isempty(response.reportProvider)
                rows(i).provider = string(response.reportProvider);
            end
            fprintf('[PASS] %-20s -> id=%d classification=%s provider=%s\n', scenario, response.id, response.classification, string(rows(i).provider));
        else
            fprintf('[FAIL] %-20s -> %s\n', scenario, err);
        end
    end
    results.scenarioRows = rows;
    assert(all([rows.ok]), 'One or more scenario POSTs failed.');

    % Duplicate protection: same node + sequence should return the original row.
    dupSeq = double(seqBase+999);
    p = scenarioPayload('THERMAL_WARNING', 1, dupSeq);
    [ok1, r1, e1] = gridwatch_post_reading(baseUrl, p);
    [ok2, r2, e2] = gridwatch_post_reading(baseUrl, p);
    assert(ok1 && ok2, 'Duplicate test POST failed: %s / %s', e1, e2);
    results.duplicateCheck = struct('firstId', r1.id, 'secondId', r2.id, 'sameId', isequal(r1.id, r2.id));
    assert(isequal(r1.id, r2.id), 'Duplicate protection failed: IDs differ.');
    fprintf('[PASS] Duplicate protection -> same database id=%d\n', r1.id);

    % Incident endpoint should return the most recent non-NORMAL incident.
    [ok, report, err] = gridwatch_get(baseUrl, '/api/incident-report/1');
    assert(ok, 'Incident report endpoint failed: %s', err);
    results.incidentReport = report;
    fprintf('[PASS] /api/incident-report/1 -> provider=%s, chars=%d\n', string(report.provider), strlength(string(report.report)));
    assert(strlength(string(report.report)) > 10, 'Incident report is empty or unusable.');

    % RAG Q&A through the real backend.
    question = 'What should an operator do if the cooling fan does not spin up?';
    body = struct('question', question);
    try
        options = weboptions('MediaType','application/json','Timeout',30);
        qa = webwrite(char(baseUrl + "/api/ask"), body, options);
        results.qa = qa;
        fprintf('[PASS] /api/ask -> provider=%s, chars=%d\n', string(qa.provider), strlength(string(qa.answer)));
        assert(strlength(string(qa.answer)) > 10, 'Q&A answer is empty.');
    catch ME
        error('RAG Q&A failed: %s', ME.message);
    end

    results.passed = true;
    fprintf('\n=== ALL MATLAB BACKEND-INTEGRATION TESTS PASSED ===\n\n');
end

function payload = scenarioPayload(scenario, nodeId, seq)
    switch scenario
        case 'NORMAL'
            p = struct('tempC',32.5,'tempRiseRate',0.05,'ambientC',27,'ambientSensorOk',true,...
                'fsrValue',300,'ir1',1,'ir2',0,'classification','NORMAL','healthScore',98,...
                'fanVerified',false,'fanDriverEnabled',false,'buffered',false,'bufferedAgoMs',0);
        case 'THERMAL_WARNING'
            p = struct('tempC',70,'tempRiseRate',0.4,'ambientC',27,'ambientSensorOk',true,...
                'fsrValue',400,'ir1',1,'ir2',0,'classification','THERMAL_WARNING','healthScore',65,...
                'fanVerified',false,'fanDriverEnabled',false,'buffered',false,'bufferedAgoMs',0);
        case 'COOLING_FAILURE'
            p = struct('tempC',84,'tempRiseRate',2.0,'ambientC',27,'ambientSensorOk',true,...
                'fsrValue',400,'ir1',1,'ir2',0,'classification','COOLING_FAILURE','healthScore',30,...
                'fanVerified',false,'fanDriverEnabled',false,'buffered',false,'bufferedAgoMs',0);
        case 'CRITICAL_OVERHEAT'
            p = struct('tempC',95,'tempRiseRate',1.2,'ambientC',27,'ambientSensorOk',true,...
                'fsrValue',400,'ir1',1,'ir2',0,'classification','CRITICAL_OVERHEAT','healthScore',15,...
                'fanVerified',false,'fanDriverEnabled',false,'buffered',false,'bufferedAgoMs',0);
        case 'POSSIBLE_TAMPER'
            p = struct('tempC',35,'tempRiseRate',0.1,'ambientC',27,'ambientSensorOk',true,...
                'fsrValue',1200,'ir1',0,'ir2',0,'classification','POSSIBLE_TAMPER','healthScore',92,...
                'fanVerified',false,'fanDriverEnabled',false,'buffered',false,'bufferedAgoMs',0);
        case 'TAMPER'
            p = struct('tempC',35,'tempRiseRate',0.1,'ambientC',27,'ambientSensorOk',true,...
                'fsrValue',3000,'ir1',0,'ir2',0,'classification','TAMPER','healthScore',80,...
                'fanVerified',false,'fanDriverEnabled',false,'buffered',false,'bufferedAgoMs',0);
        case 'SENSOR_FAULT'
            p = struct('tempC',40,'tempRiseRate',0,'ambientC',25,'ambientSensorOk',false,...
                'fsrValue',350,'ir1',1,'ir2',0,'classification','SENSOR_FAULT','healthScore',0,...
                'fanVerified',false,'fanDriverEnabled',false,'buffered',false,'bufferedAgoMs',0);
        otherwise
            error('Unknown scenario %s', scenario);
    end
    p.nodeId = nodeId;
    p.sequenceId = seq;
    payload = p;
end
