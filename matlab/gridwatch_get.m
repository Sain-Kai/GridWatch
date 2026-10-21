function [ok, response, errText] = gridwatch_get(baseUrl, path)
% GRIDWATCH_GET Simple GET helper for GridWatch REST endpoints.
    ok = false;
    response = struct();
    errText = '';
    url = regexprep(strtrim(baseUrl), '/+$', '') + string(path);
    try
        options = weboptions('Timeout', 10);
        response = webread(char(url), options);
        ok = true;
    catch ME
        errText = ME.message;
    end
end
