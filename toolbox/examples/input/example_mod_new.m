% Initialize neuron session
n = neuron.launch();
n.reset_sections();
filePath = mfilename("fullpath");
neuron.nrnivmodl(fullfile(fileparts(filePath), "mod", "*.mod"));

% Hardcoding the mod file path
% modPath_nmdanet = fullfile(fileparts(filePath), "mod", "nmdanet.mod");
% modPath_h = fullfile(fileparts(filePath), "mod", "h.mod");
% neuron.nrnivmodl([modPath_nmdanet, modPath_h]);

dllPath = fullfile("/home/bpancras/gitRepo/neurontoolbox/examples/x86_64/libnrnmech.so");

try
    % Also for linux and mac use nrn_load_dll
    n.nrn_load_dll(dllPath);
catch
    warning("Could not load shared library file; is it already loaded?");
end

% Try to find 'hd' mechanism; now it should exist.
axon = n.Section('axon');
axon.insert_mechanism('hd');  % No error!

% Try to find NMDA object.
syn = n.NMDA(axon(0.5));
disp(syn);  % Displays: "Beta: 0.0066, e: 45, Alpha: 0.0720"
syn.e = 42;
disp(syn.e);  % Displays: 42
