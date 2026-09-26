function plan = buildfile
import matlab.buildtool.tasks.MexTask
import matlab.buildtool.tasks.CleanTask

plan = buildplan(localfunctions);

% Add a task to delete outputs and traces
plan("clean") = CleanTask;

% Build the neuron_api MEX file from C++ source
cppSource = ["source/neuron_api.cpp"];
mexOptions = ["COMPFLAGS=$COMPFLAGS /std:c++17"...
    "-Itoolbox/nrn/include/"];
plan("mex") = MexTask.forEachFile(cppSource, "toolbox/", ...
    Options=mexOptions);

% The mex task needs the NEURON headers/libs from the wheel.
plan("mex").Dependencies = "downloadNeuron";
end


function libmodelregTask(~)
% Compile libmodelreg
status = system("cc -shared -fPIC -o ./toolbox/libmodelreg.so ./source/modl_reg.c");
end


function downloadNeuronTask(~)
% Download and extract the NEURON wheel package (Linux only)
%
% Fetches the manylinux NEURON wheel and unpacks its runtime files
% (bin, include, lib, share) into toolbox/nrn/. A wheel is a zip archive
% whose payload lives under "<dist>.data/data/".

if ~strcmp(computer("arch"), "glnxa64")
    error("downloadNeuron:UnsupportedPlatform", ...
        "This task only supports Linux (glnxa64); detected '%s'.", ...
        computer("arch"));
end

wheelUrl = "https://github.com/neuronsimulator/nrn/releases/download/" + ...
    "msvc-wheel-dev/neuron_nightly-9.0.2.dev298-cp314-cp314-" + ...
    "manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl";

destDir = fullfile("toolbox", "nrn");
tmpDir = "temp";
mkdir(tmpDir);
cleanup = onCleanup(@() rmdir(tmpDir, "s"));

% Wheels use the .whl extension but unzip requires a .zip name.
wheelFile = fullfile(tmpDir, "neuron.zip");
fprintf("Downloading NEURON wheel...\n");
websave(wheelFile, wheelUrl);

extractDir = fullfile(tmpDir, "extracted");
unzip(wheelFile, extractDir);

% Locate the "<dist>.data/data" directory that holds bin/include/lib/share.
dataDirs = dir(fullfile(extractDir,"neuron", ".data"));
dataDirs = dataDirs([dataDirs.isdir]);
if isempty(dataDirs)
    error("downloadNeuron:LayoutError", ...
        "Could not find a '*.data/data' directory in the wheel.");
end
dataDir = fullfile(dataDirs(1).folder, dataDirs(1).name);

if ~isfolder(destDir)
    mkdir(destDir);
end

for name = ["bin", "include", "lib", "share"]
    src = fullfile(dataDir, name);
    if isfolder(src)
        copyfile(src, fullfile(destDir, name), "f");
    end
end

fprintf("NEURON wheel extracted to %s\n", destDir);
cleanup;
end
