function launch_gridwatch_matlab()
% Convenience launcher for the GridWatch MATLAB digital twin.
    here = fileparts(mfilename('fullpath'));
    addpath(genpath(here));
    gridwatch_simulator();
end

% The simulator can also be launched by opening this file and pressing Run.
