%% Initialize neuron session
n = neuron.launch();
n.reset_sections();
filePath = mfilename("fullpath");

%% Trans-compile the mod files
mechLibPath = neuron.nrnivmodl(fullfile(fileparts(filePath), "mod", "*.mod"), OutputFolder="tmp");

%% Load the mechanism file
try
    % Also for linux and mac use nrn_load_dll
    n.nrn_load_dll(mechLibPath);
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
