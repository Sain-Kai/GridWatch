function [ok, response, errText, statusCode] = gridwatch_post_reading(baseUrl, payload)
% GRIDWATCH_POST_READING Send one telemetry record to the real backend.
%
% MATLAB encodes an empty numeric field ([]) as JSON [] rather than JSON null.
% Jackson cannot deserialize [] into nullable scalar fields such as Integer.
% Remove empty optional fields before transmission; omitted JSON properties map
% cleanly to null on the Spring Boot side.

    ok = false;
    response = struct();
    errText = '';
    statusCode = NaN;

    payload = sanitizePayload(payload);
    url = regexprep(strtrim(baseUrl), '/+$', '') + "/api/readings";
    try
        options = weboptions('MediaType', 'application/json', 'Timeout', 15);
        response = webwrite(char(url), payload, options);
        ok = true;
        statusCode = 200; % webwrite throws for HTTP error responses.
    catch ME
        errText = ME.message;
        token = regexp(errText, 'HTTP (\d+)', 'tokens', 'once');
        if ~isempty(token)
            statusCode = str2double(token{1});
        end
    end
end

function out = sanitizePayload(in)
    out = in;
    if ~isstruct(in) || numel(in) ~= 1
        return;
    end
    names = fieldnames(in);
    for k = 1:numel(names)
        name = names{k};
        value = in.(name);
        if isempty(value)
            out = rmfield(out, name);
        elseif isstruct(value) && isscalar(value)
            out.(name) = sanitizePayload(value);
        end
    end
end
