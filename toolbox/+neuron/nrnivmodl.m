function [mechLib, special] = nrnivmodl(modFiles, options)
% Compile NMODL (.mod) files into a NEURON mechanism library.
%   [mechLib, special] = neuron.nrnivmodl()
%   [mechLib, special] = neuron.nrnivmodl(modFiles)
%   [mechLib, special] = neuron.nrnivmodl(modFiles, IncludeFlags=flags, LoadFlags=flags)
% MATLAB port of nrn/bin/nrnivmodl; the build itself is done by
% neuron.nrnmech_makefile.
% modFiles are absolute paths to mod files, C files, folders containing
% mod files or regular expressions matched against the whole file name,
% e.g. "/home/me/mechs/(kv|nav)\.mod" (the folder part is taken
% literally); if omitted, the mod files in the current folder are used. Output is
% written to <pwd>/x86_64 (arm64 on Apple silicon): the shared library
% libnrnmech.so and the special executable, whose paths are returned.
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

% Locate the NEURON installation.
nrnHome = string(getenv("NRNHOME"));

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
                "or a regular expression matching any mod or C file.", modFiles(i));
        end
        isC = endsWith(matches, ".c");
        cFiles = [cFiles; matches(isC)]; %#ok<AGROW>
        files = [files; matches(~isC)]; %#ok<AGROW>
    end
end
[~, baseNames] = fileparts(files);
fprintf("Mod files:%s\n\n", join(" """ + files + """", ""));

% Create the output folder
outFolder = options.OutputFolder;
if outFolder == ""
    outFolder = pwd;
end

if ismac && computer("arch") == "maca64"
    modSubDir = fullfile(outFolder, "arm64");
else
    modSubDir = fullfile(outFolder, "x86_64");
end
if ~isfolder(modSubDir)
    fprintf("Creating '%s' directory for .o files.\n\n", modSubDir);
    mkdir(modSubDir);
end

% Generate mod_func.cpp, which registers the mechanisms.
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

% Build the library and special with the makefile port.
[mechLib, special] = neuron.nrnmech_makefile("mechlib" , ModFiles=files, CFiles=cFiles, ...
    BuildFolder=modSubDir, IncludeFlags=options.IncludeFlags, ...
    LoadFlags=options.LoadFlags, Root=nrnHome);
fprintf("Successfully created %s\n", special);
end

function matches = matchFiles(f)
g = matlab.buildtool.io.Glob(f);
matches = g.paths;
if isempty(matches)
    error("Neuron Toolbox: Invalid regular expression/ no mod files found in %s", f);
end
end
