function mechLib = nrnivmodl(modFiles, options)
% Compile NMODL (.mod) files into a NEURON mechanism library.
%   mechLib = neuron.nrnivmodl()
%   mechLib = neuron.nrnivmodl(modFiles)
%   mechLib = neuron.nrnivmodl(modFiles, IncludeFlags=flags, LoadFlags=flags, OutputFolder=folder)
% MATLAB port of nrn/bin/nrnivmodl; the build itself is done by
% neuron.nrnmech_makefile.
% modFiles are absolute paths to mod files, C files, folders containing
% mod files or wildcard patterns, e.g. "/home/me/mechs/k*.mod"; if
% omitted, the mod files in the current folder are used.
% Output is written to <OutputFolder>/x86_64 (arm64 on Apple silicon),
% OutputFolder defaulting to pwd; the absolute path of the shared library
% libnrnmech.so is returned.
% IncludeFlags and LoadFlags are extra compiler and linker flags.
% CoreNEURON (-coreneuron) and the NMODL transpiler (-nmodl) are not
% supported.
arguments
    modFiles string = string.empty
    options.IncludeFlags (1,1) string = ""
    options.LoadFlags (1,1) string = ""
    options.OutputFolder string = ""
end

if ispc
    error("Neuron Toolbox: nrnivmodl is not supported yet on Windows.");
end

% Collect mod and C files, resolved to absolute paths.
files = strings(0, 1);
cFiles = strings(0, 1);
for f=modFiles
    if isfolder(f)
        listing = dir(fullfile(f, "*.mod"));
        files = [files; fullfile(string({listing.folder}'), string({listing.name}'))]; %#ok<AGROW>
    elseif endsWith(f, ".c")
        cFiles = [cFiles; f]; %#ok<AGROW>
    elseif isfile(f)
        files = [files; f]; %#ok<AGROW>
    else
        matches = matchFiles(f);
        if isempty(matches)
            error("Neuron Toolbox: ""%s"" is not a folder, mod file name or prefix, " + ...
                "or a regular expression matching any mod or C file.", f);
        end
        isC = endsWith(matches, ".c");
        cFiles = [cFiles; matches(isC)]; %#ok<AGROW>
        files = [files; matches(~isC)]; %#ok<AGROW>
    end
end

%% Pretty print the list of all the mod files
[~, baseNames] = fileparts(files);
fprintf(" => Mod files to build:\n")
i = 1;
for f = files
    fprintf("   %d. %s \n", i, f);
    i = i+1;
end

% Create the output folder
if options.OutputFolder == ""
    options.OutputFolder = pwd;
end

if ismac && computer("arch") == "maca64"
    modSubDir = fullfile(options.OutputFolder, "arm64");
else
    modSubDir = fullfile(options.OutputFolder, "x86_64");
end
if ~isfolder(modSubDir)
    fprintf("Creating '%s' directory for .o files.\n\n", modSubDir);
    mkdir(modSubDir);
end
% Resolve to an absolute path so the returned library path is absolute.
listing = dir(modSubDir);
modSubDir = string(listing(1).folder);

%% Generate mod_func.cpp, which registers the mechanisms.
regNames = erase(baseNames, " ");
src = ["#include <stdio.h>"
    "#include ""hocdec.h"""
    "extern int nrnmpi_myid;"
    "extern int nrn_nobanner_;"
    ""
    "extern ""C"" void _" + regNames(:) + "_reg(void);"
    ""
    "extern ""C"" void modl_reg() {"
    "  if (!nrn_nobanner_) if (nrnmpi_myid < 1) {"
    "    fprintf(stderr, ""Additional mechanisms from files\n"");"
    "    fprintf(stderr, ""\n"");"
    "  }"
    "  _" + regNames(:) + "_reg();"
    "}"
    ];
writelines(src, fullfile(modSubDir, "mod_func.cpp"));

%% Build the mechanism shared library.
mechLib = neuron.nrnmech_makefile("mechlib" , ModFiles=files, CFiles=cFiles, ...
    BuildFolder=modSubDir, IncludeFlags=options.IncludeFlags, ...
    LoadFlags=options.LoadFlags);
fprintf("Successfully created %s\n", mechLib);
end

function matches = matchFiles(f)
g = matlab.buildtool.io.Glob(f);
matches = g.paths;
if isempty(matches)
    error("Neuron Toolbox: Invalid regular expression or no mod files found in %s", f);
end
end
